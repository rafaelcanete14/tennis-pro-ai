import Foundation
import AVFoundation
import Photos
import UIKit

enum VideoStorageError: LocalizedError {
    case directoryCreationFailed
    case fileMissing(String)
    case insufficientDiskSpace(availableMB: Int64)
    case photosPermissionDenied
    case photosExportFailed(String)
    case invalidVideoAsset

    var errorDescription: String? {
        switch self {
        case .directoryCreationFailed:
            return "Unable to prepare local media storage directory."
        case .fileMissing(let name):
            return "Video file \"\(name)\" could not be found on disk."
        case .insufficientDiskSpace(let availableMB):
            return "Low iPhone storage (\(availableMB) MB free)."
        case .photosPermissionDenied:
            return "Photos library access was denied."
        case .photosExportFailed(let reason):
            return "Failed to save video to Photos: \(reason)"
        case .invalidVideoAsset:
            return "The video file could not be read or appears corrupted."
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .insufficientDiskSpace:
            return "Free up at least 500 MB of storage on your iPhone before recording or exporting high-resolution tennis video."
        case .photosPermissionDenied:
            return "Open iOS Settings > Privacy & Security > Photos and grant Tennis Pro AI 'Add Photos Only' access."
        case .fileMissing:
            return "The file may have been deleted outside the app. You can remove this broken entry from your library."
        default:
            return "Please try again or restart the application."
        }
    }
}

struct ExtractedVideoMetadata: Sendable {
    var durationSeconds: Double
    var width: Int
    var height: Int
    var frameRate: Double
    var fileSizeBytes: Int64
}

protocol VideoStorageServiceProtocol: AnyObject {
    var baseDirectoryURL: URL { get }
    func resolveURL(forRelativePath relativePath: String) -> URL
    func fileExists(forRelativePath relativePath: String) -> Bool
    func makeNewRecordingDestination(id: UUID, fileExtension: String) throws -> (url: URL, relativePath: String)
    func makeNewClipDestination(id: UUID, fileExtension: String) throws -> (url: URL, relativePath: String)
    func checkSufficientDiskSpace(minimumBytes: Int64) throws -> Int64
    func inspectVideoMetadata(at url: URL) async throws -> ExtractedVideoMetadata
    func generateAndCacheThumbnail(forRelativePath videoRelativePath: String, id: UUID, atSeconds: Double) async -> String?
    func loadThumbnailImage(forRelativePath thumbnailRelativePath: String?) -> UIImage?
    func deleteMediaFile(atRelativePath relativePath: String?)
    func deleteAllManagedMediaFiles() throws
    func totalManagedStorageBytes() -> Int64
    func exportVideoToPhotosLibrary(fileURL: URL) async throws
}

final class VideoStorageService: VideoStorageServiceProtocol {
    static let shared = VideoStorageService()

    private let fileManager = FileManager.default
    private let thumbnailMemoryCache = NSCache<NSString, UIImage>()
    let baseDirectoryURL: URL

    init(customBaseDirectory: URL? = nil) {
        if let customBaseDirectory {
            self.baseDirectoryURL = customBaseDirectory
        } else {
            let appSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
            self.baseDirectoryURL = appSupport.appendingPathComponent("TennisProAI", isDirectory: true)
        }
        thumbnailMemoryCache.countLimit = 80
        ensureSubdirectoriesExist()
    }

    private func ensureSubdirectoriesExist() {
        for folder in ["Recordings", "Clips", "Thumbnails"] {
            let dir = baseDirectoryURL.appendingPathComponent(folder, isDirectory: true)
            if !fileManager.fileExists(atPath: dir.path) {
                try? fileManager.createDirectory(at: dir, withIntermediateDirectories: true)
            }
        }
    }

    func resolveURL(forRelativePath relativePath: String) -> URL {
        baseDirectoryURL.appendingPathComponent(relativePath)
    }

    func fileExists(forRelativePath relativePath: String) -> Bool {
        guard !relativePath.isEmpty else { return false }
        let url = resolveURL(forRelativePath: relativePath)
        return fileManager.fileExists(atPath: url.path)
    }

    func makeNewRecordingDestination(id: UUID = UUID(), fileExtension: String = "mov") throws -> (url: URL, relativePath: String) {
        ensureSubdirectoriesExist()
        _ = try checkSufficientDiskSpace(minimumBytes: 300 * 1024 * 1024) // 300 MB safety floor
        let relative = "Recordings/\(id.uuidString).\(fileExtension)"
        let url = resolveURL(forRelativePath: relative)
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
        return (url, relative)
    }

    func makeNewClipDestination(id: UUID = UUID(), fileExtension: String = "mp4") throws -> (url: URL, relativePath: String) {
        ensureSubdirectoriesExist()
        _ = try checkSufficientDiskSpace(minimumBytes: 100 * 1024 * 1024) // 100 MB safety floor
        let relative = "Clips/\(id.uuidString).\(fileExtension)"
        let url = resolveURL(forRelativePath: relative)
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
        return (url, relative)
    }

