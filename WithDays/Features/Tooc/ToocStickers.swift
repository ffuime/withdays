import CoreImage
import PhotosUI
import SwiftUI
import UIKit
import Vision

// MARK: - Stickers

/// One of your stickers: a picture on the server.
struct ToocSticker: Identifiable, Hashable {
    let id: String
    let url: String
}

/// A sticker's picture, whole and with its see-through edges.
struct ToocStickerImage: View {
    let url: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .transition(.opacity)
            } else {
                ProgressView()
            }
        }
        .task(id: url) {
            if let cached = ToocFiles.image(ToocFiles.remoteName(url)) {
                image = cached
            } else if let fetched = await ToocFiles.remoteImage(url) {
                withAnimation(.easeOut(duration: 0.2)) { image = fetched }
            }
        }
    }
}

/// Under the input: your stickers (tap to send, hold to delete) and ＋ to make one from a photo.
struct ToocStickerPanel: View {
    var onSend: (String) -> Void

    @Environment(ToocStore.self) private var store
    @Environment(\.toocTheme) private var theme
    @State private var making = false

    private static let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)

    var body: some View {
        ScrollView {
            LazyVGrid(columns: Self.columns, spacing: 8) {
                Button { making = true } label: {
                    VStack(spacing: 4) {
                        Image(systemName: "plus")
                            .toocFont(.system(size: 22, weight: .semibold))
                        Text("作る")
                            .toocFont(.caption2.weight(.semibold))
                    }
                    .foregroundStyle(theme.accent)
                    .frame(maxWidth: .infinity)
                    .frame(height: 76)
                    .background(theme.accent.opacity(0.1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("写真からスタンプを作る")
                ForEach(store.stickers) { sticker in
                    Button { onSend(sticker.url) } label: {
                        ToocStickerImage(url: sticker.url)
                            .frame(height: 76)
                            .frame(maxWidth: .infinity)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(ToocPressStyle())
                    .accessibilityLabel("スタンプを送る")
                    .contextMenu {
                        Button("削除", systemImage: "trash", role: .destructive) {
                            withAnimation(.snappy) { store.deleteSticker(sticker.id) }
                        }
                    }
                }
            }
            .padding(12)
            if store.stickers.isEmpty {
                Text("写真から自分だけのスタンプを作れます。")
                    .toocFont(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 12)
            }
        }
        .frame(height: 250)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .sheet(isPresented: $making) { ToocStickerMaker() }
    }
}

/// Shrinks a little under the finger.
struct ToocPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

/// Pick a photo, cut it square, take the background away (or not), and keep it as a sticker.
struct ToocStickerMaker: View {
    @Environment(ToocStore.self) private var store
    @Environment(\.toocTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var item: PhotosPickerItem?
    @State private var crop: ToocCropRequest?
    @State private var base: UIImage?
    @State private var lifted: UIImage?
    @State private var removeBackground = true
    @State private var lifting = false
    @State private var saving = false
    @State private var error: String?

    private var result: UIImage? { removeBackground ? (lifted ?? base) : base }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ZStack {
                        ToocCheckerboard()
                        if let result {
                            Image(uiImage: result)
                                .resizable()
                                .scaledToFit()
                                .padding(16)
                                .transition(.scale(scale: 0.9).combined(with: .opacity))
                        } else {
                            PhotosPicker(selection: $item, matching: .images) {
                                Label("写真を選ぶ", systemImage: "photo.on.rectangle")
                                    .toocFont(.headline)
                            }
                        }
                        if lifting { ProgressView().controlSize(.large) }
                    }
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
                    .animation(.snappy, value: result)
                }
                if base != nil {
                    Section {
                        Toggle("背景を消す", isOn: $removeBackground.animation(.snappy))
                        PhotosPicker(selection: $item, matching: .images) {
                            Label("ほかの写真にする", systemImage: "photo.on.rectangle")
                        }
                    } footer: {
                        if removeBackground && lifted == nil && !lifting {
                            Text("写っているものを見つけられませんでした。背景ごとスタンプになります。")
                        }
                    }
                }
            }
            .navigationTitle("スタンプを作る")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(Color.toocBrand) }
                        .accessibilityLabel("キャンセル")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: save) {
                        if saving { ProgressView() } else { Image(systemName: "checkmark") }
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(result == nil || saving || lifting)
                    .accessibilityLabel("追加")
                }
            }
            .onChange(of: item) { _, item in
                guard let item else { return }
                self.item = nil
                Task {
                    if let data = try? await item.loadTransferable(type: Data.self), let image = UIImage(data: data) {
                        crop = ToocCropRequest(image: image, icon: false)
                    }
                }
            }
            .fullScreenCover(item: $crop) { request in
                ToocCropView(image: request.image, aspect: 1, circle: false) { image in
                    base = image
                    lifted = nil
                    lift(image)
                }
            }
            .alert("作れませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
    }

    private func lift(_ image: UIImage) {
        lifting = true
        Task {
            let cut = await ToocCutout.subject(of: image)
            withAnimation(.snappy) {
                lifted = cut
                lifting = false
            }
        }
    }

    private func save() {
        guard let result else { return }
        saving = true
        Task {
            do {
                try await store.addSticker(result)
                dismiss()
            } catch {
                self.error = ToocServer.describe(error)
            }
            saving = false
        }
    }
}

