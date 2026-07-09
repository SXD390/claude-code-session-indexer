import SwiftUI
import Charts

// MARK: - Middle-column range control panel

struct InsightsSidePanel: View {
    @EnvironmentObject var store: SessionStore
    @Binding var preset: RangePreset
    @Binding var customStart: Date
    @Binding var customEnd: Date

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.coral)
                Text("Time range")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 10)

            VStack(spacing: 3) {
                ForEach(RangePreset.allCases) { p in
                    RangeRow(preset: p, isSelected: preset == p) { preset = p }
                }
            }
            .padding(.horizontal, 10)

            if preset == .custom {
                VStack(alignment: .leading, spacing: 10) {
                    Divider().overlay(Theme.border)
                    DatePicker("From", selection: $customStart, displayedComponents: .date)
                    DatePicker("To", selection: $customEnd, displayedComponents: .date)
                }
                .font(.system(size: 12))
                .datePickerStyle(.compact)
                .padding(.horizontal, 16)
                .padding(.top, 8)
            }

            Spacer()

            Divider().overlay(Theme.border)
            HStack(spacing: 6) {
                if store.usageLoaded {
                    Image(systemName: "checkmark.circle.fill").font(.system(size: 10)).foregroundStyle(Theme.running)
                    Text("\(store.usageRecords.count) sessions analyzed")
                } else {
                    ProgressView().controlSize(.small).scaleEffect(0.7).frame(width: 12, height: 12)
                    Text("Analyzing usage…").foregroundStyle(Theme.coral)
                }
                Spacer()
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Theme.windowBase)
    }
}

private struct RangeRow: View {
    let preset: RangePreset
    let isSelected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Text(preset.label)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.primary)
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Theme.coral)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(isSelected ? Theme.coralTint.opacity(0.16)
                                     : (hovering ? Color.primary.opacity(0.05) : Color.clear))
            )
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(isSelected ? Theme.coral.opacity(0.4) : .clear, lineWidth: 1))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.14), value: hovering)
    }
}

// MARK: - Dashboard

struct InsightsView: View {
    @EnvironmentObject var store: SessionStore
    let range: DateInterval?
    let rangeLabel: String
    let onSelect: (String) -> Void

    @State private var agg = UsageAggregation()
    @State private var metric: TokenMetric = .output
    @Environment(\.colorScheme) private var scheme

    private var recomputeKey: String {
        "\(range?.start.timeIntervalSince1970 ?? -1)-\(range?.end.timeIntervalSince1970 ?? -1)-\(store.usageRecords.count)-\(store.usageLoaded)"
    }

    private var bucketByWeek: Bool {
        guard let first = agg.days.first?.date, let last = agg.days.last?.date else { return false }
        return last.timeIntervalSince(first) > 60 * 86_400
    }

    private var timePoints: [DayPoint] {
        bucketByWeek ? UsageAnalytics.weekBuckets(agg.days) : agg.days
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header
                statTiles
                timeCard
                metricCard
                midRow
                projectCard
                efficiencySection
            }
            .padding(24)
            .frame(maxWidth: 1060, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .background(Theme.windowBase)
        .task(id: recomputeKey) {
            let range = self.range
            let names = store.projectNames
            let records = Array(store.usageRecords.values)
            let result = await Task.detached(priority: .userInitiated) {
                UsageAnalytics.aggregate(records: records, range: range, projectNames: names)
            }.value
            agg = result
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Insights")
                    .font(.system(size: 26, weight: .bold, design: .rounded))
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !store.usageLoaded {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small).scaleEffect(0.8)
                    Text("Analyzing…").font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var subtitle: String {
        var s = rangeLabel
        if let range {
            let f = Date.FormatStyle.dateTime.month(.abbreviated).day()
            s += " · \(range.start.formatted(f)) – \(range.end.formatted(f))"
        }
        return s
    }

    // MARK: Stat tiles

    private var statTiles: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
            InsightStatTile(systemImage: "clock.fill", value: Fmt.duration(agg.totalActiveSeconds),
                            label: "Time spent", sub: rangeLabel, tint: Theme.coral)
            InsightStatTile(systemImage: "dollarsign.circle.fill", value: Fmt.cost(agg.totalCost),
                            label: "Est. cost (API-equiv)", sub: rangeLabel, tint: Color(hex: 0xC9A24E))
            InsightStatTile(systemImage: "number.square.fill", value: Fmt.tokens(agg.totalInOutTokens),
                            label: "Tokens (in + out)", sub: "\(Fmt.tokens(agg.totalCacheRead)) cache read", tint: Color(hex: 0x57A6C9))
            InsightStatTile(systemImage: "square.stack.3d.up.fill", value: "\(agg.sessionsActive)",
                            label: "Sessions active", sub: rangeLabel, tint: Color(hex: 0x9B7ED1))
        }
    }

    // MARK: Charts

    private var timeCard: some View {
        Card(title: bucketByWeek ? "Time spent per week" : "Time spent per day",
             systemImage: "clock.fill", accent: Theme.coral) {
            DailyBarChart(points: timePoints, value: { $0.activeSeconds },
                          color: Theme.coral, format: { Fmt.duration($0) }, unit: "seconds")
        }
    }

