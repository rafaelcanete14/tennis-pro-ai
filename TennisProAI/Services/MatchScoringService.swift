import Foundation

// MARK: - Validation Errors for Manual Match Scores

enum MatchScoreValidationError: LocalizedError, Equatable {
    case emptySets
    case tooManySets(maxAllowed: Int)
    case invalidSetGameScore(setNumber: Int, playerGames: Int, opponentGames: Int)
    case incompleteMatchWinnerMismatch
    case setsContinuedAfterMatchWon

    var errorDescription: String? {
        switch self {
        case .emptySets:
            return "At least one set score is required."
        case .tooManySets(let maxAllowed):
            return "A best-of-\(maxAllowed) match cannot contain more than \(maxAllowed) sets."
        case .invalidSetGameScore(let setNumber, let p, let o):
            return "Set \(setNumber) score (\(p)-\(o)) is not valid for the selected tennis scoring format."
        case .incompleteMatchWinnerMismatch:
            return "Completed match requires one side to win the required number of sets."
        case .setsContinuedAfterMatchWon:
            return "Additional sets cannot be recorded after a player has already clinched the match."
        }
    }
}

// MARK: - Serializable Live Engine State (Supports Unlimited Undo & Persistence)

struct TennisEngineState: Codable, Equatable, Sendable {
    var format: MatchFormatConfig
    var sets: [SetScoreSnapshot]
    var currentSetIndex: Int
    var playerRawPoints: Int
    var opponentRawPoints: Int
    var isCurrentlyInTiebreak: Bool
    var isCurrentTiebreakSuper: Bool
    var currentServer: MatchParticipantSide
    /// Tracks who served first in a tiebreak so odd-point rotation (1, 2, 2...) restores accurately after tiebreak ends.
    var tiebreakInitialServer: MatchParticipantSide?
    var matchWinner: MatchParticipantSide?
    var statistics: MatchStatisticsData
    var pointHistory: [PointHistoryEntry]

    init(
        format: MatchFormatConfig = MatchFormatConfig(),
        initialServer: MatchParticipantSide = .player
    ) {
        self.format = format
        self.sets = [SetScoreSnapshot(setNumber: 1)]
        self.currentSetIndex = 0
        self.playerRawPoints = 0
        self.opponentRawPoints = 0
        self.isCurrentlyInTiebreak = false
        self.isCurrentTiebreakSuper = false
        self.currentServer = initialServer
        self.tiebreakInitialServer = nil
        self.matchWinner = nil
        self.statistics = MatchStatisticsData()
        self.pointHistory = []
    }
}

// MARK: - Pure Tennis Scoring Engine

final class MatchScoringService {
    private(set) var state: TennisEngineState
    private var undoStack: [TennisEngineState] = []

    init(format: MatchFormatConfig = MatchFormatConfig(), initialServer: MatchParticipantSide = .player) {
        self.state = TennisEngineState(format: format, initialServer: initialServer)
    }

    init(restoredState: TennisEngineState) {
        self.state = restoredState
    }

    var canUndo: Bool {
        !undoStack.isEmpty
    }

    var isMatchComplete: Bool {
        state.matchWinner != nil
    }

    // MARK: - Display Point Labels (Love, 15, 30, 40, Deuce, Ad)

    var playerPointDisplay: String {
        pointDisplay(for: .player)
    }

    var opponentPointDisplay: String {
        pointDisplay(for: .opponent)
    }

    var gameSituationLabel: String {
        if let winner = state.matchWinner {
            return winner == .player ? "Match Complete • Player Won" : "Match Complete • Opponent Won"
        }
        if state.isCurrentlyInTiebreak {
            return state.isCurrentTiebreakSuper ? "Final Set 10-Point Match Tiebreak" : "7-Point Set Tiebreak"
        }
        if isDeuce {
            return state.format.noAdScoring ? "Deuce (Deciding Point)" : "Deuce"
        }
        if let adSide = advantageSide {
            return adSide == .player ? "Advantage Player" : "Advantage Opponent"
        }
        if let bpHolder = currentBreakPointHolder() {
            return bpHolder == .player ? "Break Point Opportunity" : "Break Point Faced"
        }
        return state.currentServer == .player ? "Player Serving" : "Opponent Serving"
    }

