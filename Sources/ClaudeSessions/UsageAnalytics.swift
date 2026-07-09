import Foundation

// MARK: - Pricing

/// USD per 1,000,000 tokens.
struct ModelPricing {
    let input: Double
    let output: Double
    let cacheRead: Double
    let cacheWrite: Double
}

enum Pricing {
    /// Prefix match, first match wins — order matters (see spec).
    static let table: [(prefix: String, price: ModelPricing)] = [
        ("claude-fable-5",  ModelPricing(input: 10.0, output: 50.0, cacheRead: 1.00, cacheWrite: 12.50)),
        ("claude-mythos",   ModelPricing(input: 10.0, output: 50.0, cacheRead: 1.00, cacheWrite: 12.50)),
        ("claude-opus-4-1", ModelPricing(input: 15.0, output: 75.0, cacheRead: 1.50, cacheWrite: 18.75)),
        ("claude-opus-4-0", ModelPricing(input: 15.0, output: 75.0, cacheRead: 1.50, cacheWrite: 18.75)),
        ("claude-opus",     ModelPricing(input:  5.0, output: 25.0, cacheRead: 0.50, cacheWrite:  6.25)),
        ("claude-sonnet",   ModelPricing(input:  3.0, output: 15.0, cacheRead: 0.30, cacheWrite:  3.75)),
        ("claude-haiku",    ModelPricing(input:  1.0, output:  5.0, cacheRead: 0.10, cacheWrite:  1.25)),
    ]

    static let fallback = ModelPricing(input: 3.0, output: 15.0, cacheRead: 0.30, cacheWrite: 3.75)

    static func pricing(for model: String) -> ModelPricing {
        for entry in table where model.hasPrefix(entry.prefix) { return entry.price }
        return fallback
    }

    static func cost(model: String, input: Int, output: Int, cacheRead: Int, cacheWrite: Int) -> Double {
        let p = pricing(for: model)
        return (Double(input) * p.input
                + Double(output) * p.output
                + Double(cacheRead) * p.cacheRead
                + Double(cacheWrite) * p.cacheWrite) / 1_000_000
    }
}

// MARK: - Per-session record

struct UsageEvent: Codable, Hashable {
    let model: String
    let input: Int
    let output: Int
    let cacheRead: Int
    let cacheWrite: Int
    let timestamp: Date?

    var cost: Double {
        Pricing.cost(model: model, input: input, output: output, cacheRead: cacheRead, cacheWrite: cacheWrite)
    }
    var totalTokens: Int { input + output + cacheRead + cacheWrite }
}

/// Cached, incrementally-recomputed usage record for one transcript.
struct UsageRecord: Codable {
    let sessionId: String
    let transcriptPath: String
    let projectKey: String
    var fileModifiedAt: Date
    var fileSize: Int64

    var events: [UsageEvent]
    /// Heartbeat active seconds, attributed to local days ("yyyy-MM-dd").
    var dailyActiveSeconds: [String: Double]
    var totalActiveSeconds: Double
    var firstTimestamp: Date?
    var lastTimestamp: Date?

    // Precomputed whole-session totals (for the per-session Usage card).
    var totalInput: Int
    var totalOutput: Int
    var totalCacheRead: Int
    var totalCacheWrite: Int
    var totalCost: Double

    var totalTokens: Int { totalInput + totalOutput + totalCacheRead + totalCacheWrite }

    /// Per-model token+cost breakdown for this session (for the detail Usage card).
    var perModel: [ModelStat] {
        UsageAnalytics.modelStats(from: events)
    }
}

// MARK: - Aggregation output

struct DayPoint: Identifiable {
    var id: String { day }
    let day: String            // yyyy-MM-dd (local)
    let date: Date
    var activeSeconds: Double = 0
    var input: Int = 0
    var output: Int = 0
    var cacheRead: Int = 0
    var cacheWrite: Int = 0
    var cost: Double = 0
    var sessions = Set<String>()

    func tokens(_ metric: TokenMetric) -> Double {
        switch metric {
        case .output:     return Double(output)
        case .input:      return Double(input)
        case .cacheRead:  return Double(cacheRead)
        case .cacheWrite: return Double(cacheWrite)
        case .cost:       return cost
        }
    }
}

