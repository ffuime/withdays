import Foundation
import UIKit
import UserNotifications

/// tooc's notifications, kept on this device until there is a server: each reply is booked with the system for the
/// moment it's due, so it arrives even with tooc in the background. Tapping one opens its talk.
enum ToocNotifications {
    static let openRoom = Notification.Name("toocOpenRoom")

    @MainActor private static var pendingRoom: String?

    static func requestAuthorization() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    static func schedule(id: String, title: String, body: String, roomID: String, at date: Date) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.threadIdentifier = roomID
        content.userInfo = ["toocRoom": roomID]
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: max(1, date.timeIntervalSinceNow), repeats: false)
        UNUserNotificationCenter.current().add(UNNotificationRequest(identifier: id, content: content, trigger: trigger))
    }

    static func cancel(_ id: String) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [id])
        center.removeDeliveredNotifications(withIdentifiers: [id])
    }

    /// Asks the open tooc (or the next one to open) to show this talk.
    @MainActor
    static func open(_ room: String) {
        pendingRoom = room
        NotificationCenter.default.post(name: openRoom, object: nil)
    }

    @MainActor
    static func takePendingRoom() -> String? {
        defer { pendingRoom = nil }
        return pendingRoom
    }

    @MainActor private static var pendingFriend: String?

    /// From a link (ffui.me/tooc/@ID): open tooc's search with that ID.
    @MainActor
    static func find(_ id: String) {
        pendingFriend = id
        NotificationCenter.default.post(name: openRoom, object: nil)
    }

    @MainActor
    static func takePendingFriend() -> String? {
        defer { pendingFriend = nil }
        return pendingFriend
    }
}

/// Lets tooc's own banner speak while the app is in front, and opens the talk when a notification is tapped.
/// Other notifications behave as before.
final class ToocNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = ToocNotificationDelegate()

    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([])
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                withCompletionHandler completionHandler: @escaping () -> Void) {
        defer { completionHandler() }
        guard let room = response.notification.request.content.userInfo["toocRoom"] as? String else { return }
        var components = URLComponents()
        components.scheme = "withdays"
        components.host = "tooc"
        components.queryItems = [URLQueryItem(name: "room", value: room)]
        guard let url = components.url else { return }
        DispatchQueue.main.async { UIApplication.shared.open(url) }
    }
}
