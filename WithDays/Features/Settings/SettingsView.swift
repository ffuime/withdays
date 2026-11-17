import EventKit
import SwiftUI
import WidgetKit

struct SettingsView: View {
    @Environment(CalendarStore.self) private var store
    @Environment(TodoStore.self) private var todos
    @AppStorage(SettingsKey.theme, store: AppGroup.defaults) private var theme = AppTheme.system.rawValue
    @AppStorage(SettingsKey.weekStart, store: AppGroup.defaults) private var weekStart = 1
    @AppStorage(SettingsKey.dimPastEvents) private var dimPast = false
    @AppStorage(SettingsKey.goTransitMargin) private var transitMargin = 2
    @AppStorage(SettingsKey.moMonthStart) private var moMonthStart = 1

    var body: some View {
        List {
            Section("表示") {
                Picker("テーマ", selection: $theme) {
                    ForEach(AppTheme.allCases) { Text($0.label).tag($0.rawValue) }
                }
                Picker("週の始まり", selection: $weekStart) {
                    Text("日曜日").tag(1)
                    Text("月曜日").tag(2)
                }
                Toggle("過去の予定を薄く表示", isOn: $dimPast)
            }

            Section("カレンダー") {
                NavigationLink("カレンダー") { CalendarSettingsView() }
                Picker("新しい予定のカレンダー", selection: defaultCalendarBinding) {
                    Text("システムの設定").tag("")
                    ForEach(store.writableCalendars, id: \.calendarIdentifier) { calendar in
                        Text(calendar.title).tag(calendar.calendarIdentifier)
                    }
                }
                Picker("祝日カレンダー", selection: holidayCalendarBinding) {
                    Text("自動").tag("")
                    ForEach(store.calendars.filter { !$0.allowsContentModifications }, id: \.calendarIdentifier) { calendar in
                        Text(calendar.title).tag(calendar.calendarIdentifier)
                    }
                }
                NavigationLink("テンプレート") { TemplateListView() }
            }

            if todos.access == .granted {
                Section("Td") {
                    NavigationLink("カテゴリ") { TodoCategorySettingsView() }
                    Picker("ウィジェットにするカテゴリ", selection: widgetListBinding) {
                        ForEach(todos.sortedLists, id: \.calendarIdentifier) { list in
                            Text(list.title).tag(list.calendarIdentifier)
                        }
                    }
                }
            }

            Section {
                Picker("月の始まり", selection: $moMonthStart) {
                    ForEach(1...28, id: \.self) { Text("毎月\($0)日").tag($0) }
                }
            } header: {
                Text("Mo")
            } footer: {
                Text("統計の「今月」がこの日から始まります。カレンダーは変わりません。")
            }

            Section {
                Stepper("電車の余裕 \(transitMargin)分", value: $transitMargin, in: 0...30)
            } header: {
                Text("Go")
            } footer: {
                Text("＋ボタン長押しで電車から作るとき、この時間より後に出発する経路を候補にします。")
            }

            Section {
                Button("iPhoneの設定を開く") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .foregroundStyle(.primary)
            }

            Section("WithDays") {
                LabeledContent("バージョン", value: "\(AppInfo.version) (\(AppInfo.build))")
                NavigationLink("更新履歴") { ChangelogView() }
                Link(destination: AppInfo.repositoryURL) {
                    Label("GitHub", systemImage: "chevron.left.forwardslash.chevron.right")
                        .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle("設定")
        .navigationBarTitleDisplayMode(.inline)
        // Widgets read these from the App Group.
        .onChange(of: theme) { WidgetCenter.shared.reloadAllTimelines() }
        .onChange(of: weekStart) { WidgetCenter.shared.reloadAllTimelines() }
    }

    private var defaultCalendarBinding: Binding<String> {
        Binding(get: { store.defaultCalendarID }, set: { store.defaultCalendarID = $0 })
    }

    private var holidayCalendarBinding: Binding<String> {
        Binding(get: { store.holidayCalendarID }, set: { store.holidayCalendarID = $0 })
    }

    private var widgetListBinding: Binding<String> {
        Binding(get: { todos.widgetListID }, set: { todos.widgetListID = $0 })
    }
}

/// Show/hide, add, edit (swipe right) and delete (swipe left) calendars.
private struct CalendarSettingsView: View {
    @Environment(CalendarStore.self) private var store
    @State private var adding = false
    @State private var editing: EKCalendar?
    @State private var pendingDelete: EKCalendar?
    @State private var errorMessage: String?

    var body: some View {
        List {
            ForEach(store.grouped(store.displayableCalendars)) { group in
                Section(group.source) {
                    ForEach(group.calendars, id: \.calendarIdentifier) { calendar in
                        Toggle(isOn: binding(for: calendar.calendarIdentifier)) {
                            HStack(spacing: 10) {
                                CalendarDot(color: Color(cgColor: calendar.cgColor))
                                Text(calendar.title)
                            }
                        }
                        .calendarEditSwipe(calendar, editing: $editing)
                        .swipeActions(edge: .trailing) {
                            if store.canDelete(calendar) {
                                Button(role: .destructive) { pendingDelete = calendar } label: {
                                    Image(systemName: "trash")
                                }
                                .tint(.red)
                            }
                        }
                    }
                }
            }
            Section {
                Button { adding = true } label: {
                    Label("カレンダーを追加", systemImage: "plus")
                        .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle("カレンダー")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $adding) {
            NavigationStack {
                NewCalendarView { _ in adding = false }
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button { adding = false } label: { Image(systemName: "xmark") }
                        }
                    }
            }
        }
        .calendarEditSheet($editing)
        .calendarDeleteDialog($pendingDelete, errorMessage: $errorMessage)
        .errorAlert($errorMessage)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { !store.hiddenCalendarIDs.contains(id) },
            set: { visible in
                if visible { store.hiddenCalendarIDs.remove(id) } else { store.hiddenCalendarIDs.insert(id) }
            }
        )
    }
}

/// Show/hide, edit (tap), add and delete (swipe left) ToDo categories.
private struct TodoCategorySettingsView: View {
    @Environment(TodoStore.self) private var todos
    @State private var sheet: CategorySheet?
    @State private var pendingDelete: EKCalendar?
    @State private var errorMessage: String?

    var body: some View {
        List {
            Section {
                ForEach(todos.sortedLists, id: \.calendarIdentifier) { list in
                    HStack(spacing: 10) {
                        Button { sheet = .edit(list) } label: {
                            HStack(spacing: 10) {
                                CalendarDot(color: Color(cgColor: list.cgColor))
                                Text(list.title).foregroundStyle(.primary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Toggle("", isOn: binding(for: list.calendarIdentifier))
                            .labelsHidden()
                    }
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { pendingDelete = list } label: {
                            Image(systemName: "trash")
                        }
                        .tint(.red)
                    }
                }
            }
            Section {
                Button { sheet = .new } label: {
                    Label("カテゴリを追加", systemImage: "plus")
                        .foregroundStyle(.primary)
                }
            }
        }
        .navigationTitle("カテゴリ")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $sheet) { CategoryEditorView(sheet: $0) }
        .confirmationDialog(
            "「\(pendingDelete?.title ?? "")」とその中のToDoを削除します",
            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
            titleVisibility: .visible,
            presenting: pendingDelete
        ) { list in
            Button("削除", role: .destructive) {
                do { try todos.deleteList(list) } catch { errorMessage = error.localizedDescription }
            }
        }
        .errorAlert($errorMessage)
    }

    private func binding(for id: String) -> Binding<Bool> {
        Binding(
            get: { !todos.hiddenListIDs.contains(id) },
            set: { visible in
                if visible { todos.hiddenListIDs.remove(id) } else { todos.hiddenListIDs.insert(id) }
            }
        )
    }
}

private struct TemplateListView: View {
    @Environment(TemplateStore.self) private var templates
    @State private var editing: EditorMode?

    var body: some View {
        List {
            ForEach(templates.templates) { template in
                Button { editing = .template(template) } label: {
                    Text(template.draft.title).foregroundStyle(.primary)
                }
            }
            .onDelete { offsets in
                let ids = offsets.map { templates.templates[$0].id }
                for id in ids { templates.delete(id: id) }
            }
            .onMove { templates.move(from: $0, to: $1) }

            Button {
                editing = .template(nil)
            } label: {
                Label("テンプレートを登録", systemImage: "plus")
                    .foregroundStyle(.primary)
            }
        }
        .toolbar { EditButton() }
        .navigationTitle("テンプレート")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(item: $editing) { mode in
            EventEditorView(mode: mode)
        }
    }
}

private struct ChangelogView: View {
    var body: some View {
        List(AppInfo.changelog) { release in
            Section {
                ForEach(release.notes, id: \.self) { Text($0).font(.system(size: 14)) }
            } header: {
                HStack {
                    Text(release.version)
                    Spacer()
                    Text(release.date)
                }
            }
        }
        .navigationTitle("更新履歴")
        .navigationBarTitleDisplayMode(.inline)
    }
}
