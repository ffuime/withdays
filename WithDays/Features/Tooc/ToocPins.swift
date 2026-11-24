import SwiftUI

/// ピン留め, floating at the top of the talk: the newest pin (two lines at most, the sender's name under it), and
/// ⌄ at the right for all of them. Tap a pin to go to its message; swipe one left to unpin it; under the list,
/// すべてのピン留めを解除.
struct ToocPinBar: View {
    let room: ToocRoom
    var onJump: (UUID) -> Void

    @Environment(ToocStore.self) private var store
    @Environment(\.toocTheme) private var theme
    @State private var expanded = false
    @State private var confirmAll = false

    var body: some View {
        let pins = room.pinnedMessages
        VStack(spacing: 0) {
            if let newest = pins.first {
                HStack(spacing: 0) {
                    row(newest)
                    Button {
                        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) { expanded.toggle() }
                    } label: {
                        Image(systemName: "chevron.down")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(Color.toocBrand)
                            .rotationEffect(.degrees(expanded ? 180 : 0))
                            .frame(width: 44, height: 44)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(expanded ? "ピン留めを閉じる" : "すべてのピン留め（\(pins.count)件）")
                }
            }
            if expanded {
                ForEach(pins.dropFirst()) { pin in
                    Divider().padding(.leading, 44)
                    row(pin)
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                Divider()
                Button(role: .destructive) {
                    confirmAll = true
                } label: {
                    Label("すべてのピン留めを解除", systemImage: "pin.slash")
                        .toocFont(.subheadline.weight(.semibold))
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .padding(.leading, 4)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
        .padding(.horizontal, 12)
        .padding(.top, 4)
        .padding(.bottom, 6)
        .onChange(of: pins.count) { _, count in if count <= 1 { withAnimation(.snappy) { expanded = false } } }
        .alert("すべてのピン留めを解除しますか？", isPresented: $confirmAll) {
            Button("キャンセル", role: .cancel) {}
            Button("解除", role: .destructive) {
                withAnimation(.snappy) {
                    expanded = false
                    store.unpinAll(in: room.id)
                }
            }
        } message: {
            Text("トークの全員の画面から外れます。")
        }
    }

    /// One pin: the words (two lines at most) with the sender's name under them, small.
    private func row(_ pin: ToocPin) -> some View {
        ToocSwipeToUnpin {
            withAnimation(.snappy) { store.unpin(pin.messageID, in: room.id) }
        } content: {
            Button {
                withAnimation(.snappy) { expanded = false }
                onJump(pin.messageID)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "pin.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.toocBrand)
                        .rotationEffect(.degrees(35))
                        .frame(width: 30)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(pin.text)
                            .toocFont(.subheadline)
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)
                        Text(store.displayName(pin.senderID))
                            .toocFont(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 9)
                .padding(.trailing, 8)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }
}

/// A row that slides left to show a red unpin mark; let go far enough and it's unpinned.
struct ToocSwipeToUnpin<Content: View>: View {
    var onUnpin: () -> Void
    @ViewBuilder var content: () -> Content

    @State private var offset: CGFloat = 0
    @State private var armed = false

    private static var threshold: CGFloat { 90 }

    var body: some View {
        content()
            .offset(x: offset)
            .background(alignment: .trailing) {
                Image(systemName: "pin.slash.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: max(0, -offset), alignment: .center)
                    .frame(maxHeight: .infinity)
                    .background(Color.red.opacity(armed ? 1 : 0.75))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .opacity(offset < -8 ? 1 : 0)
            }
            .simultaneousGesture(
                DragGesture(minimumDistance: 18)
                    .onChanged { value in
                        guard abs(value.translation.width) > abs(value.translation.height) else { return }
                        offset = min(0, value.translation.width)
                        armed = offset < -Self.threshold
                    }
                    .onEnded { _ in
                        if armed {
                            withAnimation(.snappy) { offset = -400 }
                            onUnpin()
                        }
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                            offset = 0
                            armed = false
                        }
                    }
            )
            .sensoryFeedback(.impact(weight: .light), trigger: armed) { _, new in new }
            .accessibilityAction(named: "ピン留めを解除", onUnpin)
    }
}
