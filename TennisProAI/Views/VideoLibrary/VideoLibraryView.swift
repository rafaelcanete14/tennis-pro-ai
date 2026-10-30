import SwiftUI
import SwiftData
import PhotosUI
import UniformTypeIdentifiers

struct VideoLibraryView: View {
    @Environment(AppNavigationRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VideoRecording.recordedAt, order: .reverse) private var recordings: [VideoRecording]
    @Query(sort: \VideoClip.createdAt, order: .reverse) private var allClips: [VideoClip]

    @State private var viewModel = VideoLibraryViewModel()
    @State private var showHighlightCollections = false
    @State private var selectedPhotoPickerItems: [PhotosPickerItem] = []
    @State private var showPhotosPicker = false
    @State private var showFileImporter = false

    private var displayedRecordings: [VideoRecording] {
        viewModel.filteredRecordings(recordings)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    // Prominent Courtside Import Action Row
                    importActionsBar

                    if viewModel.isImportingVideo {
                        CourtCard(padding: 14) {
                            HStack(spacing: 12) {
                                ProgressView()
                                    .tint(AppTheme.opticLime)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(viewModel.importStatusLabel)
                                        .font(.subheadline.weight(.bold))
                                    Text("Copying locally & generating thumbnail...")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                        }
                    }

                    // Highlight Collections Banner
                    Button {
                        showHighlightCollections = true
                    } label: {
                        CourtCard(padding: 14) {
                            HStack(spacing: 12) {
                                Image(systemName: "sparkles.tv.fill")
                                    .font(.title2)
                                    .foregroundStyle(AppTheme.opticLime)
                                    .frame(width: 44, height: 44)
                                    .background(AppTheme.courtGreen.opacity(0.2))
                                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Stroke Highlight Collections")
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(.primary)
                                    Text("\(allClips.count) clips across Forehand, Serve, Rally & 7 more categories")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("library.highlightCollectionsButton")

                    filterControlsBar

                    if let status = viewModel.statusBannerMessage {
                        HStack {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(AppTheme.courtGreen)
                            Text(status)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Button("Dismiss") { viewModel.statusBannerMessage = nil }
                                .font(.caption.weight(.bold))
                        }
                        .padding(12)
                        .background(AppTheme.elevatedCardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }

                    if let err = viewModel.errorMessage {
                        ErrorRecoveryBanner(message: err, recoverySuggestion: viewModel.errorRecovery) {
                            viewModel.errorMessage = nil
                        }
                    }

                    if recordings.isEmpty {
                        EmptyStateCardView(
                            icon: "film.stack",
                            title: "Your Video Library Is Empty",
                            message: "Import an existing match video from Photos or Files above, or record a new session from the Record tab to trim highlights and run Vision analysis.",
                            buttonTitle: "Start Court Recording",
                            buttonIcon: "video.badge.plus"
                        ) {
                            router.navigateToRecord()
                        }
                    } else if displayedRecordings.isEmpty {
                        EmptyStateCardView(
                            icon: "magnifyingglass",
                            title: "No Matching Videos",
                            message: "Try clearing your search query or adjusting the date/session filters.",
                            buttonTitle: "Reset Filters",
                            buttonIcon: "arrow.counterclockwise"
                        ) {
                            viewModel.searchQuery = ""
                            viewModel.selectedSessionFilter = nil
                            viewModel.selectedDateRange = .allTime
                            viewModel.favoritesOnly = false
                        }
                    } else {
                        LazyVStack(spacing: 14) {
                            ForEach(displayedRecordings) { video in
                                NavigationLink {
                                    VideoDetailPlayerView(recording: video)
                                } label: {
                                    videoRowCard(video)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("library.videoRow.\(video.id.uuidString)")
                            }
                        }
                    }
                }
                .padding(AppSpacing.md)
            }
            .background(AppTheme.primaryBackground.ignoresSafeArea())
            .navigationTitle("Video Library")
            .searchable(text: $viewModel.searchQuery, prompt: "Search by name, tag, or note")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button {
                            showPhotosPicker = true
                        } label: {
                            Label("Import from Photos", systemImage: "photo.on.rectangle.angled")
                        }

                        Button {
                            showFileImporter = true
                        } label: {
                            Label("Import from Files / USB Drive", systemImage: "folder.badge.plus")
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "square.and.arrow.down")
                            Text("Import")
                                .fontWeight(.bold)
                        }
                        .foregroundStyle(AppTheme.courtGreen)
                    }
                    .disabled(viewModel.isImportingVideo)
                    .accessibilityIdentifier("library.toolbarImportMenu")
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("Sort By", selection: $viewModel.sortOption) {
                            ForEach(VideoSortOption.allCases) { opt in
                                Text(opt.rawValue).tag(opt)
                            }
                        }
                    } label: {
                        Label("Sort", systemImage: "arrow.up.arrow.down.circle")
                    }
                }
            }
            .photosPicker(
                isPresented: $showPhotosPicker,
                selection: $selectedPhotoPickerItems,
                maxSelectionCount: 5,
                matching: .videos
            )
            .onChange(of: selectedPhotoPickerItems) { _, newItems in
                guard !newItems.isEmpty else { return }
                let itemsToImport = newItems
                selectedPhotoPickerItems = []
                Task {
                    await viewModel.importPhotosPickerItems(itemsToImport, in: modelContext)
                }
            }
            .fileImporter(
                isPresented: $showFileImporter,
                allowedContentTypes: [.movie, .mpeg4Movie, .quickTimeMovie],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    Task {
                        await viewModel.importFilesFromURLs(urls, in: modelContext)
                    }
                case .failure(let error):
                    viewModel.errorMessage = "File selection failed: \(error.localizedDescription)"
                }
            }
            .navigationDestination(isPresented: $showHighlightCollections) {
                HighlightCollectionsView()
            }
            .confirmationDialog(
                "Delete Recording?",
                isPresented: $viewModel.showDeleteConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete Video & Clips", role: .destructive) {
                    viewModel.confirmDelete(in: modelContext)
                }
                Button("Cancel", role: .cancel) {
                    viewModel.videoPendingDeletion = nil
                }
            } message: {
                if let target = viewModel.videoPendingDeletion {
                    Text("Permanently delete \"\(target.title)\" and its \(target.clips.count) extracted clip(s) from this iPhone?")
                }
            }
        }
    }

    // MARK: - Prominent Courtside Import Buttons

    private var importActionsBar: some View {
        HStack(spacing: 10) {
            PrimaryCourtButton(
                "Import Photos",
                systemImage: "photo.on.rectangle.angled",
                tint: AppTheme.courtGreen,
                isDisabled: viewModel.isImportingVideo
            ) {
                showPhotosPicker = true
            }
            .accessibilityIdentifier("library.importPhotosButton")

            SecondaryCourtButton(
                "Import Files",
                systemImage: "folder.badge.plus",
                tint: AppTheme.hardcourtBlue
            ) {
                showFileImporter = true
            }
            .disabled(viewModel.isImportingVideo)
            .accessibilityIdentifier("library.importFilesButton")
        }
    }

    private var filterControlsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                Button {
                    viewModel.favoritesOnly.toggle()
                } label: {
                    Label("Favorites", systemImage: viewModel.favoritesOnly ? "star.fill" : "star")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(viewModel.favoritesOnly ? .black : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(viewModel.favoritesOnly ? AppTheme.opticLime : AppTheme.cardBackground)
                        .clipShape(Capsule())
                }

                Menu {
                    Button("All Session Types") { viewModel.selectedSessionFilter = nil }
                    ForEach(SessionType.allCases) { type in
                        Button(type.rawValue) { viewModel.selectedSessionFilter = type }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(viewModel.selectedSessionFilter?.rawValue ?? "All Sessions")
                        Image(systemName: "chevron.down")
                    }
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppTheme.cardBackground)
                    .clipShape(Capsule())
                }

                Menu {
                    ForEach(DateFilterRange.allCases) { range in
                        Button(range.rawValue) { viewModel.selectedDateRange = range }
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                        Text(viewModel.selectedDateRange.rawValue)
                    }
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(AppTheme.cardBackground)
                    .clipShape(Capsule())
                }
            }
        }
    }

    private func videoRowCard(_ video: VideoRecording) -> some View {
        let exists = viewModel.fileExists(for: video)
        let thumbImage = viewModel.storageService.loadThumbnailImage(forRelativePath: video.thumbnailRelativePath)

        return CourtCard(padding: 12) {
            HStack(spacing: 14) {
                ZStack(alignment: .bottomTrailing) {
                    if let thumbImage {
                        Image(uiImage: thumbImage)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 112, height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(AppTheme.elevatedCardBackground)
                            .frame(width: 112, height: 76)
                            .overlay(
                                Image(systemName: exists ? "play.rectangle.fill" : "exclamationmark.triangle.fill")
                                    .font(.title2)
                                    .foregroundStyle(exists ? AppTheme.courtGreen : AppTheme.liveRecordRed)
                            )
                    }

                    Text(video.formattedDuration)
                        .font(.caption2.weight(.bold).monospacedDigit())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(Color.black.opacity(0.75))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .padding(5)
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        BadgePill(text: video.sessionType.rawValue, icon: video.sessionType.iconName)
                        if !exists {
                            BadgePill(text: "FILE MISSING", color: AppTheme.liveRecordRed)
                        }
                        Spacer()
                        Button {
                            viewModel.toggleFavorite(video, in: modelContext)
                        } label: {
                            Image(systemName: video.isFavorite ? "star.fill" : "star")
                                .foregroundStyle(video.isFavorite ? AppTheme.opticLime : .secondary)
                                .frame(width: 34, height: 34)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(video.isFavorite ? "Remove favorite" : "Mark favorite")
                    }

                    Text(video.title)
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        Text(video.recordedAt.formatted(date: .abbreviated, time: .shortened))
                        Text("•")
                        Text(video.resolutionSummary)
                    }
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                    HStack(spacing: 8) {
                        if !video.clips.isEmpty {
                            Label("\(video.clips.count) clips", systemImage: "scissors")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.courtGreen)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            viewModel.requestDelete(video)
                        } label: {
                            Image(systemName: "trash")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(AppTheme.liveRecordRed)
                                .frame(width: 32, height: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("library.deleteButton.\(video.id.uuidString)")
                        .accessibilityLabel("Delete \(video.title)")
                    }
                }
            }
        }
    }
}
