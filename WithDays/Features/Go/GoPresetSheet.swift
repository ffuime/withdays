import SwiftUI

enum GoEditTarget: Identifiable {
    case new
    case edit(GoPreset)

    var id: String {
        switch self {
        case .new: "new"
        case .edit(let preset): preset.id
        }
    }
}

/// The presets: tap to use one, swipe left to delete (with undo), swipe right to edit, ＋ to add.
struct GoPresetSheet: View {
    /// The top-right button: back to the calendar.
    var onCalendar: () -> Void

    @Environment(GoStore.self) private var go
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @State private var editing: GoEditTarget?
    @State private var showTransit = false
    @State private var longPressed = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(go.presets) { preset in
                    // TEMPORARY stays first; a little space separates it from the lasting presets.
                    if !preset.isTemporary, preset.id == firstLastingID, go.presets.contains(where: \.isTemporary) {
                        Color.clear
                            .frame(height: 14)
                            .listRowSeparator(.hidden)
                            .listRowInsets(EdgeInsets())
                            .listRowBackground(Color.clear)
                    }
                    Button {
                        go.select(preset.id)
                        dismiss()
                    } label: {
                        row(preset)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(rowBackground(selected: preset.id == go.state.selected))
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) { delete(preset) } label: {
                            Image(systemName: "trash")
                        }
                        .tint(.red)
                    }
                    .swipeActions(edge: .leading) {
                        Button { editing = .edit(preset) } label: {
                            Image(systemName: "pencil.and.outline")
                        }
                        .tint(.brand)
                    }
                }
            }
            .listStyle(.plain)
            .contentMargins(.bottom, 96, for: .scrollContent)
            .overlay {
                if go.presets.isEmpty {
                    Text("プリセットがありません")
                        .font(.system(size: 15, weight: .light))
                        .foregroundStyle(.secondary)
                }
            }
            .toolbar {
                // One pill top left: back to WithDays first, then close.
                ToolbarItemGroup(placement: .topBarLeading) {
                    WithDaysBackButton {
                        dismiss()
                        onCalendar()
                    }
                    Button { dismiss() } label: { Image(systemName: "xmark") }
                        .accessibilityLabel("閉じる")
                }
            }
            .overlay(alignment: .bottom) {
                HStack(alignment: .bottom, spacing: 10) {
                    // The undo toast shows here too, since this sheet covers the main one.
                    if let toast = toasts.current {
                        UndoToastView(toast: toast) { toasts.performUndo() }
                            .id(toast.id)
                    }
                    Spacer(minLength: 0)
                    Button {
                        // The long press already opened the train search; the release must not also open the editor.
                        if longPressed { longPressed = false } else { editing = .new }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 26.4, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 56, height: 56)
                    }
                    .buttonStyle(.glassProminent)
                    .buttonBorderShape(.circle)
                    // Holding ＋ makes a temporary preset from trains.
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.5).onEnded { _ in
                            longPressed = true
                            showTransit = true
                        }
                    )
                    .sensoryFeedback(.impact(weight: .medium), trigger: showTransit) { _, new in new }
                }
                .padding(20)
            }
        }
        .sheet(item: $editing) { target in
            GoEditorView(target: target)
        }
        .sheet(isPresented: $showTransit) {
            GoTransitSheet { dismiss() }
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private func row(_ preset: GoPreset) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(go.displayName(of: preset))
                .font(.system(size: 15, weight: .bold))
                .textCase(.uppercase)
                .foregroundStyle(Color.brand)
            HStack(spacing: 10) {
                ForEach(Array(preset.times.enumerated()), id: \.offset) { index, time in
                    if index > 0 {
                        Text("-").foregroundStyle(.tertiary)
                    }
                    Text(time)
                        .monospacedDigit()
                }
            }
            .font(.system(size: 22, weight: .light))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
        .padding(.vertical, 10)
        // Clear of the selected row's inset bar.
        .padding(.leading, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var firstLastingID: String? {
        go.presets.first { !$0.isTemporary }?.id
    }

    /// The preset in use: a faint tint with an inset bar on its left.
    @ViewBuilder
    private func rowBackground(selected: Bool) -> some View {
        if selected {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.brand.opacity(0.07))
                Capsule()
                    .fill(Color.brand)
                    .frame(width: 4)
                    .padding(.vertical, 12)
                    .padding(.leading, 8)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
        } else {
            Color.clear
        }
    }

    private func delete(_ preset: GoPreset) {
        guard let removed = go.delete(preset.id) else { return }
        toasts.show("プリセットを削除しました") {
            go.restore(removed.preset, at: removed.index, select: removed.wasSelected)
        }
    }
}
