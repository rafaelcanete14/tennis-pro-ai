import SwiftUI
import SwiftData
import AVKit

struct VideoDetailPlayerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var recording: VideoRecording

    @State private var player: AVPlayer? = nil
    @State private var playbackRate: Float = 1.0
    @State private var showEditMetadataSheet: Bool = false
    @State private var showVideoEditor: Bool = false
    @State private var showAIAnalyzer: Bool = false
    @State private var showDeleteDialog: Bool = false
    @State private var feedbackMessage: String? = nil
    @State private var errorMessage: String? = nil

    private let storage = VideoStorageService.shared

    private var videoURL: URL {
        storage.resolveURL(forRelativePath: recording.relativeFilePath)
    }

    private var fileExists: Bool {
        storage.fileExists(forRelativePath: recording.relativeFilePath)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                if fileExists {
                    playerSection
                } else {
                    missingFileSection
                }

                primaryActionRow

                if let msg = feedbackMessage {
                    HStack {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.courtGreen)
                        Text(msg)
                            .font(.caption.weight(.semibold))
                        Spacer()
                    }
                    .padding(12)
                    .background(AppTheme.elevatedCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if let err = errorMessage {
                    ErrorRecoveryBanner(message: err, recoverySuggestion: nil) {
                        errorMessage = nil
                    }
                }

                metadataCard

                extractedClipsSection
            }
            .padding(AppSpacing.md)
        }
        .background(AppTheme.primaryBackground.ignoresSafeArea())
        .navigationTitle(recording.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if fileExists {
                    ShareLink(item: videoURL) {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                Button {
                    showEditMetadataSheet = true
                } label: {
                    Image(systemName: "pencil")
                }
                .accessibilityIdentifier("videoDetail.editMetadataButton")
            }
        }
        .onAppear {
            if fileExists && player == nil {
                player = AVPlayer(url: videoURL)
            }
        }
        .onDisappear {
            player?.pause()
        }
        .sheet(isPresented: $showEditMetadataSheet) {
            MetadataEditorSheet(recording: recording)
        }
        .sheet(isPresented: $showVideoEditor) {
            NavigationStack {
                VideoEditorView(recording: recording)
            }
        }
        .sheet(isPresented: $showAIAnalyzer) {
            AIVideoAnalysisView(initialRecording: recording)
        }
        .confirmationDialog("Delete Recording?", isPresented: $showDeleteDialog, titleVisibility: .visible) {
            Button("Delete Permanently", role: .destructive) {
                for clip in recording.clips {
                    storage.deleteMediaFile(atRelativePath: clip.relativeFilePath)
                    storage.deleteMediaFile(atRelativePath: clip.thumbnailRelativePath)
                }
                storage.deleteMediaFile(atRelativePath: recording.relativeFilePath)
                storage.deleteMediaFile(atRelativePath: recording.thumbnailRelativePath)
                modelContext.delete(recording)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var playerSection: some View {
        VStack(spacing: 10) {
            VideoPlayer(player: player)
                .frame(height: 260)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .strokeBorder(AppTheme.subtleBorder, lineWidth: 1)
                )

            // Slow-Motion & Frame-Step Controls for Stroke Technique Inspection
            HStack(spacing: 10) {
                Button {
                    stepFrame(bySeconds: -1.0 / max(24.0, recording.frameRate))
                } label: {
                    Label("-1f", systemImage: "backward.frame.fill")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppTheme.cardBackground)
                        .clipShape(Capsule())
                }

                ForEach([Float(0.25), Float(0.5), Float(1.0)], id: \.self) { speed in
                    Button {
                        playbackRate = speed
                        player?.rate = speed
                    } label: {
                        Text("\(String(format: "%g", speed))x")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(playbackRate == speed ? .black : .primary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(playbackRate == speed ? AppTheme.opticLime : AppTheme.cardBackground)
                            .clipShape(Capsule())
                    }
                }

                Button {
                    stepFrame(bySeconds: 1.0 / max(24.0, recording.frameRate))
                } label: {
                    Label("+1f", systemImage: "forward.frame.fill")
                        .font(.caption.weight(.bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(AppTheme.cardBackground)
                        .clipShape(Capsule())
                }
            }
        }
    }

    private func stepFrame(bySeconds delta: Double) {
        guard let player else { return }
        player.pause()
        let current = CMTimeGetSeconds(player.currentTime())
        let target = max(0, min(recording.durationSeconds, current + delta))
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: .zero, toleranceAfter: .zero)
    }

    private var missingFileSection: some View {
        EmptyStateCardView(
            icon: "exclamationmark.triangle.fill",
            title: "Video File Unavailable",
            message: "The underlying video file could not be located at \(recording.relativeFilePath). You can remove this metadata record safely.",
            buttonTitle: "Remove Broken Entry",
            buttonIcon: "trash"
        ) {
            showDeleteDialog = true
        }
    }

    private var primaryActionRow: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                PrimaryCourtButton("Cut Highlights", systemImage: "scissors", isDisabled: !fileExists) {
                    player?.pause()
                    showVideoEditor = true
                }
                .accessibilityIdentifier("videoDetail.openEditorButton")

                PrimaryCourtButton(
                    "AI Pose Scan",
                    systemImage: "viewfinder",
                    tint: AppTheme.hardcourtBlue,
                    isDisabled: !fileExists
                ) {
                    player?.pause()
                    showAIAnalyzer = true
                }
                .accessibilityIdentifier("videoDetail.openAIButton")
            }

            HStack(spacing: 10) {
                SecondaryCourtButton("Save to Photos", systemImage: "photo.badge.arrow.down") {
                    Task {
                        do {
                            try await storage.exportVideoToPhotosLibrary(fileURL: videoURL)
                            feedbackMessage = "Saved full video to iPhone Photos."
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    }
                }

                SecondaryCourtButton("Delete Video", systemImage: "trash", tint: AppTheme.liveRecordRed) {
                    showDeleteDialog = true
                }
            }
        }
    }

    private var metadataCard: some View {
        CourtCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Recording Metadata")
                        .font(.headline.weight(.bold))
                    Spacer()
                    BadgePill(text: recording.sessionType.rawValue, icon: recording.sessionType.iconName)
                }

                Divider()

                metadataRow("Recorded", value: recording.recordedAt.formatted(date: .abbreviated, time: .shortened))
                metadataRow("Duration", value: recording.formattedDuration)
                metadataRow("Format", value: recording.resolutionSummary)
                metadataRow("Camera Lens", value: recording.cameraLensLabel)
                metadataRow("File Size", value: recording.formattedFileSize)

                if !recording.tags.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(recording.tags, id: \.self) { tag in
                                BadgePill(text: "#\(tag)", color: AppTheme.hardcourtBlue)
                            }
                        }
                    }
                }

                if !recording.notes.isEmpty {
                    Text(recording.notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.top, 4)
                }
            }
        }
    }

    private func metadataRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
        }
    }

    private var extractedClipsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderView(title: "Extracted Clips (\(recording.clips.count))", actionTitle: "New Clip") {
                showVideoEditor = true
            }

            if recording.clips.isEmpty {
                CourtCard {
                    Text("No highlight clips trimmed from this match yet. Tap 'Cut Highlights' above to mark start and end timestamps.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                ForEach(recording.clips.sorted(by: { $0.startTimeSeconds < $1.startTimeSeconds })) { clip in
                    let clipURL = storage.resolveURL(forRelativePath: clip.relativeFilePath)
                    CourtCard(padding: 12) {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 6) {
                                    BadgePill(text: clip.category.rawValue, icon: clip.category.iconName)
                                    if clip.isFavorite {
                                        Image(systemName: "star.fill")
                                            .font(.caption2)
                                            .foregroundStyle(AppTheme.opticLime)
                                    }
                                }
                                Text(clip.title)
                                    .font(.subheadline.weight(.bold))
                                Text("\(clip.formattedTrimRange) (\(clip.formattedDuration))")
                                    .font(.caption2.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                player?.seek(
                                    to: CMTime(seconds: clip.startTimeSeconds, preferredTimescale: 600),
                                    toleranceBefore: .zero,
                                    toleranceAfter: .zero
                                )
                                player?.play()
                            } label: {
                                Image(systemName: "play.circle.fill")
                                    .font(.title2)
                                    .foregroundStyle(AppTheme.courtGreen)
                                    .frame(width: 44, height: 44)
                            }
                            if storage.fileExists(forRelativePath: clip.relativeFilePath) {
                                ShareLink(item: clipURL) {
                                    Image(systemName: "square.and.arrow.up")
                                        .frame(width: 40, height: 44)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}

private struct MetadataEditorSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var recording: VideoRecording

    @State private var titleText: String = ""
    @State private var notesText: String = ""
    @State private var tagsText: String = ""
    @State private var sessionType: SessionType = .match

    var body: some View {
        NavigationStack {
            Form {
                Section("Video Name & Category") {
                    TextField("Video Title", text: $titleText)
                    Picker("Session Type", selection: $sessionType) {
                        ForEach(SessionType.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                }

                Section("Tags (Comma-separated)") {
                    TextField("forehand, clay, tournament", text: $tagsText)
                }

                Section("Description & Notes") {
                    TextField("Match observations...", text: $notesText, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle("Edit Video Info")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let clean = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !clean.isEmpty {
                            recording.title = clean
                        }
                        recording.sessionType = sessionType
                        recording.notes = notesText.trimmingCharacters(in: .whitespacesAndNewlines)
                        recording.tags = tagsText.split(separator: ",").map(String.init)
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
            .onAppear {
                titleText = recording.title
                notesText = recording.notes
                tagsText = recording.tags.joined(separator: ", ")
                sessionType = recording.sessionType
            }
        }
    }
}

