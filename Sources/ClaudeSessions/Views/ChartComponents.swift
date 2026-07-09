import SwiftUI
import Charts

// MARK: - Chart palette + chrome (dataviz-aligned)
//
// Single-series charts carry the coral accent (the chart's title names the metric,
// so no legend is needed). The project chart is the one categorical case — it uses
// the established project palette, and every bar is directly labeled + carries its
// ProjectDot, so identity is never color-alone (the relief rule). Axis/grid are
// recessive hairlines; all text wears text tokens, never the series color.

enum Chart2 {
    static var grid: Color { Theme.border }
    static var axis: Color { Theme.borderStrong }

    /// Thin bars, capped near the dataviz ≤24px guidance, thinner as the count grows.
    static func barWidth(_ count: Int) -> MarkDimension {
        if count > 45 { return .fixed(4) }
        if count > 20 { return .fixed(8) }
        if count > 10 { return .fixed(14) }
        return .fixed(20)
    }
}

// MARK: - Daily bar chart (time / tokens / cost per day)

struct DailyBarChart: View {
    let points: [DayPoint]
    let value: (DayPoint) -> Double
    var color: Color = Theme.coral
    let format: (Double) -> String
    let unit: String
    var height: CGFloat = 180

    @State private var selectedDate: Date?
    @Environment(\.colorScheme) private var scheme

    private var selected: DayPoint? {
        guard let selectedDate else { return nil }
        return points.min { a, b in
            abs(a.date.timeIntervalSince(selectedDate)) < abs(b.date.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        if points.isEmpty || points.allSatisfy({ value($0) == 0 }) {
            ChartEmpty()
                .frame(height: height)
        } else {
            Chart {
                ForEach(points) { p in
                    BarMark(
                        x: .value("Day", p.date, unit: .day),
                        y: .value(unit, value(p)),
                        width: Chart2.barWidth(points.count)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 2.5))
                    .foregroundStyle(color.opacity(selected == nil || isSame(p) ? 1 : 0.32))
                }
                if let sel = selected {
                    RuleMark(x: .value("Day", sel.date, unit: .day))
                        .foregroundStyle(Chart2.axis.opacity(0.6))
                        .lineStyle(.init(lineWidth: 1))
                        .annotation(position: .top, spacing: 6,
                                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                            Tooltip(title: sel.date.formatted(.dateTime.month().day()),
                                    value: format(value(sel)))
                        }
                }
            }
            .chartXSelection(value: $selectedDate)
            .chartYAxis {
                AxisMarks(position: .leading) { v in
                    AxisGridLine().foregroundStyle(Chart2.grid)
                    AxisValueLabel {
                        if let d = v.as(Double.self) { Text(axisTick(d)) }
                    }
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                }
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 6)) { _ in
                    AxisValueLabel(format: .dateTime.month(.abbreviated).day())
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: height)
        }
    }

    private func isSame(_ p: DayPoint) -> Bool {
        guard let s = selected else { return false }
        return Calendar.current.isDate(p.date, inSameDayAs: s.date)
    }

    private func axisTick(_ v: Double) -> String {
        if unit == "USD" { return Fmt.cost(v) }
        if v >= 3600, unit == "seconds" { return "\(Int(v/3600))h" }
        if unit == "seconds" { return "\(Int(v/60))m" }
        return Fmt.tokens(Int(v))
    }
}

// MARK: - Hour-of-day histogram

struct HourHistogram: View {
    let hours: [Double]   // 24
    var color: Color = Theme.coral
    @State private var selectedHour: Int?

    var body: some View {
        if hours.allSatisfy({ $0 == 0 }) {
            ChartEmpty().frame(height: 150)
        } else {
            Chart {
                ForEach(0..<24, id: \.self) { h in
                    BarMark(
                        x: .value("Hour", h),
                        y: .value("Messages", hours[h]),
                        width: .fixed(9)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 2))
                    .foregroundStyle(color.opacity(selectedHour == nil || selectedHour == h ? 1 : 0.32))
                    .annotation(position: .top) {
                        if selectedHour == h {
                            Tooltip(title: hourLabel(h), value: "\(Int(hours[h])) msgs")
                        }
                    }
                }
            }
            .chartXSelection(value: $selectedHour)
            .chartXScale(domain: -0.5...23.5)
            .chartXAxis {
                AxisMarks(values: [0, 6, 12, 18, 23]) { v in
                    AxisValueLabel {
                        if let h = v.as(Int.self) { Text(hourLabel(h)) }
                    }
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisGridLine().foregroundStyle(Chart2.grid)
                    AxisValueLabel()
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 150)
        }
    }