enum TokenMetric: String, CaseIterable, Identifiable {
    case output = "Output"
    case input = "Input"
    case cacheRead = "Cache read"
    case cacheWrite = "Cache write"
    case cost = "Est. cost"
    var id: String { rawValue }
    var isCost: Bool { self == .cost }
}

struct ModelStat: Codable, Identifiable {
    var id: String { model }
    let model: String
    var input: Int
    var output: Int
    var cacheRead: Int
    var cacheWrite: Int
    var cost: Double
    var messageCount: Int

    var totalTokens: Int { input + output + cacheRead + cacheWrite }
    var displayName: String { Fmt.shortModel(model) }
}

struct ProjectStat: Identifiable {
    var id: String { projectKey }
    let projectKey: String
    let projectName: String
    var activeSeconds: Double
    var cost: Double
    var sessions: Int
}

struct UsageAggregation {
    var days: [DayPoint] = []               // ascending by date
    var models: [ModelStat] = []            // descending by cost
    var projects: [ProjectStat] = []        // descending by activeSeconds
    var hourHistogram: [Double] = Array(repeating: 0, count: 24)  // messages by local hour

    var totalActiveSeconds: Double = 0
    var totalCost: Double = 0
    var totalInput: Int = 0
    var totalOutput: Int = 0
    var totalCacheRead: Int = 0
    var totalCacheWrite: Int = 0
    var sessionsActive: Int = 0

    var longest: (sessionId: String, seconds: Double)?
    var mostExpensive: (sessionId: String, cost: Double)?

    var totalInOutTokens: Int { totalInput + totalOutput }
    var totalTokens: Int { totalInput + totalOutput + totalCacheRead + totalCacheWrite }

    /// cache_read / (input + cache_read)
    var cacheHitRate: Double {
        let denom = Double(totalInput + totalCacheRead)
        return denom > 0 ? Double(totalCacheRead) / denom : 0
    }

    /// Σ cache_read × (input_rate − cacheRead_rate) / 1e6 across models.
    var cacheSavings: Double {
        models.reduce(0) { acc, m in
            let p = Pricing.pricing(for: m.model)
            return acc + Double(m.cacheRead) * (p.input - p.cacheRead) / 1_000_000
        }
    }

    var costPerActiveHour: Double {
        let hours = totalActiveSeconds / 3600
        return hours > 0 ? totalCost / hours : 0
    }
}

// MARK: - Engine

enum UsageAnalytics {

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    /// Builds a per-session record from a raw scan. `heartbeatGap` = 300s, tail = 60s (spec).
    static func buildRecord(sessionId: String, transcriptPath: String, projectKey: String,
                            mtime: Date, size: Int64, extraction: UsageExtraction) -> UsageRecord {
        let events = extraction.events.map {
            UsageEvent(model: $0.model, input: $0.input, output: $0.output,
                       cacheRead: $0.cacheRead, cacheWrite: $0.cacheWrite, timestamp: $0.timestamp)
        }

        // Heartbeat active-time from all timestamps.
        var daily: [String: Double] = [:]
        var totalActive: Double = 0
        let ts = extraction.allTimestamps          // sorted ascending
        if ts.count >= 2 {
            for i in 1..<ts.count {
                let gap = ts[i].timeIntervalSince(ts[i - 1])
                guard gap > 0, gap <= 300 else { continue }   // idle gap contributes 0
                totalActive += gap
                daily[dayFormatter.string(from: ts[i - 1]), default: 0] += gap
            }
        }
        // Fixed 60s tail per session, attributed to the last timestamp's day.
        if let last = ts.last {
            totalActive += 60
            daily[dayFormatter.string(from: last), default: 0] += 60
        }

        var tin = 0, tout = 0, tcr = 0, tcw = 0
        var cost: Double = 0
        for e in events {
            tin += e.input; tout += e.output; tcr += e.cacheRead; tcw += e.cacheWrite
            cost += e.cost
        }

        return UsageRecord(
            sessionId: sessionId, transcriptPath: transcriptPath, projectKey: projectKey,
            fileModifiedAt: mtime, fileSize: size,
            events: events, dailyActiveSeconds: daily, totalActiveSeconds: totalActive,
            firstTimestamp: ts.first, lastTimestamp: ts.last,
            totalInput: tin, totalOutput: tout, totalCacheRead: tcr, totalCacheWrite: tcw, totalCost: cost
        )
    }

