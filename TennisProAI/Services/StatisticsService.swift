import Foundation

// MARK: - Aggregated Statistics & Analytics Value Types

struct SurfacePerformanceSummary: Identifiable, Equatable, Sendable {
    var id: String { surface.rawValue }
    let surface: CourtSurface
    let matchesPlayed: Int
    let wins: Int
    let losses: Int
    var winPercentage: Double {
        guard matchesPlayed > 0 else { return 0 }
        return (Double(wins) / Double(matchesPlayed)) * 100.0
    }
}

struct OpponentPerformanceSummary: Identifiable, Equatable, Sendable {
    var id: String { opponentName.lowercased() }
    let opponentName: String
    let matchesPlayed: Int
    let wins: Int
    let losses: Int
    var winPercentage: Double {
        guard matchesPlayed > 0 else { return 0 }
        return (Double(wins) / Double(matchesPlayed)) * 100.0
    }
}

struct MatchTrendPoint: Identifiable, Equatable, Sendable {
    let id: UUID
    let matchDate: Date
    let shortLabel: String
    let opponentName: String
    let isWin: Bool
    let durationMinutes: Double
    let aces: Int
    let doubleFaults: Int
    let firstServePercentage: Double?
    let winners: Int
    let unforcedErrors: Int
}

struct AggregatedPlayerStatistics: Equatable, Sendable {
    let filterRange: DateFilterRange
    let totalMatches: Int
    let completedMatches: Int
    let wins: Int
    let losses: Int
    /// Nil when completedMatches == 0 to avoid misleading 0% win rate on empty data.
    let winPercentage: Double?
    let totalPlayingDurationSeconds: Double
    let averageMatchDurationMinutes: Double?
    let acesPerMatch: Double?
    let doubleFaultsPerMatch: Double?
    /// Weighted across all recorded first-serve attempts; nil if no serve attempts were tracked.
    let overallFirstServePercentage: Double?
    let totalWinners: Int
    let totalUnforcedErrors: Int
    let surfaceBreakdowns: [SurfacePerformanceSummary]
    let opponentBreakdowns: [OpponentPerformanceSummary]
    let chronologicalTrend: [MatchTrendPoint]

    var hasSufficientData: Bool {
        totalMatches > 0
    }
}

struct MatchComparisonMetricDelta: Identifiable, Equatable, Sendable {
    var id: String { metricName }
    let metricName: String
    let primaryDisplay: String
    let baselineDisplay: String
    /// Positive when higher is better and primary > baseline (or when lower is better, e.g. double faults/errors, and primary < baseline).
    let isFavorable: Bool?
}

// MARK: - Statistics Calculation Service

enum StatisticsService {
    static func calculateStatistics(
        matches: [MatchRecord],
        range: DateFilterRange,
        referenceDate: Date = Date()
    ) -> AggregatedPlayerStatistics {
        let cutoff = range.startDate(relativeTo: referenceDate)
        let filtered = matches.filter { match in
            if let cutoff {
                return match.matchDate >= cutoff
            }
            return true
        }.sorted { $0.matchDate < $1.matchDate }

        let totalMatches = filtered.count
        let decidedMatches = filtered.filter { $0.isPlayerWinner != nil }
        let wins = decidedMatches.filter { $0.isPlayerWinner == true }.count
        let losses = decidedMatches.filter { $0.isPlayerWinner == false }.count

        let winPct: Double? = decidedMatches.isEmpty
            ? nil
            : (Double(wins) / Double(decidedMatches.count)) * 100.0

        let totalDurationSec = filtered.reduce(0.0) { $0 + max(0, $1.durationSeconds) }
        let matchesWithDuration = filtered.filter { $0.durationSeconds > 0 }
        let avgDurationMin: Double? = matchesWithDuration.isEmpty
            ? nil
            : (matchesWithDuration.reduce(0.0) { $0 + $1.durationSeconds } / Double(matchesWithDuration.count)) / 60.0

        var sumFirstServesMade = 0
        var sumFirstServeAttempts = 0
        var sumAces = 0
        var sumDoubleFaults = 0
        var sumWinners = 0
        var sumUnforcedErrors = 0

        for match in filtered {
            let s = match.statistics
            sumFirstServesMade += max(0, s.firstServesMade)
            sumFirstServeAttempts += max(0, s.firstServeAttempts)
            sumAces += max(0, s.aces)
            sumDoubleFaults += max(0, s.doubleFaults)
            sumWinners += max(0, s.winners)
            sumUnforcedErrors += max(0, s.unforcedErrors)
        }

        let acesPerMatch: Double? = totalMatches > 0 ? Double(sumAces) / Double(totalMatches) : nil
        let dfPerMatch: Double? = totalMatches > 0 ? Double(sumDoubleFaults) / Double(totalMatches) : nil
        let firstServePct: Double? = sumFirstServeAttempts > 0
            ? (Double(min(sumFirstServesMade, sumFirstServeAttempts)) / Double(sumFirstServeAttempts)) * 100.0
            : nil

        // Surface Breakdown
        var surfaceMap: [CourtSurface: (played: Int, wins: Int, losses: Int)] = [:]
        for match in decidedMatches {
            var entry = surfaceMap[match.surface] ?? (0, 0, 0)
            entry.played += 1
            if match.isPlayerWinner == true {
                entry.wins += 1
            } else {
                entry.losses += 1
            }
            surfaceMap[match.surface] = entry
        }
        let surfaceBreakdowns = surfaceMap.map { surface, counts in
            SurfacePerformanceSummary(
                surface: surface,
                matchesPlayed: counts.played,
                wins: counts.wins,
                losses: counts.losses
            )
        }.sorted { $0.matchesPlayed > $1.matchesPlayed }

        // Opponent Breakdown
        var opponentMap: [String: (displayName: String, played: Int, wins: Int, losses: Int)] = [:]
        for match in decidedMatches {
            let trimmed = match.opponentTeamDisplayName.trimmingCharacters(in: .whitespacesAndNewlines)
            let key = trimmed.isEmpty ? "Unknown Opponent" : trimmed.lowercased()
            let display = trimmed.isEmpty ? "Unknown Opponent" : trimmed
            var entry = opponentMap[key] ?? (display, 0, 0, 0)
            entry.played += 1
            if match.isPlayerWinner == true {
                entry.wins += 1
            } else {
                entry.losses += 1
            }
            opponentMap[key] = entry
        }
        let opponentBreakdowns = opponentMap.values.map { item in
            OpponentPerformanceSummary(
                opponentName: item.displayName,
                matchesPlayed: item.played,
                wins: item.wins,
                losses: item.losses
            )
        }.sorted { lhs, rhs in
            if lhs.matchesPlayed != rhs.matchesPlayed {
                return lhs.matchesPlayed > rhs.matchesPlayed
            }
            return lhs.winPercentage > rhs.winPercentage
        }

        // Chronological Trend Points
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MMM d"

        let trend = filtered.enumerated().map { index, match in
            let s = match.statistics
            return MatchTrendPoint(
                id: match.id,
                matchDate: match.matchDate,
                shortLabel: "M\(index + 1) (\(dateFormatter.string(from: match.matchDate)))",
                opponentName: match.opponentTeamDisplayName,
                isWin: match.isPlayerWinner ?? false,
                durationMinutes: max(0, match.durationSeconds / 60.0),
                aces: s.aces,
                doubleFaults: s.doubleFaults,
                firstServePercentage: s.firstServePercentage,
                winners: s.winners,
                unforcedErrors: s.unforcedErrors
            )
        }

        return AggregatedPlayerStatistics(
            filterRange: range,
            totalMatches: totalMatches,
            completedMatches: decidedMatches.count,
            wins: wins,
            losses: losses,
            winPercentage: winPct,
            totalPlayingDurationSeconds: totalDurationSec,
            averageMatchDurationMinutes: avgDurationMin,
            acesPerMatch: acesPerMatch,
            doubleFaultsPerMatch: dfPerMatch,
            overallFirstServePercentage: firstServePct,
            totalWinners: sumWinners,
            totalUnforcedErrors: sumUnforcedErrors,
            surfaceBreakdowns: surfaceBreakdowns,
            opponentBreakdowns: opponentBreakdowns,
            chronologicalTrend: trend
        )
    }

