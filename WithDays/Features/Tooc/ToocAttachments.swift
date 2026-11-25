import CoreLocation
import MapKit
import SwiftUI

/// What the ＋ menu can make besides photos and files.
enum ToocComposer: String, Identifiable {
    case location, poll, datePoll, amida
    var id: String { rawValue }
}

struct ToocComposerView: View {
    let kind: ToocComposer
    let roomID: String
    var onSend: (ToocMessage.Kind) -> Void

    var body: some View {
        switch kind {
        case .location: ToocLocationPicker(onSend: onSend)
        case .poll: ToocPollEditor(onSend: onSend)
        case .datePoll: ToocDatePollEditor(onSend: onSend)
        case .amida: ToocAmidaEditor(roomID: roomID, onSend: onSend)
        }
    }
}

/// 期限: off, or a date and time after which answers can't change.
private struct ToocDeadlineSection: View {
    @Binding var on: Bool
    @Binding var date: Date

    var body: some View {
        Section {
            Toggle("期限", isOn: $on.animation(.snappy))
            if on {
                DatePicker("締め切り", selection: $date, in: Date.now..., displayedComponents: [.date, .hourAndMinute])
            }
        }
    }
}

private func defaultDeadline() -> Date {
    Calendar.current.date(bySettingHour: 23, minute: 59, second: 0, of: Date.now.addingTimeInterval(60 * 60 * 24 * 2)) ?? .now
}

/// The ✕ and ✓ of an editor sheet.
private struct ToocEditorToolbar: ToolbarContent {
    var canSend: Bool
    var dismiss: DismissAction
    var send: () -> Void

    var body: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(Color.primary) }
                .accessibilityLabel("キャンセル")
        }
        ToolbarItem(placement: .topBarTrailing) {
            Button {
                send()
                dismiss()
            } label: { Image(systemName: "paperplane.fill") }
                .buttonStyle(.glassProminent)
                .disabled(!canSend)
                .accessibilityLabel("送信")
        }
    }
}

// MARK: - Editors

struct ToocPollEditor: View {
    var onSend: (ToocMessage.Kind) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var question = ""
    @State private var options = ["", ""]
    @State private var multiple = false
    @State private var hasDeadline = false
    @State private var deadline = defaultDeadline()

    private var filled: [String] {
        options.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例：打ち上げどこにする？", text: $question, axis: .vertical)
                } header: {
                    Text("質問").toocFont(.footnote)
                }
                Section {
                    ForEach(options.indices, id: \.self) { index in
                        TextField("選択肢\(index + 1)", text: $options[index])
                    }
                    .onDelete { offsets in
                        if options.count - offsets.count >= 2 { options.remove(atOffsets: offsets) }
                    }
                    if options.count < 10 {
                        Button("選択肢を追加", systemImage: "plus") { options.append("") }
                    }
                } header: {
                    Text("選択肢").toocFont(.footnote)
                }
                Section {
                    Toggle("複数選択できる", isOn: $multiple)
                }
                ToocDeadlineSection(on: $hasDeadline, date: $deadline)
            }
            .navigationTitle("投票")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToocEditorToolbar(canSend: !question.trimmingCharacters(in: .whitespaces).isEmpty && filled.count >= 2, dismiss: dismiss) {
                    onSend(.poll(ToocPoll(question: question.trimmingCharacters(in: .whitespacesAndNewlines),
                                          options: filled, multiple: multiple, deadline: hasDeadline ? deadline : nil)))
                }
            }
        }
    }
}

