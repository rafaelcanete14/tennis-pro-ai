import XCTest
import SwiftData
@testable import TennisProAI

final class VideoAndPersistenceTests: XCTestCase {

    func testVideoTrimParametersValidation() {
        let valid = VideoTrimParameters(startTimeSeconds: 4.0, endTimeSeconds: 12.5, sourceDurationSeconds: 60.0)
        XCTAssertNoThrow(try valid.validate())

        let inverted = VideoTrimParameters(startTimeSeconds: 15.0, endTimeSeconds: 10.0, sourceDurationSeconds: 60.0)
        XCTAssertThrowsError(try inverted.validate())

        let tooShort = VideoTrimParameters(startTimeSeconds: 5.0, endTimeSeconds: 5.2, sourceDurationSeconds: 60.0)
        XCTAssertThrowsError(try tooShort.validate())

        let pastDuration = VideoTrimParameters(startTimeSeconds: 10.0, endTimeSeconds: 75.0, sourceDurationSeconds: 60.0)
        XCTAssertThrowsError(try pastDuration.validate())
    }

    @MainActor
    func testSwiftDataPersistenceAndDeleteAllUserData() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("TennisProAITestStorage-\(UUID().uuidString)", isDirectory: true)
        let storage = VideoStorageService(customBaseDirectory: tempDir)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let controller = PersistenceController(inMemory: true)
        let context = controller.container.mainContext

        // Ensure primary profile deduplicates properly
        let p1 = PersistenceController.ensurePrimaryProfile(in: context)
        p1.name = "Serena"
        let p2 = PersistenceController.ensurePrimaryProfile(in: context)
        XCTAssertEqual(p1.id, p2.id)
        XCTAssertEqual(p2.name, "Serena")

        // Create dummy managed recording file & metadata
        let videoID = UUID()
        let dest = try storage.makeNewRecordingDestination(id: videoID, fileExtension: "mp4")
        try Data("mock-video-bytes".utf8).write(to: dest.url)
        XCTAssertTrue(storage.fileExists(forRelativePath: dest.relativePath))

        let recording = VideoRecording(
            id: videoID,
            title: "Serve Practice Set",
            relativeFilePath: dest.relativePath,
            durationSeconds: 42.0,
            sessionType: .serveSession,
            tags: ["serve", "flat"]
        )
        context.insert(recording)

        let clip = VideoClip(
            parentRecordingID: videoID,
            title: "Wide Ace",
            relativeFilePath: "Clips/mock.mp4",
            startTimeSeconds: 3.0,
            endTimeSeconds: 8.5,
            category: .serve,
            recording: recording
        )
        context.insert(clip)

        let drill = TrainingSession(
            name: "Kick Serve Targets",
            drillType: .servePractice,
            plannedDurationMinutes: 30,
            targetRepetitions: 50
        )
        context.insert(drill)
        try context.save()

        let fetchedVideos = try context.fetch(FetchDescriptor<VideoRecording>())
        XCTAssertEqual(fetchedVideos.count, 1)
        XCTAssertEqual(fetchedVideos.first?.tags, ["serve", "flat"])

        // Verify missing file graceful handling
        XCTAssertFalse(storage.fileExists(forRelativePath: "Recordings/nonexistent.mp4"))

        // Verify complete user data wipe deletes both SwiftData entities and managed files
        try PersistenceController.deleteAllUserData(in: context, videoStorage: storage)
        XCTAssertFalse(storage.fileExists(forRelativePath: dest.relativePath))
        XCTAssertEqual(try context.fetch(FetchDescriptor<VideoRecording>()).count, 0)
        XCTAssertEqual(try context.fetch(FetchDescriptor<TrainingSession>()).count, 0)
    }

    func testAIAnalysisHonestCapabilityReportingAndModelInjection() async throws {
        let aiService = AIAnalysisService()

        // Default: Pose available via Apple Vision; Stroke Classifier honestly awaits Core ML model
        if case .availableOnDevice = aiService.poseCapability {
            // Expected
        } else {
            XCTFail("Expected Apple Vision pose capability to be available on-device.")
        }

        if case .awaitingCoreMLModel = aiService.shotClassifierCapability {
            // Expected: never pretend shot classifier exists before loading a model
        } else {
            XCTFail("Expected shot classifier to report awaitingCoreMLModel by default.")
        }

        // Injecting a conforming Core ML wrapper transitions capability cleanly
        struct MockActionModel: StrokeClassifierModelProtocol {
            let modelName = "TennisStrokeActionClassifier"
            let modelVersion = "1.0.0"
            func classifyPoseWindow(_ poses: [PoseBiomechanicsMetrics]) async throws -> ShotClassificationPrediction? {
                ShotClassificationPrediction(
                    category: .forehand,
                    confidence: 0.91,
                    modelName: modelName,
                    modelVersion: modelVersion
                )
            }
        }

        aiService.registerStrokeClassifier(MockActionModel())
        XCTAssertEqual(
            aiService.shotClassifierCapability,
            .availableOnDevice(engineName: "TennisStrokeActionClassifier", version: "1.0.0")
        )
    }
}

