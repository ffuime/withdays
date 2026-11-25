import SwiftUI
import UIKit

struct ToocMenuItem {
    let title: String
    let symbol: String
    var destructive = false
    let action: () -> Void
}

/// Hosts a row with the system's long-press menu, built in UIKit so the preview can be anything and a tap on the
/// preview opens it (SwiftUI's own context menu can't do the latter).
struct ToocContextMenuHost<Content: View, Preview: View>: UIViewControllerRepresentable {
    var enabled: Bool
    var items: [ToocMenuItem]
    var onOpen: () -> Void
    var preview: () -> Preview
    var content: Content
    /// Light or dark as around it (the row is drawn in a host of its own, which doesn't follow by itself).
    var scheme: ColorScheme = .light

    func makeUIViewController(context: Context) -> UIHostingController<Content> {
        let host = UIHostingController(rootView: content)
        host.overrideUserInterfaceStyle = scheme == .dark ? .dark : .light
        host.view.backgroundColor = .clear
        host.view.addInteraction(UIContextMenuInteraction(delegate: context.coordinator))
        return host
    }

    func updateUIViewController(_ host: UIHostingController<Content>, context: Context) {
        let style: UIUserInterfaceStyle = scheme == .dark ? .dark : .light
        if host.overrideUserInterfaceStyle != style { host.overrideUserInterfaceStyle = style }
        host.rootView = content
        context.coordinator.parent = self
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    @MainActor
    final class Coordinator: NSObject, UIContextMenuInteractionDelegate {
        var parent: ToocContextMenuHost

        init(_ parent: ToocContextMenuHost) { self.parent = parent }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            guard parent.enabled else { return nil }
            let parent = self.parent
            return UIContextMenuConfiguration(identifier: nil, previewProvider: {
                let host = UIHostingController(rootView: parent.preview())
                host.overrideUserInterfaceStyle = parent.scheme == .dark ? .dark : .light
                host.preferredContentSize = CGSize(width: 340, height: 460)
                return host
            }, actionProvider: { _ in
                UIMenu(children: parent.items.map { item in
                    UIAction(title: item.title, image: UIImage(systemName: item.symbol)?
                        .withTintColor(item.destructive ? .systemRed : .label, renderingMode: .alwaysOriginal),
                             attributes: item.destructive ? .destructive : []) { _ in item.action() }
                })
            })
        }

        /// A tap on the preview opens what it shows.
        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    willPerformPreviewActionForMenuWith configuration: UIContextMenuConfiguration,
                                    animator: UIContextMenuInteractionCommitAnimating) {
            let open = parent.onOpen
            animator.preferredCommitStyle = .dismiss
            animator.addCompletion { open() }
        }
    }
}

/// A peek at a room (from a long press): its latest messages drawn just as in the talk — photos, polls, あみだくじ
/// and all — without marking them read.
struct ToocRoomPreview: View {
    let room: ToocRoom
    @Environment(ToocStore.self) private var store
    @Environment(\.toocTheme) private var theme

    private struct Item: Identifiable {
        let message: ToocMessage
        let first: Bool
        let last: Bool
        let joinedAbove: Bool
        let joinedBelow: Bool
        var id: UUID { message.id }
    }

    private var items: [Item] {
        let list = Array(room.sent.suffix(20))
        return list.indices.map { index in
            let message = list[index]
            let previous = index > 0 ? list[index - 1] : nil
            let next = index < list.count - 1 ? list[index + 1] : nil
            let first = previous.map { !ToocRoomView.sameBurst($0, message) } ?? true
            let last = next.map { !ToocRoomView.sameBurst(message, $0) } ?? true
            return Item(message: message, first: first, last: last,
                        joinedAbove: !first && message.isText && (previous?.isText ?? false),
                        joinedBelow: !last && message.isText && (next?.isText ?? false))
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                ToocAvatar(user: store.iconUser(of: room), size: 32)
                Text(store.name(of: room))
                    .toocFont(.headline)
                    .lineLimit(1)
            }
            .padding(14)
            Divider()
            if room.sent.isEmpty {
                ToocStartTalkText(size: 15)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(items) { item in
                            ToocMessageRow(
                                message: item.message,
                                room: room,
                                first: item.first,
                                last: item.last,
                                joinedAbove: item.joinedAbove,
                                joinedBelow: item.joinedBelow,
                                textSize: store.settings.textPoints * 0.9,
                                actions: .none
                            )
                            .padding(.top, item.first ? 8 : 0)
                        }
                    }
                    .padding(10)
                }
                .defaultScrollAnchor(.bottom)
                .allowsHitTesting(false)
            }
        }
        .frame(width: 340, height: 460)
        .background(theme.fill)
    }
}

/// Watches tooc's tab bar for a long press or a double tap on a tab (the system's tab bar offers neither).
struct ToocTabBarHook: UIViewControllerRepresentable {

    var onLongPress: (Int) -> Void
    var onDoubleTap: (Int) -> Void

    func makeUIViewController(context: Context) -> HookController {
        let controller = HookController()
        controller.coordinator = context.coordinator
        return controller
    }

    func updateUIViewController(_ controller: HookController, context: Context) {
        context.coordinator.parent = self

    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class HookController: UIViewController {
        weak var coordinator: Coordinator?

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            coordinator?.attach(from: self)
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var parent: ToocTabBarHook
        private weak var tabBar: UITabBar?

        init(_ parent: ToocTabBarHook) { self.parent = parent }

        func attach(from controller: UIViewController) {
            var current: UIViewController? = controller
            while let next = current, !(next is UITabBarController) { current = next.parent }
            guard let bar = (current as? UITabBarController)?.tabBar, bar !== tabBar else { return }
            tabBar = bar
            let press = UILongPressGestureRecognizer(target: self, action: #selector(pressed(_:)))
            press.minimumPressDuration = 0.45
            press.cancelsTouchesInView = false
            press.delegate = self
            let double = UITapGestureRecognizer(target: self, action: #selector(tapped(_:)))
            double.numberOfTapsRequired = 2
            double.cancelsTouchesInView = false
            double.delaysTouchesEnded = false
            double.delegate = self
            bar.addGestureRecognizer(press)
            bar.addGestureRecognizer(double)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        @objc private func pressed(_ recognizer: UILongPressGestureRecognizer) {
            guard recognizer.state == .began else { return }
            parent.onLongPress(index(recognizer))
        }

        @objc private func tapped(_ recognizer: UITapGestureRecognizer) {
            parent.onDoubleTap(index(recognizer))
        }

        /// Which of the two tabs (トーク, じぶん) the finger is on: by the tab buttons when they can be found, else by halves.
        private func index(_ recognizer: UIGestureRecognizer) -> Int {
            guard let bar = tabBar else { return 0 }
            let point = recognizer.location(in: bar)
            var buttons: [UIView] = []
            func collect(_ view: UIView) {
                let name = String(describing: type(of: view))
                if name.contains("TabBarButton") || name.contains("TabButton") { buttons.append(view) }
                view.subviews.forEach(collect)
            }
            collect(bar)
            let centers = buttons.map { $0.convert(CGPoint(x: $0.bounds.midX, y: $0.bounds.midY), to: bar).x }.sorted()
            if centers.count == Self.tabCount {
                return centers.indices.min { abs(centers[$0] - point.x) < abs(centers[$1] - point.x) } ?? 0
            }
            let count = CGFloat(Self.tabCount)
            return min(Self.tabCount - 1, max(0, Int(point.x / max(1, bar.bounds.width / count))))
        }

        private static let tabCount = 2
    }
}