struct ToocDatePollEditor: View {
    var onSend: (ToocMessage.Kind) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var dates: [Date] = []
    @State private var hasDeadline = false
    @State private var deadline = defaultDeadline()
    @State private var next = Calendar.current.date(bySettingHour: 19, minute: 0, second: 0,
                                                     of: Date.now.addingTimeInterval(60 * 60 * 24)) ?? .now

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例：打ち上げ", text: $title)
                } header: {
                    Text("タイトル").toocFont(.footnote)
                }
                Section {
                    ForEach(dates, id: \.self) { date in
                        Text(ToocTime.candidate(date))
                    }
                    .onDelete { dates.remove(atOffsets: $0) }
                    DatePicker("候補", selection: $next, displayedComponents: [.date, .hourAndMinute])
                    Button("候補に追加", systemImage: "plus") {
                        withAnimation(.snappy) {
                            if !dates.contains(next) { dates.append(next) }
                            dates.sort()
                            next = next.addingTimeInterval(60 * 60 * 24)
                        }
                    }
                } header: {
                    Text("候補日（\(dates.count)）").toocFont(.footnote)
                }
                ToocDeadlineSection(on: $hasDeadline, date: $deadline)
            }
            .navigationTitle("日程調整")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToocEditorToolbar(canSend: !title.trimmingCharacters(in: .whitespaces).isEmpty && !dates.isEmpty, dismiss: dismiss) {
                    onSend(.datePoll(ToocDatePoll(title: title.trimmingCharacters(in: .whitespacesAndNewlines), dates: dates,
                                                  deadline: hasDeadline ? deadline : nil)))
                }
            }
        }
    }
}

struct ToocAmidaEditor: View {
    let roomID: String
    var onSend: (ToocMessage.Kind) -> Void
    @Environment(ToocStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var entrants: [String] = []
    @State private var prizes: [String] = []
    @State private var loaded = false

    private var ready: Bool {
        entrants.count >= 2 && entrants.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            && prizes.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("例：買い出し係", text: $title)
                } header: {
                    Text("タイトル").toocFont(.footnote)
                }
                Section {
                    ForEach(entrants.indices, id: \.self) { index in
                        TextField("参加者\(index + 1)", text: $entrants[index])
                    }
                    .onDelete { offsets in
                        if entrants.count - offsets.count >= 2 { entrants.remove(atOffsets: offsets) }
                    }
                    if entrants.count < 10 {
                        Button("参加者を追加", systemImage: "plus") { entrants.append("") }
                    }
                } header: {
                    Text("参加する人").toocFont(.footnote)
                }
                Section {
                    ForEach(prizes.indices, id: \.self) { index in
                        TextField("結果\(index + 1)", text: $prizes[index])
                    }
                } header: {
                    Text("結果").toocFont(.footnote)
                }
            }
            .navigationTitle("あみだくじ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToocEditorToolbar(canSend: ready, dismiss: dismiss) {
                    let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
                    // No deadline: a draw is over as soon as it's drawn.
                    onSend(.amida(ToocAmida(title: name.isEmpty ? "あみだくじ" : name, entrants: entrants, prizes: prizes,
                                            deadline: nil)))
                }
            }
            .onChange(of: entrants.count) { fitPrizes() }
            .onAppear {
                guard !loaded else { return }
                loaded = true
                let members = store.room(roomID)?.memberIDs ?? []
                entrants = [store.me.name] + members.compactMap { store.user($0)?.displayName }
                if entrants.count < 2 { entrants.append("") }
                fitPrizes()
            }
        }
    }

    private func fitPrizes() {
        while prizes.count < entrants.count { prizes.append(prizes.isEmpty ? "当たり" : "はずれ") }
        if prizes.count > entrants.count { prizes.removeLast(prizes.count - entrants.count) }
    }
}

/// Move the map under the pin, then send that place.
struct ToocLocationPicker: View {
    var onSend: (ToocMessage.Kind) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var position: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var center: CLLocationCoordinate2D?
    @State private var title = ""
    @State private var manager = CLLocationManager()