    var isDeuce: Bool {
        guard !state.isCurrentlyInTiebreak else { return false }
        if state.format.noAdScoring {
            return state.playerRawPoints == 3 && state.opponentRawPoints == 3
        }
        return state.playerRawPoints >= 3 && state.opponentRawPoints >= 3 && state.playerRawPoints == state.opponentRawPoints
    }

    var advantageSide: MatchParticipantSide? {
        guard !state.isCurrentlyInTiebreak, !state.format.noAdScoring else { return nil }
        guard state.playerRawPoints >= 3 && state.opponentRawPoints >= 3 else { return nil }
        if state.playerRawPoints == state.opponentRawPoints + 1 { return .player }
        if state.opponentRawPoints == state.playerRawPoints + 1 { return .opponent }
        return nil
    }

    private func pointDisplay(for side: MatchParticipantSide) -> String {
        if state.isCurrentlyInTiebreak {
            return side == .player ? "\(state.playerRawPoints)" : "\(state.opponentRawPoints)"
        }

        let p = state.playerRawPoints
        let o = state.opponentRawPoints

        if !state.format.noAdScoring && p >= 3 && o >= 3 {
            if p == o {
                return "40"
            }
            let hasAd = (side == .player && p > o) || (side == .opponent && o > p)
            return hasAd ? "AD" : "40"
        }

        let raw = side == .player ? p : o
        switch raw {
        case 0: return "0"
        case 1: return "15"
        case 2: return "30"
        default: return "40"
        }
    }

    // MARK: - Point Awarding & Stat Tracking

    func recordPoint(
        winner: MatchParticipantSide,
        wasFirstServeIn: Bool = true,
        outcome: PointOutcomeTag = .standardRally
    ) {
        guard state.matchWinner == nil else { return }

        // Save snapshot for exact point-by-point undo
        undoStack.append(state)

        let pointServer = state.currentServer
        let breakPointHolderBefore = currentBreakPointHolder()

        // Normalize outcome: a double fault always awards the point to the receiver
        let effectiveWinner: MatchParticipantSide
        let effectiveFirstServeIn: Bool
        if outcome == .doubleFault {
            effectiveWinner = (pointServer == .player) ? .opponent : .player
            effectiveFirstServeIn = false
        } else {
            effectiveWinner = winner
            effectiveFirstServeIn = (outcome == .ace) ? true : wasFirstServeIn
        }

        updateStatisticsBeforeScoreAdvance(
            winner: effectiveWinner,
            server: pointServer,
            wasFirstServeIn: effectiveFirstServeIn,
            outcome: outcome,
            breakPointHolderBefore: breakPointHolderBefore
        )

        if state.isCurrentlyInTiebreak {
            advanceTiebreakPoint(winner: effectiveWinner)
        } else {
            advanceStandardGamePoint(winner: effectiveWinner)
        }

        let summaryCall = formattedScoreSummary()
        state.pointHistory.append(
            PointHistoryEntry(
                winner: effectiveWinner,
                server: pointServer,
                wasFirstServeIn: effectiveFirstServeIn,
                outcomeTag: outcome,
                scoreCallAfterPoint: summaryCall
            )
        )
    }

