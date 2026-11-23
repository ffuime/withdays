import AppIntents
import Foundation

/// The apps inside WithDays, for the ショートカット app and Siri.
enum WithDaysScreen: String, AppEnum {
    case calendar, todo, tooc, slides, notes, go, planner, subscribes

    static let typeDisplayRepresentation: TypeDisplayRepresentation = "アプリ"

    static let caseDisplayRepresentations: [WithDaysScreen: DisplayRepresentation] = [
        .calendar: DisplayRepresentation(title: "Calendar", image: .init(systemName: "calendar")),
        .todo: DisplayRepresentation(title: "ToDo", image: .init(systemName: "checklist")),
        .tooc: DisplayRepresentation(title: "tooc", image: .init(systemName: "message")),
        .slides: DisplayRepresentation(title: "Slides", image: .init(systemName: "rectangle.on.rectangle.angled")),
        .notes: DisplayRepresentation(title: "Notes", image: .init(systemName: "pencil.and.scribble")),
        .go: DisplayRepresentation(title: "Go", image: .init(systemName: "tram")),
        .planner: DisplayRepresentation(title: "Planner", image: .init(systemName: "yensign.circle")),
        .subscribes: DisplayRepresentation(title: "Subscribes", image: .init(systemName: "creditcard")),
    ]

    var mode: HomeMode {
        switch self {
        case .calendar: .calendar
        case .todo: .todo
        case .tooc: .tooc
        case .slides: .slides
        case .notes: .notes
        case .go: .go
        case .planner: .mo
        case .subscribes: .subs
        }
    }
}

struct OpenScreenIntent: AppIntent {
    static let title: LocalizedStringResource = "WithDaysのアプリを開く"
    static let description = IntentDescription("Calendar・ToDo・tooc・Slides・Notes・Go・Planner・Subscribes を直接開きます。")
    static let openAppWhenRun: Bool = true

    @Parameter(title: "アプリ")
    var screen: WithDaysScreen

    init() {}

    init(screen: WithDaysScreen) {
        self.screen = screen
    }

    static var parameterSummary: some ParameterSummary {
        Summary("\(\.$screen)を開く")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        HomeModeRequest.open(screen.mode)
        return .result()
    }
}

/// Shows each app as its own shortcut in the ショートカット app.
struct WithDaysShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: OpenScreenIntent(),
            phrases: [
                "\(.applicationName)で\(\.$screen)を開く",
                "\(.applicationName)の\(\.$screen)",
            ],
            shortTitle: "アプリを開く",
            systemImageName: "square.grid.2x2"
        )
    }
}

/// Asks HomeView to show an app. Saved too, so a cold launch opens straight into it.
@MainActor
enum HomeModeRequest {
    static let notification = Notification.Name("WithDaysOpenMode")

    static func open(_ mode: HomeMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: SettingsKey.homeMode)
        NotificationCenter.default.post(name: notification, object: mode.rawValue)
    }
}