    var body: some View {
        NavigationStack {
            Map(position: $position) {
                UserAnnotation()
            }
            .mapControls {
                MapUserLocationButton()
                MapCompass()
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                center = context.region.center
                Task { await name(context.region.center) }
            }
            .overlay {
                Image(systemName: "mappin")
                    .toocFont(.system(size: 34, weight: .semibold))
                    .foregroundStyle(.red)
                    .shadow(radius: 3)
                    .offset(y: -17)
                    .allowsHitTesting(false)
            }
            .safeAreaInset(edge: .bottom) {
                Text(title.isEmpty ? "地図を動かして場所を選ぶ" : title)
                    .toocFont(.subheadline.weight(.semibold))
                    .lineLimit(2)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.bottom, 12)
            }
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle("位置情報")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(Color.primary) }
                        .accessibilityLabel("キャンセル")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        if let center {
                            onSend(.location(latitude: center.latitude, longitude: center.longitude,
                                             title: title.isEmpty ? "位置情報" : title))
                        }
                        dismiss()
                    } label: { Image(systemName: "paperplane.fill") }
                        .buttonStyle(.glassProminent)
                        .disabled(center == nil)
                        .accessibilityLabel("この場所を送信")
                }
            }
            .onAppear { manager.requestWhenInUseAuthorization() }
        }
    }

    private func name(_ coordinate: CLLocationCoordinate2D) async {
        let location = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let placemark = try? await CLGeocoder().reverseGeocodeLocation(location, preferredLocale: Locale(identifier: "ja_JP")).first
        title = placemark?.name ?? placemark?.locality ?? ""
    }
}

// MARK: - Cards in the talk

/// A file, a place, a poll, a 日程調整 or an あみだくじ, as a card in the talk.
struct ToocCardBubble: View {
    let message: ToocMessage
    let room: ToocRoom
    let mine: Bool
    var openFile: (String) -> Void

    @Environment(ToocStore.self) private var store
    @Environment(\.toocTheme) private var theme
    @Environment(\.openURL) private var openURL
    @State private var showAmida = false