/// The grey and white squares behind something see-through.
struct ToocCheckerboard: View {
    var body: some View {
        Canvas { context, size in
            let side: CGFloat = 12
            for row in 0..<Int(size.height / side + 1) {
                for column in 0..<Int(size.width / side + 1) where (row + column).isMultiple(of: 2) {
                    context.fill(Path(CGRect(x: CGFloat(column) * side, y: CGFloat(row) * side, width: side, height: side)),
                                 with: .color(Color.gray.opacity(0.18)))
                }
            }
        }
    }
}

/// Lifts what's in a photo off its background (the system's subject cut-out).
enum ToocCutout {
    static func subject(of image: UIImage) async -> UIImage? {
        guard let cgImage = image.cgImage else { return nil }
        return await Task.detached(priority: .userInitiated) { () -> UIImage? in
            let request = VNGenerateForegroundInstanceMaskRequest()
            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
                guard let observation = request.results?.first else { return nil }
                let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler,
                                                                 croppedToInstancesExtent: true)
                let picture = CIImage(cvPixelBuffer: buffer)
                guard let output = CIContext().createCGImage(picture, from: picture.extent) else { return nil }
                return UIImage(cgImage: output)
            } catch {
                return nil
            }
        }.value
    }
}

// MARK: - Forwarding

/// Pick the talks to send a copy of a message to.
struct ToocForwardView: View {
    let message: ToocMessage

