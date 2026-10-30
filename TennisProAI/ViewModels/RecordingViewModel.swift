import Foundation
import Observation
import SwiftData
import UIKit

@MainActor
@Observable
final class RecordingViewModel: CameraServiceDelegate {
    let cameraService: CameraServiceProtocol
    let storageService: VideoStorageServiceProtocol

    var recordingState: RecordingLifecycleState = .idle
    var authorizationState: CameraAuthorizationState = .notDetermined
    var elapsedSeconds: Double = 0
    var showCourtGuideOverlay: Bool = true
    var isTripodDimmerActive: Bool = false

    // Session Metadata Draft
    var sessionTitle: String = ""
    var selectedSessionType: SessionType = .match
    var sessionNotes: String = ""
    var selectedMatchID: UUID? = nil
    var selectedTrainingID: UUID? = nil

    // Post-recording review & accidental deletion protection
    var pendingCompletedFileURL: URL? = nil
    var pendingRelativePath: String? = nil
    var pendingRecordingID: UUID? = nil
    var showSaveRecordingSheet: Bool = false
    var showStopConfirmationDialog: Bool = false
    var showDiscardConfirmationDialog: Bool = false

    // Status & Alerts
    var thermalWarningMessage: String? = nil
    var interruptionBannerMessage: String? = nil
    var errorMessage: String? = nil
    var errorRecoverySuggestion: String? = nil
    var savedConfirmationBanner: String? = nil

    private var timerTask: Task<Void, Never>?

    init(
        cameraService: CameraServiceProtocol? = nil,
        storageService: VideoStorageServiceProtocol? = nil
    ) {
        let resolvedCamera = cameraService ?? CameraService()
        let resolvedStorage = storageService ?? VideoStorageService.shared
        self.cameraService = resolvedCamera
        self.storageService = resolvedStorage
        resolvedCamera.delegate = self
    }

    var isActivelyRecordingOrPaused: Bool {
        recordingState == .recording || recordingState == .paused
    }

    var formattedTimer: String {
        TimeFormatters.clockString(from: elapsedSeconds)
    }

