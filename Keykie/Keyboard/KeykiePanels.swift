import KanaKanjiConverterModuleWithDefaultDictionary
import SwiftUI

// MARK: - Candidate bar

/// Clipboard on the left, close on the right. In between: the candidates while typing, otherwise a strip
/// to drag the cursor along (or the line-delete question / its undo).
struct KeykieCandidateBar: View {
    @Environment(KeykieState.self) private var state
    @State private var moved = 0

    var body: some View {
        HStack(spacing: 0) {
            barButton("doc.on.clipboard") { state.openClipboard() }
            center
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            barButton("chevron.down") { state.dismiss() }
        }
    }

    private func barButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .medium))
                .frame(width: 44, height: state.settings.barHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var center: some View {
        if state.confirmingLineDelete {
            HStack(spacing: 10) {
                Text("行頭まで削除しますか？")
                    .font(.system(size: 14, weight: .semibold))
                Spacer(minLength: 0)
                Button("削除") { state.deleteToLineStart() }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.red)
                Button("やめる") { state.confirmingLineDelete = false }
                    .font(.system(size: 14))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
        } else if let query = state.emojiQuery {
            emojiSearch(query)
        } else if state.isComposing {
            candidates
        } else if state.undoText != nil {
            HStack {
                Button { state.undoDelete() } label: {
                    Label("元に戻す", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 14, weight: .semibold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(state.palette.key))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .transition(.opacity)
        } else {
            cursorStrip
        }
    }

    private var candidates: some View {
        HStack(spacing: 0) {
            ScrollViewReader { reader in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 2) {
                        ForEach(Array(state.candidates.prefix(40).enumerated()), id: \.offset) { index, candidate in
                            Button { state.commit(candidate) } label: {
                                Text(candidate.text)
                                    .font(.system(size: 17))
                                    .lineLimit(1)
                                    .padding(.horizontal, 10)
                                    .frame(maxHeight: .infinity)
                                    .background {
                                        if state.selected == index {
                                            RoundedRectangle(cornerRadius: 8, style: .continuous).fill(state.palette.key)
                                        }
                                    }
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .id(index)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .onChange(of: state.selected) { _, selected in
                    if let selected { withAnimation { reader.scrollTo(selected, anchor: .center) } }
                }
            }
            if state.candidates.count > 1 {
                Button { withAnimation(.snappy) { state.showAllCandidates.toggle() } } label: {
                    Image(systemName: state.showAllCandidates ? "chevron.up" : "square.grid.2x2")
                        .font(.system(size: 15))
                        .frame(width: 36, height: state.settings.barHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Drag sideways to move the cursor (no ← → keys).
    @ViewBuilder
    private var cursorStrip: some View {
        if state.settings.candidateSwipe {
            HStack {
                Image(systemName: "chevron.left")
                Spacer()
                Image(systemName: "chevron.right")
            }
            .font(.system(size: 11, weight: .semibold))
            .opacity(0.25)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        let steps = Int(value.translation.width / state.settings.cursorStep)
                        if steps != moved {
                            state.moveCursor(steps - moved)
                            moved = steps
                        }
                    }
                    .onEnded { _ in moved = 0 }
            )
        } else {
            Color.clear
        }
    }

    private func emojiSearch(_ query: String) -> some View {
        HStack(spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass")
                Text(query.isEmpty ? "絵文字を検索" : query)
                    .opacity(query.isEmpty ? 0.5 : 1)
                    .lineLimit(1)
            }
            .font(.system(size: 14))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Capsule().fill(state.palette.key))
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 2) {
                    ForEach(state.emojiResults, id: \.self) { emoji in
                        Button { state.insertEmoji(emoji) } label: {
                            Text(emoji).font(.system(size: 26)).padding(.horizontal, 3)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Button { state.endEmojiSearch() } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 17)).opacity(0.6)
            }
            .buttonStyle(.plain)
        }
    }
}

// MARK: - All candidates

struct KeykieAllCandidates: View {
    @Environment(KeykieState.self) private var state

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 64), spacing: 6)], spacing: 6) {
                ForEach(Array(state.candidates.enumerated()), id: \.offset) { _, candidate in
                    Button { state.commit(candidate) } label: {
                        Text(candidate.text)
                            .font(.system(size: 17))
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .padding(.horizontal, 6)
                    }
                    .buttonStyle(KeykieKeyButtonStyle(special: false))
                    .frame(height: 42)
                }
            }
            .padding(8)
        }
        .background(state.palette.background)
    }
}

// MARK: - Clipboard

/// The clipboard history and the phrases, over the whole keyboard.
struct KeykieClipboardSheet: View {
    @Environment(KeykieState.self) private var state
    @State private var tab = 0
    @State private var confirmClear = false

