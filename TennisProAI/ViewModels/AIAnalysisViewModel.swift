import Foundation
import Observation
import SwiftData
import UIKit

@MainActor
@Observable
final class AIAnalysisViewModel {
    let aiService: AIAnalysisServiceProtocol
    let editingService: VideoEditingServiceProtocol
    let storageService: VideoStorageServiceProtocol

    var selectedRecording: VideoRecording?
    var scrubTimestampSeconds: Double = 0.5
    var currentFrameInspection: FramePoseInspectionResult?
    var isInspectingFrame: Bool = false

    // Batch Vision Scan & Highlight Detection Workflow
    var isRunningFullScan: Bool = false
    var scanProgress: Double = 0
    var candidateHighlights: [CandidateHighlightEvent] = []
    var scanSummaryBanner: String? = nil

    // Manual Observation Form
    var manualPhaseTitle: String = "Contact Point Observation"
    var manualNoteText: String = ""

    // Batch Highlight Clip Export
    var isExportingCandidates: Bool = false
    var candidateExportProgress: Double = 0
    var errorMessage: String? = nil

    private var scanTask: Task<Void, Never>?

    init(
        selectedRecording: VideoRecording? = nil,
        aiService: AIAnalysisServiceProtocol = AIAnalysisService(),
        editingService: VideoEditingServiceProtocol = VideoEditingService(),
        storageService: VideoStorageServiceProtocol = VideoStorageService.shared
    ) {
        self.selectedRecording = selectedRecording
        self.aiService = aiService
        self.editingService = editingService
        self.storageService = storageService
    }

    func selectRecording(_ recording: VideoRecording, dominantHand: DominantHand) async {
        selectedRecording = recording
        scrubTimestampSeconds = min(1.0, max(0, recording.durationSeconds * 0.25))
        candidateHighlights = []
        scanSummaryBanner = nil
        await inspectFrameAtCurrentTimestamp(dominantHand: dominantHand)
    }

    func inspectFrameAtCurrentTimestamp(dominantHand: DominantHand) async {
        guard let recording = selectedRecording else { return }
        let url = storageService.resolveURL(forRelativePath: recording.relativeFilePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "Video file not found on disk for Vision analysis."
            return
        }

        isInspectingFrame = true
        defer { isInspectingFrame = false }

        do {
            currentFrameInspection = try await aiService.inspectSingleFrame(
                at: scrubTimestampSeconds,
                in: url,
                dominantHand: dominantHand
            )
            errorMessage = nil
        } catch {
            errorMessage = "Unable to inspect frame: \(error.localizedDescription)"
        }
    }

    func startFullVideoScan(dominantHand: DominantHand, in context: ModelContext) {
        guard let recording = selectedRecording, !isRunningFullScan else { return }
        let url = storageService.resolveURL(forRelativePath: recording.relativeFilePath)
        guard FileManager.default.fileExists(atPath: url.path) else {
            errorMessage = "Video file is missing from local storage."
            return
        }

        isRunningFullScan = true
        scanProgress = 0.01
        errorMessage = nil
        scanSummaryBanner = nil

        let videoID = recording.id
        scanTask = Task { [weak self] in
            guard let self else { return }
            do {
                let summary = try await self.aiService.runOnDeviceVisionScan(
                    videoURL: url,
                    videoID: videoID,
                    dominantHand: dominantHand,
                    sampleIntervalSeconds: 1.0
                ) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        self?.scanProgress = progress
                    }
                }

                for record in summary.records {
                    record.recording = recording
                    context.insert(record)
                    recording.analysisRecords.append(record)
                }
                try? context.save()

                self.candidateHighlights = summary.candidateHighlights
                self.scanSummaryBanner = "Vision scan completed locally: \(summary.framesWithPlayerDetected)/\(summary.sampledFrameCount) sampled frames contained a player; \(summary.candidateHighlights.count) candidate highlight interval(s) identified."
                self.isRunningFullScan = false
                HapticsManager.notification(.success)
            } catch is CancellationError {
                self.isRunningFullScan = false
            } catch {
                self.isRunningFullScan = false
                self.errorMessage = error.localizedDescription
            }
        }
    }

    func cancelFullScan() {
        scanTask?.cancel()
        scanTask = nil
        isRunningFullScan = false
    }

    func saveManualObservationBookmark(in context: ModelContext) {
        guard let recording = selectedRecording else { return }
        let cleanNote = manualNoteText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanNote.isEmpty else { return }

        let record = AIAnalysisRecord(
            videoID: recording.id,
            eventType: .manualTechniqueNote,
            timestampSeconds: scrubTimestampSeconds,
            analysisResultText: "[\(manualPhaseTitle)] \(cleanNote)",
            confidenceScore: nil, // Never assign fake confidence to manual notes
            modelName: "Coach / Self Review",
            modelVersion: "Manual",
            status: .manualEntry,
            metrics: currentFrameInspection?.poseMetrics,
            recording: recording
        )

        context.insert(record)
        recording.analysisRecords.append(record)
        try? context.save()
        manualNoteText = ""
        HapticsManager.impact(.light)
    }

    func exportSelectedCandidateHighlights(in context: ModelContext) async {
        guard let recording = selectedRecording else { return }
        let chosen = candidateHighlights.filter(\.isSelectedForExport)
        guard !chosen.isEmpty else { return }

        let sourceURL = storageService.resolveURL(forRelativePath: recording.relativeFilePath)
        isExportingCandidates = true
        candidateExportProgress = 0
        errorMessage = nil

        var exportedCount = 0
        for (idx, candidate) in chosen.enumerated() {
            let params = VideoTrimParameters(
                startTimeSeconds: candidate.startTimestamp,
                endTimeSeconds: candidate.endTimestamp,
                sourceDurationSeconds: max(candidate.endTimestamp, recording.durationSeconds)
            )
            do {
                let clipID = UUID()
                let dest = try storageService.makeNewClipDestination(id: clipID, fileExtension: "mp4")
                try await editingService.exportTrimmedClip(
                    sourceURL: sourceURL,
                    destinationURL: dest.url,
                    parameters: params
                ) { _ in }

                let thumb = await storageService.generateAndCacheThumbnail(
                    forRelativePath: dest.relativePath,
                    id: clipID,
                    atSeconds: 0.5
                )

                let clip = VideoClip(
                    id: clipID,
                    parentRecordingID: recording.id,
                    title: "\(candidate.userSelectedCategory.rawValue) @ \(TimeFormatters.clockString(from: candidate.startTimestamp))",
                    relativeFilePath: dest.relativePath,
                    thumbnailRelativePath: thumb,
                    startTimeSeconds: candidate.startTimestamp,
                    endTimeSeconds: candidate.endTimestamp,
                    category: candidate.userSelectedCategory,
                    notes: candidate.observationSummary,
                    recording: recording
                )
                context.insert(clip)
                recording.clips.append(clip)
                exportedCount += 1
            } catch {
                errorMessage = "Some clips could not be exported: \(error.localizedDescription)"
            }
            candidateExportProgress = Double(idx + 1) / Double(chosen.count)
        }

        try? context.save()
        isExportingCandidates = false
        scanSummaryBanner = "Created \(exportedCount) highlight clip(s) from reviewed timestamps."
        HapticsManager.notification(.success)
    }
}

