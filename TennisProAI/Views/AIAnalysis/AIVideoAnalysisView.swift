import SwiftUI
import SwiftData

struct AIVideoAnalysisView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \PlayerProfile.createdAt) private var profiles: [PlayerProfile]
    @Query(sort: \VideoRecording.recordedAt, order: .reverse) private var recordings: [VideoRecording]

    @State private var viewModel: AIAnalysisViewModel

    init(initialRecording: VideoRecording? = nil) {
        _viewModel = State(initialValue: AIAnalysisViewModel(selectedRecording: initialRecording))
    }

    private var dominantHand: DominantHand {
        profiles.first?.dominantHand ?? .right
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    capabilityDisclosureCard

                    videoSelectionCard

                    if let recording = viewModel.selectedRecording {
                        framePoseInspectorCard(recording: recording)

                        automatedHighlightScanCard(recording: recording)

                        if !viewModel.candidateHighlights.isEmpty {
                            candidateHighlightsReviewCard
                        }

                        manualTechniqueBookmarkCard

                        savedAnalysisRecordsSection(recording: recording)
                    } else {
                        EmptyStateCardView(
                            icon: "viewfinder.circle",
                            title: "Select a Recorded Video to Analyze",
                            message: "Record a tennis session first, then open the AI Vision Lab to inspect skeletal body pose angles and detect active rally segments locally on your iPhone."
                        )
                    }
                }
                .padding(AppSpacing.md)
            }
            .background(AppTheme.primaryBackground.ignoresSafeArea())
            .navigationTitle("AI Tennis Vision Lab")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") {
                        viewModel.cancelFullScan()
                        dismiss()
                    }
                }
            }
            .task {
                if viewModel.selectedRecording == nil, let first = recordings.first {
                    await viewModel.selectRecording(first, dominantHand: dominantHand)
                } else if let current = viewModel.selectedRecording {
                    await viewModel.selectRecording(current, dominantHand: dominantHand)
                }
            }
        }
    }

    // MARK: - Honest AI Capability & Privacy Disclosure

    private var capabilityDisclosureCard: some View {
        CourtCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("On-Device Computer Vision Status", systemImage: "cpu.fill")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.courtGreen)
                    Spacer()
                    BadgePill(text: "100% LOCAL", icon: "lock.fill", color: AppTheme.opticLime)
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(AppTheme.courtGreen)
                        .font(.caption)
                    Text("**Active Now (Apple Vision):** Player detection, 2D body-pose skeletal landmarks, elbow/knee joint flexion angles, overhead wrist elevation, court-zone estimation, and active play interval segmentation.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundStyle(AppTheme.clayAmber)
                        .font(.caption)
                    Text("**Awaiting Core ML Action Model:** Automatic Forehand/Backhand/Winner/Error shot classification requires a trained `.mlmodelc` action classifier via `StrokeClassifierModelProtocol`. Assign shot categories manually when reviewing detected segments.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var videoSelectionCard: some View {
        CourtCard(padding: 14) {
            HStack {
                Text("Target Video")
                    .font(.subheadline.weight(.bold))
                Spacer()
                if recordings.isEmpty {
                    Text("No videos saved")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Menu {
                        ForEach(recordings) { video in
                            Button(video.title) {
                                Task {
                                    await viewModel.selectRecording(video, dominantHand: dominantHand)
                                }
                            }
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(viewModel.selectedRecording?.title ?? "Choose Video")
                                .lineLimit(1)
                            Image(systemName: "chevron.up.chevron.down")
                        }
                        .font(.caption.weight(.bold))
                        .foregroundStyle(AppTheme.courtGreen)
                    }
                }
            }
        }
    }

    // MARK: - Single Frame Pose Skeleton Overlay & Biomechanics

    private func framePoseInspectorCard(recording: VideoRecording) -> some View {
        CourtCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Frame Pose & Joint Inspector")
                        .font(.headline.weight(.bold))
                    Spacer()
                    if viewModel.isInspectingFrame {
                        ProgressView()
                            .controlSize(.small)
                    }
                }

                if let inspection = viewModel.currentFrameInspection {
                    ZStack {
                        Image(uiImage: inspection.frameImage)
                            .resizable()
                            .scaledToFit()
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            .overlay {
                                if let joints = inspection.poseMetrics?.joints {
                                    PoseSkeletonCanvasOverlay(joints: joints)
                                }
                            }
                    }
                    .frame(maxHeight: 260)

                    HStack(spacing: 8) {
                        BadgePill(text: inspection.modelVersion, color: AppTheme.hardcourtBlue)
                        if let conf = inspection.observationConfidence {
                            BadgePill(
                                text: String(format: "Vision Confidence %.0f%%", conf * 100.0),
                                color: AppTheme.courtGreen
                            )
                        }
                    }

                    Text(inspection.summaryText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Frame Timestamp: \(TimeFormatters.preciseString(from: viewModel.scrubTimestampSeconds))")
                        .font(.caption.weight(.bold).monospacedDigit())

                    Slider(
                        value: $viewModel.scrubTimestampSeconds,
                        in: 0...max(0.5, recording.durationSeconds),
                        onEditingChanged: { editing in
                            if !editing {
                                Task { await viewModel.inspectFrameAtCurrentTimestamp(dominantHand: dominantHand) }
                            }
                        }
                    )
                    .tint(AppTheme.courtGreen)
                }

                SecondaryCourtButton("Analyze Current Frame Pose", systemImage: "figure.tennis") {
                    Task { await viewModel.inspectFrameAtCurrentTimestamp(dominantHand: dominantHand) }
                }
            }
        }
    }

    // MARK: - Extensible Highlight Candidate Detection

    private func automatedHighlightScanCard(recording: VideoRecording) -> some View {
        CourtCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Candidate Highlight Detection")
                    .font(.headline.weight(.bold))

                Text("Scans video frames on-device using Apple Vision to detect player movement bursts and overhead serve postures, then lets you review and export selected clips.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                if viewModel.isRunningFullScan {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("Scanning frames on iPhone...")
                                .font(.caption.weight(.bold))
                            Spacer()
                            Text("\(Int((viewModel.scanProgress * 100).rounded()))%")
                                .font(.caption.weight(.bold).monospacedDigit())
                        }
                        ProgressView(value: viewModel.scanProgress)
                            .tint(AppTheme.courtGreen)
                        SecondaryCourtButton("Cancel Scan", systemImage: "xmark", tint: AppTheme.liveRecordRed) {
                            viewModel.cancelFullScan()
                        }
                    }
                } else {
                    PrimaryCourtButton("Scan Video for Active Segments", systemImage: "waveform.and.magnifyingglass") {
                        viewModel.startFullVideoScan(dominantHand: dominantHand, in: modelContext)
                    }
                }

                if let summary = viewModel.scanSummaryBanner {
                    Text(summary)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppTheme.opticLime)
                }

                if let err = viewModel.errorMessage {
                    ErrorRecoveryBanner(message: err, recoverySuggestion: nil) {
                        viewModel.errorMessage = nil
                    }
                }
            }
        }
    }

    private var candidateHighlightsReviewCard: some View {
        CourtCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Review Suggested Highlights (\(viewModel.candidateHighlights.count))")
                    .font(.headline.weight(.bold))

                ForEach($viewModel.candidateHighlights) { $candidate in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Toggle(isOn: $candidate.isSelectedForExport) {
                                Text("\(TimeFormatters.clockString(from: candidate.startTimestamp)) – \(TimeFormatters.clockString(from: candidate.endTimestamp))")
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                            }
                            .tint(AppTheme.courtGreen)
                        }

                        HStack(spacing: 8) {
                            Text("Assign Category:")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Picker("Category", selection: $candidate.userSelectedCategory) {
                                ForEach(HighlightCategory.allCases) { cat in
                                    Text(cat.rawValue).tag(cat)
                                }
                            }
                            .pickerStyle(.menu)
                            Spacer()
                            if let conf = candidate.modelConfidence {
                                Text(String(format: "Pose Conf %.0f%%", conf * 100))
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }

                        Text(candidate.observationSummary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(10)
                    .background(AppTheme.elevatedCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                if viewModel.isExportingCandidates {
                    ProgressView("Exporting Selected Clips...", value: viewModel.candidateExportProgress)
                        .tint(AppTheme.courtGreen)
                } else {
                    PrimaryCourtButton("Create Clips From Selected Highlights", systemImage: "scissors") {
                        Task {
                            await viewModel.exportSelectedCandidateHighlights(in: modelContext)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Manual Technique Bookmark Alternative

    private var manualTechniqueBookmarkCard: some View {
        CourtCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Manual Technique Observation")
                        .font(.headline.weight(.bold))
                    Spacer()
                    BadgePill(text: "COACH / SELF", color: AppTheme.clayAmber)
                }

                Picker("Stroke Phase", selection: $viewModel.manualPhaseTitle) {
                    Text("Split-Step & Preparation").tag("Split-Step & Preparation")
                    Text("Backswing / Unit Turn").tag("Backswing / Unit Turn")
                    Text("Contact Point Observation").tag("Contact Point Observation")
                    Text("Follow-Through & Recovery").tag("Follow-Through & Recovery")
                }
                .pickerStyle(.menu)

                TextField("Note at \(TimeFormatters.preciseString(from: viewModel.scrubTimestampSeconds))...", text: $viewModel.manualNoteText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)

                SecondaryCourtButton("Save Technique Bookmark at Current Frame", systemImage: "bookmark.fill") {
                    viewModel.saveManualObservationBookmark(in: modelContext)
                }
            }
        }
    }

    private func savedAnalysisRecordsSection(recording: VideoRecording) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Saved Analysis Log (\(recording.analysisRecords.count))")
                .font(.headline.weight(.bold))

            ForEach(recording.analysisRecords.sorted(by: { $0.timestampSeconds < $1.timestampSeconds })) { item in
                CourtCard(padding: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            BadgePill(text: item.eventType.rawValue)
                            Spacer()
                            Text(TimeFormatters.preciseString(from: item.timestampSeconds))
                                .font(.caption.weight(.bold).monospacedDigit())
                        }
                        Text(item.analysisResultText)
                            .font(.caption)
                        HStack {
                            Text("\(item.modelName) • \(item.modelVersion)")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let conf = item.confidenceScore {
                                Text(String(format: "Confidence: %.0f%%", conf * 100))
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(AppTheme.courtGreen)
                            }
                        }
                    }
                }
            }
        }
    }
}

/// Renders detected Apple Vision skeletal landmarks onto the inspected video frame.
private struct PoseSkeletonCanvasOverlay: View {
    let joints: [NormalizedJointPoint]

    var body: some View {
        GeometryReader { geo in
            Canvas { context, size in
                for pt in joints {
                    // Convert Vision normalized coordinates (origin bottom-left) to SwiftUI (origin top-left)
                    let x = pt.x * size.width
                    let y = (1.0 - pt.y) * size.height
                    let circle = Path(ellipseIn: CGRect(x: x - 4, y: y - 4, width: 8, height: 8))
                    context.fill(circle, with: .color(AppTheme.opticLime))
                }
            }
        }
        .allowsHitTesting(false)
    }
}

