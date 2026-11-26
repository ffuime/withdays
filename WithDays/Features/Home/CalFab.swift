import SwiftUI

/// Cal's ＋. A tap adds an event; holding it opens the list of services (ServicePicker), which grows out of ＋.
struct CalFab: View {
    let icon: String
    /// The same size as the other bottom button (a glass button's circle), measured by the caller.
    let size: CGFloat
    /// Off while moving / duplicating, when ＋ is the confirm button.
    let menuEnabled: Bool
    let disabled: Bool
    /// Where the service list zooms out of.
    let zoom: Namespace.ID
    var onTap: () -> Void
    var onOpenMenu: () -> Void

    @State private var held = 0

    static let zoomID = "calFab"

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: 26.4, weight: .semibold))
            .foregroundStyle(.white)
            .contentTransition(.symbolEffect(.replace))
            .frame(width: size, height: size)
            .glassEffect(.regular.tint(Color.brand).interactive(), in: .circle)
            .contentShape(Circle())
            .matchedTransitionSource(id: Self.zoomID, in: zoom)
            .opacity(disabled ? 0.5 : 1)
            .onTapGesture {
                if !disabled { onTap() }
            }
            .onLongPressGesture(minimumDuration: 0.45) {
                guard menuEnabled else { return }
                held += 1
                onOpenMenu()
            }
            .sensoryFeedback(.impact(weight: .medium), trigger: held)
            .padding(20)
            .accessibilityAction(named: "サービスを開く") {
                if menuEnabled { onOpenMenu() }
            }
    }
}