    var body: some View {
        content
            .padding(12)
            .frame(width: 256, alignment: .leading)
            .background(theme.theirBubble, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(mine ? theme.accent.opacity(0.6) : Color.clear, lineWidth: 1.5)
            }
            .sheet(isPresented: $showAmida) {
                if case .amida(let amida) = message.kind {
                    ToocAmidaSheet(amida: amida) { store.reveal(message.id, roomID: room.id) }
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch message.kind {
        case .file(let name, let file, let size):
            fileRow(name, size) { openFile(file) }
        case .remoteFile(let name, let url, let size):
            fileRow(name, size) { openFile(url) }
        case .location(let latitude, let longitude, let title):
            locationCard(latitude, longitude, title)
        case .poll(let poll):
            pollCard(poll)
        case .datePoll(let poll):
            datePollCard(poll)
        case .amida(let amida):
            amidaCard(amida)
        default:
            EmptyView()
        }
    }

    private func fileRow(_ name: String, _ size: Int, open: @escaping () -> Void) -> some View {
            Button(action: open) {
                HStack(spacing: 10) {
                    Image(systemName: "doc.fill")
                        .toocFont(.system(size: 18))
                        .foregroundStyle(.white)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(theme.accent))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(name)
                            .toocFont(.subheadline.weight(.semibold))
                            .lineLimit(2)
                        Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                            .toocFont(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
    }

    private func locationCard(_ latitude: Double, _ longitude: Double, _ title: String) -> some View {
            let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            return Button {
                let query = title.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
                if let url = URL(string: "maps://?ll=\(latitude),\(longitude)&q=\(query)") { openURL(url) }
            } label: {
                VStack(alignment: .leading, spacing: 8) {
                    Map(initialPosition: .region(MKCoordinateRegion(center: coordinate, latitudinalMeters: 700,
                                                                     longitudinalMeters: 700)),
                        interactionModes: []) {
                        Marker(title, coordinate: coordinate)
                    }
                    .frame(height: 130)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .allowsHitTesting(false)
                    Label(title, systemImage: "mappin.circle.fill")
                        .toocFont(.subheadline.weight(.semibold))
                        .lineLimit(2)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
    }

    private func header(_ title: String, _ symbol: String) -> some View {
        Label(title, systemImage: symbol)
            .toocFont(.caption.weight(.semibold))
            .foregroundStyle(theme.accent)
    }

    /// 「締め切り 11/24(月) 23:59」, or 「締め切りました」 once past.
    @ViewBuilder
    private func deadline(_ date: Date?) -> some View {
        if let date {
            let closed = date <= .now
            Label(closed ? "締め切りました" : "締め切り \(ToocTime.candidate(date))", systemImage: closed ? "lock.fill" : "clock")
                .toocFont(.caption)
                .foregroundStyle(closed ? Color.red : Color.secondary)
        }
    }

    private func pollCard(_ poll: ToocPoll) -> some View {
        let total = max(1, poll.votes.count)
        let mineVotes = poll.votes[store.me.id] ?? []
        return VStack(alignment: .leading, spacing: 8) {
            header(poll.multiple ? "投票（複数選択）" : "投票", "chart.bar.fill")
            Text(poll.question)
                .toocFont(.headline)
            deadline(poll.deadline)
            ForEach(poll.options.indices, id: \.self) { index in
                let count = poll.count(index)
                let chosen = mineVotes.contains(index)
                Button {
                    withAnimation(.snappy) { store.vote(index, in: message.id, roomID: room.id) }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: chosen ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(chosen ? theme.accent : Color.secondary)
                        Text(poll.options[index])
                            .toocFont(.subheadline)
                            .lineLimit(2)
                        Spacer(minLength: 4)
                        Text("\(count)")
                            .toocFont(.subheadline.weight(.semibold))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(alignment: .leading) {
                        GeometryReader { proxy in
                            theme.accent.opacity(chosen ? 0.28 : 0.14)
                                .frame(width: proxy.size.width * CGFloat(count) / CGFloat(total))
                        }
                    }
                    .background(Color.primary.opacity(0.05))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(poll.closed)
            }
            Text("\(poll.votes.count)人が投票")
                .toocFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func datePollCard(_ poll: ToocDatePoll) -> some View {
        let mineAnswers = poll.answers[store.me.id] ?? []
        let best = poll.dates.indices.max { poll.count($0, 2) < poll.count($1, 2) }
        return VStack(alignment: .leading, spacing: 8) {
            header("日程調整", "calendar")
            Text(poll.title)
                .toocFont(.headline)
            deadline(poll.deadline)
            ForEach(poll.dates.indices, id: \.self) { index in
                let answer = index < mineAnswers.count ? mineAnswers[index] : -1
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(ToocTime.candidate(poll.dates[index]))
                            .toocFont(.subheadline.weight(index == best && poll.count(index, 2) > 0 ? .bold : .regular))
                        Spacer()
                        Text("○\(poll.count(index, 2)) △\(poll.count(index, 1)) ×\(poll.count(index, 0))")
                            .toocFont(.caption)
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        ForEach([2, 1, 0], id: \.self) { value in
                            Button {
                                withAnimation(.snappy) { store.answer(index, value, in: message.id, roomID: room.id) }
                            } label: {
                                Text(value == 2 ? "○" : value == 1 ? "△" : "×")
                                    .toocFont(.subheadline.weight(.bold))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 5)
                                    .foregroundStyle(answer == value ? Color.white : Color.primary)
                                    .background(answer == value ? theme.accent : Color.primary.opacity(0.06),
                                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .disabled(poll.closed)
                        }
                    }
                }
                .padding(.vertical, 2)
            }
            Text("\(poll.answers.count)人が回答")
                .toocFont(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func amidaCard(_ amida: ToocAmida) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            header("あみだくじ", "line.3.horizontal")
            Text(amida.title)
                .toocFont(.headline)
            if amida.revealed {
                ForEach(amida.entrants.indices, id: \.self) { index in
                    HStack {
                        Text(amida.entrants[index]).toocFont(.subheadline)
                        Spacer()
                        Text(amida.prizes[amida.result(for: index)])
                            .toocFont(.subheadline.weight(.semibold))
                            .foregroundStyle(theme.accent)
                    }
                }
            } else {
                Text("\(amida.entrants.count)人が参加")
                    .toocFont(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Button(amida.revealed ? "もう一度見る" : "結果を見る") { showAmida = true }
                .toocFont(.subheadline.weight(.semibold))
                .foregroundStyle(theme.accent)
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .padding(.top, 2)
        }
    }
}

/// The ladder, drawn and walked: each entrant's line runs down in their colour to their result.
struct ToocAmidaSheet: View {
    let amida: ToocAmida
    var onReveal: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.toocTheme) private var theme
    @State private var progress: CGFloat = 0
    @State private var started = false

    private func color(_ index: Int) -> Color {
        Color(hue: Double(index) / Double(max(1, amida.entrants.count)), saturation: 0.65, brightness: 0.85)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 10) {
                GeometryReader { outer in
                    // Up to 5 fit the width; more scroll sideways at a fixed width each.
                    let wide = amida.entrants.count > Self.fitting
                    let width = wide ? CGFloat(amida.entrants.count) * Self.columnWidth : outer.size.width
                    ScrollView(.horizontal) {
                        board(width: width, height: outer.size.height)
                    }
                    .scrollDisabled(!wide)
                    .scrollIndicators(wide ? .visible : .hidden)
                }
                if progress >= 1 {
                    VStack(spacing: 6) {
                        ForEach(amida.entrants.indices, id: \.self) { index in
                            HStack {
                                Circle().fill(color(index)).frame(width: 10, height: 10)
                                Text(amida.entrants[index])
                                Spacer()
                                Text(amida.prizes[amida.result(for: index)]).bold()
                            }
                            .toocFont(.subheadline)
                        }
                    }
                    .padding(14)
                    .background(theme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
                } else {
                    Button {
                        guard !started else { return }
                        started = true
                        withAnimation(.easeInOut(duration: 2.6)) { progress = 1 } completion: { onReveal() }
                    } label: {
                        Text("スタート")
                            .toocFont(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 6)
                    }
                    .buttonStyle(.glassProminent)
                    .disabled(started)
                }
            }
            .padding(20)
            .navigationTitle(amida.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { dismiss() } label: { Image(systemName: "xmark").foregroundStyle(Color.primary) }
                        .accessibilityLabel("閉じる")
                }
            }
            .onAppear { if amida.revealed { progress = 1 } }
        }
    }

    private static let fitting = 5
    private static let columnWidth: CGFloat = 72

    /// Names on top, the ladder, then the results.
    private func board(width: CGFloat, height: CGFloat) -> some View {
        VStack(spacing: 10) {
            labels(amida.entrants, colored: true)
            GeometryReader { proxy in
                let size = proxy.size
                ZStack {
                    ladder(size)
                        .stroke(Color.secondary.opacity(0.5), lineWidth: 2)
                    ForEach(amida.entrants.indices, id: \.self) { index in
                        walk(index, size)
                            .trim(from: 0, to: progress)
                            .stroke(color(index), style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    }
                }
            }
            labels(amida.entrants.indices.map { index in
                // Each prize shows once someone reaches it.
                progress >= 1 ? amida.prizes[index] : "？"
            }, colored: false)
        }
        .frame(width: width, height: height)
    }

    private func labels(_ texts: [String], colored: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(texts.indices, id: \.self) { index in
                Text(texts[index])
                    .toocFont(.caption.weight(.semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(colored ? color(index) : Color.primary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private func x(_ column: Int, _ size: CGSize) -> CGFloat {
        size.width * (CGFloat(column) + 0.5) / CGFloat(max(1, amida.entrants.count))
    }

    private func y(_ level: Int, _ size: CGSize) -> CGFloat {
        size.height * CGFloat(level + 1) / CGFloat(ToocAmida.levels + 1)
    }

    private func ladder(_ size: CGSize) -> Path {
        var path = Path()
        for column in amida.entrants.indices {
            path.move(to: CGPoint(x: x(column, size), y: 0))
            path.addLine(to: CGPoint(x: x(column, size), y: size.height))
        }
        for rung in amida.rungs {
            path.move(to: CGPoint(x: x(rung.column, size), y: y(rung.level, size)))
            path.addLine(to: CGPoint(x: x(rung.column + 1, size), y: y(rung.level, size)))
        }
        return path
    }

    private func walk(_ entrant: Int, _ size: CGSize) -> Path {
        let columns = amida.walk(from: entrant)
        var path = Path()
        path.move(to: CGPoint(x: x(columns[0], size), y: 0))
        for level in 0..<ToocAmida.levels {
            path.addLine(to: CGPoint(x: x(columns[level], size), y: y(level, size)))
            if columns[level + 1] != columns[level] {
                path.addLine(to: CGPoint(x: x(columns[level + 1], size), y: y(level, size)))
            }
        }
        path.addLine(to: CGPoint(x: x(columns[ToocAmida.levels], size), y: size.height))
        return path
    }
}
