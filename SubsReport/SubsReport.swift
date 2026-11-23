import DeviceActivity
import ManagedSettings
import SwiftUI

/// Subscribes' Screen Time report: this month's time in the subscription's app, and what an hour of it costs.
@main
struct SubsReportExtension: DeviceActivityReportExtension {
    var body: some DeviceActivityReportScene {
        SubsUsageScene { SubsUsageView(usage: $0) }
    }
}

struct SubsUsage {
    var seconds: TimeInterval
    var monthlyYen: Int?
}

struct SubsUsageScene: DeviceActivityReportScene {
    let context: DeviceActivityReport.Context = .subsUsage
    let content: (SubsUsage) -> SubsUsageView

    func makeConfiguration(representing data: DeviceActivityResults<DeviceActivityData>) async -> SubsUsage {
        let prices = AppGroup.defaults.dictionary(forKey: SubsUsageKeys.prices) as? [String: Int] ?? [:]
        var seconds: TimeInterval = 0
        var price: Int?
        for await item in data {
            for await segment in item.activitySegments {
                for await category in segment.categories {
                    for await app in category.applications {
                        seconds += app.totalActivityDuration
                        if price == nil, let token = app.application.token, let encoded = try? JSONEncoder().encode(token) {
                            price = prices[SubsUsageKeys.key(encoded)]
                        }
                    }
                }
            }
        }
        if price == nil {
            price = AppGroup.defaults.object(forKey: SubsUsageKeys.current) as? Int
        }
        return SubsUsage(seconds: seconds, monthlyYen: price)
    }
}

struct SubsUsageView: View {
    let usage: SubsUsage

    private var hours: Double { usage.seconds / 3600 }

    var body: some View {
        HStack(alignment: .lastTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text("利用時間")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.secondary)
                HStack(alignment: .firstTextBaseline, spacing: 2) {
                    Text(String(format: "%.1f", hours))
                        .font(.system(size: 30, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("時間")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 8)
            if let price = usage.monthlyYen {
                HStack(alignment: .firstTextBaseline, spacing: 1) {
                    Text(hours >= 0.05 ? Self.yen(Double(price) / hours) : "—")
                        .font(.system(size: 20, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("/h")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    private static func yen(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.groupingSeparator = ","
        return "¥" + (formatter.string(from: NSNumber(value: Int(value.rounded()))) ?? "\(Int(value))")
    }
}