    private func hourLabel(_ h: Int) -> String {
        if h == 0 { return "12a" }
        if h == 12 { return "12p" }
        return h < 12 ? "\(h)a" : "\(h-12)p"
    }
}

// MARK: - Horizontal ranked bars (models by cost)

struct ModelBars: View {
    let models: [ModelStat]
    let totalTokens: Int

    var body: some View {
        if models.isEmpty {
            ChartEmpty().frame(height: 120)
        } else {
            Chart {
                ForEach(models) { m in
                    BarMark(
                        x: .value("Cost", m.cost),
                        y: .value("Model", m.displayName)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 2.5))
                    .foregroundStyle(Theme.coral)
                    .annotation(position: .trailing, alignment: .leading) {
                        Text(Fmt.cost(m.cost))
                            .font(.system(size: 10, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .chartXAxis {
                AxisMarks { _ in
                    AxisGridLine().foregroundStyle(Chart2.grid)
                    AxisValueLabel(format: .currency(code: "USD").precision(.fractionLength(0)))
                        .font(.system(size: 10, design: .rounded))
                        .foregroundStyle(.secondary)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading) { _ in
                    AxisValueLabel()
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.primary)
                }
            }
            .chartXScale(range: .plotDimension(padding: 44))
            .frame(height: CGFloat(max(1, models.count)) * 34 + 24)
        }
    }
}

// MARK: - Project bars (categorical — project colors, direct-labeled)

struct ProjectBars: View {
    let projects: [ProjectStat]

    var body: some View {
        if projects.isEmpty {
            ChartEmpty().frame(height: 120)
        } else {
            VStack(spacing: 12) {
                let maxSecs = max(projects.map(\.activeSeconds).max() ?? 1, 1)
                ForEach(projects.prefix(8)) { p in
                    HStack(spacing: 10) {
                        ProjectDot(key: p.projectKey, size: 9)
                        Text(p.projectName)
                            .font(.system(size: 12.5, weight: .medium))
                            .lineLimit(1)
                            .frame(width: 140, alignment: .leading)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(Theme.field)
                                Capsule()
                                    .fill(Theme.projectColor(for: p.projectKey))
                                    .frame(width: max(6, geo.size.width * CGFloat(p.activeSeconds / maxSecs)))
                            }
                        }
                        .frame(height: 9)
                        Text(Fmt.duration(p.activeSeconds))
                            .font(.system(size: 11.5, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 68, alignment: .trailing)
                    }
                }
            }
        }
    }
}

// MARK: - Small shared pieces

struct Tooltip: View {
    let title: String
    let value: String
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(title)
                .font(.system(size: 9.5, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 12, weight: .bold, design: .rounded).monospacedDigit())
                .foregroundStyle(.primary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.cardRaised, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .shadow(color: .black.opacity(scheme == .light ? 0.1 : 0.4), radius: 5, y: 2)
        .fixedSize()
    }
}

struct ChartEmpty: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 20))
                .foregroundStyle(.quaternary)
            Text("No data in this range")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Stat tile (dashboard headline figures)

struct InsightStatTile: View {
    let systemImage: String
    let value: String
    let label: String
    let sub: String
    var tint: Color = Theme.coral
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Image(systemName: systemImage)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
            Text(value)
                .font(.system(size: 25, weight: .bold, design: .rounded))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(sub)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(15)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.border, lineWidth: 1))
        .cardShadow(scheme)
    }
}

// MARK: - Efficiency insight callout

struct InsightCallout: View {
    let systemImage: String
    let tint: Color
    let title: String
    let message: String
    var action: (() -> Void)?
    var actionLabel: String?
    @State private var hovering = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(width: 22, height: 22)
                    .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                Text(title)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                Spacer(minLength: 0)
            }
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            if let action, let actionLabel {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Text(actionLabel).font(.system(size: 11, weight: .semibold, design: .rounded))
                        Image(systemName: "arrow.right").font(.system(size: 9, weight: .bold))
                    }
                    .foregroundStyle(Theme.coral)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .strokeBorder(hovering && action != nil ? tint.opacity(0.4) : Theme.border, lineWidth: 1))
        .cardShadow(scheme)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.15), value: hovering)
    }
}
