import Foundation
import SwiftData

// MARK: - Match Format & Scoring Value Types

struct MatchFormatConfig: Codable, Equatable, Sendable {
    var bestOfSets: Int // 3 or 5
    var tiebreakAtSixAll: Bool // 7-point tiebreak at 6-6
    var finalSetSuperTiebreak: Bool // 10-point match tiebreak instead of full final set
    var noAdScoring: Bool // Sudden-death point at Deuce (40-40)

    init(
        bestOfSets: Int = 3,
        tiebreakAtSixAll: Bool = true,
        finalSetSuperTiebreak: Bool = false,
        noAdScoring: Bool = false
    ) {
        self.bestOfSets = (bestOfSets == 5) ? 5 : 3
        self.tiebreakAtSixAll = tiebreakAtSixAll
        self.finalSetSuperTiebreak = finalSetSuperTiebreak
        self.noAdScoring = noAdScoring
    }

    var setsRequiredToWin: Int {
        (bestOfSets / 2) + 1
    }

    var summaryDescription: String {
        var parts = ["Best of \(bestOfSets)"]
        parts.append(noAdScoring ? "No-Ad" : "Standard Ad")
        if finalSetSuperTiebreak {
            parts.append("Final Set 10-pt TB")
        } else if tiebreakAtSixAll {
            parts.append("7-pt Set TB")
        } else {
            parts.append("Advantage Sets")
        }
        return parts.joined(separator: " • ")
    }
}

struct SetScoreSnapshot: Codable, Equatable, Identifiable, Sendable {
    var id: Int { setNumber }
    var setNumber: Int
    var playerGames: Int
    var opponentGames: Int
    var isTiebreakSet: Bool
    var tiebreakPlayerPoints: Int?
    var tiebreakOpponentPoints: Int?
    var isSuperTiebreakOnly: Bool
    var winner: MatchParticipantSide?

    init(
        setNumber: Int,
        playerGames: Int = 0,
        opponentGames: Int = 0,
        isTiebreakSet: Bool = false,
        tiebreakPlayerPoints: Int? = nil,
        tiebreakOpponentPoints: Int? = nil,
        isSuperTiebreakOnly: Bool = false,
        winner: MatchParticipantSide? = nil
    ) {
        self.setNumber = setNumber
        self.playerGames = playerGames
        self.opponentGames = opponentGames
        self.isTiebreakSet = isTiebreakSet
        self.tiebreakPlayerPoints = tiebreakPlayerPoints
        self.tiebreakOpponentPoints = tiebreakOpponentPoints
        self.isSuperTiebreakOnly = isSuperTiebreakOnly
        self.winner = winner
    }

    var displayScore: String {
        if isSuperTiebreakOnly, let pTB = tiebreakPlayerPoints, let oTB = tiebreakOpponentPoints {
            return "[\(pTB)-\(oTB)]"
        }
        if isTiebreakSet, let pTB = tiebreakPlayerPoints, let oTB = tiebreakOpponentPoints {
            let loserPoints = min(pTB, oTB)
            return "\(playerGames)-\(opponentGames)(\(loserPoints))"
        }
        return "\(playerGames)-\(opponentGames)"
    }
}

struct PointHistoryEntry: Codable, Equatable, Identifiable, Sendable {
    var id: UUID
    var timestamp: Date
    var winner: MatchParticipantSide
    var server: MatchParticipantSide
    var wasFirstServeIn: Bool
    var outcomeTag: PointOutcomeTag
    var scoreCallAfterPoint: String

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        winner: MatchParticipantSide,
        server: MatchParticipantSide,
        wasFirstServeIn: Bool = true,
        outcomeTag: PointOutcomeTag = .standardRally,
        scoreCallAfterPoint: String = ""
    ) {
        self.id = id
        self.timestamp = timestamp
        self.winner = winner
        self.server = server
        self.wasFirstServeIn = wasFirstServeIn
        self.outcomeTag = outcomeTag
        self.scoreCallAfterPoint = scoreCallAfterPoint
    }
}

// MARK: - Comprehensive Match Statistics Value Type

struct MatchStatisticsData: Codable, Equatable, Sendable {
    var firstServesMade: Int = 0
    var firstServeAttempts: Int = 0
    var secondServesMade: Int = 0
    var secondServeAttempts: Int = 0
    var doubleFaults: Int = 0
    var aces: Int = 0
    var winners: Int = 0
    var unforcedErrors: Int = 0
    var forehandErrors: Int = 0
    var backhandErrors: Int = 0
    var netPointsWon: Int = 0
    var netPointsApproached: Int = 0
    var breakPointsConverted: Int = 0
    var breakPointOpportunities: Int = 0
    var breakPointsSaved: Int = 0
    var breakPointsFaced: Int = 0
    var totalPointsWon: Int = 0
    var opponentTotalPointsWon: Int = 0
    var totalGamesWon: Int = 0
    var opponentTotalGamesWon: Int = 0

    /// Returns First-Serve Percentage (0...100), or nil when firstServeAttempts == 0 to avoid misleading 0% or NaN.
    var firstServePercentage: Double? {
        guard firstServeAttempts > 0 else { return nil }
        let clampedMade = min(max(0, firstServesMade), firstServeAttempts)
        return (Double(clampedMade) / Double(firstServeAttempts)) * 100.0
    }

    var secondServePercentage: Double? {
        guard secondServeAttempts > 0 else { return nil }
        let clampedMade = min(max(0, secondServesMade), secondServeAttempts)
        return (Double(clampedMade) / Double(secondServeAttempts)) * 100.0
    }

    var netSuccessPercentage: Double? {
        guard netPointsApproached > 0 else { return nil }
        let clamped = min(max(0, netPointsWon), netPointsApproached)
        return (Double(clamped) / Double(netPointsApproached)) * 100.0
    }

