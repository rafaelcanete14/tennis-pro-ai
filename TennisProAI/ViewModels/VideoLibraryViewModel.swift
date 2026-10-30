import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class VideoLibraryViewModel {
    let storageService: VideoStorageServiceProtocol

    var searchQuery: String = ""
    var selectedSessionFilter: SessionType? = nil
    var selectedDateRange: DateFilterRange = .allTime
    var favoritesOnly: Bool = false
    var sortOption: VideoSortOption = .newest

    var videoPendingDeletion: VideoRecording? = nil
    var showDeleteConfirmation: Bool = false
    var statusBannerMessage: String? = nil
    var errorMessage: String? = nil
    var errorRecovery: String? = nil
    var isExportingToPhotos: Bool = false

    init(storageService: VideoStorageServiceProtocol = VideoStorageService.shared) {
        self.storageService = storageService
    }

    func filteredRecordings(_ recordings: [VideoRecording], referenceDate: Date = Date()) -> [VideoRecording] {
        let cutoff = selectedDateRange.startDate(relativeTo: referenceDate)
        let trimmedSearch = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let filtered = recordings.filter { video in
            if favoritesOnly && !video.isFavorite {
                return false
            }
            if let sessionFilter = selectedSessionFilter, video.sessionType != sessionFilter {
                return false
            }
            if let cutoff, video.recordedAt < cutoff {
                return false
            }
            if !trimmedSearch.isEmpty {
                let inTitle = video.title.lowercased().contains(trimmedSearch)
                let inNotes = video.notes.lowercased().contains(trimmedSearch)
                let inTags = video.tags.contains { $0.lowercased().contains(trimmedSearch) }
                if !(inTitle || inNotes || inTags) {
                    return false
                }
            }
            return true
        }

        switch sortOption {
        case .newest:
            return filtered.sorted { $0.recordedAt > $1.recordedAt }
        case .oldest:
            return filtered.sorted { $0.recordedAt < $1.recordedAt }
        case .durationLongest:
            return filtered.sorted { $0.durationSeconds > $1.durationSeconds }
        }
    }

    func fileExists(for recording: VideoRecording) -> Bool {
        storageService.fileExists(forRelativePath: recording.relativeFilePath)
    }

    func toggleFavorite(_ recording: VideoRecording, in context: ModelContext) {
        recording.isFavorite.toggle()
        try? context.save()
        HapticsManager.impact(.light)
    }

    func requestDelete(_ recording: VideoRecording) {
        videoPendingDeletion = recording
        showDeleteConfirmation = true
    }

    func confirmDelete(in context: ModelContext) {
        guard let target = videoPendingDeletion else { return }
        for clip in target.clips {
            storageService.deleteMediaFile(atRelativePath: clip.relativeFilePath)
            storageService.deleteMediaFile(atRelativePath: clip.thumbnailRelativePath)
        }
        storageService.deleteMediaFile(atRelativePath: target.relativeFilePath)
        storageService.deleteMediaFile(atRelativePath: target.thumbnailRelativePath)

        context.delete(target)
        try? context.save()
        videoPendingDeletion = nil
        showDeleteConfirmation = false
        statusBannerMessage = "Recording and associated clips deleted."
        HapticsManager.notification(.success)
    }

    func exportToPhotos(_ recording: VideoRecording) async {
        errorMessage = nil
        let url = storageService.resolveURL(forRelativePath: recording.relativeFilePath)
        isExportingToPhotos = true
        defer { isExportingToPhotos = false }

        do {
            try await storageService.exportVideoToPhotosLibrary(fileURL: url)
            statusBannerMessage = "Saved \"\(recording.title)\" to your iPhone Photos library."
            HapticsManager.notification(.success)
        } catch let err as LocalizedError {
            errorMessage = err.errorDescription
            errorRecovery = err.recoverySuggestion
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

