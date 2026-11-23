import SwiftUI

/// One subscription: its icon and name, price, next renewal, this month's use and the rest.
struct SubsDetailView: View {
    let id: String

    @Environment(SubsStore.self) private var store
    @Environment(SubsRouter.self) private var router

    var body: some View {
        if let sub = store.sub(id) {
            content(sub)
        } else {
            ContentUnavailableView("削除されました", systemImage: "trash")
        }
    }

    private func content(_ sub: Sub) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(spacing: 10) {
                    SubsIconView(sub: sub, size: 96)
                        .shadow(color: .black.opacity(0.12), radius: 10, y: 4)
                    Text(sub.name)
                        .font(.system(size: 24, weight: .bold))
                        .multilineTextAlignment(.center)
                    HStack(spacing: 10) {
                        Text(sub.category)
                        Text(sub.cycle.label)
                    }
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 12)
                .padding(.bottom, 36)

                price(sub)
                renewal(sub)
                    .padding(.top, 4)
                if sub.trial {
                    trial(sub)
                        .padding(.top, 4)
                }

                usage(sub)
                    .padding(.top, 32)

                facts(sub)
                    .padding(.top, 24)

                if !sub.memo.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("メモ")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text(sub.memo)
                            .font(.system(size: 15))
                            .textSelection(.enabled)
                    }
                    .padding(.top, 24)
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
        .navigationTitle(sub.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.edit(sub) } label: { Image(systemName: "pencil") }
                    .accessibilityLabel("編集")
            }
            ToolbarSpacer(.fixed, placement: .topBarTrailing)
            ToolbarItem(placement: .topBarTrailing) {
                Button { router.deleting = sub } label: { Image(systemName: "trash") }
                    .tint(.red)
                    .accessibilityLabel("削除")
            }
        }
    }

    /// ¥1,000/月 and, beside it, the same over a year (or, for a year, a month).
    private func price(_ sub: Sub) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            SubsPriceText(price: sub.price, suffix: sub.cycle.suffix, size: 30)
            Group {
                if sub.cycle == .monthly {
                    Text("\(SubsFormat.yen(sub.price * 12))/年")
                } else {
                    Text("\(SubsFormat.yen(sub.monthly))/月")
                }
            }
            .font(.system(size: 13, weight: .medium))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
    }

    private func renewal(_ sub: Sub) -> some View {
        let next = sub.nextRenewal
        return HStack(spacing: 6) {
            Image(systemName: "\(CalendarMath.day(next)).calendar")
                .foregroundStyle(Color.brand)
            Text("次回更新日")
            Spacer()
            Text(SubsFormat.date(next))
                .font(SubsFormat.number(16, .semibold))
                .monospacedDigit()
        }
        .font(.system(size: 15, weight: .medium))
    }

    private func trial(_ sub: Sub) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "gift")
                .foregroundStyle(.green)
            Text(sub.inTrial ? "無料トライアル終了日" : "無料トライアルは終了")
            Spacer()
            Text(SubsFormat.date(sub.trialEnd))
                .font(SubsFormat.number(16, .semibold))
                .monospacedDigit()
        }
        .font(.system(size: 15, weight: .medium))
    }

    @ViewBuilder
    private func usage(_ sub: Sub) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            if let token = SubsScreenTime.token(sub.appToken), SubsScreenTime.approved {
                SubsUsageReport(token: token, monthlyYen: Int(sub.monthly.rounded()))
            } else {
                HStack(alignment: .lastTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("利用時間")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.secondary)
                        Text("—")
                            .font(SubsFormat.number(30, .bold))
                    }
                    Spacer()
                }
                Button {
                    router.edit(sub)
                } label: {
                    Label("スクリーンタイムと連携", systemImage: "hourglass")
                        .font(.system(size: 14, weight: .semibold))
                }
                .buttonStyle(.glass)
                Text("連携すると、今月このアプリを使った時間と、1時間あたりの料金が表示されます。")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Color(.secondarySystemBackground)))
    }

    private func facts(_ sub: Sub) -> some View {
        let paid = store.paid(sub.id)
        return VStack(spacing: 10) {
            fact("登録日", SubsFormat.date(sub.startDate))
            fact("これまでの支払い", paid.count == 0 ? "なし" : "\(SubsFormat.yen(paid.total))（\(paid.count)回）")
        }
    }

    private func fact(_ title: String, _ value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .monospacedDigit()
        }
        .font(.system(size: 14, weight: .medium))
    }
}

/// 過去の記録: every renewal paid, by month, newest first.
struct SubsHistoryView: View {
    @Environment(SubsStore.self) private var store
    @Environment(SubsRouter.self) private var router

    private var months: [(month: Date, payments: [SubsPayment])] {
        let groups = Dictionary(grouping: store.payments) { CalendarMath.startOfMonth($0.date) }
        return groups.keys.sorted(by: >).map { month in
            (month, groups[month]!.sorted { $0.date > $1.date })
        }
    }

    var body: some View {
        let total = store.payments.reduce(0) { $0 + $1.amount }
        List {
            if !store.payments.isEmpty {
                HStack {
                    Text("これまでの合計")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(SubsFormat.yen(total))
                        .font(SubsFormat.number(24, .bold))
                        .monospacedDigit()
                }
                .listRowSeparator(.hidden)
            }
            ForEach(months, id: \.month) { group in
                Section {
                    ForEach(group.payments) { payment in
                        row(payment)
                            .listRowSeparator(.hidden)
                    }
                } header: {
                    HStack {
                        Text(Fmt.monthTitle(group.month))
                        Spacer()
                        Text(SubsFormat.yen(group.payments.reduce(0) { $0 + $1.amount }))
                            .monospacedDigit()
                    }
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.primary)
                }
            }
        }
        .listStyle(.plain)
        .overlay {
            if store.payments.isEmpty {
                ContentUnavailableView("まだ記録はありません", systemImage: "backward",
                                       description: Text("更新日が過ぎるごとに、支払いがここに記録されます。"))
            }
        }
        .navigationTitle("過去の記録")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func row(_ payment: SubsPayment) -> some View {
        let sub = store.sub(payment.subID)
        return HStack(spacing: 12) {
            if let sub {
                SubsIconView(sub: sub, size: 32)
            } else {
                SubsSymbolIcon(symbol: payment.symbol, tint: payment.tint, size: 32)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(payment.name)
                    .font(.system(size: 15, weight: .bold))
                    .lineLimit(1)
                Text(SubsFormat.date(payment.date))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            SubsPriceText(price: payment.amount, size: 16)
        }
        .contentShape(Rectangle())
        .onTapGesture { if let sub { router.open(sub) } }
    }
}
