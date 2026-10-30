import XCTest
@testable import TennisProAI

final class StatisticsServiceTests: XCTestCase {

    func testEmptyMatchListProducesCleanEmptyStateWithoutNaN() {
        let summary = StatisticsService.calculateStatistics(matches: [], range: .allTime)
        XCTAssertFalse(summary.hasSufficientData)
        XCTAssertEqual(summary.totalMatches, 0)
        XCTAssertNil(summary.winPercentage)
        XCTAssertNil(summary.overallFirstServePercentage)
        XCTAssertNil(summary.acesPerMatch)
        XCTAssertTrue(summary.surfaceBreakdowns.isEmpty)
        XCTAssertTrue(summary.opponentBreakdowns.isEmpty)
    }

    func testMissingServeAttemptsDoesNotProduceMisleadingZeroPercent() {
        // Match logged without tracking serve attempts
        var stats = MatchStatisticsData()
        stats.winners = 14
        stats.unforcedErrors = 10
        XCTAssertNil(stats.firstServePercentage)
        XCTAssertNil(stats.secondServePercentage)
        XCTAssertNil(stats.netSuccessPercentage)

        let match = MatchRecord(
            playerName: "Alex",
            opponentName: "Sam",
            status: .completed,
            isPlayerWinner: true,
            finalScoreSummary: "6-3, 6-4",
            statistics: stats
        )

        let agg = StatisticsService.calculateStatistics(matches: [match], range: .allTime)
        XCTAssertTrue(agg.hasSufficientData)
        XCTAssertEqual(agg.winPercentage, 100.0)
        XCTAssertNil(agg.overallFirstServePercentage)
    }

    func testAggregatedStatisticsDateFilteringSurfaceAndOpponentBreakdowns() {
        let now = Date()
        let fiveDaysAgo = Calendar.current.date(byAdding: .day, value: -5, to: now)!
        let fortyDaysAgo = Calendar.current.date(byAdding: .day, value: -40, to: now)!

        var s1 = MatchStatisticsData()
        s1.firstServesMade = 30
        s1.firstServeAttempts = 50 // 60%
        s1.aces = 8
        s1.doubleFaults = 2
        s1.winners = 24
        s1.unforcedErrors = 16

        let recentHardWin = MatchRecord(
            playerName: "Alex",
            opponentName: "Novak",
            matchDate: fiveDaysAgo,
            surface: .hard,
            status: .completed,
            isPlayerWinner: true,
            finalScoreSummary: "6-4, 6-4",
            durationSeconds: 5400,
            statistics: s1
        )

        var s2 = MatchStatisticsData()
        s2.firstServesMade = 40
        s2.firstServeAttempts = 50 // 80%
        s2.aces = 2
        s2.doubleFaults = 4
        s2.winners = 15
        s2.unforcedErrors = 25

        let olderClayLoss = MatchRecord(
            playerName: "Alex",
            opponentName: "Carlos",
            matchDate: fortyDaysAgo,
            surface: .clay,
            status: .completed,
            isPlayerWinner: false,
            finalScoreSummary: "3-6, 4-6",
            durationSeconds: 4800,
            statistics: s2
        )

        // Last 7 days should include only recentHardWin
        let last7 = StatisticsService.calculateStatistics(
            matches: [recentHardWin, olderClayLoss],
            range: .last7Days,
            referenceDate: now
        )
        XCTAssertEqual(last7.totalMatches, 1)
        XCTAssertEqual(last7.wins, 1)
        XCTAssertEqual(last7.losses, 0)
        XCTAssertEqual(last7.overallFirstServePercentage, 60.0)

        // All time includes both -> weighted 1st serve = (30 + 40) / (50 + 50) = 70%
        let allTime = StatisticsService.calculateStatistics(
            matches: [recentHardWin, olderClayLoss],
            range: .allTime,
            referenceDate: now
        )
        XCTAssertEqual(allTime.totalMatches, 2)
        XCTAssertEqual(allTime.wins, 1)
        XCTAssertEqual(allTime.losses, 1)
        XCTAssertEqual(allTime.winPercentage, 50.0)
        XCTAssertEqual(allTime.overallFirstServePercentage, 70.0)
        XCTAssertEqual(allTime.acesPerMatch, 5.0)
        XCTAssertEqual(allTime.doubleFaultsPerMatch, 3.0)
        XCTAssertEqual(allTime.totalWinners, 39)
        XCTAssertEqual(allTime.totalUnforcedErrors, 41)
        XCTAssertEqual(allTime.surfaceBreakdowns.count, 2)
        XCTAssertEqual(allTime.opponentBreakdowns.count, 2)

        // Match comparison check
        let comparison = StatisticsService.compareMatch(recentHardWin, against: olderClayLoss)
        let acesDelta = comparison.first(where: { $0.metricName == "Aces" })
        XCTAssertEqual(acesDelta?.isFavorable, true)
        let dfDelta = comparison.first(where: { $0.metricName == "Double Faults" })
        XCTAssertEqual(dfDelta?.isFavorable, true) // 2 double faults < 4 double faults is favorable
    }
}