    func onAppear() async {
        let granted = await cameraService.checkAndRequestPermissions()
        authorizationState = cameraService.authorizationState
        guard granted else {
            errorMessage = CameraServiceError.cameraPermissionDenied.errorDescription
            errorRecoverySuggestion = CameraServiceError.cameraPermissionDenied.recoverySuggestion
            return
        }

        do {
            try await cameraService.startSession()
            evaluateThermalState(cameraService.thermalState)
        } catch let err as LocalizedError {
            errorMessage = err.errorDescription
            errorRecoverySuggestion = err.recoverySuggestion
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func onDisappear() {
        if !isActivelyRecordingOrPaused {
            UIApplication.shared.isIdleTimerDisabled = false
            isTripodDimmerActive = false
            cameraService.stopSession()
        }
    }

    func selectLens(_ lens: CameraLensOption) async {
        do {
            try await cameraService.selectLens(lens)
        } catch let err as LocalizedError {
            errorMessage = err.errorDescription
            errorRecoverySuggestion = err.recoverySuggestion
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectFormat(_ format: VideoRecordingFormatOption) async {
        do {
            try await cameraService.selectFormat(format)
        } catch let err as LocalizedError {
            errorMessage = err.errorDescription
            errorRecoverySuggestion = err.recoverySuggestion
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func startRecording() {
        errorMessage = nil
        savedConfirmationBanner = nil

        let newID = UUID()
        let ext = cameraService.isSimulatedCapture ? "mp4" : "mov"
        do {
            let destination = try storageService.makeNewRecordingDestination(id: newID, fileExtension: ext)
            pendingRecordingID = newID
            pendingRelativePath = destination.relativePath
            elapsedSeconds = 0
            if sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let df = DateFormatter()
                df.dateFormat = "MMM d • h:mm a"
                sessionTitle = "\(selectedSessionType.rawValue) — \(df.string(from: Date()))"
            }

            UIApplication.shared.isIdleTimerDisabled = true
            try cameraService.startRecording(to: destination.url)
            startElapsedTimer()
            HapticsManager.notification(.success)
        } catch let err as LocalizedError {
            UIApplication.shared.isIdleTimerDisabled = false
            errorMessage = err.errorDescription
            errorRecoverySuggestion = err.recoverySuggestion
        } catch {
            UIApplication.shared.isIdleTimerDisabled = false
            errorMessage = error.localizedDescription
        }
    }

    func togglePauseResume() {
        if recordingState == .recording {
            cameraService.pauseRecording()
            HapticsManager.impact(.light)
        } else if recordingState == .paused {
            cameraService.resumeRecording()
            HapticsManager.impact(.medium)
        }
    }

    func requestStopRecording() {
        // If recording has been running > 15s, confirm stop to prevent accidental bump on tripod;
        // otherwise stop immediately for fast drills/tests.
        if elapsedSeconds >= 15 {
            showStopConfirmationDialog = true
        } else {
            confirmStopRecording()
        }
    }

    func confirmStopRecording() {
        showStopConfirmationDialog = false
        isTripodDimmerActive = false
        stopElapsedTimer()
        UIApplication.shared.isIdleTimerDisabled = false
        cameraService.stopRecording()
        HapticsManager.notification(.warning)
    }

    func saveCompletedRecording(in context: ModelContext) async {
        guard let url = pendingCompletedFileURL,
              let relativePath = pendingRelativePath,
              let id = pendingRecordingID else {
            showSaveRecordingSheet = false
            return
        }

        let cleanTitle = sessionTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalTitle = cleanTitle.isEmpty ? "Tennis Session" : cleanTitle

        let metadata = try? await storageService.inspectVideoMetadata(at: url)
        let thumbRelative = await storageService.generateAndCacheThumbnail(
            forRelativePath: relativePath,
            id: id,
            atSeconds: min(1.0, max(0.1, (metadata?.durationSeconds ?? elapsedSeconds) * 0.25))
        )

        let record = VideoRecording(
            id: id,
            title: finalTitle,
            relativeFilePath: relativePath,
            thumbnailRelativePath: thumbRelative,
            recordedAt: Date(),
            durationSeconds: metadata?.durationSeconds ?? max(1, elapsedSeconds),
            sessionType: selectedSessionType,
            resolutionWidth: metadata?.width ?? (cameraService.selectedFormat?.width ?? 1920),
            resolutionHeight: metadata?.height ?? (cameraService.selectedFormat?.height ?? 1080),
            frameRate: metadata?.frameRate ?? (cameraService.selectedFormat?.frameRate ?? 60),
            fileSizeBytes: metadata?.fileSizeBytes ?? 0,
            cameraLensLabel: cameraService.selectedLens?.displayLabel ?? "1x Main",
            notes: sessionNotes.trimmingCharacters(in: .whitespacesAndNewlines),
            tags: [selectedSessionType.rawValue.lowercased()],
            linkedMatchID: selectedMatchID,
            linkedTrainingSessionID: selectedTrainingID
        )

        context.insert(record)

        // Synchronize reverse link if associated with a MatchRecord or TrainingSession
        if let matchID = selectedMatchID,
           let matches = try? context.fetch(FetchDescriptor<MatchRecord>()) {
            matches.first(where: { $0.id == matchID })?.linkedVideoID = record.id
        }
        if let trainingID = selectedTrainingID,
           let trainings = try? context.fetch(FetchDescriptor<TrainingSession>()) {
            trainings.first(where: { $0.id == trainingID })?.linkedVideoID = record.id
        }

        try? context.save()

        savedConfirmationBanner = "Saved \"\(finalTitle)\" to Video Library."
        resetDraftAfterSave()
    }

    func discardPendingRecording() {
        storageService.deleteMediaFile(atRelativePath: pendingRelativePath)
        showDiscardConfirmationDialog = false
        resetDraftAfterSave()
    }

    private func resetDraftAfterSave() {
        pendingCompletedFileURL = nil
        pendingRelativePath = nil
        pendingRecordingID = nil
        sessionTitle = ""
        sessionNotes = ""
        selectedMatchID = nil
        selectedTrainingID = nil
        elapsedSeconds = 0
        showSaveRecordingSheet = false
    }

    // MARK: - Timer & Thermal Helpers

    private func startElapsedTimer() {
        stopElapsedTimer()
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard let self else { return }
                if self.recordingState == .recording {
                    self.elapsedSeconds += 0.5
                }
            }
        }
    }

    private func stopElapsedTimer() {
        timerTask?.cancel()
        timerTask = nil
    }

    private func evaluateThermalState(_ state: ProcessInfo.ThermalState) {
        switch state {
        case .nominal, .fair:
            thermalWarningMessage = nil
        case .serious:
            thermalWarningMessage = "iPhone temperature is elevated. Enable Tripod Screen Dimmer or switch to 1080p • 30 fps for long outdoor sets."
        case .critical:
            thermalWarningMessage = "Critical device temperature! Shade your iPhone immediately to prevent iOS thermal shutdown."
        @unknown default:
            thermalWarningMessage = nil
        }
    }

    // MARK: - CameraServiceDelegate

    func cameraServiceDidUpdateState(_ state: RecordingLifecycleState) {
        self.recordingState = state
    }

    func cameraServiceDidFinishRecording(outputURL: URL, error: Error?) {
        stopElapsedTimer()
        UIApplication.shared.isIdleTimerDisabled = false

        if let error {
            // Even if interrupted (e.g. phone call / low battery), check if iOS wrote a playable file so user doesn't lose footage!
            if FileManager.default.fileExists(atPath: outputURL.path) {
                pendingCompletedFileURL = outputURL
                showSaveRecordingSheet = true
                errorMessage = "Recording stopped early (\(error.localizedDescription)). Your partial footage was recovered and can be saved."
            } else {
                errorMessage = error.localizedDescription
                errorRecoverySuggestion = "Verify available iPhone storage and try recording again."
            }
            return
        }

        pendingCompletedFileURL = outputURL
        showSaveRecordingSheet = true
    }

    func cameraServiceDidChangeThermalState(_ thermalState: ProcessInfo.ThermalState) {
        evaluateThermalState(thermalState)
    }

    func cameraServiceDidEncounterInterruption(_ reason: String?) {
        interruptionBannerMessage = reason
    }
}

