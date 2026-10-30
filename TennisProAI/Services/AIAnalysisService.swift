import Foundation
import AVFoundation
import Vision
import CoreML
import CoreGraphics
import UIKit

// MARK: - Extensible Core ML Shot Classifier Interface

struct ShotClassificationPrediction: Sendable {
    let category: HighlightCategory
    let confidence: Double
    let modelName: String
    let modelVersion: String
}

/// Protocol enabling drop-in integration of a trained Core ML Action / Stroke Classifier (.mlmodelc).
/// Until a validated Core ML stroke classifier model is bundled or imported, no fake shot classifications are emitted.
protocol StrokeClassifierModelProtocol: Sendable {
    var modelName: String { get }
    var modelVersion: String { get }
    func classifyPoseWindow(_ poses: [PoseBiomechanicsMetrics]) async throws -> ShotClassificationPrediction?
}

enum AIAnalysisCapabilityStatus: Equatable, Sendable {
    case availableOnDevice(engineName: String, version: String)
    case awaitingCoreMLModel(expectedInputDescription: String)
}

struct FramePoseInspectionResult: Sendable {
    let timestampSeconds: Double
    let frameImage: UIImage
    let detectedPlayerCount: Int
    let poseMetrics: PoseBiomechanicsMetrics?
    let observationConfidence: Double?
    let summaryText: String
    let modelName: String
    let modelVersion: String
}

struct VideoVisionAnalysisSummary: Sendable {
    let sampledFrameCount: Int
    let framesWithPlayerDetected: Int
    let records: [AIAnalysisRecord]
    let candidateHighlights: [CandidateHighlightEvent]
}

protocol AIAnalysisServiceProtocol: AnyObject {
    var poseCapability: AIAnalysisCapabilityStatus { get }
    var shotClassifierCapability: AIAnalysisCapabilityStatus { get }
    func registerStrokeClassifier(_ classifier: StrokeClassifierModelProtocol)
    func inspectSingleFrame(at seconds: Double, in videoURL: URL, dominantHand: DominantHand) async throws -> FramePoseInspectionResult
    func runOnDeviceVisionScan(
        videoURL: URL,
        videoID: UUID,
        dominantHand: DominantHand,
        sampleIntervalSeconds: Double,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> VideoVisionAnalysisSummary
}

// MARK: - On-Device Apple Vision Implementation (100% Local, Zero Fabricated Results)

final class AIAnalysisService: AIAnalysisServiceProtocol {
    private var customStrokeClassifier: StrokeClassifierModelProtocol?

    private let visionEngineName = "Apple Vision Human Pose & Detection"
    private let visionEngineVersion = "VNDetectHumanBodyPoseRequest v1"

    var poseCapability: AIAnalysisCapabilityStatus {
        .availableOnDevice(engineName: visionEngineName, version: visionEngineVersion)
    }

    var shotClassifierCapability: AIAnalysisCapabilityStatus {
        if let classifier = customStrokeClassifier {
            return .availableOnDevice(engineName: classifier.modelName, version: classifier.modelVersion)
        }
        return .awaitingCoreMLModel(
            expectedInputDescription: "Requires a compiled Core ML Action Classifier (.mlmodelc) trained on labeled tennis strokes (Forehand, Backhand, Serve, Volley, Smash)."
        )
    }

    func registerStrokeClassifier(_ classifier: StrokeClassifierModelProtocol) {
        self.customStrokeClassifier = classifier
    }

    // MARK: - Single Frame Pose & Biomechanics Inspection

    func inspectSingleFrame(
        at seconds: Double,
        in videoURL: URL,
        dominantHand: DominantHand
    ) async throws -> FramePoseInspectionResult {
        let asset = AVURLAsset(url: videoURL)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 1280, height: 1280)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.05, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.05, preferredTimescale: 600)

        let reqTime = CMTime(seconds: max(0, seconds), preferredTimescale: 600)
        let (cgImage, actualTime) = try await generator.image(at: reqTime)
        let uiImage = UIImage(cgImage: cgImage)
        let actualSeconds = CMTimeGetSeconds(actualTime)

        let analysis = Self.performVisionRequests(on: cgImage, dominantHand: dominantHand)

