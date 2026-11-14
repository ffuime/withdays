import SlidesFeature
import SwiftUI
import UIKit

/// Only for the screen's orientation: portrait, except while Slides plays.
final class WithDaysAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        SlidesFonts.registerImportedFonts()
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        SlidesOrientation.supported
    }
}

@main
struct WithDaysApp: App {
    @UIApplicationDelegateAdaptor(WithDaysAppDelegate.self) private var appDelegate
    @State private var store = CalendarStore()
    @State private var templates = TemplateStore()
    @State private var todos = TodoStore()
    @State private var toasts = ToastCenter()
    @State private var go = GoStore()
    @State private var mo = MoStore()
    @State private var notes = NotesStore()
    @AppStorage(SettingsKey.theme, store: AppGroup.defaults) private var theme = AppTheme.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .environment(templates)
                .environment(todos)
                .environment(toasts)
                .environment(go)
                .environment(mo)
                .environment(notes)
                .tint(.brand)
                .preferredColorScheme((AppTheme(rawValue: theme) ?? .system).colorScheme)
        }
    }
}

struct RootView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.scenePhase) private var scenePhase
    @State private var board = Springboard()

    var body: some View {
        Group {
            switch store.access {
            case .granted:
                LauncherView(board: board)
            case .undetermined:
                Color(.systemBackground)
                    .ignoresSafeArea()
                    .task { await store.requestAccess() }
            case .denied:
                AccessDeniedView()
            }
        }
        // While an app is open, a swipe up from the bottom edge goes to our home screen; the system's needs a second
        // swipe. Set here at the root, where the system reads it.
        .defersSystemGestures(on: board.openApp != nil ? .bottom : [])
        .persistentSystemOverlays(board.openApp != nil ? .hidden : .automatic)
        .onChange(of: scenePhase) { _, phase in
            // Access may have been granted in the Settings app while we were away.
            if phase == .active { store.refreshStatus() }
        }
    }
}

struct AccessDeniedView: View {
    var body: some View {
        ContentUnavailableView {
            Label("カレンダーへのアクセスが必要です", systemImage: "calendar.badge.exclamationmark")
        } description: {
            Text("WithDays は Appleのカレンダーの予定をそのまま表示・編集します。設定で「カレンダー」を「フルアクセス」にしてください。")
        } actions: {
            Button("設定を開く") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.glassProminent)
        }
    }
}