    @discardableResult
    func checkSufficientDiskSpace(minimumBytes: Int64 = 500 * 1024 * 1024) throws -> Int64 {
        let values = try? baseDirectoryURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
        if let available = values?.volumeAvailableCapacityForImportantUsage {
            if available < minimumBytes {
                throw VideoStorageError.insufficientDiskSpace(availableMB: available / (1024 * 1024))
            }
            return available
        }
        return Int64.max
    }

    func inspectVideoMetadata(at url: URL) async throws -> ExtractedVideoMetadata {
        guard fileManager.fileExists(atPath: url.path) else {
            throw VideoStorageError.fileMissing(url.lastPathComponent)
        }

        let asset = AVURLAsset(url: url)
        let durationTime = try await asset.load(.duration)
        let durationSeconds = max(0, CMTimeGetSeconds(durationTime))

        var width = 1920
        var height = 1080
        var fps: Double = 30.0

        if let videoTrack = try await asset.loadTracks(withMediaType: .video).first {
            let naturalSize = try await videoTrack.load(.naturalSize)
            let preferredTransform = try await videoTrack.load(.preferredTransform)
            let transformedSize = naturalSize.applying(preferredTransform)
            width = max(1, Int(abs(transformedSize.width).rounded()))
            height = max(1, Int(abs(transformedSize.height).rounded()))
            let nominalFPS = try await videoTrack.load(.nominalFrameRate)
            if nominalFPS > 0 {
                fps = Double(nominalFPS)
            }
        }

        let attrs = try? fileManager.attributesOfItem(atPath: url.path)
        let fileSize = (attrs?[.size] as? NSNumber)?.int64Value ?? 0

        return ExtractedVideoMetadata(
            durationSeconds: durationSeconds.isFinite ? durationSeconds : 0,
            width: width,
            height: height,
            frameRate: fps,
            fileSizeBytes: fileSize
        )
    }

    func generateAndCacheThumbnail(
        forRelativePath videoRelativePath: String,
        id: UUID,
        atSeconds: Double = 0.5
    ) async -> String? {
        let videoURL = resolveURL(forRelativePath: videoRelativePath)
        guard fileManager.fileExists(atPath: videoURL.path) else { return nil }

        ensureSubdirectoriesExist()
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 720, height: 720)

        let requestTime = CMTime(seconds: max(0, atSeconds), preferredTimescale: 600)
        do {
            let (cgImage, _) = try await generator.image(at: requestTime)
            let uiImage = UIImage(cgImage: cgImage)
            let thumbRelative = "Thumbnails/\(id.uuidString).jpg"
            let thumbURL = resolveURL(forRelativePath: thumbRelative)
            if let jpegData = uiImage.jpegData(compressionQuality: 0.78) {
                try jpegData.write(to: thumbURL, options: .atomic)
                thumbnailMemoryCache.setObject(uiImage, forKey: thumbRelative as NSString)
                return thumbRelative
            }
        } catch {
            return nil
        }
        return nil
    }

    func loadThumbnailImage(forRelativePath thumbnailRelativePath: String?) -> UIImage? {
        guard let thumbnailRelativePath, !thumbnailRelativePath.isEmpty else { return nil }
        if let cached = thumbnailMemoryCache.object(forKey: thumbnailRelativePath as NSString) {
            return cached
        }
        let url = resolveURL(forRelativePath: thumbnailRelativePath)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data) else {
            return nil
        }
        thumbnailMemoryCache.setObject(image, forKey: thumbnailRelativePath as NSString)
        return image
    }

    func deleteMediaFile(atRelativePath relativePath: String?) {
        guard let relativePath, !relativePath.isEmpty else { return }
        thumbnailMemoryCache.removeObject(forKey: relativePath as NSString)
        let url = resolveURL(forRelativePath: relativePath)
        if fileManager.fileExists(atPath: url.path) {
            try? fileManager.removeItem(at: url)
        }
    }

    func deleteAllManagedMediaFiles() throws {
        thumbnailMemoryCache.removeAllObjects()
        if fileManager.fileExists(atPath: baseDirectoryURL.path) {
            try fileManager.removeItem(at: baseDirectoryURL)
        }
        ensureSubdirectoriesExist()
    }

    func totalManagedStorageBytes() -> Int64 {
        guard let enumerator = fileManager.enumerator(
            at: baseDirectoryURL,
            includingPropertiesForKeys: [.fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let values = try? fileURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
               values.isRegularFile == true,
               let size = values.fileSize {
                total += Int64(size)
            }
        }
        return total
    }

    func exportVideoToPhotosLibrary(fileURL: URL) async throws {
        guard fileManager.fileExists(atPath: fileURL.path) else {
            throw VideoStorageError.fileMissing(fileURL.lastPathComponent)
        }

        let status = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw VideoStorageError.photosPermissionDenied
        }

        try await PHPhotoLibrary.shared().performChanges {
            PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: fileURL)
        }
    }
}

