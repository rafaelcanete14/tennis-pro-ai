import Foundation
import SwiftData

@MainActor
final class PersistenceController {
    static let shared = PersistenceController()

    let container: ModelContainer
    let isUITesting: Bool

    init(inMemory: Bool = false) {
        let args = ProcessInfo.processInfo.arguments
        let runningUITests = args.contains("--uitesting")
        self.isUITesting = runningUITests

        let schema = Schema([
            PlayerProfile.self,
            VideoRecording.self,
            VideoClip.self,
            MatchRecord.self,
            TrainingSession.self,
            AIAnalysisRecord.self
        ])

        let storeInMemory = inMemory || runningUITests
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: storeInMemory,
            allowsSave: true
        )

        do {
            self.container = try ModelContainer(for: schema, configurations: [configuration])
        } catch {
            // Fallback to in-memory container rather than crashing immediately if disk store is corrupted,
            // allowing the UI to surface a recovery banner.
            let fallbackConfig = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
            do {
                self.container = try ModelContainer(for: schema, configurations: [fallbackConfig])
            } catch {
                fatalError("Unable to initialize SwiftData ModelContainer: \(error.localizedDescription)")
            }
        }

        if runningUITests {
            configureUITestingSeedIfNeeded()
        }
    }

    @discardableResult
    static func ensurePrimaryProfile(in context: ModelContext) -> PlayerProfile {
        let descriptor = FetchDescriptor<PlayerProfile>(
            sortBy: [SortDescriptor(\.createdAt, order: .forward)]
        )
        if let existing = try? context.fetch(descriptor), let first = existing.first {
            // Deduplicate accidental multiple profiles while keeping oldest canonical profile
            if existing.count > 1 {
                for duplicate in existing.dropFirst() {
                    context.delete(duplicate)
                }
                try? context.save()
            }
            return first
        }

        let profile = PlayerProfile()
        context.insert(profile)
        try? context.save()
        return profile
    }

    static func deleteAllUserData(
        in context: ModelContext,
        videoStorage: VideoStorageServiceProtocol
    ) throws {
        try videoStorage.deleteAllManagedMediaFiles()

        try context.delete(model: VideoClip.self)
        try context.delete(model: AIAnalysisRecord.self)
        try context.delete(model: VideoRecording.self)
        try context.delete(model: MatchRecord.self)
        try context.delete(model: TrainingSession.self)
        try context.delete(model: PlayerProfile.self)

        let freshProfile = PlayerProfile(hasCompletedOnboarding: true)
        context.insert(freshProfile)
        try context.save()
    }

    private func configureUITestingSeedIfNeeded() {
        let args = ProcessInfo.processInfo.arguments
        let context = container.mainContext

        if args.contains("--uitesting-skip-onboarding") {
            let profile = PlayerProfile(
                name: "Alex Rivera",
                skillLevel: .clubAdvanced,
                dominantHand: .right,
                backhandStyle: .twoHanded,
                preferredSurface: .hard,
                hasCompletedOnboarding: true
            )
            context.insert(profile)
        }

        if args.contains("--uitesting-seed-sample") {
            let sampleVideo = VideoRecording(
                title: "Baseline Rally Session",
                relativeFilePath: "Recordings/uitest_sample.mp4",
                recordedAt: Date().addingTimeInterval(-3600),
                durationSeconds: 185,
                sessionType: .practice,
                resolutionWidth: 1920,
                resolutionHeight: 1080,
                frameRate: 60,
                fileSizeBytes: 48_500_000,
                cameraLensLabel: "1x Wide",
                notes: "UI test seeded video",
                tags: ["forehand", "baseline"]
            )
            context.insert(sampleVideo)

            var stats = MatchStatisticsData()
            stats.firstServesMade = 36
            stats.firstServeAttempts = 54
            stats.secondServesMade = 16
            stats.secondServeAttempts = 18
            stats.doubleFaults = 2
            stats.aces = 6
            stats.winners = 22
            stats.unforcedErrors = 17
            stats.forehandErrors = 9
            stats.backhandErrors = 8
            stats.netPointsWon = 11
            stats.netPointsApproached = 15
            stats.breakPointsConverted = 3
            stats.breakPointOpportunities = 6
            stats.breakPointsSaved = 4
            stats.breakPointsFaced = 5
            stats.totalPointsWon = 68
            stats.opponentTotalPointsWon = 55
            stats.totalGamesWon = 12
            stats.opponentTotalGamesWon = 8

            let sampleMatch = MatchRecord(
                playerName: "Alex Rivera",
                opponentName: "Jordan Vance",
                matchDate: Date().addingTimeInterval(-86400),
                location: "City Tennis Center",
                surface: .hard,
                status: .completed,
                isPlayerWinner: true,
                finalScoreSummary: "6-4, 6-4",
                durationSeconds: 5100,
                sets: [
                    SetScoreSnapshot(setNumber: 1, playerGames: 6, opponentGames: 4, winner: .player),
                    SetScoreSnapshot(setNumber: 2, playerGames: 6, opponentGames: 4, winner: .player)
                ],
                statistics: stats
            )
            context.insert(sampleMatch)
        }

        try? context.save()
    }
}