    @discardableResult
    func undoLastPoint() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        state = previous
        return true
    }

    func formattedScoreSummary() -> String {
        let completedOrActive = state.sets.filter {
            $0.playerGames > 0 || $0.opponentGames > 0 || $0.isSuperTiebreakOnly || $0.winner != nil || $0.setNumber == 1
        }
        if completedOrActive.isEmpty { return "0-0" }
        return completedOrActive.map(\.displayScore).joined(separator: ", ")
    }

    // MARK: - Internal Scoring Mechanics

    private func currentBreakPointHolder() -> MatchParticipantSide? {
        guard !state.isCurrentlyInTiebreak else { return nil }
        let p = state.playerRawPoints
        let o = state.opponentRawPoints
        let server = state.currentServer

        if server == .opponent {
            // Player is receiving: can player win the game on this point?
            if state.format.noAdScoring {
                if p == 3 { return .player }
            } else {
                if (p == 3 && o < 3) || (p >= 4 && p == o + 1) { return .player }
            }
        } else {
            // Opponent is receiving: can opponent win the game on this point?
            if state.format.noAdScoring {
                if o == 3 { return .opponent }
            } else {
                if (o == 3 && p < 3) || (o >= 4 && o == p + 1) { return .opponent }
            }
        }
        return nil
    }

    private func updateStatisticsBeforeScoreAdvance(
        winner: MatchParticipantSide,
        server: MatchParticipantSide,
        wasFirstServeIn: Bool,
        outcome: PointOutcomeTag,
        breakPointHolderBefore: MatchParticipantSide?
    ) {
        if winner == .player {
            state.statistics.totalPointsWon += 1
        } else {
            state.statistics.opponentTotalPointsWon += 1
        }

        // Serve stats tracked for the user's player side
        if server == .player {
            state.statistics.firstServeAttempts += 1
            if outcome == .doubleFault {
                state.statistics.secondServeAttempts += 1
                state.statistics.doubleFaults += 1
            } else if wasFirstServeIn {
                state.statistics.firstServesMade += 1
            } else {
                state.statistics.secondServeAttempts += 1
                state.statistics.secondServesMade += 1
            }

            if outcome == .ace && winner == .player {
                state.statistics.aces += 1
                state.statistics.winners += 1
            }
        }

        // Shot outcome stats for the user's player side
        switch outcome {
        case .forehandWinner, .backhandWinner, .serviceWinner:
            if winner == .player { state.statistics.winners += 1 }
        case .netWinner:
            if winner == .player {
                state.statistics.winners += 1
                state.statistics.netPointsWon += 1
                state.statistics.netPointsApproached += 1
            }
        case .forehandUnforcedError:
            if winner == .opponent {
                state.statistics.unforcedErrors += 1
                state.statistics.forehandErrors += 1
            }
        case .backhandUnforcedError:
            if winner == .opponent {
                state.statistics.unforcedErrors += 1
                state.statistics.backhandErrors += 1
            }
        default:
            break
        }

        // Break point tracking
        if let bpHolder = breakPointHolderBefore {
            if bpHolder == .player {
                state.statistics.breakPointOpportunities += 1
                if winner == .player {
                    state.statistics.breakPointsConverted += 1
                }
            } else {
                state.statistics.breakPointsFaced += 1
                if winner == .player {
                    state.statistics.breakPointsSaved += 1
                }
            }
        }
    }

    private func advanceStandardGamePoint(winner: MatchParticipantSide) {
        if winner == .player {
            state.playerRawPoints += 1
        } else {
            state.opponentRawPoints += 1
        }

        let p = state.playerRawPoints
        let o = state.opponentRawPoints

        let gameWinner: MatchParticipantSide?
        if state.format.noAdScoring {
            if p >= 4 && p > o {
                gameWinner = .player
            } else if o >= 4 && o > p {
                gameWinner = .opponent
            } else {
                gameWinner = nil
            }
        } else {
            if p >= 4 && (p - o) >= 2 {
                gameWinner = .player
            } else if o >= 4 && (o - p) >= 2 {
                gameWinner = .opponent
            } else {
                gameWinner = nil
            }
        }

        if let gameWinner {
            completeGame(winner: gameWinner)
        }
    }

    private func completeGame(winner: MatchParticipantSide) {
        state.playerRawPoints = 0
        state.opponentRawPoints = 0

        if winner == .player {
            state.sets[state.currentSetIndex].playerGames += 1
            state.statistics.totalGamesWon += 1
        } else {
            state.sets[state.currentSetIndex].opponentGames += 1
            state.statistics.opponentTotalGamesWon += 1
        }

        // Rotate server after a standard game
        state.currentServer = (state.currentServer == .player) ? .opponent : .player

        let pGames = state.sets[state.currentSetIndex].playerGames
        let oGames = state.sets[state.currentSetIndex].opponentGames

        // Check if 6-6 triggers a tiebreak
        if pGames == 6 && oGames == 6 && state.format.tiebreakAtSixAll {
            state.isCurrentlyInTiebreak = true
            state.isCurrentTiebreakSuper = false
            state.tiebreakInitialServer = state.currentServer
            state.sets[state.currentSetIndex].isTiebreakSet = true
            state.sets[state.currentSetIndex].tiebreakPlayerPoints = 0
            state.sets[state.currentSetIndex].tiebreakOpponentPoints = 0
            return
        }

        // Check standard set win (6+ games, margin >= 2)
        if pGames >= 6 && (pGames - oGames) >= 2 {
            completeSet(winner: .player)
        } else if oGames >= 6 && (oGames - pGames) >= 2 {
            completeSet(winner: .opponent)
        }
    }

    private func advanceTiebreakPoint(winner: MatchParticipantSide) {
        if winner == .player {
            state.playerRawPoints += 1
        } else {
            state.opponentRawPoints += 1
        }

        state.sets[state.currentSetIndex].tiebreakPlayerPoints = state.playerRawPoints
        state.sets[state.currentSetIndex].tiebreakOpponentPoints = state.opponentRawPoints

        let p = state.playerRawPoints
        let o = state.opponentRawPoints
        let targetPoints = state.isCurrentTiebreakSuper ? 10 : 7

        if p >= targetPoints && (p - o) >= 2 {
            finishTiebreakAndSet(winner: .player)
            return
        } else if o >= targetPoints && (o - p) >= 2 {
            finishTiebreakAndSet(winner: .opponent)
            return
        }

        // Standard tennis tiebreak serve rotation: changes after the 1st point and every 2 points thereafter (odd total points)
        let totalTiebreakPoints = p + o
        if totalTiebreakPoints % 2 == 1 {
            state.currentServer = (state.currentServer == .player) ? .opponent : .player
        }
    }

    private func finishTiebreakAndSet(winner: MatchParticipantSide) {
        if !state.isCurrentTiebreakSuper {
            if winner == .player {
                state.sets[state.currentSetIndex].playerGames += 1
                state.statistics.totalGamesWon += 1
            } else {
                state.sets[state.currentSetIndex].opponentGames += 1
                state.statistics.opponentTotalGamesWon += 1
            }
        }

        // Next set first server is the receiver of the first point of the tiebreak
        if let initialTBServer = state.tiebreakInitialServer {
            state.currentServer = (initialTBServer == .player) ? .opponent : .player
        }

        state.playerRawPoints = 0
        state.opponentRawPoints = 0
        state.isCurrentlyInTiebreak = false
        state.isCurrentTiebreakSuper = false
        state.tiebreakInitialServer = nil

        completeSet(winner: winner)
    }

    private func completeSet(winner: MatchParticipantSide) {
        state.sets[state.currentSetIndex].winner = winner

        let playerSetsWon = state.sets.filter { $0.winner == .player }.count
        let opponentSetsWon = state.sets.filter { $0.winner == .opponent }.count
        let requiredSets = state.format.setsRequiredToWin

        if playerSetsWon >= requiredSets {
            state.matchWinner = .player
            return
        }
        if opponentSetsWon >= requiredSets {
            state.matchWinner = .opponent
            return
        }

        // Prepare next set
        let nextSetNumber = state.sets.count + 1
        let isDecidingSet = (nextSetNumber == state.format.bestOfSets)
        let useSuperTB = isDecidingSet && state.format.finalSetSuperTiebreak

        var nextSet = SetScoreSnapshot(setNumber: nextSetNumber)
        if useSuperTB {
            nextSet.isSuperTiebreakOnly = true
            nextSet.isTiebreakSet = true
            nextSet.tiebreakPlayerPoints = 0
            nextSet.tiebreakOpponentPoints = 0
            state.isCurrentlyInTiebreak = true
            state.isCurrentTiebreakSuper = true
            state.tiebreakInitialServer = state.currentServer
        }

        state.sets.append(nextSet)
        state.currentSetIndex = state.sets.count - 1
    }
}

