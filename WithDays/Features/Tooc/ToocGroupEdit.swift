import PhotosUI
import SwiftUI
import UIKit

/// A photo picked or taken in a talk, waiting at the input to be sent.
struct ToocPendingPhoto: Identifiable {
    let id = UUID()
    let image: UIImage
}

/// A group's profile: its background and icon (tap to choose and crop, hold to take off), its name and its members.
struct ToocGroupEditView: View {
    let roomID: String

    @Environment(ToocStore.self) private var store
    @Environment(\.toocTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var iconFile: String?
    @State private var backgroundFile: String?
    @State private var members: Set<String> = []
    @State private var pickingIcon = false
    @State private var pickingBackground = false
    @State private var iconItem: PhotosPickerItem?
    @State private var backgroundItem: PhotosPickerItem?
    @State private var crop: ToocCropRequest?
    @State private var made: [String] = []
    @State private var loaded = false

    private var room: ToocRoom? { store.room(roomID) }
    private var canEditProfile: Bool { room.map { store.can(.editProfile, in: $0) } ?? false }
    private var canAdd: Bool { room.map { store.can(.addMembers, in: $0) } ?? false }
    private var canRemove: Bool { room.map { store.can(.removeMembers, in: $0) } ?? false }

    private var preview: ToocUser {
        var user = ToocUser(id: roomID, name: name.isEmpty ? "G" : name, bio: "", hue: ToocUser.hue(for: roomID))
        user.iconFile = iconFile
        user.backgroundFile = backgroundFile
        if let room, iconFile == room.iconURL.map(ToocFiles.remoteName) { user.iconURL = room.iconURL }
        if let room, backgroundFile == room.backgroundURL.map(ToocFiles.remoteName) { user.backgroundURL = room.backgroundURL }
        user.hasBackground = true
        return user
    }

    /// Everyone who can be in the group: friends, and anyone already in it.
    private var candidates: [ToocUser] {
        let current = (room?.memberIDs ?? []).compactMap { store.user($0) }
        let others = store.friends.filter { friend in !current.contains { $0.id == friend.id } }
        return current + others.sorted { $0.displayName < $1.displayName }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    header
                        .allowsHitTesting(canEditProfile)
                        .listRowBackground(Color.clear)
                        .listRowInsets(EdgeInsets())
                }
                Section {
                    TextField("グループ名", text: $name)
                        .disabled(!canEditProfile)
                } header: {
                    Text("グループ名").toocFont(.footnote)
                }
                Section {
                    HStack(spacing: 12) {
                        ToocAvatar(user: store.me, size: 36)
                        Text("\(store.me.displayName)（あなた）")
                    }
                    ForEach(candidates) { user in
                        let inGroup = room?.memberIDs.contains(user.id) == true
                        Button {
                            if members.contains(user.id) { members.remove(user.id) } else { members.insert(user.id) }
                        } label: {
                            HStack(spacing: 12) {
                                ToocAvatar(user: user, size: 36)
                                user.nameText.foregroundStyle(.primary)
                                Spacer()
                                Image(systemName: members.contains(user.id) ? "checkmark.circle.fill" : "circle")
                                    .toocFont(.title3)
                                    .foregroundStyle(members.contains(user.id) ? theme.accent : Color.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        // Taking someone out needs メンバーを削除; bringing someone in needs メンバーを追加.
                        .disabled(inGroup ? !canRemove : !canAdd)
                        .opacity((inGroup ? canRemove : canAdd) ? 1 : 0.45)
                    }
                } header: {
                    Text("メンバー（\(members.count + 1)）").toocFont(.footnote)
                }
            }
            .navigationTitle("グループプロフィール")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(Color.primary) }
                        .accessibilityLabel("キャンセル")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: save) { Image(systemName: "checkmark") }
                        .buttonStyle(.glassProminent)
                        .disabled(members.isEmpty || name.trimmingCharacters(in: .whitespaces).isEmpty)
                        .accessibilityLabel("保存")
                }
            }
            .photosPicker(isPresented: $pickingIcon, selection: $iconItem, matching: .images)
            .photosPicker(isPresented: $pickingBackground, selection: $backgroundItem, matching: .images)
            .onChange(of: iconItem) { _, item in load(item, icon: true) }
            .onChange(of: backgroundItem) { _, item in load(item, icon: false) }
            .sheet(item: $crop) { request in
                ToocCropView(image: request.image, aspect: request.icon ? 1 : 1.6, circle: request.icon) { cropped in
                    guard let file = ToocFiles.save(cropped, side: request.icon ? 1024 : 2048) else { return }
                    made.append(file)
                    withAnimation(.snappy) {
                        if request.icon { iconFile = file } else { backgroundFile = file }
                    }
                }
            }
        }
        .onAppear {
            guard !loaded, let room else { return }
            loaded = true
            name = room.title ?? ""
            iconFile = room.iconFile ?? room.iconURL.map(ToocFiles.remoteName)
            backgroundFile = room.backgroundFile ?? room.backgroundURL.map(ToocFiles.remoteName)
            members = Set(room.memberIDs)
        }
        .onDisappear {
            let room = store.room(roomID)
            for file in made where file != room?.iconFile && file != room?.backgroundFile { ToocFiles.delete(file) }
        }
    }

    private var header: some View {
        ZStack(alignment: .bottom) {
            ToocIconBackdrop(user: preview, blur: 0)
                .frame(height: 180)
                .overlay(Color.black.opacity(0.12))
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "photo.badge.plus")
                        .toocFont(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.35), in: Circle())
                        .padding(10)
                }
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .onTapGesture { pickingBackground = true }
                .onLongPressGesture { withAnimation(.snappy) { backgroundFile = nil } }
                .padding(.bottom, 40)
            ToocAvatar(user: preview, size: 96)
                .overlay(Circle().strokeBorder(.white, lineWidth: 3))
                .overlay(alignment: .bottomTrailing) {
                    Image(systemName: "camera.fill")
                        .toocFont(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(.black.opacity(0.55)))
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                }
                .contentShape(Circle())
                .onTapGesture { pickingIcon = true }
                .onLongPressGesture { withAnimation(.snappy) { iconFile = nil } }
        }
        .sensoryFeedback(.impact(weight: .medium), trigger: iconFile)
        .sensoryFeedback(.impact(weight: .medium), trigger: backgroundFile)
    }

    private func load(_ item: PhotosPickerItem?, icon: Bool) {
        guard let item else { return }
        if icon { iconItem = nil } else { backgroundItem = nil }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                crop = ToocCropRequest(image: image, icon: icon)
            }
        }
    }

    private func save() {
        let order = candidates.map(\.id).filter(members.contains)
        store.editGroup(roomID, name: name.trimmingCharacters(in: .whitespacesAndNewlines), iconFile: iconFile,
                        backgroundFile: backgroundFile, members: order)
        dismiss()
    }
}

