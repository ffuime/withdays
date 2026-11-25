import SwiftUI

/// アカウントを削除: what goes, then your toocID typed to be sure. Once deleted, your icon breaks up into pieces
/// that drift away, and tooc settles back on the sign-in form.
struct ToocDeleteAccountView: View {
    @Environment(ToocStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var typed = ""
    @State private var deleting = false
    @State private var error: String?
    /// The goodbye: 0 whole, 1 gone.
    @State private var progress: CGFloat = 0
    @FocusState private var focused: Bool

    private var matches: Bool {
        typed.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "@"))
            .lowercased() == store.me.id.lowercased()
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    ToocDissolvingAvatar(user: store.me, progress: progress)
                        .frame(width: 120, height: 120)
                        .padding(.top, 24)
                    VStack(spacing: 6) {
                        Text("アカウントを削除")
                            .toocFont(.title2.bold())
                        Text("友だち・トーク・写真・スタンプがすべて消え、元に戻せません。")
                            .toocFont(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .opacity(Double(1 - progress))
                    VStack(alignment: .leading, spacing: 8) {
                        Text("確認のため、toocID（@\(store.me.id)）を入力してください。")
                            .toocFont(.footnote)
                            .foregroundStyle(.secondary)
                        TextField("@\(store.me.id)", text: $typed)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($focused)
                            .padding(14)
                            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .strokeBorder(matches ? Color.red : Color.clear, lineWidth: 1.5)
                            }
                    }
                    .opacity(Double(1 - progress))
                    Button(role: .destructive) {
                        delete()
                    } label: {
                        Group {
                            if deleting { ProgressView().tint(.white) } else { Text("削除する") }
                        }
                        .toocFont(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                    .disabled(!matches || deleting)
                    .opacity(Double(1 - progress))
                }
                .padding(.horizontal, 24)
            }
            .scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(.primary) }
                        .accessibilityLabel("キャンセル")
                        .disabled(deleting)
                }
            }
            .alert("削除できませんでした", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(error ?? "")
            }
        }
        .interactiveDismissDisabled(deleting)
        .sensoryFeedback(.warning, trigger: deleting)
        .onAppear { focused = true }
    }

    private func delete() {
        focused = false
        deleting = true
        Task {
            do {
                try await store.deleteAccount(leave: false)
            } catch {
                deleting = false
                self.error = (error as? ToocError)?.message ?? error.localizedDescription
                return
            }
            // Gone on the server: the icon breaks up and drifts off, then back to the sign-in form.
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            withAnimation(.easeIn(duration: 1.3)) { progress = 1 }
            try? await Task.sleep(for: .seconds(1.4))
            dismiss()
            try? await Task.sleep(for: .milliseconds(300))
            store.leaveDeleted()
        }
    }
}

/// The icon cut into a grid of pieces that fly apart, spin and fade as `progress` goes from 0 to 1.
struct ToocDissolvingAvatar: View, Animatable {
    let user: ToocUser
    var progress: CGFloat

    var animatableData: CGFloat {
        get { progress }
        set { progress = newValue }
    }

    private static let grid = 8

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size.width
            let side = size / CGFloat(Self.grid)
            ZStack(alignment: .topLeading) {
                ForEach(0..<(Self.grid * Self.grid), id: \.self) { index in
                    piece(index, side: side, size: size)
                }
            }
            .frame(width: size, height: size, alignment: .topLeading)
            // Round at first; once breaking up, the pieces are free of the circle.
            .mask { Circle().scale(1 + progress * 6) }
        }
        .accessibilityHidden(true)
    }

    private func piece(_ index: Int, side: CGFloat, size: CGFloat) -> some View {
        let row = CGFloat(index / Self.grid)
        let column = CGFloat(index % Self.grid)
        // Each piece leaves a little after the one to its left, so the icon peels off sideways.
        let start: CGFloat = column / CGFloat(Self.grid) * 0.5
        let local: CGFloat = min(1, max(0, (progress - start) / 0.5))
        let drift = Self.random(index)
        let dx: CGFloat = local * (80 + drift.x * 120)
        let dy: CGFloat = local * (-60 + drift.y * 140)
        return ToocIconImage(user: user)
            .frame(width: size, height: size)
            .offset(x: -column * side, y: -row * side)
            .frame(width: side, height: side, alignment: .topLeading)
            .clipped()
            .rotationEffect(.degrees(Double(local * drift.spin * 180)))
            .scaleEffect(1 - local * 0.6)
            .opacity(Double(1 - local))
            .offset(x: column * side + dx, y: row * side + dy)
    }

    /// The same scatter for a piece every time.
    private static func random(_ index: Int) -> (x: CGFloat, y: CGFloat, spin: CGFloat) {
        var seed = UInt64(index + 1) &* 6364136223846793005 &+ 1442695040888963407
        func next() -> CGFloat {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return CGFloat(Double(seed >> 11) / 9_007_199_254_740_992)
        }
        let x = next()
        let y = next()
        let spin = next() * 2 - 1
        return (x, y, spin)
    }
}
