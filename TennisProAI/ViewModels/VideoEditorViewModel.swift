import Foundation
import AVFoundation
import Observation
import SwiftData
import UIKit

@MainActor
@Observable
final class VideoEditorViewModel {
    let recording: VideoRecording
    let editingService: VideoEditingServiceProtocol
    let storageService: VideoStorageServiceProtocol

    var player: AVPlayer?
    var timelineThumbnails: [UIImage] = []
    var sourceDuration: Double = 0
    var currentPlayheadSeconds: Double = 0
    var startTimeSeconds: Double = 0
    var endTimeSeconds: Double = 5.0
    var isPlayingSegment: Bool = false

    // Clip Creation Form
    var clipTitle: String = ""
    var selectedCategory: HighlightCategory = .forehand
    var clipNotes: String = ""
    var markClipFavorite: Bool = false

    // Export State
    var isExporting: Bool = false
    var exportProgress: Double = 0
    var statusMessage: String? = nil
    var errorMessage: String? = nil

    private var timeObserverToken: Any?

    init(
        recording: VideoRecording,
        editingService: VideoEditingServiceProtocol = VideoEditingService(),
        storageService: VideoStorageServiceProtocol = VideoStorageService.shared
    ) {
        self.recording = recording
        self.editingService = editingService
        self.storageService = storageService
        let dur = max(1.0, recording.durationSeconds)
        self.sourceDuration = dur
        self.startTimeSeconds = 0
        self.endTimeSeconds = min(dur, max(1.0, min(12.0, dur)))
        self.clipTitle = "\(selectedCategory.rawValue) Highlight"
    }

    var selectedSegmentDuration: Double {
        max(0, endTimeSeconds - startTimeSeconds)
    }

    var sourceFileExists: Bool {
        storageService.fileExists(forRelativePath: recording.relativeFilePath)
    }

    func prepareEditor() async {
        let url = storageService.resolveURL(forRelativePath: recording.relativeFilePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "The source recording file is missing from local storage."
            return
        }

        if let meta = try? await storageService.inspectVideoMetadata(at: url), meta.durationSeconds > 0 {
            sourceDuration = meta.durationSeconds
            endTimeSeconds = min(sourceDuration, max(VideoTrimParameters.minimumClipDuration, min(12.0, sourceDuration)))
        }

        let item = AVPlayerItem(url: url)
        let avPlayer = AVPlayer(playerItem: item)
        self.player = avPlayer
        installTimeObserver(on: avPlayer)

        timelineThumbnails = await editingService.generateTimelineThumbnails(for: url, count: 8)
    }

    func tearDownPlayer() {
        player?.pause()
        if let token = timeObserverToken {
            player?.removeTimeObserver(token)
            timeObserverToken = nil
        }
        isPlayingSegment = false
    }

    private func installTimeObserver(on avPlayer: AVPlayer) {
        let interval = CMTime(seconds: 0.1, preferredTimescale: 600)
        timeObserverToken = avPlayer.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let sec = CMTimeGetSeconds(time)
                if sec.isFinite {
                    self.currentPlayheadSeconds = sec
                    if self.isPlayingSegment && sec >= self.endTimeSeconds {
                        self.seek(to: self.startTimeSeconds)
                        self.player?.play()
                    }
                }
            }
        }
    }

    func seek(to seconds: Double) {
        let clamped = min(max(0, seconds), sourceDuration)
        currentPlayheadSeconds = clamped
        let cm = CMTime(seconds: clamped, preferredTimescale: 600)
        player?.seek(to: cm, toleranceBefore: .zero, toleranceAfter: .zero)
    }

    func togglePreviewSegmentPlayback() {
        guard let player else { return }
        if isPlayingSegment {
            player.pause()
            isPlayingSegment = false
        } else {
            if currentPlayheadSeconds < startTimeSeconds || currentPlayheadSeconds >= endTimeSeconds {
                seek(to: startTimeSeconds)
            }
            player.play()
            isPlayingSegment = true
        }
    }

    func nudgeStart(by delta: Double) {
        let newStart = min(max(0, startTimeSeconds + delta), max(0, endTimeSeconds - VideoTrimParameters.minimumClipDuration))
        startTimeSeconds = newStart
        seek(to: newStart)
    }

    func nudgeEnd(by delta: Double) {
        let newEnd = max(min(sourceDuration, endTimeSeconds + delta), min(sourceDuration, startTimeSeconds + VideoTrimParameters.minimumClipDuration))
        endTimeSeconds = newEnd
        seek(to: newEnd)
    }

    func onCategoryChanged(_ category: HighlightCategory) {
        selectedCategory = category
        if clipTitle.hasSuffix("Highlight") || clipTitle.trimmingCharacters(in: .whitespaces).isEmpty {
            clipTitle = "\(category.rawValue) Highlight"
        }
    }

    func exportAndSaveClip(in context: ModelContext) async {
        errorMessage = nil
        statusMessage = nil
        player?.pause()
        isPlayingSegment = false

        let params = VideoTrimParameters(
            startTimeSeconds: startTimeSeconds,
            endTimeSeconds: endTimeSeconds,
            sourceDurationSeconds: sourceDuration
        )

        do {
            try editingService.validateTrim(params)
            let clipID = UUID()
            let destination = try storageService.makeNewClipDestination(id: clipID, fileExtension: "mp4")
            let sourceURL = storageService.resolveURL(forRelativePath: recording.relativeFilePath)

            isExporting = true
            exportProgress = 0.02

            try await editingService.exportTrimmedClip(
                sourceURL: sourceURL,
                destinationURL: destination.url,
                parameters: params
            ) { [weak self] progress in
                Task { @MainActor [weak self] in
                    self?.exportProgress = progress
                }
            }

            let thumbRelative = await storageService.generateAndCacheThumbnail(
                forRelativePath: destination.relativePath,
                id: clipID,
                atSeconds: min(0.5, params.endTimeSeconds - params.startTimeSeconds)
            )

            let finalTitle = clipTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "\(selectedCategory.rawValue) Clip"
                : clipTitle.trimmingCharacters(in: .whitespacesAndNewlines)

            let clip = VideoClip(
                id: clipID,
                parentRecordingID: recording.id,
                title: finalTitle,
                relativeFilePath: destination.relativePath,
                thumbnailRelativePath: thumbRelative,
                startTimeSeconds: startTimeSeconds,
                endTimeSeconds: endTimeSeconds,
                category: selectedCategory,
                notes: clipNotes.trimmingCharacters(in: .whitespacesAndNewlines),
                isFavorite: markClipFavorite,
                recording: recording
            )

            context.insert(clip)
            recording.clips.append(clip)
            try? context.save()

            isExporting = false
            exportProgress = 1.0
            statusMessage = "Created clip \"\(finalTitle)\" (\(clip.formattedDuration)). Ready to extract another clip!"
            clipNotes = ""
            markClipFavorite = false
            HapticsManager.notification(.success)
        } catch let err as LocalizedError {
            isExporting = false
            errorMessage = err.errorDescription
        } catch {
            isExporting = false
            errorMessage = error.localizedDescription
        }
    }

    func cancelExport() {
        editingService.cancelActiveExport()
        isExporting = false
    }

    func exportClipToPhotos(_ clip: VideoClip) async {
        let url = storageService.resolveURL(forRelativePath: clip.relativeFilePath)
        do {
            try await storageService.exportVideoToPhotosLibrary(fileURL: url)
            statusMessage = "Exported \"\(clip.title)\" to Photos."
            HapticsManager.notification(.success)
        } catch let err as LocalizedError {
            errorMessage = err.errorDescription
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