/// After signing in: the tooc mark blooms out of the theme colour, says hello, then opens onto the tabs.
struct ToocWelcomeView: View {
    let name: String
    var onDone: () -> Void

    @Environment(\.toocTheme) private var theme
    @State private var stage = 0

    var body: some View {
        ZStack {
            theme.accent
                .ignoresSafeArea()
            Circle()
                .fill(.white.opacity(0.16))
                .frame(width: 220, height: 220)
                .scaleEffect(stage >= 1 ? 4 : 0.2)
                .opacity(stage >= 2 ? 0 : 1)
            VStack(spacing: 10) {
                Image("ToocLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(height: 90)
                    .accessibilityLabel("tooc")
                    .scaleEffect(stage >= 1 ? 1 : 0.4)
                    .blur(radius: stage >= 1 ? 0 : 14)
                    .opacity(stage >= 1 ? 1 : 0)
                Text("ようこそ、\(name)")
                    .toocFont(.headline)
                    .opacity(stage >= 2 ? 1 : 0)
                    .offset(y: stage >= 2 ? 0 : 12)
            }
            .foregroundStyle(.white)
        }
        .scaleEffect(stage >= 3 ? 1.25 : 1)
        .opacity(stage >= 3 ? 0 : 1)
        .sensoryFeedback(.success, trigger: stage) { _, new in new == 1 }
        .task {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.68)) { stage = 1 }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeOut(duration: 0.4)) { stage = 2 }
            try? await Task.sleep(for: .milliseconds(900))
            withAnimation(.easeIn(duration: 0.4)) { stage = 3 }
            try? await Task.sleep(for: .milliseconds(420))
            onDone()
        }
        .allowsHitTesting(stage < 3)
    }
}