    private var metricCard: some View {
        Card(title: "\(metric.rawValue) per \(bucketByWeek ? "week" : "day")",
             systemImage: metric.isCost ? "dollarsign.circle" : "chart.bar.fill", accent: Theme.coral) {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Metric", selection: $metric) {
                    ForEach(TokenMetric.allCases) { m in Text(m.rawValue).tag(m) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                DailyBarChart(points: timePoints, value: { $0.tokens(metric) },
                              color: Theme.coral,
                              format: metric.isCost ? { Fmt.cost($0) } : { Fmt.tokens(Int($0)) },
                              unit: metric.isCost ? "USD" : "tokens")
            }
        }
    }

    private var midRow: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 16) {
                modelCard.frame(maxWidth: .infinity)
                hourCard.frame(maxWidth: .infinity)
            }
            VStack(spacing: 16) {
                modelCard
                hourCard
            }
        }
    }

    private var modelCard: some View {
        Card(title: "Model usage by cost", systemImage: "cpu", accent: Theme.coral) {
            VStack(alignment: .leading, spacing: 8) {
                ModelBars(models: Array(agg.models.prefix(6)), totalTokens: agg.totalTokens)
                if let top = agg.models.first, agg.totalTokens > 0 {
                    Text("\(top.displayName) leads with \(Fmt.tokens(top.totalTokens)) tokens · \(pct(Double(top.totalTokens) / Double(agg.totalTokens))) of all tokens")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }

    private var hourCard: some View {
        Card(title: "When you code (local time)", systemImage: "moon.stars.fill", accent: Theme.coral) {
            HourHistogram(hours: agg.hourHistogram)
        }
    }

    private var projectCard: some View {
        Card(title: "Top projects by time", systemImage: "folder.fill", accent: Theme.coral) {
            ProjectBars(projects: agg.projects)
        }
    }

    // MARK: Efficiency insights

    private var efficiencySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.coral)
                Text("Efficiency insights").font(.system(size: 15, weight: .semibold, design: .rounded))
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 288), spacing: 14)], spacing: 14) {
                cacheCallout
                costPerHourCallout
                modelMixCallout
                longestCallout
                expensiveCallout
            }
        }
    }

    private var cacheCallout: some View {
        let rate = agg.cacheHitRate
        let quality = rate >= 0.9 ? ">90% — excellent, prompt caching is doing heavy lifting."
                    : rate >= 0.6 ? "Solid — most context is being served from cache."
                    : "Room to improve — more of your context is uncached."
        return InsightCallout(
            systemImage: "bolt.fill", tint: Theme.running,
            title: "Cache hit rate \(pct(rate))",
            message: "\(quality) Caching saved about \(Fmt.cost(agg.cacheSavings)) (API-equivalent) in this range.")
    }

    private var costPerHourCallout: some View {
        InsightCallout(
            systemImage: "gauge.with.dots.needle.50percent", tint: Color(hex: 0xC9A24E),
            title: "\(Fmt.cost(agg.costPerActiveHour)) per active hour",
            message: "Across \(Fmt.duration(agg.totalActiveSeconds)) of active coding at \(Fmt.cost(agg.totalCost)) total (API-equivalent).")
    }

    private var modelMixCallout: some View {
        InsightCallout(
            systemImage: "chart.pie.fill", tint: Color(hex: 0x9B7ED1),
            title: "Model mix",
            message: modelMixBody)
    }

    private var modelMixBody: String {
        guard agg.totalOutput > 0 else { return "No model usage in this range." }
        var byTier: [ModelTier: Int] = [:]
        for m in agg.models { byTier[ModelTier.of(m.model), default: 0] += m.output }
        let ranked = byTier.sorted { $0.value > $1.value }
        let parts = ranked.prefix(3).map { "\($0.key.rawValue) \(pct(Double($0.value) / Double(agg.totalOutput)))" }
        var s = parts.joined(separator: " · ") + " of output tokens."
        if let top = ranked.first, Double(top.value) / Double(agg.totalOutput) > 0.8,
           (top.key == .opus || top.key == .fable) {
            s += " Over 80% on \(top.key.rawValue) — your most capable (and priciest) tier."
        }
        return s
    }

    private var longestCallout: some View {
        InsightCallout(
            systemImage: "hourglass", tint: Theme.coral,
            title: "Longest session",
            message: longest.map { "\($0.title) — \(Fmt.duration($0.secs)) of active time." } ?? "No sessions in range.",
            action: longest.map { l in { onSelect(l.id) } },
            actionLabel: longest != nil ? "Open session" : nil)
    }

    private var expensiveCallout: some View {
        InsightCallout(
            systemImage: "dollarsign.circle.fill", tint: Color(hex: 0xC9A24E),
            title: "Most expensive session",
            message: expensive.map { "\($0.title) — \(Fmt.cost($0.cost)) (API-equivalent)." } ?? "No sessions in range.",
            action: expensive.map { e in { onSelect(e.id) } },
            actionLabel: expensive != nil ? "Open session" : nil)
    }

    private var longest: (id: String, title: String, secs: Double)? {
        guard let l = agg.longest else { return nil }
        return (l.sessionId, store.session(forId: l.sessionId)?.displayTitle ?? "Session", l.seconds)
    }
    private var expensive: (id: String, title: String, cost: Double)? {
        guard let e = agg.mostExpensive else { return nil }
        return (e.sessionId, store.session(forId: e.sessionId)?.displayTitle ?? "Session", e.cost)
    }

    private func pct(_ v: Double) -> String {
        // Avoid a misleading "100.0%" when the true value is just under.
        if v >= 0.9995 && v < 1.0 { return "99.9%" }
        return String(format: "%.1f%%", v * 100)
    }
}
