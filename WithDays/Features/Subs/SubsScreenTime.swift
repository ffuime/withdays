import DeviceActivity
import FamilyControls
import ManagedSettings
import SwiftUI

/// Screen Time: picking the app a subscription belongs to, its icon, and this month's use.
/// iOS only lets the report extension see the time, so the app shows the report's view as it is.
@MainActor
enum SubsScreenTime {
    static var approved: Bool {
        AuthorizationCenter.shared.authorizationStatus == .approved
    }

    static func authorize() async throws {
        if approved { return }
        try await AuthorizationCenter.shared.requestAuthorization(for: .individual)
    }

    private static var cache: [Data: ApplicationToken] = [:]

    static func token(_ data: Data?) -> ApplicationToken? {
        guard let data else { return nil }
        if let token = cache[data] { return token }
        guard let token = try? JSONDecoder().decode(ApplicationToken.self, from: data) else { return nil }
        cache[data] = token
        return token
    }

    static func encode(_ token: ApplicationToken?) -> Data? {
        guard let token else { return nil }
        return try? JSONEncoder().encode(token)
    }
}

enum SubsUsageShare {
    /// Leaves each linked subscription's monthly price for the report.
    static func publish(_ subs: [Sub]) {
        var prices: [String: Int] = [:]
        for sub in subs {
            if let token = sub.appToken { prices[SubsUsageKeys.key(token)] = Int(sub.monthly.rounded()) }
        }
        AppGroup.defaults.set(prices, forKey: SubsUsageKeys.prices)
    }
}

/// The app's own icon, from Screen Time.
struct SubsAppIcon: View {
    let token: ApplicationToken
    let size: CGFloat

    var body: some View {
        Label(token)
            .labelStyle(.iconOnly)
            // The icon comes at its own size; scaled to fit.
            .scaleEffect(size / 30)
            .frame(width: size, height: size)
    }
}

/// 今月の利用時間 and ¥/h, drawn by the report extension.
struct SubsUsageReport: View {
    let token: ApplicationToken
    let monthlyYen: Int

    var body: some View {
        let start = CalendarMath.startOfMonth(.now)
        let filter = DeviceActivityFilter(
            segment: .daily(during: DateInterval(start: start, end: max(Date.now, start.addingTimeInterval(60)))),
            users: .all,
            devices: .init([.iPhone]),
            applications: [token]
        )
        DeviceActivityReport(.subsUsage, filter: filter)
            .frame(height: 64)
            .onAppear { AppGroup.defaults.set(monthlyYen, forKey: SubsUsageKeys.current) }
    }
}