    @Environment(ToocStore.self) private var store
    @Environment(\.toocTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var chosen: Set<String> = []

    /// Talks you can write in (not a one-to-one talk with someone who isn't your friend).
    private var rooms: [ToocRoom] {
        store.visibleRooms.filter { room in
            guard !room.isGroup, !room.isMynote, let other = room.memberIDs.first else { return true }
            return store.user(other)?.isFriend == true
        }
    }

    var body: some View {
        NavigationStack {
            List(rooms) { room in
                Button {
                    withAnimation(.snappy) {
                        if chosen.contains(room.id) { chosen.remove(room.id) } else { chosen.insert(room.id) }
                    }
                } label: {
                    HStack(spacing: 12) {
                        ToocAvatar(user: store.iconUser(of: room), size: 40)
                        Text(store.name(of: room))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: chosen.contains(room.id) ? "checkmark.circle.fill" : "circle")
                            .toocFont(.title3)
                            .foregroundStyle(chosen.contains(room.id) ? theme.accent : Color.secondary.opacity(0.5))
                            .contentTransition(.symbolEffect(.replace))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .listRowSeparator(.hidden)
            }
            .listStyle(.plain)
            .safeAreaInset(edge: .top) {
                HStack(spacing: 10) {
                    Image(systemName: message.symbol ?? "text.bubble")
                        .foregroundStyle(theme.accent)
                    Text(message.preview)
                        .lineLimit(2)
                        .toocFont(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .background(theme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
            .navigationTitle(chosen.isEmpty ? "転送" : "\(chosen.count)件に転送")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(Color.toocBrand) }
                        .accessibilityLabel("キャンセル")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        store.forward(message, to: Array(chosen))
                        dismiss()
                    } label: {
                        Image(systemName: "paperplane.fill")
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(chosen.isEmpty)
                    .accessibilityLabel("送信")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sensoryFeedback(.selection, trigger: chosen)
    }
}

// MARK: - Mentions

/// Above the input in a group, while typing @: the members whose name fits, tap one to call them.
struct ToocMentionStrip: View {
    let candidates: [ToocUser]
    var onPick: (ToocUser) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(candidates) { user in
                    Button { onPick(user) } label: {
                        HStack(spacing: 6) {
                            ToocAvatar(user: user, size: 26)
                            Text(user.displayName)
                                .toocFont(.subheadline.weight(.semibold))
                                .lineLimit(1)
                        }
                        .padding(.leading, 4)
                        .padding(.trailing, 12)
                        .padding(.vertical, 4)
                        .glassEffect(.regular.interactive(), in: .capsule)
                    }
                    .buttonStyle(.plain)
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
        }
        .scrollIndicators(.hidden)
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }
}

extension ToocLinks {
    /// The text with its links made tappable and the @names it calls in bold (and in `color`, when given).
    static func attributed(_ text: String, mentions names: [String], color: Color?) -> AttributedString {
        var result = attributed(text)
        for name in Set(names) where !name.isEmpty {
            var searchStart = text.startIndex
            while let range = text.range(of: "@" + name, range: searchStart..<text.endIndex) {
                if let lower = AttributedString.Index(range.lowerBound, within: result),
                   let upper = AttributedString.Index(range.upperBound, within: result) {
                    result[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
                    if let color { result[lower..<upper].foregroundColor = color }
                }
                searchStart = range.upperBound
            }
        }
        return result
    }
}

// MARK: - Switching accounts

/// Over everything while switching: the old account's icon turns over into the new one's, a ring bursts when it's
/// ready, and the whole thing opens up onto the new account.
struct ToocSwitchOverlay: View {
    let from: ToocUser
    let to: ToocAccounts.Saved
    let ready: Bool
    var onMidway: () -> Void
    var onDone: () -> Void

    @Environment(\.toocTheme) private var theme
    @State private var stage = 0

    private static let size: CGFloat = 104

    var body: some View {
        ZStack {
            Rectangle()
                .fill(.ultraThinMaterial)
                .ignoresSafeArea()
            theme.accent.opacity(0.18)
                .ignoresSafeArea()
            VStack(spacing: 14) {
                ZStack {
                    ToocAvatar(user: from, size: Self.size)
                        .rotation3DEffect(.degrees(stage >= 1 ? 90 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                        .opacity(stage >= 1 ? 0 : 1)
                    ToocAvatar(user: to.user, size: Self.size)
                        .rotation3DEffect(.degrees(stage >= 1 ? 0 : -90), axis: (x: 0, y: 1, z: 0), perspective: 0.6)
                        .opacity(stage >= 1 ? 1 : 0)
                }
                .background {
                    Circle()
                        .stroke(theme.accent, lineWidth: 3)
                        .frame(width: Self.size + 14, height: Self.size + 14)
                        .scaleEffect(stage >= 2 ? 2.2 : 1)
                        .opacity(stage >= 2 ? 0 : (stage >= 1 ? 0.9 : 0))
                }
                .scaleEffect(stage == 0 ? 0.82 : 1)
                VStack(spacing: 3) {
                    Text(stage >= 1 ? to.name : from.name)
                        .toocFont(.title3.bold())
                        .contentTransition(.opacity)
                    Text("@\(stage >= 1 ? to.id : from.id)")
                        .toocFont(.subheadline)
                        .foregroundStyle(.secondary)
                        .contentTransition(.opacity)
                }
                ProgressView()
                    .opacity(stage >= 1 && !ready ? 1 : 0)
            }
            .scaleEffect(stage >= 3 ? 1.25 : 1)
        }
        .opacity(stage >= 3 ? 0 : 1)
        .sensoryFeedback(.impact(weight: .medium), trigger: stage) { _, new in new == 1 }
        .sensoryFeedback(.success, trigger: stage) { _, new in new == 2 }
        .task {
            try? await Task.sleep(for: .milliseconds(40))
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { stage = 0 }
            try? await Task.sleep(for: .milliseconds(260))
            withAnimation(.spring(response: 0.5, dampingFraction: 0.78)) { stage = 1 }
            try? await Task.sleep(for: .milliseconds(480))
            if ready { await finish() }
        }
        .onChange(of: ready) { _, ready in
            if ready && stage == 1 { Task { await finish() } }
        }
    }

    private func finish() async {
        guard stage == 1 else { return }
        onMidway()
        withAnimation(.easeOut(duration: 0.45)) { stage = 2 }
        try? await Task.sleep(for: .milliseconds(380))
        withAnimation(.easeIn(duration: 0.32)) { stage = 3 }
        try? await Task.sleep(for: .milliseconds(340))
        onDone()
    }
}
