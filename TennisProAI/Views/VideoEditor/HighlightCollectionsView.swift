import SwiftUI
import SwiftData
import AVKit

struct HighlightCollectionsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VideoClip.createdAt, order: .reverse) private var clips: [VideoClip]

    @State private var selectedCategory: HighlightCategory? = nil
    @State private var favoritesOnly: Bool = false
    @State private var activeClipToPlay: VideoClip? = nil

    private let storage = VideoStorageService.shared

    private var filteredClips: [VideoClip] {
        clips.filter { clip in
            if favoritesOnly && !clip.isFavorite { return false }
            if let cat = selectedCategory, clip.category != cat { return false }
            return true
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                // Category Collection Pills
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        Button {
                            selectedCategory = nil
                        } label: {
                            Text("All (\(clips.count))")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(selectedCategory == nil ? .black : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedCategory == nil ? AppTheme.opticLime : AppTheme.cardBackground)
                                .clipShape(Capsule())
                        }

                        ForEach(HighlightCategory.allCases) { category in
                            let count = clips.filter { $0.category == category }.count
                            let active = selectedCategory == category
                            Button {
                                selectedCategory = category
                            } label: {
                                HStack(spacing: 5) {
                                    Image(systemName: category.iconName)
                                    Text("\(category.rawValue) (\(count))")
                                }
                                .font(.caption.weight(.bold))
                                .foregroundStyle(active ? .black : .primary)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(active ? AppTheme.opticLime : AppTheme.cardBackground)
                                .clipShape(Capsule())
                            }
                        }
                    }
                }

                Toggle("Favorite Clips Only", isOn: $favoritesOnly)
                    .font(.subheadline.weight(.semibold))
                    .tint(AppTheme.courtGreen)

                if filteredClips.isEmpty {
                    EmptyStateCardView(
                        icon: "scissors.badge.ellipsis",
                        title: "No Highlight Clips in This Collection",
                        message: "Open any recorded match in the Video Editor to trim and categorize shots into Forehand, Backhand, Serve, Volley, Smash, Rally, and more."
                    )
                } else {
                    ForEach(filteredClips) { clip in
                        let clipURL = storage.resolveURL(forRelativePath: clip.relativeFilePath)
                        CourtCard(padding: 14) {
                            HStack(spacing: 12) {
                                Button {
                                    activeClipToPlay = clip
                                } label: {
                                    ZStack {
                                        if let img = storage.loadThumbnailImage(forRelativePath: clip.thumbnailRelativePath) {
                                            Image(uiImage: img)
                                                .resizable()
                                                .scaledToFill()
                                                .frame(width: 96, height: 66)
                                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                        } else {
                                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                                .fill(AppTheme.elevatedCardBackground)
                                                .frame(width: 96, height: 66)
                                        }
                                        Image(systemName: "play.circle.fill")
                                            .font(.title2)
                                            .foregroundStyle(.white)
                                    }
                                }
                                .buttonStyle(.plain)

                                VStack(alignment: .leading, spacing: 4) {
                                    HStack {
                                        BadgePill(text: clip.category.rawValue, icon: clip.category.iconName)
                                        Spacer()
                                        Button {
                                            clip.isFavorite.toggle()
                                            try? modelContext.save()
                                        } label: {
                                            Image(systemName: clip.isFavorite ? "star.fill" : "star")
                                                .foregroundStyle(clip.isFavorite ? AppTheme.opticLime : .secondary)
                                        }
                                        .buttonStyle(.plain)
                                    }

                                    Text(clip.title)
                                        .font(.headline.weight(.bold))
                                        .lineLimit(1)

                                    Text("\(clip.formattedDuration) • Trim \(clip.formattedTrimRange)")
                                        .font(.caption2.monospacedDigit())
                                        .foregroundStyle(.secondary)

                                    if !clip.notes.isEmpty {
                                        Text(clip.notes)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }
                                }

                                if storage.fileExists(forRelativePath: clip.relativeFilePath) {
                                    ShareLink(item: clipURL) {
                                        Image(systemName: "square.and.arrow.up")
                                            .frame(width: 36, height: 36)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .padding(AppSpacing.md)
        }
        .background(AppTheme.primaryBackground.ignoresSafeArea())
        .navigationTitle("Highlight Collections")
        .sheet(item: $activeClipToPlay) { clip in
            NavigationStack {
                let url = storage.resolveURL(forRelativePath: clip.relativeFilePath)
                VStack(spacing: 16) {
                    if storage.fileExists(forRelativePath: clip.relativeFilePath) {
                        VideoPlayer(player: AVPlayer(url: url))
                            .frame(maxHeight: 360)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    } else {
                        Text("Clip file missing on disk.")
                            .foregroundStyle(AppTheme.liveRecordRed)
                    }
                    Text(clip.notes)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding()
                .background(AppTheme.primaryBackground.ignoresSafeArea())
                .navigationTitle(clip.title)
                .navigationBarTitleDisplayMode(.inline)
            }
            .presentationDetents([.medium, .large])
        }
    }
}

