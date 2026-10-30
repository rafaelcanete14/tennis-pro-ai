import SwiftUI
import SwiftData
import AVKit

struct VideoEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: VideoEditorViewModel

    init(recording: VideoRecording) {
        _viewModel = State(initialValue: VideoEditorViewModel(recording: recording))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                // Playback Preview
                if let player = viewModel.player {
                    VideoPlayer(player: player)
                        .frame(height: 230)
                        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(AppTheme.cardBackground)
                        .frame(height: 230)
                        .overlay(ProgressView("Loading Video Timeline..."))
                }

                // Timeline Filmstrip & Trim Controls
                timelineTrimmerCard

                // Highlight Shot Category Selection (Manual Assignment)
                categoryPickerCard

                // Clip Metadata & Export Trigger
                clipMetadataFormCard

                if viewModel.isExporting {
                    CourtCard {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Exporting Highlight Segment...")
                                    .font(.subheadline.weight(.bold))
                                Spacer()
                                Text("\(Int((viewModel.exportProgress * 100).rounded()))%")
                                    .font(.subheadline.weight(.bold).monospacedDigit())
                                    .foregroundStyle(AppTheme.courtGreen)
                            }
                            ProgressView(value: viewModel.exportProgress)
                                .tint(AppTheme.courtGreen)
                            SecondaryCourtButton("Cancel Export", systemImage: "xmark", tint: AppTheme.liveRecordRed) {
                                viewModel.cancelExport()
                            }
                        }
                    }
                }

                if let status = viewModel.statusMessage {
                    HStack {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundStyle(AppTheme.opticLime)
                        Text(status)
                            .font(.caption.weight(.semibold))
                        Spacer()
                    }
                    .padding(12)
                    .background(AppTheme.elevatedCardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }

                if let err = viewModel.errorMessage {
                    ErrorRecoveryBanner(message: err, recoverySuggestion: "Adjust start/end handles so the clip is at least 0.5s long.") {
                        viewModel.errorMessage = nil
                    }
                }

                existingClipsList
            }
            .padding(AppSpacing.md)
        }
        .background(AppTheme.primaryBackground.ignoresSafeArea())
        .navigationTitle("Highlight Cutter")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") {
                    viewModel.tearDownPlayer()
                    dismiss()
                }
            }
        }
        .task {
            await viewModel.prepareEditor()
        }
        .onDisappear {
            viewModel.tearDownPlayer()
        }
    }

    private var timelineTrimmerCard: some View {
        CourtCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Label("Timeline Selection", systemImage: "timeline.selection")
                        .font(.headline.weight(.bold))
                    Spacer()
                    BadgePill(
                        text: "Clip: \(TimeFormatters.preciseString(from: viewModel.selectedSegmentDuration))",
                        color: AppTheme.opticLime
                    )
                }

                // Filmstrip Thumbnail Strip
                if !viewModel.timelineThumbnails.isEmpty {
                    HStack(spacing: 2) {
                        ForEach(Array(viewModel.timelineThumbnails.enumerated()), id: \.offset) { _, img in
                            Image(uiImage: img)
                                .resizable()
                                .scaledToFill()
                                .frame(maxWidth: .infinity)
                                .frame(height: 46)
                                .clipped()
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(AppTheme.courtGreen, lineWidth: 2)
                    )
                }

                // Start Time Slider + Fine Nudge
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Start: \(TimeFormatters.preciseString(from: viewModel.startTimeSeconds))")
                            .font(.caption.weight(.bold).monospacedDigit())
                        Spacer()
                        Button("-0.5s") { viewModel.nudgeStart(by: -0.5) }
                            .font(.caption.weight(.bold))
                            .buttonStyle(.bordered)
                        Button("+0.5s") { viewModel.nudgeStart(by: 0.5) }
                            .font(.caption.weight(.bold))
                            .buttonStyle(.bordered)
                    }
                    Slider(
                        value: Binding(
                            get: { viewModel.startTimeSeconds },
                            set: { newVal in
                                viewModel.startTimeSeconds = min(newVal, max(0, viewModel.endTimeSeconds - 0.5))
                                viewModel.seek(to: viewModel.startTimeSeconds)
                            }
                        ),
                        in: 0...max(1.0, viewModel.sourceDuration)
                    )
                    .tint(AppTheme.courtGreen)
                    .accessibilityIdentifier("editor.startTimeSlider")
                }

                // End Time Slider + Fine Nudge
                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("End: \(TimeFormatters.preciseString(from: viewModel.endTimeSeconds))")
                            .font(.caption.weight(.bold).monospacedDigit())
                        Spacer()
                        Button("-0.5s") { viewModel.nudgeEnd(by: -0.5) }
                            .font(.caption.weight(.bold))
                            .buttonStyle(.bordered)
                        Button("+0.5s") { viewModel.nudgeEnd(by: 0.5) }
                            .font(.caption.weight(.bold))
                            .buttonStyle(.bordered)
                    }
                    Slider(
                        value: Binding(
                            get: { viewModel.endTimeSeconds },
                            set: { newVal in
                                viewModel.endTimeSeconds = max(newVal, min(viewModel.sourceDuration, viewModel.startTimeSeconds + 0.5))
                                viewModel.seek(to: viewModel.endTimeSeconds)
                            }
                        ),
                        in: 0...max(1.0, viewModel.sourceDuration)
                    )
                    .tint(AppTheme.opticLime)
                    .accessibilityIdentifier("editor.endTimeSlider")
                }

                SecondaryCourtButton(
                    viewModel.isPlayingSegment ? "Pause Segment Preview" : "Loop Selected Segment",
                    systemImage: viewModel.isPlayingSegment ? "pause.fill" : "play.fill"
                ) {
                    viewModel.togglePreviewSegmentPlayback()
                }
            }
        }
    }

    private var categoryPickerCard: some View {
        CourtCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Highlight Collection Category")
                        .font(.headline.weight(.bold))
                    Spacer()
                    BadgePill(text: "MANUAL TAG", color: AppTheme.hardcourtBlue)
                }

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 108), spacing: 8)], spacing: 8) {
                    ForEach(HighlightCategory.allCases) { category in
                        let isSelected = viewModel.selectedCategory == category
                        Button {
                            viewModel.onCategoryChanged(category)
                            HapticsManager.impact(.light)
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: category.iconName)
                                    .font(.caption)
                                Text(category.rawValue)
                                    .font(.caption.weight(.bold))
                                    .lineLimit(1)
                            }
                            .foregroundStyle(isSelected ? .black : .primary)
                            .frame(maxWidth: .infinity, minHeight: 40)
                            .padding(.horizontal, 8)
                            .background(isSelected ? AppTheme.opticLime : AppTheme.elevatedCardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
    }

    private var clipMetadataFormCard: some View {
        CourtCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Clip Details")
                    .font(.headline.weight(.bold))

                TextField("Clip Name", text: $viewModel.clipTitle)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("editor.clipTitleField")

                TextField("Coaching note (e.g. early split-step, clean contact in front)", text: $viewModel.clipNotes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...4)

                Toggle("Mark Clip as Favorite", isOn: $viewModel.markClipFavorite)
                    .font(.subheadline.weight(.medium))
                    .tint(AppTheme.courtGreen)

                PrimaryCourtButton(
                    "Trim & Create Highlight Clip",
                    systemImage: "scissors",
                    isDisabled: viewModel.isExporting || !viewModel.sourceFileExists
                ) {
                    Task {
                        await viewModel.exportAndSaveClip(in: modelContext)
                    }
                }
                .accessibilityIdentifier("editor.exportClipButton")
            }
        }
    }

    private var existingClipsList: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Clips Created From This Match (\(viewModel.recording.clips.count))")
                .font(.headline.weight(.bold))

            ForEach(viewModel.recording.clips.sorted(by: { $0.createdAt > $1.createdAt })) { clip in
                let clipURL = viewModel.storageService.resolveURL(forRelativePath: clip.relativeFilePath)
                CourtCard(padding: 12) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            BadgePill(text: clip.category.rawValue, icon: clip.category.iconName)
                            Text(clip.title)
                                .font(.subheadline.weight(.bold))
                            Text("\(clip.formattedTrimRange) • \(clip.formattedDuration)")
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Task { await viewModel.exportClipToPhotos(clip) }
                        } label: {
                            Image(systemName: "photo.badge.arrow.down")
                                .frame(width: 40, height: 40)
                        }
                        if viewModel.storageService.fileExists(forRelativePath: clip.relativeFilePath) {
                            ShareLink(item: clipURL) {
                                Image(systemName: "square.and.arrow.up")
                                    .frame(width: 40, height: 40)
                            }
                        }
                    }
                }
            }
        }
    }
}