    static func compareMatch(_ current: MatchRecord, against baseline: MatchRecord) -> [MatchComparisonMetricDelta] {
        let c = current.statistics
        let b = baseline.statistics

        var rows: [MatchComparisonMetricDelta] = []

        rows.append(makePercentDelta(
            name: "First-Serve %",
            primary: c.firstServePercentage,
            baseline: b.firstServePercentage,
            higherIsBetter: true
        ))
        rows.append(makeIntDelta(name: "Aces", primary: c.aces, baseline: b.aces, higherIsBetter: true))
        rows.append(makeIntDelta(name: "Double Faults", primary: c.doubleFaults, baseline: b.doubleFaults, higherIsBetter: false))
        rows.append(makeIntDelta(name: "Winners", primary: c.winners, baseline: b.winners, higherIsBetter: true))
        rows.append(makeIntDelta(name: "Unforced Errors", primary: c.unforcedErrors, baseline: b.unforcedErrors, higherIsBetter: false))
        rows.append(makeIntDelta(name: "Forehand Errors", primary: c.forehandErrors, baseline: b.forehandErrors, higherIsBetter: false))
        rows.append(makeIntDelta(name: "Backhand Errors", primary: c.backhandErrors, baseline: b.backhandErrors, higherIsBetter: false))
        rows.append(makePercentDelta(
            name: "Net Points Won %",
            primary: c.netSuccessPercentage,
            baseline: b.netSuccessPercentage,
            higherIsBetter: true
        ))
        rows.append(makePercentDelta(
            name: "Break Points Won %",
            primary: c.breakPointConversionPercentage,
            baseline: b.breakPointConversionPercentage,
            higherIsBetter: true
        ))
        rows.append(makeIntDelta(name: "Total Points Won", primary: c.totalPointsWon, baseline: b.totalPointsWon, higherIsBetter: true))

        return rows
    }

    private static func makeIntDelta(name: String, primary: Int, baseline: Int, higherIsBetter: Bool) -> MatchComparisonMetricDelta {
        let favorable: Bool?
        if primary == baseline {
            favorable = nil
        } else {
            favorable = higherIsBetter ? (primary > baseline) : (primary < baseline)
        }
        return MatchComparisonMetricDelta(
            metricName: name,
            primaryDisplay: "\(primary)",
            baselineDisplay: "\(baseline)",
            isFavorable: favorable
        )
    }

    private static func makePercentDelta(name: String, primary: Double?, baseline: Double?, higherIsBetter: Bool) -> MatchComparisonMetricDelta {
        let pText = primary.map { String(format: "%.1f%%", $0) } ?? "—"
        let bText = baseline.map { String(format: "%.1f%%", $0) } ?? "—"
        var favorable: Bool? = nil
        if let p = primary, let b = baseline, abs(p - b) >= 0.05 {
            favorable = higherIsBetter ? (p > b) : (p < b)
        }
        return MatchComparisonMetricDelta(
            metricName: name,
            primaryDisplay: pText,
            baselineDisplay: bText,
            isFavorable: favorable
        )
    }
}

