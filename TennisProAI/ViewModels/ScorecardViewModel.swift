import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class ScorecardViewModel {
    let matchRecord: MatchRecord
    private var scoringService: MatchScoringService

    // Observable mirrored state for SwiftUI
    var engineState: TennisEngineState
    var playerPointText: String = "0"
    var opponentPointText: String = "0"
    var situationBanner: String = ""
    var canUndo: Bool = false

    // Point-entry modifiers
    var firstServeWasIn: Bool = true
    var selectedOutcomeTag: PointOutcomeTag = .standardRally
    var elapsedSeconds: Double = 0
    var isTimerRunning: Bool = false

    private var timerTask: Task<Void, Never>?

    init(matchRecord: MatchRecord) {
        self.matchRecord = matchRecord
        self.elapsedSeconds = matchRecord.durationSeconds

        if let savedStateData = matchRecord.liveEngineStateJSON,
           let decoded = try? JSONDecoder().decode(TennisEngineState.self, from: savedStateData) {
            let service = MatchScoringService(restoredState: decoded)
            self.scoringService = service
            self.engineState = service.state
        } else {
            let service = MatchScoringService(format: matchRecord.format, initialServer: .player)
            self.scoringService = service
            self.engineState = service.state
        }

        syncPublishedProperties()
    }

    func startMatchClockIfNeeded() {
        guard matchRecord.status == .inProgress, !isTimerRunning else { return }
        isTimerRunning = true
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                guard let self, self.isTimerRunning else { return }
                self.elapsedSeconds += 1
                self.matchRecord.durationSeconds = self.elapsedSeconds
            }
        }
    }

    func pauseMatchClock() {
        isTimerRunning = false
        timerTask?.cancel()
        timerTask = nil
    }

    func awardPoint(to winner: MatchParticipantSide, in context: ModelContext) {
        scoringService.recordPoint(
            winner: winner,
            wasFirstServeIn: firstServeWasIn,
            outcome: selectedOutcomeTag
        )
        // Reset per-point modifiers back to common defaults for fast next-point entry
        firstServeWasIn = true
        selectedOutcomeTag = .standardRally

        syncPublishedProperties()
        persistToMatchRecord(in: context)
        HapticsManager.impact(.medium)
    }

    func recordQuickAce(by side: MatchParticipantSide, in context: ModelContext) {
        guard engineState.currentServer == side else { return }
        scoringService.recordPoint(winner: side, wasFirstServeIn: true, outcome: .ace)
        syncPublishedProperties()
        persistToMatchRecord(in: context)
        HapticsManager.notification(.success)
    }

    func recordQuickDoubleFault(in context: ModelContext) {
        let receiver: MatchParticipantSide = (engineState.currentServer == .player) ? .opponent : .player
        scoringService.recordPoint(winner: receiver, wasFirstServeIn: false, outcome: .doubleFault)
        syncPublishedProperties()
        persistToMatchRecord(in: context)
        HapticsManager.notification(.warning)
    }

    func undoPreviousPoint(in context: ModelContext) {
        guard scoringService.undoLastPoint() else { return }
        if matchRecord.status == .completed && scoringService.state.matchWinner == nil {
            matchRecord.status = .inProgress
            matchRecord.isPlayerWinner = nil
        }
        syncPublishedProperties()
        persistToMatchRecord(in: context)
        HapticsManager.impact(.light)
    }

    func markRetired(winner: MatchParticipantSide, in context: ModelContext) {
        pauseMatchClock()
        matchRecord.status = .retired
        matchRecord.isPlayerWinner = (winner == .player)
        matchRecord.finalScoreSummary = "\(scoringService.formattedScoreSummary()) ret."
        matchRecord.durationSeconds = elapsedSeconds
        try? context.save()
    }

    private func syncPublishedProperties() {
        engineState = scoringService.state
        playerPointText = scoringService.playerPointDisplay
        opponentPointText = scoringService.opponentPointDisplay
        situationBanner = scoringService.gameSituationLabel
        canUndo = scoringService.canUndo
    }

    private func persistToMatchRecord(in context: ModelContext) {
        matchRecord.sets = engineState.sets
        matchRecord.statistics = engineState.statistics
        matchRecord.pointHistory = engineState.pointHistory
        matchRecord.finalScoreSummary = scoringService.formattedScoreSummary()
        matchRecord.durationSeconds = elapsedSeconds
        matchRecord.liveEngineStateJSON = try? JSONEncoder().encode(engineState)

        if let winner = engineState.matchWinner {
            pauseMatchClock()
            matchRecord.status = .completed
            matchRecord.isPlayerWinner = (winner == .player)
        }

        try? context.save()
    }
}

