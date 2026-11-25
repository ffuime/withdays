import SwiftUI

/// Holder: one photo, full screen, with no buttons at all. Holding the screen opens its sheet (back to Gallery, settings).
struct HolderView: View {
    var onGallery: () -> Void

    @State private var store = GalleryStore.shared
    @State private var image: UIImage?
    @State private var showSettings = false

    private var settings: HolderSettings { store.holder }
    private var item: GalleryItem? { store.holderItem }

    var body: some View {
        ZStack {
            background
            if let image {
                GalleryZoomableImage(image: image, zoomEnabled: settings.zoom, onLongPress: openSettings)
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "rectangle.portrait.on.rectangle.portrait")
                        .font(.system(size: 40, weight: .semibold))
                    Text("長押しして写真を選ぶ")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onLongPressGesture(minimumDuration: 0.5, perform: openSettings)
            }
        }
        .ignoresSafeArea()
        .statusBarHidden(!settings.statusBar)
        .persistentSystemOverlays(.hidden)
        .task(id: item?.file) {
            if let item { image = await GalleryImages.display(item) } else { image = nil }
        }
        .onAppear { UIApplication.shared.isIdleTimerDisabled = !settings.autoSleep }
        .onChange(of: settings.autoSleep) { _, on in UIApplication.shared.isIdleTimerDisabled = !on }
        .onDisappear { UIApplication.shared.isIdleTimerDisabled = false }
        .sheet(isPresented: $showSettings) {
            HolderSettingsSheet {
                showSettings = false
                Task {
                    try? await Task.sleep(for: .milliseconds(350))
                    onGallery()
                }
            }
            .environment(store)
            .presentationDetents([.large])
        }
    }

    /// A firm tap under the finger, and the settings straight up full height.
    private func openSettings() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        showSettings = true
    }

    /// Around the photo.
    @ViewBuilder
    private var background: some View {
        switch settings.background {
        case .white: Color.white
        case .black: Color.black
        case .gray: Color(white: 0.5)
        case .lightBlur, .darkBlur:
            ZStack {
                if let image {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                        .blur(radius: 50)
                        .clipped()
                }
                settings.background == .lightBlur ? Color.white.opacity(0.45) : Color.black.opacity(0.5)
            }
            .background(settings.background == .lightBlur ? Color.white : Color.black)
        }
    }
}

/// Holder's sheet: back to Gallery, the photo and how it's shown.
struct HolderSettingsSheet: View {
    var onGallery: () -> Void

    @Environment(GalleryStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var choosing = false

    var body: some View {
        @Bindable var store = store
        return NavigationStack {
            Form {
                Section {
                    Button(action: onGallery) {
                        Label("Galleryに戻る", systemImage: "photo.on.rectangle")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                Section("写真") {
                    Button {
                        choosing = true
                    } label: {
                        HStack(spacing: 14) {
                            Group {
                                if let item = store.holderItem {
                                    GalleryThumb(item: item)
                                } else {
                                    Image(systemName: "photo")
                                        .foregroundStyle(.secondary)
                                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                                        .background(Color(.tertiarySystemFill))
                                }
                            }
                            .frame(width: 52, height: 52)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            Text(store.holder.item == nil ? "写真を選ぶ" : "写真を変更")
                                .font(.system(size: 16, weight: .semibold))
                        }
                    }
                }
                Section {
                    Toggle("ステータスバーを表示", isOn: $store.holder.statusBar)
                    Toggle("ズームを許可", isOn: $store.holder.zoom)
                    Picker("写真の背景色", selection: $store.holder.background) {
                        ForEach(HolderBackground.allCases) { background in
                            Text(background.label).tag(background)
                        }
                    }
                    Toggle("自動スリープ", isOn: $store.holder.autoSleep)
                } header: {
                    Text("表示")
                } footer: {
                    Text("自動スリープをオフにすると、Holderを表示している間は画面が消えません。")
                }
            }
            .navigationTitle("Holder")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button { dismiss() } label: { Image(systemName: "checkmark") }
                        .accessibilityLabel("閉じる")
                }
            }
        }
        .sheet(isPresented: $choosing) {
            GalleryItemPicker(title: "Holderの写真", items: store.pickable(photosOnly: true)) { item in
                store.holder.item = item.id
            }
        }
    }
}
