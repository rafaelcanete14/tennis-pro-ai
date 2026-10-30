import XCTest
@testable import TennisProAI

final class MatchScoringServiceTests: XCTestCase {

    func testStandardGameProgressionLove153040Game() {
        let engine = MatchScoringService(format: MatchFormatConfig(bestOfSets: 3), initialServer: .player)
        XCTAssertEqual(engine.playerPointDisplay, "0")
        XCTAssertEqual(engine.opponentPointDisplay, "0")

        engine.recordPoint(winner: .player)
        XCTAssertEqual(engine.playerPointDisplay, "15")

        engine.recordPoint(winner: .player)
        XCTAssertEqual(engine.playerPointDisplay, "30")

        engine.recordPoint(winner: .player)
        XCTAssertEqual(engine.playerPointDisplay, "40")

        engine.recordPoint(winner: .player)
        XCTAssertEqual(engine.state.sets[0].playerGames, 1)
        XCTAssertEqual(engine.state.sets[0].opponentGames, 0)
        XCTAssertEqual(engine.playerPointDisplay, "0")
        // Server rotates after game completion
        XCTAssertEqual(engine.state.currentServer, .opponent)
    }

    func testDeuceAndAdvantageHandling() {
        let engine = MatchScoringService(format: MatchFormatConfig(bestOfSets: 3, noAdScoring: false))
        for _ in 0..<3 {
            engine.recordPoint(winner: .player)
            engine.recordPoint(winner: .opponent)
        }
        XCTAssertTrue(engine.isDeuce)
        XCTAssertNil(engine.advantageSide)
        XCTAssertEqual(engine.playerPointDisplay, "40")
        XCTAssertEqual(engine.opponentPointDisplay, "40")

        // Advantage Player
        engine.recordPoint(winner: .player)
        XCTAssertFalse(engine.isDeuce)
        XCTAssertEqual(engine.advantageSide, .player)
        XCTAssertEqual(engine.playerPointDisplay, "AD")
        XCTAssertEqual(engine.opponentPointDisplay, "40")

        // Back to Deuce
        engine.recordPoint(winner: .opponent)
        XCTAssertTrue(engine.isDeuce)
        XCTAssertNil(engine.advantageSide)

        // Advantage Opponent -> Game Opponent (Break of serve)
        engine.recordPoint(winner: .opponent)
        XCTAssertEqual(engine.advantageSide, .opponent)
        engine.recordPoint(winner: .opponent)
        XCTAssertEqual(engine.state.sets[0].opponentGames, 1)
        XCTAssertEqual(engine.state.statistics.breakPointsFaced, 1)
    }

    func testNoAdSuddenDeathDeuce() {
        let engine = MatchScoringService(format: MatchFormatConfig(bestOfSets: 3, noAdScoring: true))
        for _ in 0..<3 {
            engine.recordPoint(winner: .player)
            engine.recordPoint(winner: .opponent)
        }
        XCTAssertTrue(engine.isDeuce)

        // Next point immediately wins the game in No-Ad format
        engine.recordPoint(winner: .player)
        XCTAssertEqual(engine.state.sets[0].playerGames, 1)
    }

    func testSevenPointTiebreakAtSixAllAndServerRotation() {
        let engine = MatchScoringService(
            format: MatchFormatConfig(bestOfSets: 3, tiebreakAtSixAll: true),
            initialServer: .player
        )

        // Advance to 6-6 (alternating games)
        for game in 0..<12 {
            let winner: MatchParticipantSide = (game % 2 == 0) ? .player : .opponent
            for _ in 0..<4 {
                engine.recordPoint(winner: winner)
            }
        }

        XCTAssertEqual(engine.state.sets[0].playerGames, 6)
        XCTAssertEqual(engine.state.sets[0].opponentGames, 6)
        XCTAssertTrue(engine.state.isCurrentlyInTiebreak)
        XCTAssertEqual(engine.state.currentServer, .player) // First point of TB served by Player

        // Point 1: Player wins -> odd total (1) rotates server to Opponent
        engine.recordPoint(winner: .player)
        XCTAssertEqual(engine.state.currentServer, .opponent)

        // Point 2: Opponent wins -> even total (2) keeps Opponent serving
        engine.recordPoint(winner: .opponent)
        XCTAssertEqual(engine.state.currentServer, .opponent)

        // Point 3: Player wins -> odd total (3) rotates server back to Player
        engine.recordPoint(winner: .player)
        XCTAssertEqual(engine.state.currentServer, .player)

        // Bring tiebreak to 6-6 (must win by 2)
        // Currently 2-1 Player; add 4 for Player (6) and 5 for Opponent (6)
        for _ in 0..<4 { engine.recordPoint(winner: .player) }
        for _ in 0..<5 { engine.recordPoint(winner: .opponent) }
        XCTAssertTrue(engine.state.isCurrentlyInTiebreak)

        // 7-6 in TB is not enough (margin 1)
        engine.recordPoint(winner: .player)
        XCTAssertTrue(engine.state.isCurrentlyInTiebreak)

        // 8-6 clinches the tiebreak and Set 1 (7-6(6))
        engine.recordPoint(winner: .player)
        XCTAssertFalse(engine.state.isCurrentlyInTiebreak)
        XCTAssertEqual(engine.state.sets[0].winner, .player)
        XCTAssertEqual(engine.state.sets[0].displayScore, "7-6(6)")
        XCTAssertEqual(engine.state.currentSetIndex, 1)
        // Since Player served first in the tiebreak, Opponent serves first in Set 2
        XCTAssertEqual(engine.state.currentServer, .opponent)
    }