    /// Per-model rollup for a set of events (used by the per-session Usage card).
    static func modelStats(from events: [UsageEvent]) -> [ModelStat] {
        var byModel: [String: ModelStat] = [:]
        for e in events {
            var s = byModel[e.model] ?? ModelStat(model: e.model, input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, messageCount: 0)
            s.input += e.input; s.output += e.output; s.cacheRead += e.cacheRead; s.cacheWrite += e.cacheWrite
            s.cost += e.cost; s.messageCount += 1
            byModel[e.model] = s
        }
        return byModel.values.sorted { $0.cost > $1.cost }
    }

    private static func dayIsInRange(_ day: String, _ range: DateInterval?) -> Bool {
        guard let range else { return true }
        guard let d = dayFormatter.date(from: day) else { return true }
        // A local day belongs to the range if its midnight falls within it, or the
        // range starts partway through the day.
        let dayEnd = d.addingTimeInterval(86_400)
        return dayEnd > range.start && d <= range.end
    }

    /// Aggregates per-session records into dashboard buckets, filtered by `range`.
    static func aggregate(records: [UsageRecord], range: DateInterval?,
                          projectNames: [String: String]) -> UsageAggregation {
        var days: [String: DayPoint] = [:]
        var models: [String: ModelStat] = [:]
        var projects: [String: ProjectStat] = [:]
        var hours = Array(repeating: 0.0, count: 24)
        var sessionActive: [String: Double] = [:]
        var sessionCost: [String: Double] = [:]
        var activeSessionIds = Set<String>()

        let cal = Calendar.current
        var agg = UsageAggregation()

        for rec in records {
            // Token/cost events, bucketed by their own timestamps.
            for e in rec.events {
                guard let ts = e.timestamp else { continue }
                if let range, !range.contains(ts) { continue }
                let dayKey = dayFormatter.string(from: ts)
                let cost = e.cost

                var dp = days[dayKey] ?? DayPoint(day: dayKey, date: dayFormatter.date(from: dayKey) ?? ts)
                dp.input += e.input; dp.output += e.output; dp.cacheRead += e.cacheRead; dp.cacheWrite += e.cacheWrite
                dp.cost += cost; dp.sessions.insert(rec.sessionId)
                days[dayKey] = dp

                var ms = models[e.model] ?? ModelStat(model: e.model, input: 0, output: 0, cacheRead: 0, cacheWrite: 0, cost: 0, messageCount: 0)
                ms.input += e.input; ms.output += e.output; ms.cacheRead += e.cacheRead; ms.cacheWrite += e.cacheWrite
                ms.cost += cost; ms.messageCount += 1
                models[e.model] = ms

                var ps = projects[rec.projectKey] ?? ProjectStat(projectKey: rec.projectKey, projectName: projectNames[rec.projectKey] ?? rec.projectKey, activeSeconds: 0, cost: 0, sessions: 0)
                ps.cost += cost
                projects[rec.projectKey] = ps

                sessionCost[rec.sessionId, default: 0] += cost
                activeSessionIds.insert(rec.sessionId)
                hours[cal.component(.hour, from: ts)] += 1

                agg.totalInput += e.input; agg.totalOutput += e.output
                agg.totalCacheRead += e.cacheRead; agg.totalCacheWrite += e.cacheWrite
                agg.totalCost += cost
            }

            // Heartbeat active seconds, bucketed by local day.
            for (day, secs) in rec.dailyActiveSeconds where dayIsInRange(day, range) {
                var dp = days[day] ?? DayPoint(day: day, date: dayFormatter.date(from: day) ?? Date())
                dp.activeSeconds += secs
                dp.sessions.insert(rec.sessionId)
                days[day] = dp

                var ps = projects[rec.projectKey] ?? ProjectStat(projectKey: rec.projectKey, projectName: projectNames[rec.projectKey] ?? rec.projectKey, activeSeconds: 0, cost: 0, sessions: 0)
                ps.activeSeconds += secs
                projects[rec.projectKey] = ps

                sessionActive[rec.sessionId, default: 0] += secs
                activeSessionIds.insert(rec.sessionId)
                agg.totalActiveSeconds += secs
            }
        }

        // Session counts per project.
        var projectSessions: [String: Set<String>] = [:]
        for id in activeSessionIds {
            if let rec = records.first(where: { $0.sessionId == id }) {
                projectSessions[rec.projectKey, default: []].insert(id)
            }
        }
        for key in projects.keys {
            projects[key]?.sessions = projectSessions[key]?.count ?? 0
        }

        agg.days = days.values.sorted { $0.date < $1.date }
        agg.models = models.values.sorted { $0.cost > $1.cost }
        agg.projects = projects.values.filter { $0.activeSeconds > 0 || $0.cost > 0 }.sorted { $0.activeSeconds > $1.activeSeconds }
        agg.hourHistogram = hours
        agg.sessionsActive = activeSessionIds.count
        agg.longest = sessionActive.max { $0.value < $1.value }.map { ($0.key, $0.value) }
        agg.mostExpensive = sessionCost.max { $0.value < $1.value }.map { ($0.key, $0.value) }
        return agg
    }

