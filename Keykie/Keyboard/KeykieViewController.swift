import SwiftUI
import UIKit

/// Keykie's keyboard: a SwiftUI board inside the input view.
final class KeykieViewController: UIInputViewController {
    private let state = KeykieState()
    private var host: UIHostingController<AnyView>?
    private var heightConstraint: NSLayoutConstraint?

    override func viewDidLoad() {
        super.viewDidLoad()
        state.controller = self
        let host = UIHostingController(rootView: AnyView(KeykieRootView().environment(state)))
        host.view.backgroundColor = .clear
        host.view.translatesAutoresizingMaskIntoConstraints = false
        addChild(host)
        view.addSubview(host.view)
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
        host.didMove(toParent: self)
        self.host = host

        // Coming back to the app the keyboard is in: look at the pasteboard again.
        NotificationCenter.default.addObserver(self, selector: #selector(hostWillEnterForeground),
                                               name: .NSExtensionHostWillEnterForeground, object: nil)
    }

    @objc private func hostWillEnterForeground() {
        state.appeared()
        updateHeight()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        state.appeared()
        updateHeight()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        state.disappeared()
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        updateAppearance()
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        state.refreshContext()
        updateAppearance()
    }

    private func updateAppearance() {
        let dark: Bool
        switch state.settings.appearance {
        case 1: dark = false
        case 2: dark = true
        default: dark = textDocumentProxy.keyboardAppearance == .dark || traitCollection.userInterfaceStyle == .dark
        }
        if state.dark != dark { state.dark = dark }
    }

    private func updateHeight() {
        updateAppearance()
        let height = state.settings.totalHeight
        if let heightConstraint {
            heightConstraint.constant = height
        } else {
            let constraint = view.heightAnchor.constraint(equalToConstant: height)
            constraint.priority = UILayoutPriority(999)
            constraint.isActive = true
            heightConstraint = constraint
        }
    }
}
