import FirebaseAuth
import FirebaseCore
import SwiftUI
import UIKit
import UserNotifications

/// What Firebase needs from the tooc app (the same as inside WithDays): its settings, the push token, the phone
/// check's silent push and its reCAPTCHA link. Notifications open their talk when tapped.
final class ToocAppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            FirebaseApp.configure()
            application.registerForRemoteNotifications()
        }
        UNUserNotificationCenter.current().delegate = ToocNotificationDelegate.shared
        return true
    }

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

/// tooc as an app of its own: the talk list opens straight away (no calendar to go back to).
@main
struct ToocApp: App {
    @UIApplicationDelegateAdaptor(ToocAppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup {
            ToocRootView()
                .background(Color(uiColor: .systemBackground))
                // tooc://room?id=… opens a talk; tooc://@ID (or tooc://find?id=…) looks someone up.
                .onOpenURL { url in
                    guard url.scheme == "tooc" else { return }
                    let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
                    let id = items.first { $0.name == "id" }?.value
                    if url.host == "room", let id {
                        ToocNotifications.open(id)
                    } else if let host = url.host, host.hasPrefix("@") {
                        ToocNotifications.find(String(host.dropFirst()))
                    } else if url.host == "find", let id {
                        ToocNotifications.find(id)
                    }
                }
        }
    }
}