    /// Collapses daily points into ISO-week buckets when a range spans > 60 days.
    static func weekBuckets(_ days: [DayPoint]) -> [DayPoint] {
        var byWeek: [String: DayPoint] = [:]
        let cal = Calendar.current
        for dp in days {
            let comps = cal.dateComponents([.yearForWeekOfYear, .weekOfYear], from: dp.date)
            let start = cal.date(from: comps) ?? dp.date
            let key = dayFormatter.string(from: start)
            var w = byWeek[key] ?? DayPoint(day: key, date: start)
            w.activeSeconds += dp.activeSeconds
            w.input += dp.input; w.output += dp.output; w.cacheRead += dp.cacheRead; w.cacheWrite += dp.cacheWrite
            w.cost += dp.cost
            byWeek[key] = w
        }
        return byWeek.values.sorted { $0.date < $1.date }
    }
}

// MARK: - Model tiers (for the model-mix insight)

enum ModelTier: String {
    case fable = "Fable"
    case opus = "Opus"
    case sonnet = "Sonnet"
    case haiku = "Haiku"
    case other = "Other"

    static func of(_ model: String) -> ModelTier {
        let m = model.lowercased()
        if m.contains("fable") || m.contains("mythos") { return .fable }
        if m.contains("opus") { return .opus }
        if m.contains("sonnet") { return .sonnet }
        if m.contains("haiku") { return .haiku }
        return .other
    }
}

// MARK: - Formatting

enum Fmt {
    /// 1.2K / 3.4M / 1.1B token counts.
    static func tokens(_ n: Int) -> String {
        let v = Double(n)
        if n >= 1_000_000_000 { return trim(v / 1_000_000_000) + "B" }
        if n >= 1_000_000 { return trim(v / 1_000_000) + "M" }
        if n >= 1_000 { return trim(v / 1_000) + "K" }
        return "\(n)"
    }

    private static func trim(_ v: Double) -> String {
        let s = String(format: "%.1f", v)
        return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
    }

    /// $1,234.56 — 2 decimals, or 4 decimals when < $1.
    static func cost(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.currencyCode = "USD"
        f.currencySymbol = "$"
        if abs(v) < 1 && v != 0 {
            f.minimumFractionDigits = 4
            f.maximumFractionDigits = 4
        } else {
            f.minimumFractionDigits = 2
            f.maximumFractionDigits = 2
        }
        return f.string(from: NSNumber(value: v)) ?? "$0.00"
    }

    /// "3h 24m" / "24m" / "45s".
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m" }
        if total > 0 { return "\(total)s" }
        return "0m"
    }

    /// Strips date suffix, "[…]" markers, and the "claude-" prefix from a model id.
    static func shortModel(_ id: String) -> String {
        var s = id
        // Drop bracketed context markers like "[1m]".
        if let b = s.range(of: "[", options: .backwards) { s = String(s[s.startIndex..<b.lowerBound]) }
        // Drop trailing -YYYYMMDD date suffix.
        s = s.replacingOccurrences(of: "-[0-9]{6,8}$", with: "", options: .regularExpression)
        if s.hasPrefix("claude-") { s = String(s.dropFirst("claude-".count)) }
        if s.isEmpty { return id }
        return s.prefix(1).uppercased() + s.dropFirst()
    }
}