    var breakPointConversionPercentage: Double? {
        guard breakPointOpportunities > 0 else { return nil }
        let clamped = min(max(0, breakPointsConverted), breakPointOpportunities)
        return (Double(clamped) / Double(breakPointOpportunities)) * 100.0
    }

    var breakPointSavePercentage: Double? {
        guard breakPointsFaced > 0 else { return nil }
        let clamped = min(max(0, breakPointsSaved), breakPointsFaced)
        return (Double(clamped) / Double(breakPointsFaced)) * 100.0
    }

    var totalPointsPlayed: Int {
        totalPointsWon + opponentTotalPointsWon
    }

    var pointsWonPercentage: Double? {
        guard totalPointsPlayed > 0 else { return nil }
        return (Double(totalPointsWon) / Double(totalPointsPlayed)) * 100.0
    }

    var winnerToUnforcedErrorDifferential: Int {
        winners - unforcedErrors
    }
}

// MARK: - SwiftData MatchRecord Model

@Model
final class MatchRecord {
    @Attribute(.unique) var id: UUID
    var playerName: String
    var partnerName: String
    var opponentName: String
    var opponentPartnerName: String
    var isDoubles: Bool
    var matchDate: Date
    var location: String
    var surfaceRaw: String
    var statusRaw: String
    /// Nil while match is in progress; true when player side won; false when opponent side won.
    var isPlayerWinner: Bool?
    var finalScoreSummary: String
    var durationSeconds: Double
    var notes: String
    var linkedVideoID: UUID?

    var formatJSON: Data
    var setsJSON: Data
    var statsJSON: Data
    @Attribute(.externalStorage) var pointHistoryJSON: Data
    var liveEngineStateJSON: Data?

    init(
        id: UUID = UUID(),
        playerName: String,
        partnerName: String = "",
        opponentName: String,
        opponentPartnerName: String = "",
        isDoubles: Bool = false,
        matchDate: Date = Date(),
        location: String = "",
        surface: CourtSurface = .hard,
        status: MatchStatus = .inProgress,
        isPlayerWinner: Bool? = nil,
        finalScoreSummary: String = "0-0",
        durationSeconds: Double = 0,
        notes: String = "",
        linkedVideoID: UUID? = nil,
        format: MatchFormatConfig = MatchFormatConfig(),
        sets: [SetScoreSnapshot] = [SetScoreSnapshot(setNumber: 1)],
        statistics: MatchStatisticsData = MatchStatisticsData(),
        pointHistory: [PointHistoryEntry] = [],
        liveEngineStateJSON: Data? = nil
    ) {
        self.id = id
        self.playerName = playerName
        self.partnerName = partnerName
        self.opponentName = opponentName
        self.opponentPartnerName = opponentPartnerName
        self.isDoubles = isDoubles
        self.matchDate = matchDate
        self.location = location
        self.surfaceRaw = surface.rawValue
        self.statusRaw = status.rawValue
        self.isPlayerWinner = isPlayerWinner
        self.finalScoreSummary = finalScoreSummary
        self.durationSeconds = durationSeconds
        self.notes = notes
        self.linkedVideoID = linkedVideoID
        self.formatJSON = (try? JSONEncoder().encode(format)) ?? Data()
        self.setsJSON = (try? JSONEncoder().encode(sets)) ?? Data()
        self.statsJSON = (try? JSONEncoder().encode(statistics)) ?? Data()
        self.pointHistoryJSON = (try? JSONEncoder().encode(pointHistory)) ?? Data()
        self.liveEngineStateJSON = liveEngineStateJSON
    }

    var surface: CourtSurface {
        get { CourtSurface(rawValue: surfaceRaw) ?? .hard }
        set { surfaceRaw = newValue.rawValue }
    }

    var status: MatchStatus {
        get { MatchStatus(rawValue: statusRaw) ?? .inProgress }
        set { statusRaw = newValue.rawValue }
    }

    var format: MatchFormatConfig {
        get { (try? JSONDecoder().decode(MatchFormatConfig.self, from: formatJSON)) ?? MatchFormatConfig() }
        set { formatJSON = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var sets: [SetScoreSnapshot] {
        get { (try? JSONDecoder().decode([SetScoreSnapshot].self, from: setsJSON)) ?? [] }
        set { setsJSON = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var statistics: MatchStatisticsData {
        get { (try? JSONDecoder().decode(MatchStatisticsData.self, from: statsJSON)) ?? MatchStatisticsData() }
        set { statsJSON = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var pointHistory: [PointHistoryEntry] {
        get { (try? JSONDecoder().decode([PointHistoryEntry].self, from: pointHistoryJSON)) ?? [] }
        set { pointHistoryJSON = (try? JSONEncoder().encode(newValue)) ?? Data() }
    }

    var playerTeamDisplayName: String {
        if isDoubles && !partnerName.trimmingCharacters(in: .whitespaces).isEmpty {
            return "\(playerName) / \(partnerName)"
        }
        return playerName
    }

    var opponentTeamDisplayName: String {
        if isDoubles && !opponentPartnerName.trimmingCharacters(in: .whitespaces).isEmpty {
            return "\(opponentName) / \(opponentPartnerName)"
        }
        return opponentName
    }

    var resultBadgeText: String {
        switch status {
        case .inProgress:
            return "LIVE"
        case .retired:
            if let won = isPlayerWinner {
                return won ? "W (RET)" : "L (RET)"
            }
            return "RET"
        case .completed:
            if let won = isPlayerWinner {
                return won ? "WIN" : "LOSS"
            }
            return "DONE"
        }
    }
}