    func testBestOfThreeMatchCompletionAndFinalSetSuperTiebreak() {
        let format = MatchFormatConfig(bestOfSets: 3, tiebreakAtSixAll: true, finalSetSuperTiebreak: true)
        let engine = MatchScoringService(format: format)

        // Set 1: Player wins 6-0
        for _ in 0..<(6 * 4) { engine.recordPoint(winner: .player) }
        XCTAssertEqual(engine.state.sets[0].winner, .player)
        XCTAssertFalse(engine.isMatchComplete)

        // Set 2: Opponent wins 6-0 -> triggers Set 3 10-point Super Tiebreak
        for _ in 0..<(6 * 4) { engine.recordPoint(winner: .opponent) }
        XCTAssertEqual(engine.state.sets[1].winner, .opponent)
        XCTAssertTrue(engine.state.isCurrentlyInTiebreak)
        XCTAssertTrue(engine.state.isCurrentTiebreakSuper)

        // Win 10 straight points in Super Tiebreak
        for _ in 0..<10 { engine.recordPoint(winner: .player) }
        XCTAssertTrue(engine.isMatchComplete)
        XCTAssertEqual(engine.state.matchWinner, .player)
        XCTAssertEqual(engine.formattedScoreSummary(), "6-0, 0-6, [10-0]")
    }

    func testUndoRestoresExactPreviousScoreAndStatsAcrossSetAndMatchBoundaries() {
        let engine = MatchScoringService(format: MatchFormatConfig(bestOfSets: 3))

        // Win Set 1 (6-0) and Set 2 up to 5-0, 40-0 (Match Point)
        for _ in 0..<(6 * 4) { engine.recordPoint(winner: .player, outcome: .forehandWinner) }
        for _ in 0..<(5 * 4 + 3) { engine.recordPoint(winner: .player) }

        XCTAssertFalse(engine.isMatchComplete)
        let winnersBeforeMatchPoint = engine.state.statistics.winners

        // Clinch Match Point with an Ace
        engine.recordPoint(winner: .player, wasFirstServeIn: true, outcome: .ace)
        XCTAssertTrue(engine.isMatchComplete)
        XCTAssertEqual(engine.state.statistics.aces, 1)
        XCTAssertEqual(engine.state.statistics.winners, winnersBeforeMatchPoint + 1)

        // Undo Match Point -> match must reopen at 5-0, 40-0 with Ace rolled back!
        XCTAssertTrue(engine.undoLastPoint())
        XCTAssertFalse(engine.isMatchComplete)
        XCTAssertNil(engine.state.matchWinner)
        XCTAssertEqual(engine.state.sets[1].playerGames, 5)
        XCTAssertEqual(engine.playerPointDisplay, "40")
        XCTAssertEqual(engine.state.statistics.aces, 0)
        XCTAssertEqual(engine.state.statistics.winners, winnersBeforeMatchPoint)
    }

    func testManualMatchScoreValidator() throws {
        let standardFormat = MatchFormatConfig(bestOfSets: 3, tiebreakAtSixAll: true)

        // Valid 6-4, 7-6 win
        let validSets = [
            SetScoreSnapshot(setNumber: 1, playerGames: 6, opponentGames: 4),
            SetScoreSnapshot(setNumber: 2, playerGames: 7, opponentGames: 6)
        ]
        let winner = try MatchScoreValidator.validate(sets: validSets, format: standardFormat, status: .completed)
        XCTAssertEqual(winner, .player)

        // Invalid 6-5 completed set score must fail
        let invalidSixFive = [
            SetScoreSnapshot(setNumber: 1, playerGames: 6, opponentGames: 5),
            SetScoreSnapshot(setNumber: 2, playerGames: 6, opponentGames: 2)
        ]
        XCTAssertThrowsError(try MatchScoreValidator.validate(sets: invalidSixFive, format: standardFormat, status: .completed))

        // Playing a 3rd set after already winning 2-0 in Best-of-3 must fail
        let extraSetAfterClinch = [
            SetScoreSnapshot(setNumber: 1, playerGames: 6, opponentGames: 2),
            SetScoreSnapshot(setNumber: 2, playerGames: 6, opponentGames: 3),
            SetScoreSnapshot(setNumber: 3, playerGames: 6, opponentGames: 4)
        ]
        XCTAssertThrowsError(try MatchScoreValidator.validate(sets: extraSetAfterClinch, format: standardFormat, status: .completed))
    }
}

