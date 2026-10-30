import Foundation
import SwiftData

@Model
final class VideoRecording {
    @Attribute(.unique) var id: UUID
    var title: String
    /// Relative path inside Application Support/TennisProAI/Recordings/ so files survive container relocation across app updates.
    var relativeFilePath: String
    var thumbnailRelativePath: String?
    var recordedAt: Date
    var durationSeconds: Double
    var sessionTypeRaw: String
    var resolutionWidth: Int
    var resolutionHeight: Int
    var frameRate: Double
    var fileSizeBytes: Int64
    var cameraLensLabel: String
    var notes: String
    var tagsCSV: String
    var isFavorite: Bool
    var linkedMatchID: UUID?
    var linkedTrainingSessionID: UUID?

    @Relationship(deleteRule: .cascade, inverse: \VideoClip.recording)
    var clips: [VideoClip] = []

    @Relationship(deleteRule: .cascade, inverse: \AIAnalysisRecord.recording)
    var analysisRecords: [AIAnalysisRecord] = []

    init(
        id: UUID = UUID(),
        title: String,
        relativeFilePath: String,
        thumbnailRelativePath: String? = nil,
        recordedAt: Date = Date(),
        durationSeconds: Double = 0,
        sessionType: SessionType = .match,
        resolutionWidth: Int = 1920,
        resolutionHeight: Int = 1080,
        frameRate: Double = 60.0,
        fileSizeBytes: Int64 = 0,
        cameraLensLabel: String = "1x Wide",
        notes: String = "",
        tags: [String] = [],
        isFavorite: Bool = false,
        linkedMatchID: UUID? = nil,
        linkedTrainingSessionID: UUID? = nil
    ) {
        self.id = id
        self.title = title
        self.relativeFilePath = relativeFilePath
        self.thumbnailRelativePath = thumbnailRelativePath
        self.recordedAt = recordedAt
        self.durationSeconds = durationSeconds
        self.sessionTypeRaw = sessionType.rawValue
        self.resolutionWidth = resolutionWidth
        self.resolutionHeight = resolutionHeight
        self.frameRate = frameRate
        self.fileSizeBytes = fileSizeBytes
        self.cameraLensLabel = cameraLensLabel
        self.notes = notes
        self.tagsCSV = tags.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: ",")
        self.isFavorite = isFavorite
        self.linkedMatchID = linkedMatchID
        self.linkedTrainingSessionID = linkedTrainingSessionID
    }

    var sessionType: SessionType {
        get { SessionType(rawValue: sessionTypeRaw) ?? .match }
        set { sessionTypeRaw = newValue.rawValue }
    }

    var tags: [String] {
        get {
            guard !tagsCSV.isEmpty else { return [] }
            return tagsCSV
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }
        set {
            tagsCSV = newValue
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
                .joined(separator: ",")
        }
    }

    var resolutionSummary: String {
        if resolutionWidth >= 3840 || resolutionHeight >= 3840 {
            return "4K • \(Int(frameRate.rounded())) fps"
        } else if resolutionWidth >= 1920 || resolutionHeight >= 1920 {
            return "1080p • \(Int(frameRate.rounded())) fps"
        } else {
            return "\(resolutionWidth)x\(resolutionHeight) • \(Int(frameRate.rounded())) fps"
        }
    }

    var formattedDuration: String {
        TimeFormatters.clockString(from: durationSeconds)
    }

    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSizeBytes, countStyle: .file)
    }
}

@Model
final class VideoClip {
    @Attribute(.unique) var id: UUID
    var parentRecordingID: UUID
    var title: String
    /// Relative path inside Application Support/TennisProAI/Clips/
    var relativeFilePath: String
    var thumbnailRelativePath: String?
    var startTimeSeconds: Double
    var endTimeSeconds: Double
    var categoryRaw: String
    var notes: String
    var isFavorite: Bool
    var createdAt: Date

    var recording: VideoRecording?

    init(
        id: UUID = UUID(),
        parentRecordingID: UUID,
        title: String,
        relativeFilePath: String,
        thumbnailRelativePath: String? = nil,
        startTimeSeconds: Double,
        endTimeSeconds: Double,
        category: HighlightCategory = .rally,
        notes: String = "",
        isFavorite: Bool = false,
        createdAt: Date = Date(),
        recording: VideoRecording? = nil
    ) {
        self.id = id
        self.parentRecordingID = parentRecordingID
        self.title = title
        self.relativeFilePath = relativeFilePath
        self.thumbnailRelativePath = thumbnailRelativePath
        self.startTimeSeconds = startTimeSeconds
        self.endTimeSeconds = endTimeSeconds
        self.categoryRaw = category.rawValue
        self.notes = notes
        self.isFavorite = isFavorite
        self.createdAt = createdAt
        self.recording = recording
    }

    var category: HighlightCategory {
        get { HighlightCategory(rawValue: categoryRaw) ?? .rally }
        set { categoryRaw = newValue.rawValue }
    }

    var durationSeconds: Double {
        max(0, endTimeSeconds - startTimeSeconds)
    }

    var formattedDuration: String {
        TimeFormatters.clockString(from: durationSeconds)
    }

    var formattedTrimRange: String {
        "\(TimeFormatters.clockString(from: startTimeSeconds)) – \(TimeFormatters.clockString(from: endTimeSeconds))"
    }
}

enum TimeFormatters {
    static func clockString(from seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00" }
        let totalSeconds = Int(seconds.rounded())
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }

    static func preciseString(from seconds: Double) -> String {
        guard seconds.isFinite && seconds >= 0 else { return "00:00.0" }
        let wholeSeconds = Int(seconds)
        let tenths = Int(((seconds - Double(wholeSeconds)) * 10).rounded()) % 10
        let minutes = wholeSeconds / 60
        let secs = wholeSeconds % 60
        return String(format: "%02d:%02d.%d", minutes, secs, tenths)
    }
}

