import SwiftUI

/// 解約シミュ: pick what to cancel and see what it frees up — a month, a year, five years —
/// with the ones worth a second look (trials ending, overlaps, the priciest) on top.
struct SubsSimView: View {
    @Environment(SubsStore.self) private var store
    @State private var picked: Set<String> = []

    private var chosen: [Sub] { store.subs.filter { picked.contains($0.id) } }
    private var monthly: Double { chosen.filter { !$0.inTrial }.reduce(0) { $0 + $1.monthly } }

    struct Hint: Identifiable {
        let sub: Sub
        let reason: String
        let symbol: String
        var id: String { sub.id }
    }

    /// One reason per subscription, the most pressing first.
    private var hints: [Hint] {
        let today = CalendarMath.startOfDay(.now)
        var hints: [Hint] = []
        var seen: Set<String> = []
        func add(_ sub: Sub, _ reason: String, _ symbol: String) {
            guard !seen.contains(sub.id) else { return }
            seen.insert(sub.id)
            hints.append(Hint(sub: sub, reason: reason, symbol: symbol))
        }
        for sub in store.subs.filter(\.inTrial).sorted(by: { $0.trialEnd < $1.trialEnd }) {
            let days = CalendarMath.days(from: today, to: sub.trialEnd)
            if days <= 14 {
                add(sub, days <= 0 ? "無料トライアルが今日で終わります" : "無料トライアルがあと\(days)日で終わります", "gift")
            }
        }
        for sub in store.subs where sub.cycle.unit == .year || (sub.cycle.unit == .month && sub.cycle.count >= 3) {
            let days = CalendarMath.days(from: today, to: sub.nextRenewal)
            if days <= 30, sub.charges(on: sub.nextRenewal) {
                add(sub, "\(days)日後に\(SubsFormat.yen(sub.price))の更新があります", "calendar.badge.exclamationmark")
            }
        }
        let byCategory = Dictionary(grouping: store.subs.filter { !$0.inTrial }, by: \.category)
        for (category, list) in byCategory where list.count >= 2 {
            // The cheaper ones in a crowded category.
            for sub in list.sorted(by: { $0.monthly > $1.monthly }).dropFirst() {
                add(sub, "\(category)のサブスクが\(list.count)つあります", "square.on.square")
            }
        }
        if let top = store.subs.filter({ !$0.inTrial }).max(by: { $0.monthly < $1.monthly }), store.subs.count >= 3 {
            add(top, "いちばん高いサブスクです（\(SubsFormat.yen(top.monthly))/月）", "arrow.up.circle")
        }
        return hints
    }

    var body: some View {
        List {
            summary
                .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

            let found = hints
            if !found.isEmpty {
                Section("見直し候補") {
                    ForEach(found) { hint in
                        pickRow(hint.sub, reason: hint.reason, symbol: hint.symbol)
                    }
                }
            }

            Section("すべてのサブスク") {
                ForEach(store.subs.sorted { $0.monthly > $1.monthly }) { sub in
                    pickRow(sub, reason: nil, symbol: nil)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if store.subs.isEmpty {
                ContentUnavailableView("サブスクがありません", systemImage: "scissors",
                                       description: Text("リストに追加すると、解約したときにいくら浮くかを試せます。"))
            }
        }
        .sensoryFeedback(.selection, trigger: picked)
        .onChange(of: store.subs.map(\.id)) { _, ids in picked.formIntersection(ids) }
    }

    private var summary: some View {
        let soonest = chosen.filter { !$0.inTrial }.min { $0.nextRenewal < $1.nextRenewal }
        return VStack(spacing: 6) {
            Text(picked.isEmpty ? "解約したいサブスクを選んでください" : "\(picked.count)件を解約すると")
                .font(.system(size: 14, weight: .medium))
                .opacity(0.9)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(SubsFormat.yen(monthly))
                    .font(SubsFormat.number(52, .regular))
                    .monospacedDigit()
                    .contentTransition(.numericText(value: monthly))
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                Text("/月")
                    .font(.system(size: 16, weight: .medium))
            }
            HStack(spacing: 24) {
                total("1年で", monthly * 12)
                total("5年で", monthly * 60)
            }
            if let soonest {
                Text("\(SubsFormat.day(soonest.nextRenewal))までに「\(soonest.name)」を解約すれば、次の\(SubsFormat.yen(soonest.price))は払わずに済みます")
                    .font(.system(size: 12, weight: .medium))
                    .multilineTextAlignment(.center)
                    .opacity(0.85)
                    .padding(.top, 4)
            }
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 22)
        .padding(.horizontal, 16)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(LinearGradient(colors: SubsListView.cardColors, startPoint: .top, endPoint: .bottom))
        )
        .animation(.snappy, value: monthly)
    }

    private func total(_ title: String, _ amount: Double) -> some View {
        VStack(spacing: 1) {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .opacity(0.8)
            Text(SubsFormat.yen(amount))
                .font(SubsFormat.number(19, .semibold))
                .monospacedDigit()
                .contentTransition(.numericText(value: amount))
        }
    }

    private func pickRow(_ sub: Sub, reason: String?, symbol: String?) -> some View {
        let on = picked.contains(sub.id)
        return Button {
            withAnimation(.snappy) {
                if on { picked.remove(sub.id) } else { picked.insert(sub.id) }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: on ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(on ? Color.red : Color.secondary)
                    .contentTransition(.symbolEffect(.replace))
                SubsIconView(sub: sub, size: 36)
                VStack(alignment: .leading, spacing: 2) {
                    Text(sub.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    if let reason, let symbol {
                        Label(reason, systemImage: symbol)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.orange)
                            .lineLimit(2)
                    }
                }
                Spacer(minLength: 8)
                SubsPriceText(price: sub.price, suffix: sub.cycle.suffix, size: 15)
                    .opacity(on ? 0.45 : 1)
                    .strikethrough(on)
            }
        }
        .buttonStyle(.plain)
        .listRowSeparator(.hidden)
    }
}
