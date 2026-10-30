import Foundation
import Observation
import PhotosUI
import SwiftData
import SwiftUI
import UniformTypeIdentifiers

/// Streams a picked movie file directly to a temporary disk URL without loading the video into memory.
struct ImportedMovieTransferable: Transferable, Sendable {
    let tempURL: URL
    let originalFilename: String

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(importedContentType: .movie) { received in
            let originalName = received.file.deletingPathExtension().lastPathComponent
            let ext = received.file.pathExtension.isEmpty ? "mov" : received.file.pathExtension
            let tempDestination = FileManager.default.temporaryDirectory
                .appendingPathComponent("tennisproai-import-\(UUID().uuidString).\(ext)")

            if FileManager.default.fileExists(atPath: tempDestination.path) {
                try? FileManager.default.removeItem(at: tempDestination)
            }
            try FileManager.default.copyItem(at: received.file, to: tempDestination)
            return ImportedMovieTransferable(tempURL: tempDestination, originalFilename: originalName)
        }
    }
}

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

    // Video Import State
    var isImportingVideo: Bool = false
    var importStatusLabel: String = "Importing video..."

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

    // MARK: - Import Videos from Photos Picker & Files App

    func importPhotosPickerItems(_ items: [PhotosPickerItem], in context: ModelContext) async {
        guard !items.isEmpty else { return }
        errorMessage = nil
        statusBannerMessage = nil
        isImportingVideo = true
        defer { isImportingVideo = false }

        var importedCount = 0
        for (index, item) in items.enumerated() {
            importStatusLabel = items.count > 1
                ? "Importing video \(index + 1) of \(items.count) from Photos..."
                : "Importing video from Photos..."

            do {
                guard let transferred = try await item.loadTransferable(type: ImportedMovieTransferable.self) else {
                    throw VideoStorageError.invalidVideoAsset
                }
                defer { try? FileManager.default.removeItem(at: transferred.tempURL) }

                let suggestedTitle = Self.cleanedImportTitle(from: transferred.originalFilename, sourceLabel: "Imported Video")
                try await finalizeImportedVideo(
                    fromSourceURL: transferred.tempURL,
                    title: suggestedTitle,
                    sourceTag: "imported",
                    in: context
                )
                importedCount += 1
            } catch let err as LocalizedError {
                errorMessage = err.errorDescription
                errorRecovery = err.recoverySuggestion
            } catch {
                errorMessage = "Could not import video: \(error.localizedDescription)"
            }
        }

        if importedCount > 0 {
            statusBannerMessage = importedCount == 1
                ? "Imported 1 video into your Video Library."
                : "Imported \(importedCount) videos into your Video Library."
            HapticsManager.notification(.success)
        }
    }

    func importFilesFromURLs(_ urls: [URL], in context: ModelContext) async {
        guard !urls.isEmpty else { return }
        errorMessage = nil
        statusBannerMessage = nil
        isImportingVideo = true
        defer { isImportingVideo = false }

        var importedCount = 0
        for (index, externalURL) in urls.enumerated() {
            importStatusLabel = urls.count > 1
                ? "Importing file \(index + 1) of \(urls.count)..."
                : "Importing video file..."

            let didStartAccessing = externalURL.startAccessingSecurityScopedResource()
            defer {
                if didStartAccessing {
                    externalURL.stopAccessingSecurityScopedResource()
                }
            }

            do {
                let rawName = externalURL.deletingPathExtension().lastPathComponent
                let suggestedTitle = Self.cleanedImportTitle(from: rawName, sourceLabel: "Imported Match")
                try await finalizeImportedVideo(
                    fromSourceURL: externalURL,
                    title: suggestedTitle,
                    sourceTag: "files-import",
                    in: context
                )
                importedCount += 1
            } catch let err as LocalizedError {
                errorMessage = err.errorDescription
                errorRecovery = err.recoverySuggestion
            } catch {
                errorMessage = "Could not import file: \(error.localizedDescription)"
            }
        }

        if importedCount > 0 {
            statusBannerMessage = importedCount == 1
                ? "Imported 1 video file into your Video Library."
                : "Imported \(importedCount) video files into your Video Library."
            HapticsManager.notification(.success)
        }
    }

    private func finalizeImportedVideo(
        fromSourceURL sourceURL: URL,
        title: String,
        sourceTag: String,
        in context: ModelContext
    ) async throws {
        let newID = UUID()
        let rawExt = sourceURL.pathExtension.lowercased()
        let fileExtension = rawExt.isEmpty ? "mov" : rawExt
        let destination = try storageService.makeNewRecordingDestination(id: newID, fileExtension: fileExtension)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: destination.url)
        } catch {
            throw VideoStorageError.invalidVideoAsset
        }

        let metadata: ExtractedVideoMetadata
        do {
            metadata = try await storageService.inspectVideoMetadata(at: destination.url)
            guard metadata.durationSeconds > 0 else {
                storageService.deleteMediaFile(atRelativePath: destination.relativePath)
                throw VideoStorageError.invalidVideoAsset
            }
        } catch {
            storageService.deleteMediaFile(atRelativePath: destination.relativePath)
            throw error
        }

        let thumbSeconds = min(1.0, max(0.1, metadata.durationSeconds * 0.2))
        let thumbRelative = await storageService.generateAndCacheThumbnail(
            forRelativePath: destination.relativePath,
            id: newID,
            atSeconds: thumbSeconds
        )

        let record = VideoRecording(
            id: newID,
            title: title,
            relativeFilePath: destination.relativePath,
            thumbnailRelativePath: thumbRelative,
            recordedAt: Date(),
            durationSeconds: metadata.durationSeconds,
            sessionType: .match,
            resolutionWidth: metadata.width,
            resolutionHeight: metadata.height,
            frameRate: metadata.frameRate,
            fileSizeBytes: metadata.fileSizeBytes,
            cameraLensLabel: "Imported",
            notes: "Imported into Tennis Pro AI",
            tags: [sourceTag]
        )

        context.insert(record)
        try context.save()
    }

    private static func cleanedImportTitle(from rawFilename: String, sourceLabel: String) -> String {
        let trimmed = rawFilename.trimmingCharacters(in: .whitespacesAndNewlines)
        let isGenericSystemName = trimmed.isEmpty
            || trimmed.lowercased().hasPrefix("trim.")
            || trimmed.lowercased().hasPrefix("img_")
            || trimmed.lowercased().hasPrefix("tennisproai-import")

        if isGenericSystemName {
            let df = DateFormatter()
            df.dateFormat = "MMM d • h:mm a"
            return "\(sourceLabel) — \(df.string(from: Date()))"
        }
        return trimmed.replacingOccurrences(of: "_", with: " ")
    }
}