    var body: some View {
        let palette = state.palette
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("", selection: $tab) {
                    Text("履歴").tag(0)
                    Text("定型文").tag(1)
                }
                .pickerStyle(.segmented)
                .frame(width: 170)
                Spacer()
                if tab == 0, state.clips.contains(where: { !$0.pinned }) {
                    Button(confirmClear ? "本当に消す" : "全消去") {
                        if confirmClear {
                            state.clearClips()
                            confirmClear = false
                        } else {
                            confirmClear = true
                            Task {
                                try? await Task.sleep(for: .seconds(3))
                                confirmClear = false
                            }
                        }
                    }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(confirmClear ? .red : palette.text)
                    .buttonStyle(.plain)
                }
                Button { withAnimation(.snappy) { state.showClipboard = false } } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 32, height: 32)
                        .background(Circle().fill(palette.key))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            if tab == 0 { history } else { phraseList }
        }
        .background(palette.background)
    }

    @ViewBuilder
    private var history: some View {
        let clips = KeykieClipboard.sorted(state.clips)
        if clips.isEmpty {
            empty(state.hasFullAccess
                  ? "コピーしたテキストが、キーボードを開いたときにここに入ります"
                  : "クリップボード履歴にはフルアクセスが必要です（WithDays の設定 › Keykie）")
        } else {
            List {
                ForEach(clips) { clip in
                    row(clip.text, pinned: clip.pinned)
                        .onTapGesture { state.insertFromClipboard(clip.text) }
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) { state.deleteClip(clip) } label: { Image(systemName: "trash") }
                        }
                        .swipeActions(edge: .leading) {
                            Button { state.togglePin(clip) } label: {
                                Image(systemName: clip.pinned ? "pin.slash" : "pin")
                            }
                            .tint(.orange)
                        }
                        .listRowBackground(state.palette.key.opacity(0.6))
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder
    private var phraseList: some View {
        if state.phrases.isEmpty {
            empty("定型文は WithDays の設定 › Keykie › 辞書 で追加できます")
        } else {
            List(state.phrases) { phrase in
                VStack(alignment: .leading, spacing: 2) {
                    Text(phrase.title).font(.system(size: 13, weight: .bold)).opacity(0.7)
                    Text(phrase.body).font(.system(size: 15)).lineLimit(2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture { state.insertFromClipboard(phrase.body) }
                .listRowBackground(state.palette.key.opacity(0.6))
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
    }

    private func row(_ text: String, pinned: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text(text)
                .font(.system(size: 15))
                .lineLimit(3)
                .frame(maxWidth: .infinity, alignment: .leading)
            if pinned {
                Image(systemName: "pin.fill").font(.system(size: 11)).foregroundStyle(.orange)
            }
        }
        .contentShape(Rectangle())
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 14))
            .multilineTextAlignment(.center)
            .opacity(0.6)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Emoji

struct KeykieEmojiBoard: View {
    @Environment(KeykieState.self) private var state
    @State private var category = "recent"

    var body: some View {
        let sp = state.spacing
        VStack(spacing: 0) {
            let list = emoji
            GeometryReader { geo in
                let rows = 4
                let size = (geo.size.height - 8) / CGFloat(rows)
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHGrid(rows: Array(repeating: GridItem(.fixed(size), spacing: 0), count: rows), spacing: 0) {
                        ForEach(Array(list.enumerated()), id: \.offset) { _, emoji in
                            Button { state.insertEmoji(emoji) } label: {
                                Text(emoji)
                                    .font(.system(size: size * 0.68))
                                    .frame(width: size * 1.05, height: size)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 6)
                }
                .overlay {
                    if list.isEmpty {
                        Text(category == "recent" ? "使った絵文字がここに並びます" : "")
                            .font(.system(size: 14)).opacity(0.5)
                    }
                }
                .id(category)
            }
            .padding(.top, 4)

            HStack(spacing: 2) {
                Button { state.toggleEmoji() } label: {
                    Text(state.textMode == .kana ? "あいう" : "ABC").font(.system(size: 13))
                }
                .buttonStyle(KeykieKeyButtonStyle())
                .frame(width: 52)
                Button { state.startEmojiSearch() } label: {
                    Image(systemName: "magnifyingglass").font(.system(size: 14))
                }
                .buttonStyle(KeykieKeyButtonStyle())
                .frame(width: 36)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 0) {
                        tab("recent", symbol: "clock")
                        ForEach(KeykieEmoji.categories) { category in
                            tab(category.id, symbol: category.symbol)
                        }
                    }
                }
                KeykieDeleteKey().frame(width: 48)
            }
            .frame(height: 38)
            .padding(.horizontal, sp)
            .padding(.bottom, sp)
        }
    }

    private var emoji: [String] {
        if category == "recent" { return state.recentEmoji }
        return KeykieEmoji.categories.first { $0.id == category }?.emoji ?? []
    }

    private func tab(_ id: String, symbol: String) -> some View {
        Button {
            state.selectionFeedback()
            category = id
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 15))
                .frame(width: 34, height: 34)
                .background(Circle().fill(category == id ? state.palette.key : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
