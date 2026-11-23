import DeviceActivity
import Foundation
import SwiftUI

/// Shared by the app and its Screen Time report: the report can't send numbers back to the app,
/// so the app leaves each subscription's monthly price where the report can read it.
extension DeviceActivityReport.Context {
    static let subsUsage = Self("subsUsage")
}

enum SubsUsageKeys {
    /// [encoded ApplicationToken (base64): monthly price in yen]
    static let prices = "subsUsagePrices"
    /// The price of the subscription on screen, in case the token's encoding doesn't match.
    static let current = "subsUsageCurrent"

    static func key(_ token: Data) -> String {
        token.base64EncodedString()
    }
}
