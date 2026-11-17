import SwiftUI
import UIKit

extension UIColor {
    convenience init(hex: UInt32) {
        self.init(
            red: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }

    /// Light and dark variants in one dynamic color.
    convenience init(light: UInt32, dark: UInt32) {
        self.init { $0.userInterfaceStyle == .dark ? UIColor(hex: dark) : UIColor(hex: light) }
    }
}

extension Color {
    static let brand = Color(uiColor: UIColor(light: 0x065A8C, dark: 0x54A0CC))
    static let saturday = Color(uiColor: UIColor(light: 0x1F5FD1, dark: 0x6EA2FF))
    static let holiday = Color(uiColor: UIColor(light: 0xD12F2F, dark: 0xFF6B6B))
    static let dayLine = Color(uiColor: .systemGray4)
    static let dayLineSelected = Color(uiColor: UIColor(light: 0x3A3A3C, dark: 0xD1D1D6))

    /// Color for a day number: Sunday and holidays red, Saturday blue.
    static func dayNumber(weekday: Int, isHoliday: Bool) -> Color {
        if weekday == 1 || isHoliday { return .holiday }
        if weekday == 7 { return .saturday }
        return .primary
    }
}

enum SettingsKey {
    static let theme = "theme"
    static let weekStart = "weekStart"
    static let lastMonth = "lastMonth"
    static let hiddenCalendars = "hiddenCalendars"
    static let holidayCalendar = "holidayCalendar"
    static let defaultCalendar = "defaultCalendar"
    static let templates = "templates"
    static let homeMode = "homeMode"
    static let hiddenTodoLists = "hiddenTodoLists"
    static let todoWidgetList = "todoWidgetList"
    static let selectedTodoList = "selectedTodoList"
    static let todoMeta = "todoMeta"
    static let createdDefaultTodoLists = "createdDefaultTodoLists"
    static let dimPastEvents = "dimPastEvents"
    static let goTransitMargin = "goTransitMargin"
    static let moMonthStart = "moMonthStart"
    static let notesTools = "notesTools"
    static let mapsSaved = "mapsSaved"
    static let mapsHistory = "mapsHistory"
    static let mapsLastLatitude = "mapsLastLatitude"
    static let mapsLastLongitude = "mapsLastLongitude"
    static let mapsLastSpan = "mapsLastSpan"
    static let mapsCameraLatitude = "mapsCameraLatitude"
    static let mapsCameraLongitude = "mapsCameraLongitude"
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "システム"
        case .light: "ライト"
        case .dark: "ダーク"
        }
    }

    /// The theme chosen in the app, readable from the widgets through the App Group.
    static var current: AppTheme {
        AppTheme(rawValue: AppGroup.defaults.string(forKey: SettingsKey.theme) ?? "") ?? .system
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Colors offered when creating a calendar; the last grid cell is a free color picker.
enum CalendarPalette {
    static let colors: [UIColor] = [
        UIColor(hex: 0xE5484D), UIColor(hex: 0xF76B15), UIColor(hex: 0xF5B100), UIColor(hex: 0x30A46C),
        UIColor(hex: 0x12A594), UIColor(hex: 0x00A2C7), UIColor(hex: 0x065A8C), UIColor(hex: 0x3E63DD),
        UIColor(hex: 0x8E4EC6), UIColor(hex: 0xD6409F), UIColor(hex: 0xA18072),
    ]
}

struct AppError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}