// MARK: - Manual Match Score Validator

enum MatchScoreValidator {
    static func validate(
        sets: [SetScoreSnapshot],
        format: MatchFormatConfig,
        status: MatchStatus
    ) throws -> MatchParticipantSide? {
        guard !sets.isEmpty else {
            throw MatchScoreValidationError.emptySets
        }
        guard sets.count <= format.bestOfSets else {
            throw MatchScoreValidationError.tooManySets(maxAllowed: format.bestOfSets)
        }

        var playerSets = 0
        var opponentSets = 0
        let setsNeeded = format.setsRequiredToWin

        for (idx, set) in sets.enumerated() {
            if playerSets >= setsNeeded || opponentSets >= setsNeeded {
                throw MatchScoreValidationError.setsContinuedAfterMatchWon
            }

            let isDecider = (idx + 1 == format.bestOfSets)
            if set.isSuperTiebreakOnly && isDecider && format.finalSetSuperTiebreak {
                let pTB = set.tiebreakPlayerPoints ?? set.playerGames
                let oTB = set.tiebreakOpponentPoints ?? set.opponentGames
                let high = max(pTB, oTB)
                let diff = abs(pTB - oTB)
                if status == .completed {
                    guard high >= 10 && diff >= 2 && (high == 10 || diff == 2) else {
                        throw MatchScoreValidationError.invalidSetGameScore(setNumber: idx + 1, playerGames: pTB, opponentGames: oTB)
                    }
                    if pTB > oTB { playerSets += 1 } else { opponentSets += 1 }
                }
                continue
            }

            let p = set.playerGames
            let o = set.opponentGames
            guard p >= 0 && o >= 0 else {
                throw MatchScoreValidationError.invalidSetGameScore(setNumber: idx + 1, playerGames: p, opponentGames: o)
            }

            if status == .completed {
                let validWin = isValidCompletedSet(p: p, o: o, tiebreakAtSixAll: format.tiebreakAtSixAll)
                guard validWin else {
                    throw MatchScoreValidationError.invalidSetGameScore(setNumber: idx + 1, playerGames: p, opponentGames: o)
                }
                if p > o { playerSets += 1 } else { opponentSets += 1 }
            } else {
                if isValidCompletedSet(p: p, o: o, tiebreakAtSixAll: format.tiebreakAtSixAll) {
                    if p > o { playerSets += 1 } else { opponentSets += 1 }
                }
            }
        }

        if status == .completed {
            if playerSets == setsNeeded { return .player }
            if opponentSets == setsNeeded { return .opponent }
            throw MatchScoreValidationError.incompleteMatchWinnerMismatch
        }

        return nil
    }

    private static func isValidCompletedSet(p: Int, o: Int, tiebreakAtSixAll: Bool) -> Bool {
        let high = max(p, o)
        let low = min(p, o)
        let diff = high - low

        if high == 6 && low <= 4 {
            return true
        }
        if high == 7 && low == 5 {
            return true
        }
        if tiebreakAtSixAll && high == 7 && low == 6 {
            return true
        }
        if !tiebreakAtSixAll && high >= 6 && diff == 2 {
            return true
        }
        return false
    }
}

