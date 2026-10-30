import Foundation
import SwiftData

struct TennisProBackupArchive: Codable, Sendable {
    struct ProfileDTO: Codable, Sendable {
        var name: String
        var skillLevel: String
        var dominantHand: String
        var backhandStyle: String
        var preferredSurface: String
        var weeklyTrainingGoalMinutes: Int
    }

    struct MatchDTO: Codable, Sendable {
        var id: UUID
        var playerName: String
        var partnerName: String
        var opponentName: String
        var opponentPartnerName: String
        var isDoubles: Bool
        var matchDate: Date
        var location: String
        var surface: String
        var status: String
        var isPlayerWinner: Bool?
        var finalScoreSummary: String
        var durationSeconds: Double
        var notes: String
        var format: MatchFormatConfig
        var sets: [SetScoreSnapshot]
        var statistics: MatchStatisticsData
    }

    struct TrainingDTO: Codable, Sendable {
        var id: UUID
        var name: String
        var drillType: String
        var objective: String
        var plannedDurationMinutes: Int
        var actualDurationMinutes: Int
        var targetRepetitions: Int
        var completedRepetitions: Int
        var targetScore: Int
        var achievedScore: Int
        var notes: String
        var isCompleted: Bool
        var sessionDate: Date
    }

    struct VideoMetadataDTO: Codable, Sendable {
        var id: UUID
        var title: String
        var recordedAt: Date
        var durationSeconds: Double
        var sessionType: String
        var resolutionSummary: String
        var notes: String
        var tags: [String]
        var clipCount: Int
    }

    var exportedAt: Date
    var appVersion: String
    var profile: ProfileDTO
    var matches: [MatchDTO]
    var trainingSessions: [TrainingDTO]
    var videoCatalog: [VideoMetadataDTO]
}

enum DataBackupService {
    @MainActor
    static func exportBackupFile(context: ModelContext) throws -> URL {
        let profile = PersistenceController.ensurePrimaryProfile(in: context)
        let matches = (try? context.fetch(FetchDescriptor<MatchRecord>(sortBy: [SortDescriptor(\.matchDate, order: .reverse)]))) ?? []
        let sessions = (try? context.fetch(FetchDescriptor<TrainingSession>(sortBy: [SortDescriptor(\.sessionDate, order: .reverse)]))) ?? []
        let videos = (try? context.fetch(FetchDescriptor<VideoRecording>(sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]))) ?? []

        let archive = TennisProBackupArchive(
            exportedAt: Date(),
            appVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0",
            profile: .init(
                name: profile.name,
                skillLevel: profile.skillLevelRaw,
                dominantHand: profile.dominantHandRaw,
                backhandStyle: profile.backhandStyleRaw,
                preferredSurface: profile.preferredSurfaceRaw,
                weeklyTrainingGoalMinutes: profile.weeklyTrainingGoalMinutes
            ),
            matches: matches.map { match in
                .init(
                    id: match.id,
                    playerName: match.playerName,
                    partnerName: match.partnerName,
                    opponentName: match.opponentName,
                    opponentPartnerName: match.opponentPartnerName,
                    isDoubles: match.isDoubles,
                    matchDate: match.matchDate,
                    location: match.location,
                    surface: match.surfaceRaw,
                    status: match.statusRaw,
                    isPlayerWinner: match.isPlayerWinner,
                    finalScoreSummary: match.finalScoreSummary,
                    durationSeconds: match.durationSeconds,
                    notes: match.notes,
                    format: match.format,
                    sets: match.sets,
                    statistics: match.statistics
                )
            },
            trainingSessions: sessions.map { session in
                .init(
                    id: session.id,
                    name: session.name,
                    drillType: session.drillTypeRaw,
                    objective: session.objective,
                    plannedDurationMinutes: session.plannedDurationMinutes,
                    actualDurationMinutes: session.actualDurationMinutes,
                    targetRepetitions: session.targetRepetitions,
                    completedRepetitions: session.completedRepetitions,
                    targetScore: session.targetScore,
                    achievedScore: session.achievedScore,
                    notes: session.notes,
                    isCompleted: session.isCompleted,
                    sessionDate: session.sessionDate
                )
            },
            videoCatalog: videos.map { video in
                .init(
                    id: video.id,
                    title: video.title,
                    recordedAt: video.recordedAt,
                    durationSeconds: video.durationSeconds,
                    sessionType: video.sessionTypeRaw,
                    resolutionSummary: video.resolutionSummary,
                    notes: video.notes,
                    tags: video.tags,
                    clipCount: video.clips.count
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(archive)

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let filename = "TennisProAI-Backup-\(formatter.string(from: Date())).json"
        let tempURL = FileManager.default.temporaryDirectory.appendingPathComponent(filename)
        try data.write(to: tempURL, options: .atomic)
        return tempURL
    }
}