        return FramePoseInspectionResult(
            timestampSeconds: actualSeconds.isFinite ? actualSeconds : seconds,
            frameImage: uiImage,
            detectedPlayerCount: analysis.humanCount,
            poseMetrics: analysis.metrics,
            observationConfidence: analysis.confidence,
            summaryText: analysis.summary,
            modelName: visionEngineName,
            modelVersion: visionEngineVersion
        )
    }

    // MARK: - Full Video On-Device Vision Scan & Candidate Highlight Segmentation

    func runOnDeviceVisionScan(
        videoURL: URL,
        videoID: UUID,
        dominantHand: DominantHand,
        sampleIntervalSeconds: Double = 1.0,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws -> VideoVisionAnalysisSummary {
        let asset = AVURLAsset(url: videoURL)
        let durationCM = try await asset.load(.duration)
        let totalDuration = max(0, CMTimeGetSeconds(durationCM))
        guard totalDuration > 0.2 else {
            return VideoVisionAnalysisSummary(
                sampledFrameCount: 0,
                framesWithPlayerDetected: 0,
                records: [],
                candidateHighlights: []
            )
        }

        let interval = max(0.5, sampleIntervalSeconds)
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 960, height: 960)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 0.2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 0.2, preferredTimescale: 600)

        var sampleTimestamps: [Double] = []
        var cursor = 0.25
        while cursor < totalDuration {
            sampleTimestamps.append(cursor)
            cursor += interval
        }
        if sampleTimestamps.isEmpty {
            sampleTimestamps = [0.0]
        }

        var records: [AIAnalysisRecord] = []
        var framesWithHumans = 0

        struct SampleActivityPoint {
            let timestamp: Double
            let motionMagnitude: Double
            let elevatedWrist: Bool
            let confidence: Double?
            let poseMetrics: PoseBiomechanicsMetrics?
        }

        var activitySeries: [SampleActivityPoint] = []
        var previousHipCenter: CGPoint?

        for (index, timestamp) in sampleTimestamps.enumerated() {
            try Task.checkCancellation()
            let cmTime = CMTime(seconds: timestamp, preferredTimescale: 600)
            if let (cgImage, _) = try? await generator.image(at: cmTime) {
                let frameResult = Self.performVisionRequests(on: cgImage, dominantHand: dominantHand)
                if frameResult.humanCount > 0 {
                    framesWithHumans += 1
                }

                var motionDelta: Double = 0
                if let hip = frameResult.hipMidpoint {
                    if let prev = previousHipCenter {
                        let dx = Double(hip.x - prev.x)
                        let dy = Double(hip.y - prev.y)
                        motionDelta = sqrt(dx * dx + dy * dy)
                    }
                    previousHipCenter = hip
                } else {
                    previousHipCenter = nil
                }

                activitySeries.append(
                    SampleActivityPoint(
                        timestamp: timestamp,
                        motionMagnitude: motionDelta,
                        elevatedWrist: frameResult.metrics?.dominantWristAboveShoulder == true,
                        confidence: frameResult.confidence,
                        poseMetrics: frameResult.metrics
                    )
                )

                // Record notable elevated-contact / trophy-posture observations directly from real Vision pose landmarks
                if let metrics = frameResult.metrics, metrics.dominantWristAboveShoulder {
                    records.append(
                        AIAnalysisRecord(
                            videoID: videoID,
                            eventType: .elevatedContactCandidate,
                            timestampSeconds: timestamp,
                            analysisResultText: frameResult.summary,
                            confidenceScore: frameResult.confidence,
                            modelName: visionEngineName,
                            modelVersion: visionEngineVersion,
                            status: .completed,
                            metrics: metrics
                        )
                    )
                }
            }

            let progress = Double(index + 1) / Double(sampleTimestamps.count)
            onProgress(progress)
        }

        // Segment contiguous active movement intervals into Candidate Highlights for user review
        var candidates: [CandidateHighlightEvent] = []
        let movementThreshold = 0.045
        var activeClusterStart: Double?
        var activeClusterPeakTime: Double = 0
        var activeClusterPeakValue: Double = 0
        var clusterConfidences: [Double] = []
        var clusterHadElevatedPose = false
        var clusterPoses: [PoseBiomechanicsMetrics] = []

        func flushCluster(endTime: Double) async {
            guard let start = activeClusterStart else { return }
            let paddedStart = max(0, start - 1.5)
            let paddedEnd = min(totalDuration, max(paddedStart + 2.0, endTime + 1.5))
            let avgConf: Double? = clusterConfidences.isEmpty
                ? nil
                : (clusterConfidences.reduce(0, +) / Double(clusterConfidences.count))

            var suggestedCategory: HighlightCategory = clusterHadElevatedPose ? .serve : .rally
            var summary = clusterHadElevatedPose
                ? "Active player movement with overhead/elevated wrist posture detected via Apple Vision. Verify stroke category below."
                : "Sustained player court movement interval detected via Apple Vision. Review and assign exact shot category."
            var sourceName = visionEngineName
            var versionLabel = visionEngineVersion
            var finalConf = avgConf

            if let classifier = customStrokeClassifier, !clusterPoses.isEmpty,
               let prediction = try? await classifier.classifyPoseWindow(clusterPoses) {
                suggestedCategory = prediction.category
                summary = "Classified as \(prediction.category.rawValue) by \(prediction.modelName)."
                sourceName = prediction.modelName
                versionLabel = prediction.modelVersion
                finalConf = prediction.confidence
            }

            candidates.append(
                CandidateHighlightEvent(
                    startTimestamp: paddedStart,
                    endTimestamp: paddedEnd,
                    peakTimestamp: activeClusterPeakTime,
                    detectionSource: sourceName,
                    observationSummary: summary,
                    modelConfidence: finalConf,
                    modelVersion: versionLabel,
                    userSelectedCategory: suggestedCategory,
                    isSelectedForExport: true
                )
            )

            activeClusterStart = nil
            activeClusterPeakValue = 0
            clusterConfidences.removeAll()
            clusterHadElevatedPose = false
            clusterPoses.removeAll()
        }

        for sample in activitySeries {
            let isActive = sample.motionMagnitude >= movementThreshold || sample.elevatedWrist
            if isActive {
                if activeClusterStart == nil {
                    activeClusterStart = sample.timestamp
                    activeClusterPeakTime = sample.timestamp
                    activeClusterPeakValue = sample.motionMagnitude
                } else if sample.motionMagnitude > activeClusterPeakValue {
                    activeClusterPeakValue = sample.motionMagnitude
                    activeClusterPeakTime = sample.timestamp
                }
                if let c = sample.confidence {
                    clusterConfidences.append(c)
                }
                if sample.elevatedWrist {
                    clusterHadElevatedPose = true
                }
                if let p = sample.poseMetrics {
                    clusterPoses.append(p)
                }
            } else if activeClusterStart != nil {
                await flushCluster(endTime: sample.timestamp)
            }
        }

        if let lastTime = activitySeries.last?.timestamp, activeClusterStart != nil {
            await flushCluster(endTime: lastTime)
        }

        // Summary record for the overall Vision scan
        records.insert(
            AIAnalysisRecord(
                videoID: videoID,
                eventType: .playerDetected,
                timestampSeconds: 0,
                analysisResultText: "Scanned \(sampleTimestamps.count) frames locally on iPhone: player detected in \(framesWithHumans) frames, \(candidates.count) active rally/motion segments proposed.",
                confidenceScore: nil,
                modelName: visionEngineName,
                modelVersion: visionEngineVersion,
                status: .completed
            ),
            at: 0
        )

        return VideoVisionAnalysisSummary(
            sampledFrameCount: sampleTimestamps.count,
            framesWithPlayerDetected: framesWithHumans,
            records: records,
            candidateHighlights: candidates
        )
    }

    // MARK: - Synchronous Vision Request Helper

    private struct InternalFrameVisionResult {
        let humanCount: Int
        let metrics: PoseBiomechanicsMetrics?
        let confidence: Double?
        let hipMidpoint: CGPoint?
        let summary: String
    }

    private static func performVisionRequests(
        on cgImage: CGImage,
        dominantHand: DominantHand
    ) -> InternalFrameVisionResult {
        let humanRectRequest = VNDetectHumanRectanglesRequest()
        humanRectRequest.upperBodyOnly = false

        let poseRequest = VNDetectHumanBodyPoseRequest()
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])

        do {
            try handler.perform([humanRectRequest, poseRequest])
        } catch {
            return InternalFrameVisionResult(
                humanCount: 0,
                metrics: nil,
                confidence: nil,
                hipMidpoint: nil,
                summary: "Apple Vision could not evaluate this frame on the current runtime (\(error.localizedDescription))."
            )
        }

        let rectCount = humanRectRequest.results?.count ?? 0
        guard let primaryPose = poseRequest.results?.first else {
            let msg = rectCount > 0
                ? "Detected \(rectCount) player silhouette(s); body landmarks were occluded or too distant for skeletal joint angles."
                : "No player body pose detected in this frame."
            let rectConf = humanRectRequest.results?.first.map { Double($0.confidence) }
            return InternalFrameVisionResult(
                humanCount: rectCount,
                metrics: nil,
                confidence: rectConf,
                hipMidpoint: nil,
                summary: msg
            )
        }

        let recognizedPoints = (try? primaryPose.recognizedPoints(.all)) ?? [:]
        let minimumJointConfidence: Float = 0.25

        func validPoint(_ key: VNHumanBodyPoseObservation.JointName) -> VNRecognizedPoint? {
            guard let pt = recognizedPoints[key], pt.confidence >= minimumJointConfidence else { return nil }
            return pt
        }

        let exportedJoints: [NormalizedJointPoint] = recognizedPoints.compactMap { key, pt in
            guard pt.confidence >= minimumJointConfidence else { return nil }
            return NormalizedJointPoint(
                jointName: key.rawValue.rawValue,
                x: Double(pt.location.x),
                y: Double(pt.location.y),
                confidence: Double(pt.confidence)
            )
        }

        let rElbowAngle = jointAngleDegrees(
            a: validPoint(.rightShoulder),
            vertex: validPoint(.rightElbow),
            c: validPoint(.rightWrist)
        )
        let lElbowAngle = jointAngleDegrees(
            a: validPoint(.leftShoulder),
            vertex: validPoint(.leftElbow),
            c: validPoint(.leftWrist)
        )
        let rKneeAngle = jointAngleDegrees(
            a: validPoint(.rightHip),
            vertex: validPoint(.rightKnee),
            c: validPoint(.rightAnkle)
        )
        let lKneeAngle = jointAngleDegrees(
            a: validPoint(.leftHip),
            vertex: validPoint(.leftKnee),
            c: validPoint(.leftAnkle)
        )

        let domWrist = (dominantHand == .right) ? validPoint(.rightWrist) : validPoint(.leftWrist)
        let domShoulder = (dominantHand == .right) ? validPoint(.rightShoulder) : validPoint(.leftShoulder)
        // Vision normalized coordinates place y = 0 at bottom and y = 1 at top
        let wristElevated: Bool = {
            guard let w = domWrist, let s = domShoulder else { return false }
            return w.location.y > (s.location.y + 0.04)
        }()

        var hipMid: CGPoint? = nil
        if let rHip = validPoint(.rightHip), let lHip = validPoint(.leftHip) {
            hipMid = CGPoint(
                x: (rHip.location.x + lHip.location.x) * 0.5,
                y: (rHip.location.y + lHip.location.y) * 0.5
            )
        }

        let zoneDescription: String = {
            guard let hipMid else { return "Undetermined Court Zone" }
            let lateral = hipMid.x < 0.36 ? "Left / Ad Side" : (hipMid.x > 0.64 ? "Right / Deuce Side" : "Center Court")
            let depth = hipMid.y < 0.35 ? "Near Baseline" : (hipMid.y > 0.62 ? "Far Court / Net Depth" : "Mid-Court")
            return "\(depth) • \(lateral)"
        }()

        let metrics = PoseBiomechanicsMetrics(
            rightElbowAngleDegrees: rElbowAngle,
            leftElbowAngleDegrees: lElbowAngle,
            rightKneeAngleDegrees: rKneeAngle,
            leftKneeAngleDegrees: lKneeAngle,
            dominantWristAboveShoulder: wristElevated,
            estimatedCourtZone: zoneDescription,
            joints: exportedJoints
        )

        var summaryParts: [String] = ["Zone: \(zoneDescription)"]
        if wristElevated {
            summaryParts.append("Dominant wrist elevated above shoulder (Serve / Overhead contact candidate)")
        }
        if let rElbowAngle {
            summaryParts.append(String(format: "Right elbow %.0f°", rElbowAngle))
        }
        if let rKneeAngle {
            summaryParts.append(String(format: "Right knee %.0f°", rKneeAngle))
        }

        return InternalFrameVisionResult(
            humanCount: max(1, rectCount),
            metrics: metrics,
            confidence: Double(primaryPose.confidence),
            hipMidpoint: hipMid,
            summary: summaryParts.joined(separator: " • ")
        )
    }

    private static func jointAngleDegrees(
        a: VNRecognizedPoint?,
        vertex: VNRecognizedPoint?,
        c: VNRecognizedPoint?
    ) -> Double? {
        guard let a, let vertex, let c else { return nil }
        let v1 = CGVector(dx: a.location.x - vertex.location.x, dy: a.location.y - vertex.location.y)
        let v2 = CGVector(dx: c.location.x - vertex.location.x, dy: c.location.y - vertex.location.y)
        let mag1 = sqrt(v1.dx * v1.dx + v1.dy * v1.dy)
        let mag2 = sqrt(v2.dx * v2.dx + v2.dy * v2.dy)
        guard mag1 > 0.0001 && mag2 > 0.0001 else { return nil }
        let cosine = max(-1.0, min(1.0, Double((v1.dx * v2.dx + v1.dy * v2.dy) / (mag1 * mag2))))
        return acos(cosine) * 180.0 / .pi
    }
}

