import FirebaseAuth
import FirebaseCore
import MediaPlayer
import SlidesFeature
import SwiftUI
import UIKit
import UserNotifications

/// The screen's orientation (portrait, except while Slides plays), and what Firebase's phone check needs from the app.
final class WithDaysAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        SlidesFonts.registerImportedFonts()
        // tooc's server: only when the build carries Firebase's settings.
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
            // The phone check first tries a silent push; without one it falls back to reCAPTCHA.
            application.registerForRemoteNotifications()
        }
        // tooc's notifications open their talk when tapped.
        UNUserNotificationCenter.current().delegate = ToocNotificationDelegate.shared
        return true
    }

    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        SlidesOrientation.supported
    }

    // MARK: Firebase phone check
    // SwiftUI's app delegate isn't swizzled by Firebase, so the push token, the check's silent push and its
    // reCAPTCHA link are handed over here (Firebase refuses to send the code otherwise).

    private var firebase: Bool { FirebaseApp.app() != nil }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        guard firebase else { return }
        Auth.auth().setAPNSToken(deviceToken, type: .unknown)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {}

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any],
                     fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        if firebase, Auth.auth().canHandleNotification(userInfo) {
            completionHandler(.noData)
            return
        }
        completionHandler(.noData)
    }

    func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey: Any] = [:]) -> Bool {
        firebase && Auth.auth().canHandle(url)
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

    var body: some View {
        Group {
            switch store.access {
            case .granted:
                HomeView()
            case .undetermined:
                Color(.systemBackground)
                    .ignoresSafeArea()
                    .task { await store.requestAccess() }
            case .denied:
                AccessDeniedView()
            }
        }
        // First launch: after the calendar question, ask for the music library (Go shows what's playing).
        .task(id: store.access == .undetermined) {
            guard store.access != .undetermined, MPMediaLibrary.authorizationStatus() == .notDetermined else { return }
            MPMediaLibrary.requestAuthorization { _ in }
        }
        .onChange(of: scenePhase) { _, phase in
            // Access may have been granted in the Settings app while we were away.
            if phase == .active { store.refreshStatus() }
        }
        // Keykie's trending words, on the interval set in its settings.
        .task {
            if KeykieDictionary.trendingIsDue { try? await KeykieDictionary.updateTrending() }
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
