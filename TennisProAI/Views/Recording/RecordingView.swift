import SwiftUI
import SwiftData
import UIKit

struct RecordingView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \MatchRecord.matchDate, order: .reverse) private var matches: [MatchRecord]
    @Query(sort: \TrainingSession.sessionDate, order: .reverse) private var trainings: [TrainingSession]

    @State private var viewModel = RecordingViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                // Live Camera / Simulator Preview Feed
                CameraPreviewView(
                    session: viewModel.cameraService.captureSession,
                    isSimulated: viewModel.cameraService.isSimulatedCapture
                )
                .ignoresSafeArea()

                if viewModel.cameraService.isSimulatedCapture {
                    VStack(spacing: 8) {
                        Image(systemName: "video.viewfinder")
                            .font(.system(size: 46))
                            .foregroundStyle(AppTheme.opticLime.opacity(0.85))
                        Text("Simulated Court Camera Ready")
                            .font(.headline.weight(.bold))
                            .foregroundStyle(.white)
                        Text("Generates real playable MP4 court footage when tested on Simulator.")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.75))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                    }
                    .allowsHitTesting(false)
                }

                if viewModel.showCourtGuideOverlay {
                    CourtAlignmentGuideOverlay()
                }

                // Foreground Tripod HUD
                VStack(spacing: 12) {
                    topStatusHUD

                    if let thermal = viewModel.thermalWarningMessage {
                        ErrorRecoveryBanner(message: thermal, recoverySuggestion: nil)
                            .padding(.horizontal, AppSpacing.md)
                    }

                    if let interruption = viewModel.interruptionBannerMessage {
                        ErrorRecoveryBanner(message: interruption, recoverySuggestion: "Recording resumes when interruption clears.")
                            .padding(.horizontal, AppSpacing.md)
                    }

                    if let err = viewModel.errorMessage {
                        ErrorRecoveryBanner(message: err, recoverySuggestion: viewModel.errorRecoverySuggestion) {
                            viewModel.errorMessage = nil
                        }
                        .padding(.horizontal, AppSpacing.md)
                    }

                    if let savedMsg = viewModel.savedConfirmationBanner {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.opticLime)
                            Text(savedMsg)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.white)
                            Spacer()
                        }
                        .padding(12)
                        .background(Color.black.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .padding(.horizontal, AppSpacing.md)
                    }

                    Spacer()

                    if viewModel.authorizationState == .denied || viewModel.authorizationState == .restricted {
                        permissionDeniedCard
                            .padding(.horizontal, AppSpacing.md)
                    } else {
                        bottomTripodControls
                    }
                }
                .padding(.vertical, 10)

                // OLED Battery-Saver Dimmer Curtain for Tripod Play
                if viewModel.isTripodDimmerActive {
                    tripodDimmerOverlay
                }
            }
            .navigationTitle("Court Recorder")
            .navigationBarTitleDisplayMode(.inline)
            .task {
                await viewModel.onAppear()
            }
            .onDisappear {
                viewModel.onDisappear()
            }
            .confirmationDialog(
                "Stop Recording?",
                isPresented: $viewModel.showStopConfirmationDialog,
                titleVisibility: .visible
            ) {
                Button("Stop & Review Recording", role: .destructive) {
                    viewModel.confirmStopRecording()
                }
                Button("Continue Recording", role: .cancel) {}
            } message: {
                Text("Elapsed recording time: \(viewModel.formattedTimer)")
            }
            .sheet(isPresented: $viewModel.showSaveRecordingSheet) {
                saveMetadataSheet
                    .interactiveDismissDisabled(true)
            }
        }
    }

    // MARK: - Top HUD

    private var topStatusHUD: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                // Recording Status Badge & Timer
                HStack(spacing: 8) {
                    Circle()
                        .fill(statusIndicatorColor)
                        .frame(width: 12, height: 12)
                    Text(statusBadgeLabel)
                        .font(.caption.weight(.heavy))
                        .foregroundStyle(.white)
                    Text(viewModel.formattedTimer)
                        .font(.title3.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.72))
                .clipShape(Capsule())
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(statusBadgeLabel), elapsed time \(viewModel.formattedTimer)")

                Spacer()

                // Court Alignment Toggle
                Button {
                    viewModel.showCourtGuideOverlay.toggle()
                    HapticsManager.impact(.light)
                } label: {
                    Image(systemName: viewModel.showCourtGuideOverlay ? "squareshape.split.2x2" : "squareshape")
                        .font(.headline)
                        .foregroundStyle(viewModel.showCourtGuideOverlay ? AppTheme.opticLime : .white)
                        .frame(width: 44, height: 44)
                        .background(Color.black.opacity(0.68))
                        .clipShape(Circle())
                }
                .accessibilityLabel(viewModel.showCourtGuideOverlay ? "Hide court alignment guides" : "Show court alignment guides")

                // OLED Tripod Dimmer Button (Available while recording)
                if viewModel.isActivelyRecordingOrPaused {
                    Button {
                        viewModel.isTripodDimmerActive = true
                    } label: {
                        Image(systemName: "moon.zzz.fill")
                            .font(.headline)
                            .foregroundStyle(AppTheme.opticLime)
                            .frame(width: 44, height: 44)
                            .background(Color.black.opacity(0.68))
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("Dim screen to save battery while on tripod")
                }
            }
            .padding(.horizontal, AppSpacing.md)

            // Format & Session Type Selector Row (Locked while actively recording)
            if !viewModel.isActivelyRecordingOrPaused {
                HStack(spacing: 10) {
                    Menu {
                        ForEach(viewModel.cameraService.availableFormats) { fmt in
                            Button {
                                Task { await viewModel.selectFormat(fmt) }
                            } label: {
                                HStack {
                                    Text(fmt.displayLabel)
                                    if viewModel.cameraService.selectedFormat?.id == fmt.id {
                                        Image(systemName: "checkmark")
                                    }
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "film")
                            Text(viewModel.cameraService.selectedFormat?.displayLabel ?? "1080p • 60 fps")
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.68))
                        .clipShape(Capsule())
                    }

                    Menu {
                        ForEach(SessionType.allCases) { type in
                            Button {
                                viewModel.selectedSessionType = type
                            } label: {
                                Label(type.rawValue, systemImage: type.iconName)
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: viewModel.selectedSessionType.iconName)
                            Text(viewModel.selectedSessionType.rawValue)
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.caption2)
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.opticLime)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.68))
                        .clipShape(Capsule())
                    }

                    Spacer()
                }
                .padding(.horizontal, AppSpacing.md)
            }
        }
    }

    private var statusIndicatorColor: Color {
        switch viewModel.recordingState {
        case .recording: return AppTheme.liveRecordRed
        case .paused: return AppTheme.clayAmber
        default: return Color.gray
        }
    }

    private var statusBadgeLabel: String {
        switch viewModel.recordingState {
        case .idle: return "STANDBY"
        case .starting: return "STARTING"
        case .recording: return "REC"
        case .paused: return "PAUSED"
        case .stopping: return "SAVING"
        }
    }

    // MARK: - Bottom Courtside Controls

    private var bottomTripodControls: some View {
        VStack(spacing: 16) {
            // Lens Selector (0.5x Court Ultra-Wide, 1x Main, 5x Telephoto)
            if !viewModel.isActivelyRecordingOrPaused && !viewModel.cameraService.availableLenses.isEmpty {
                HStack(spacing: 10) {
                    ForEach(viewModel.cameraService.availableLenses) { lens in
                        let isSelected = viewModel.cameraService.selectedLens?.id == lens.id
                        Button {
                            Task { await viewModel.selectLens(lens) }
                        } label: {
                            Text(lens.displayLabel)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(isSelected ? .black : .white)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(isSelected ? AppTheme.opticLime : Color.black.opacity(0.65))
                                .clipShape(Capsule())
                        }
                        .frame(minHeight: 44)
                    }
                }
            }

            // Large Tripod Action Bar
            HStack(spacing: 18) {
                if !viewModel.isActivelyRecordingOrPaused {
                    Button {
                        viewModel.startRecording()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "record.circle.fill")
                                .font(.title2.weight(.bold))
                            Text("Start Recording")
                                .font(.title3.weight(.heavy))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 66)
                        .background(AppTheme.liveRecordRed)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .shadow(color: AppTheme.liveRecordRed.opacity(0.45), radius: 10, y: 4)
                    }
                    .accessibilityIdentifier("recording.startButton")
                } else {
                    // Pause / Resume Button (iOS 18 native movie pause/resume)
                    Button {
                        viewModel.togglePauseResume()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: viewModel.recordingState == .paused ? "play.fill" : "pause.fill")
                            Text(viewModel.recordingState == .paused ? "Resume" : "Pause")
                                .font(.headline.weight(.bold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(Color.black.opacity(0.78))
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(Color.white.opacity(0.3), lineWidth: 1.5)
                        )
                    }
                    .accessibilityIdentifier("recording.pauseResumeButton")

                    // Clear Stop Recording Button
                    Button {
                        viewModel.requestStopRecording()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "stop.fill")
                            Text("Stop Recording")
                                .font(.headline.weight(.heavy))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity, minHeight: 64)
                        .background(AppTheme.liveRecordRed)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    }
                    .accessibilityIdentifier("recording.stopButton")
                }
            }
            .padding(.horizontal, AppSpacing.md)
            .padding(.bottom, 8)
        }
    }

    private var permissionDeniedCard: some View {
        CourtCard {
            VStack(spacing: 12) {
                Image(systemName: "camera.metering.unknown")
                    .font(.largeTitle)
                    .foregroundStyle(AppTheme.liveRecordRed)
                Text("Camera Access Required")
                    .font(.headline.weight(.bold))
                Text("Tennis Pro AI needs Camera and Microphone access to record your matches and drills. Enable permissions in iOS Settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                PrimaryCourtButton("Open iOS Settings", systemImage: "gear") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
            }
        }
    }

    private var tripodDimmerOverlay: some View {
        ZStack {
            Color.black.opacity(0.92).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "record.circle")
                    .font(.system(size: 40))
                    .foregroundStyle(AppTheme.liveRecordRed)
                Text("Tripod Power-Saver Mode Active")
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(viewModel.formattedTimer)
                    .font(.system(size: 44, weight: .heavy, design: .monospaced))
                    .foregroundStyle(AppTheme.opticLime)
                Text("Screen dimmed to reduce iPhone thermal load & battery drain.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.6))
                SecondaryCourtButton("Wake Tripod Controls", systemImage: "sun.max.fill", tint: AppTheme.opticLime) {
                    viewModel.isTripodDimmerActive = false
                }
                .frame(maxWidth: 260)
            }
            .padding()
        }
    }

    // MARK: - Post-Recording Metadata & Save Sheet

    private var saveMetadataSheet: some View {
        NavigationStack {
            Form {
                Section("Session Details") {
                    TextField("Match or Session Name", text: $viewModel.sessionTitle)
                        .accessibilityIdentifier("recording.saveTitleField")

                    Picker("Session Type", selection: $viewModel.selectedSessionType) {
                        ForEach(SessionType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }

                    HStack {
                        Text("Recorded Duration")
                        Spacer()
                        Text(viewModel.formattedTimer)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }

                if !matches.isEmpty {
                    Section("Link to Match Scorecard (Optional)") {
                        Picker("Match Scorecard", selection: $viewModel.selectedMatchID) {
                            Text("None").tag(UUID?.none)
                            ForEach(matches) { match in
                                Text("vs \(match.opponentTeamDisplayName) (\(match.matchDate.formatted(date: .abbreviated, time: .omitted)))")
                                    .tag(UUID?.some(match.id))
                            }
                        }
                    }
                }

                if !trainings.isEmpty {
                    Section("Link to Training Session (Optional)") {
                        Picker("Training Session", selection: $viewModel.selectedTrainingID) {
                            Text("None").tag(UUID?.none)
                            ForEach(trainings) { session in
                                Text(session.name).tag(UUID?.some(session.id))
                            }
                        }
                    }
                }

                Section("Court Notes") {
                    TextField("Add tactical notes, court conditions, or focus areas...", text: $viewModel.sessionNotes, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Button {
                        Task {
                            await viewModel.saveCompletedRecording(in: modelContext)
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Label("Save to Video Library", systemImage: "checkmark.circle.fill")
                                .font(.headline.weight(.bold))
                            Spacer()
                        }
                    }
                    .tint(AppTheme.courtGreen)
                    .accessibilityIdentifier("recording.confirmSaveButton")

                    Button("Discard Recording...", role: .destructive) {
                        viewModel.showDiscardConfirmationDialog = true
                    }
                }
            }
            .navigationTitle("Save Recording")
            .navigationBarTitleDisplayMode(.inline)
            .confirmationDialog(
                "Permanently Discard Recording?",
                isPresented: $viewModel.showDiscardConfirmationDialog,
                titleVisibility: .visible
            ) {
                Button("Delete Unsaved Footage", role: .destructive) {
                    viewModel.discardPendingRecording()
                }
                Button("Keep Footage", role: .cancel) {}
            } message: {
                Text("This action permanently removes the captured video file and cannot be undone.")
            }
        }
    }
}

