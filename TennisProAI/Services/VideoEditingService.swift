import Foundation
import AVFoundation
import UIKit

enum VideoEditingError: LocalizedError {
    case invalidTrimRange
    case clipTooShort
    case missingSourceVideo
    case videoTrackNotFound
    case exportSessionCreationFailed
    case exportCancelled
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidTrimRange:
            return "End time must be greater than start time and within the video duration."
        case .clipTooShort:
            return "Selected highlight segment must be at least 0.5 seconds long."
        case .missingSourceVideo:
            return "Source match recording file could not be found."
        case .videoTrackNotFound:
            return "No playable video track was found in the recording."
        case .exportSessionCreationFailed:
            return "Unable to initialize the AVFoundation video exporter."
        case .exportCancelled:
            return "Clip export was cancelled."
        case .exportFailed(let reason):
            return "Clip export failed: \(reason)"
        }
    }
}

struct VideoTrimParameters: Equatable, Sendable {
    var startTimeSeconds: Double
    var endTimeSeconds: Double
    var sourceDurationSeconds: Double

    static let minimumClipDuration: Double = 0.5

    func validate() throws {
        guard startTimeSeconds.isFinite, endTimeSeconds.isFinite, sourceDurationSeconds.isFinite else {
            throw VideoEditingError.invalidTrimRange
        }
        guard startTimeSeconds >= 0,
              endTimeSeconds <= sourceDurationSeconds + 0.05,
              endTimeSeconds > startTimeSeconds else {
            throw VideoEditingError.invalidTrimRange
        }
        guard (endTimeSeconds - startTimeSeconds) >= Self.minimumClipDuration else {
            throw VideoEditingError.clipTooShort
        }
    }

    var clampedTimeRange: CMTimeRange {
        let clampedStart = max(0, startTimeSeconds)
        let clampedEnd = min(max(clampedStart + Self.minimumClipDuration, endTimeSeconds), max(Self.minimumClipDuration, sourceDurationSeconds))
        let startCM = CMTime(seconds: clampedStart, preferredTimescale: 600)
        let endCM = CMTime(seconds: clampedEnd, preferredTimescale: 600)
        return CMTimeRange(start: startCM, end: endCM)
    }
}

protocol VideoEditingServiceProtocol: AnyObject {
    func validateTrim(_ parameters: VideoTrimParameters) throws
    func generateTimelineThumbnails(for sourceURL: URL, count: Int) async -> [UIImage]
    func exportTrimmedClip(
        sourceURL: URL,
        destinationURL: URL,
        parameters: VideoTrimParameters,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws
    func cancelActiveExport()
}

final class VideoEditingService: VideoEditingServiceProtocol {
    private let lock = NSLock()
    private var activeExportSession: AVAssetExportSession?

    func validateTrim(_ parameters: VideoTrimParameters) throws {
        try parameters.validate()
    }

    func generateTimelineThumbnails(for sourceURL: URL, count: Int = 10) async -> [UIImage] {
        guard FileManager.default.fileExists(atPath: sourceURL.path), count > 0 else { return [] }
        let asset = AVURLAsset(url: sourceURL)
        guard let durationTime = try? await asset.load(.duration) else { return [] }
        let totalSeconds = CMTimeGetSeconds(durationTime)
        guard totalSeconds.isFinite && totalSeconds > 0 else { return [] }

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 220, height: 140)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.5, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.5, preferredTimescale: 600)

        var frames: [UIImage] = []
        let step = totalSeconds / Double(count)
        for index in 0..<count {
            let sampleSec = min(totalSeconds, Double(index) * step + (step * 0.5))
            let cmTime = CMTime(seconds: sampleSec, preferredTimescale: 600)
            if let (cgImage, _) = try? await generator.image(at: cmTime) {
                frames.append(UIImage(cgImage: cgImage))
            }
        }
        return frames
    }

    func exportTrimmedClip(
        sourceURL: URL,
        destinationURL: URL,
        parameters: VideoTrimParameters,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        try parameters.validate()

        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            throw VideoEditingError.missingSourceVideo
        }

        if FileManager.default.fileExists(atPath: destinationURL.path) {
            try? FileManager.default.removeItem(at: destinationURL)
        }

        let sourceAsset = AVURLAsset(url: sourceURL)
        let composition = AVMutableComposition()
        let timeRange = parameters.clampedTimeRange

        guard let sourceVideoTrack = try await sourceAsset.loadTracks(withMediaType: .video).first,
              let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw VideoEditingError.videoTrackNotFound
        }

        let preferredTransform = try await sourceVideoTrack.load(.preferredTransform)
        try compositionVideoTrack.insertTimeRange(timeRange, of: sourceVideoTrack, at: .zero)
        compositionVideoTrack.preferredTransform = preferredTransform

        if let sourceAudioTrack = try await sourceAsset.loadTracks(withMediaType: .audio).first,
           let compositionAudioTrack = composition.addMutableTrack(
            withMediaType: .audio,
            preferredTrackID: kCMPersistentTrackID_Invalid
           ) {
            try? compositionAudioTrack.insertTimeRange(timeRange, of: sourceAudioTrack, at: .zero)
        }

        guard let exportSession = AVAssetExportSession(
            asset: composition,
            presetName: AVAssetExportPresetHighestQuality
        ) else {
            throw VideoEditingError.exportSessionCreationFailed
        }

        exportSession.shouldOptimizeForNetworkUse = true
        setActiveSession(exportSession)
        defer { setActiveSession(nil) }

        let progressTask = Task {
            for await state in exportSession.states(updateInterval: 0.12) {
                switch state {
                case .pending, .waiting:
                    onProgress(0.02)
                case .exporting(let progress):
                    onProgress(min(0.99, max(0.02, progress.fractionCompleted)))
                @unknown default:
                    break
                }
            }
        }
        defer { progressTask.cancel() }

        do {
            try await exportSession.export(to: destinationURL, as: .mp4)
            onProgress(1.0)
        } catch is CancellationError {
            throw VideoEditingError.exportCancelled
        } catch {
            throw VideoEditingError.exportFailed(error.localizedDescription)
        }
    }

    func cancelActiveExport() {
        lock.lock()
        let session = activeExportSession
        lock.unlock()
        session?.cancelExport()
    }

    private func setActiveSession(_ session: AVAssetExportSession?) {
        lock.lock()
        activeExportSession = session
        lock.unlock()
    }
}

