import SwiftUI

/// The search bar opened to the full screen: the field, 「よく使う項目」 side by side, then the history
/// (swipe left to delete).
struct MapsSearchScreen: View {
    @Binding var text: String
    var onSearch: (String) -> Void
    var onPickSaved: (SavedPlace) -> Void
    var onPickHistory: (MapsHistoryEntry) -> Void
    var onCancel: () -> Void

    @Environment(MapsStore.self) private var store
    @FocusState private var focused: Bool
    @State private var renaming: SavedPlace?
    @State private var newName = ""
    @State private var confirmClear = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("場所やジャンルを検索", text: $text)
                        .focused($focused)
                        .submitLabel(.search)
                        .onSubmit { onSearch(text) }
                    if !text.isEmpty {
                        Button { text = "" } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 14)
                .frame(height: 46)
                .glassEffect(.regular, in: .capsule)

                Button("キャンセル", action: onCancel)
                    .foregroundStyle(.primary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            List {
                Section {
                    if store.saved.isEmpty {
                        Text("検索結果の行や地図を長押しすると、ここに追加できます")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    } else {
                        savedRow
                            .listRowInsets(EdgeInsets())
                    }
                } header: {
                    Text("よく使う項目")
                }

                Section {
                    if store.history.isEmpty {
                        Text("履歴はありません")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                    ForEach(store.history) { entry in
                        Button { onPickHistory(entry) } label: { historyRow(entry) }
                            .buttonStyle(.plain)
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) { store.deleteHistory(entry.id) } label: {
                                    Image(systemName: "trash")
                                }
                                .tint(.red)
                            }
                    }
                } header: {
                    HStack {
                        Text("履歴")
                        Spacer()
                        if !store.history.isEmpty {
                            Button("すべて消去") { confirmClear = true }
                                .font(.system(size: 13))
                                .textCase(nil)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .scrollDismissesKeyboard(.immediately)
        }
        .onAppear { focused = true }
        .alert("名前を変更", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("名前", text: $newName)
            Button("保存") {
                if let renaming { store.rename(renaming.id, to: newName.trimmingCharacters(in: .whitespaces)) }
            }
            Button("キャンセル", role: .cancel) {}
        }
        .confirmationDialog("履歴をすべて消去します", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("すべて消去", role: .destructive) { store.clearHistory() }
        }
    }

    private var savedRow: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(store.saved) { place in
                    Button { onPickSaved(place) } label: {
                        VStack(spacing: 6) {
                            Image(systemName: place.placeID == nil ? "mappin" : "star.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 44, height: 44)
                                .background(Color.brand, in: .circle)
                            Text(place.name)
                                .font(.system(size: 12))
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                                .frame(maxWidth: 72)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            newName = place.name
                            renaming = place
                        } label: {
                            Label("名前を変更", systemImage: "pencil")
                        }
                        Button(role: .destructive) { store.deleteSaved(place.id) } label: {
                            Label("削除", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .scrollIndicators(.hidden)
    }

    private func historyRow(_ entry: MapsHistoryEntry) -> some View {
        HStack(spacing: 12) {
            Image(systemName: entry.kind == .query ? "clock.arrow.circlepath" : "mappin.circle.fill")
                .font(.system(size: 18))
                .foregroundStyle(entry.kind == .query ? Color.secondary : Color.brand)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.text)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                if let address = entry.address {
                    Text(address)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}
