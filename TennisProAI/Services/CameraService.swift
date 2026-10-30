import Foundation
import AVFoundation
import CoreGraphics
import UIKit

// MARK: - Camera Configuration & State Types

struct CameraLensOption: Identifiable, Equatable, Sendable {
    let id: String
    let deviceTypeRaw: String
    let displayLabel: String // e.g. "0.5x Court", "1x Main", "5x Tele"
}

struct VideoRecordingFormatOption: Identifiable, Equatable, Sendable {
    let id: String
    let width: Int
    let height: Int
    let frameRate: Double

    var displayLabel: String {
        let resLabel: String
        if width >= 3840 {
            resLabel = "4K"
        } else if width >= 1920 {
            resLabel = "1080p"
        } else {
            resLabel = "\(height)p"
        }
        return "\(resLabel) • \(Int(frameRate.rounded())) fps"
    }
}

enum CameraAuthorizationState: Equatable, Sendable {
    case notDetermined
    case authorized
    case denied
    case restricted
}

enum RecordingLifecycleState: Equatable, Sendable {
    case idle
    case starting
    case recording
    case paused
    case stopping
}

enum CameraServiceError: LocalizedError {
    case cameraPermissionDenied
    case microphonePermissionDenied
    case noRearCameraAvailable
    case unsupportedFormatConfiguration
    case recordingFailed(String)

    var errorDescription: String? {
        switch self {
        case .cameraPermissionDenied:
            return "Camera access is required to record tennis matches and drills."
        case .microphonePermissionDenied:
            return "Microphone access is required to capture court audio and ball-strike sound."
        case .noRearCameraAvailable:
            return "No rear camera hardware was detected on this device."
        case .unsupportedFormatConfiguration:
            return "The selected resolution or frame rate is not supported by the active camera lens."
        case .recordingFailed(let message):
            return "Recording interrupted: \(message)"
        }
    }

    var recoverySuggestion: String? {
        switch self {
        case .cameraPermissionDenied, .microphonePermissionDenied:
            return "Open iOS Settings > Privacy & Security and enable Camera and Microphone permissions for Tennis Pro AI."
        case .unsupportedFormatConfiguration:
            return "Select 1080p • 60 fps or switch to the 1x Main lens."
        default:
            return "Check available storage space and device temperature, then try recording again."
        }
    }
}

@MainActor
protocol CameraServiceDelegate: AnyObject {
    func cameraServiceDidUpdateState(_ state: RecordingLifecycleState)
    func cameraServiceDidFinishRecording(outputURL: URL, error: Error?)
    func cameraServiceDidChangeThermalState(_ thermalState: ProcessInfo.ThermalState)
    func cameraServiceDidEncounterInterruption(_ reason: String?)
}

@MainActor
protocol CameraServiceProtocol: AnyObject {
    var delegate: CameraServiceDelegate? { get set }
    var captureSession: AVCaptureSession { get }
    var isSimulatedCapture: Bool { get }
    var authorizationState: CameraAuthorizationState { get }
    var recordingState: RecordingLifecycleState { get }
    var availableLenses: [CameraLensOption] { get }
    var selectedLens: CameraLensOption? { get }
    var availableFormats: [VideoRecordingFormatOption] { get }
    var selectedFormat: VideoRecordingFormatOption? { get }
    var thermalState: ProcessInfo.ThermalState { get }

    func checkAndRequestPermissions() async -> Bool
    func startSession() async throws
    func stopSession()
    func selectLens(_ lens: CameraLensOption) async throws
    func selectFormat(_ format: VideoRecordingFormatOption) async throws
    func startRecording(to outputURL: URL) throws
    func pauseRecording()
    func resumeRecording()
    func stopRecording()
}

// MARK: - Production AVFoundation Camera Service (with Simulator/UITest Fallback)

@MainActor
final class CameraService: NSObject, CameraServiceProtocol {
    weak var delegate: CameraServiceDelegate?

    nonisolated let captureSession = AVCaptureSession()
    private let sessionQueue = DispatchQueue(label: "com.tennisproai.camera.sessionQueue", qos: .userInitiated)
    private nonisolated(unsafe) let movieOutput = AVCaptureMovieFileOutput()
    private nonisolated(unsafe) var currentVideoInput: AVCaptureDeviceInput?

    private(set) var isSimulatedCapture: Bool = false
    private(set) var authorizationState: CameraAuthorizationState = .notDetermined
    private(set) var recordingState: RecordingLifecycleState = .idle {
        didSet { delegate?.cameraServiceDidUpdateState(recordingState) }
    }
    private(set) var availableLenses: [CameraLensOption] = []
    private(set) var selectedLens: CameraLensOption?
    private(set) var availableFormats: [VideoRecordingFormatOption] = []
    private(set) var selectedFormat: VideoRecordingFormatOption?
    private(set) var thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState

    private var simulatedOutputURL: URL?
    private var simulatedStartDate: Date?
    private var notificationObservers: [NSObjectProtocol] = []

    override init() {
        super.init()
        let isUITest = ProcessInfo.processInfo.arguments.contains("--uitesting")
        #if targetEnvironment(simulator)
        self.isSimulatedCapture = true
        #else
        self.isSimulatedCapture = isUITest
        #endif
        registerSystemNotifications()
    }

    deinit {
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func registerSystemNotifications() {
        let center = NotificationCenter.default

        let thermalObs = center.addObserver(
            forName: ProcessInfo.thermalStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let state = ProcessInfo.processInfo.thermalState
                self.thermalState = state
                self.delegate?.cameraServiceDidChangeThermalState(state)
            }
        }

        let interruptedObs = center.addObserver(
            forName: AVCaptureSession.wasInterruptedNotification,
            object: captureSession,
            queue: .main
        ) { [weak self] notification in
            let reasonValue = notification.userInfo?[AVCaptureSessionInterruptionReasonKey] as? Int
            Task { @MainActor [weak self] in
                guard let self else { return }
                let message = Self.describeInterruptionReason(reasonValue)
                self.delegate?.cameraServiceDidEncounterInterruption(message)
            }
        }

        let endedObs = center.addObserver(
            forName: AVCaptureSession.interruptionEndedNotification,
            object: captureSession,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.delegate?.cameraServiceDidEncounterInterruption(nil)
            }
        }

        notificationObservers.append(contentsOf: [thermalObs, interruptedObs, endedObs])
    }

    private static func describeInterruptionReason(_ rawValue: Int?) -> String {
        guard let rawValue, let reason = AVCaptureSession.InterruptionReason(rawValue: rawValue) else {
            return "Camera session paused by iOS."
        }
        switch reason {
        case .videoDeviceNotAvailableInBackground:
            return "Recording paused because Tennis Pro AI moved to the background."
        case .audioDeviceInUseByAnotherClient:
            return "Audio capture interrupted by a phone call or another audio app."
        case .videoDeviceInUseByAnotherClient:
            return "Camera is currently in use by another application."
        case .videoDeviceNotAvailableWithMultipleForegroundApps:
            return "Camera unavailable in Split View / multitasking mode."
        case .videoDeviceNotAvailableDueToSystemPressure:
            return "Camera paused due to elevated iPhone temperature or system pressure."
        @unknown default:
            return "Camera session interrupted by iOS."
        }
    }

    // MARK: - Permissions

    func checkAndRequestPermissions() async -> Bool {
        if isSimulatedCapture {
            authorizationState = .authorized
            configureSimulatedOptions()
            return true
        }

        let videoStatus = AVCaptureDevice.authorizationStatus(for: .video)
        switch videoStatus {
        case .authorized:
            authorizationState = .authorized
        case .notDetermined:
            let granted = await AVCaptureDevice.requestAccess(for: .video)
            authorizationState = granted ? .authorized : .denied
        case .denied:
            authorizationState = .denied
        case .restricted:
            authorizationState = .restricted
        @unknown default:
            authorizationState = .denied
        }

        guard authorizationState == .authorized else { return false }

        let audioStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        if audioStatus == .notDetermined {
            _ = await AVCaptureDevice.requestAccess(for: .audio)
        }

        return true
    }

    // MARK: - Session Configuration

    func startSession() async throws {
        if isSimulatedCapture {
            configureSimulatedOptions()
            return
        }

        guard authorizationState == .authorized else {
            throw CameraServiceError.cameraPermissionDenied
        }

        discoverHardwareLenses()
        guard let initialLens = selectedLens ?? availableLenses.first else {
            // Fallback cleanly if running in an environment without rear cameras
            isSimulatedCapture = true
            configureSimulatedOptions()
            return
        }

        selectedLens = initialLens
        try await configureHardwareSession(with: initialLens)
    }

    func stopSession() {
        guard !isSimulatedCapture else { return }
        let session = captureSession
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    private func configureSimulatedOptions() {
        availableLenses = [
            CameraLensOption(id: "ultra", deviceTypeRaw: "ultra", displayLabel: "0.5x Court"),
            CameraLensOption(id: "wide", deviceTypeRaw: "wide", displayLabel: "1x Main"),
            CameraLensOption(id: "tele", deviceTypeRaw: "tele", displayLabel: "5x Tele")
        ]
        if selectedLens == nil {
            selectedLens = availableLenses[1]
        }
        availableFormats = [
            VideoRecordingFormatOption(id: "4k60", width: 3840, height: 2160, frameRate: 60),
            VideoRecordingFormatOption(id: "1080p120", width: 1920, height: 1080, frameRate: 120),
            VideoRecordingFormatOption(id: "1080p60", width: 1920, height: 1080, frameRate: 60),
            VideoRecordingFormatOption(id: "1080p30", width: 1920, height: 1080, frameRate: 30)
        ]
        if selectedFormat == nil {
            selectedFormat = availableFormats[2]
        }
    }

    private func discoverHardwareLenses() {
        let discovery = AVCaptureDevice.DiscoverySession(
            deviceTypes: [
                .builtInUltraWideCamera,
                .builtInWideAngleCamera,
                .builtInTelephotoCamera
            ],
            mediaType: .video,
            position: .back
        )

        var options: [CameraLensOption] = []
        for device in discovery.devices {
            switch device.deviceType {
            case .builtInUltraWideCamera:
                options.append(CameraLensOption(
                    id: device.uniqueID,
                    deviceTypeRaw: device.deviceType.rawValue,
                    displayLabel: "0.5x Court"
                ))
            case .builtInWideAngleCamera:
                options.append(CameraLensOption(
                    id: device.uniqueID,
                    deviceTypeRaw: device.deviceType.rawValue,
                    displayLabel: "1x Main"
                ))
            case .builtInTelephotoCamera:
                options.append(CameraLensOption(
                    id: device.uniqueID,
                    deviceTypeRaw: device.deviceType.rawValue,
                    displayLabel: "5x Tele"
                ))
            default:
                break
            }
        }
        availableLenses = options
        if selectedLens == nil {
            selectedLens = options.first(where: { $0.displayLabel == "1x Main" }) ?? options.first
        }
    }

    private func configureHardwareSession(with lens: CameraLensOption) async throws {
        guard let device = AVCaptureDevice(uniqueID: lens.id) else {
            throw CameraServiceError.noRearCameraAvailable
        }

        let formats = Self.supportedPresets(for: device)
        self.availableFormats = formats
        let preferredFormat = selectedFormat.flatMap { current in
            formats.first(where: { $0.id == current.id })
        } ?? formats.first(where: { $0.id == "1080p60" }) ?? formats.first
        self.selectedFormat = preferredFormat

        let session = self.captureSession
        let output = self.movieOutput

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async { [weak self] in
                guard let self else {
                    continuation.resume()
                    return
                }
                session.beginConfiguration()
                session.sessionPreset = .inputPriority

                if let existingInput = self.currentVideoInput {
                    session.removeInput(existingInput)
                }

                do {
                    let videoInput = try AVCaptureDeviceInput(device: device)
                    if session.canAddInput(videoInput) {
                        session.addInput(videoInput)
                        self.currentVideoInput = videoInput
                    }

                    // Attach audio input once if microphone access is granted
                    let hasAudioInput = session.inputs.contains { input in
                        (input as? AVCaptureDeviceInput)?.device.hasMediaType(.audio) == true
                    }
                    if !hasAudioInput,
                       AVCaptureDevice.authorizationStatus(for: .audio) == .authorized,
                       let audioDevice = AVCaptureDevice.default(for: .audio),
                       let audioInput = try? AVCaptureDeviceInput(device: audioDevice),
                       session.canAddInput(audioInput) {
                        session.addInput(audioInput)
                    }

                    if !session.outputs.contains(output), session.canAddOutput(output) {
                        session.addOutput(output)
                        if let connection = output.connection(with: .video) {
                            if connection.isVideoStabilizationSupported {
                                connection.preferredVideoStabilizationMode = .standard
                            }
                        }
                    }

                    if let chosenFormat = preferredFormat {
                        try Self.applyFormat(chosenFormat, to: device)
                    }

                    session.commitConfiguration()
                    if !session.isRunning {
                        session.startRunning()
                    }
                    continuation.resume()
                } catch {
                    session.commitConfiguration()
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    nonisolated private static func supportedPresets(for device: AVCaptureDevice) -> [VideoRecordingFormatOption] {
        let targets: [(String, Int, Int, Double)] = [
            ("4k60", 3840, 2160, 60),
            ("4k30", 3840, 2160, 30),
            ("1080p120", 1920, 1080, 120),
            ("1080p60", 1920, 1080, 60),
            ("1080p30", 1920, 1080, 30)
        ]

        var matched: [VideoRecordingFormatOption] = []
        for (id, w, h, fps) in targets {
            let exists = device.formats.contains { format in
                let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
                guard Int(dims.width) == w && Int(dims.height) == h else { return false }
                return format.videoSupportedFrameRateRanges.contains { range in
                    range.minFrameRate <= fps && fps <= range.maxFrameRate
                }
            }
            if exists {
                matched.append(VideoRecordingFormatOption(id: id, width: w, height: h, frameRate: fps))
            }
        }
        if matched.isEmpty {
            matched.append(VideoRecordingFormatOption(id: "1080p30", width: 1920, height: 1080, frameRate: 30))
        }
        return matched
    }

    nonisolated private static func applyFormat(_ option: VideoRecordingFormatOption, to device: AVCaptureDevice) throws {
        guard let matchingFormat = device.formats.last(where: { format in
            let dims = CMVideoFormatDescriptionGetDimensions(format.formatDescription)
            guard Int(dims.width) == option.width && Int(dims.height) == option.height else { return false }
            return format.videoSupportedFrameRateRanges.contains {
                $0.minFrameRate <= option.frameRate && option.frameRate <= $0.maxFrameRate
            }
        }) else {
            throw CameraServiceError.unsupportedFormatConfiguration
        }

        try device.lockForConfiguration()
        defer { device.unlockForConfiguration() }
        device.activeFormat = matchingFormat
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(option.frameRate.rounded()))
        device.activeVideoMinFrameDuration = frameDuration
        device.activeVideoMaxFrameDuration = frameDuration
    }

    func selectLens(_ lens: CameraLensOption) async throws {
        guard recordingState == .idle else { return }
        selectedLens = lens
        if !isSimulatedCapture {
            try await configureHardwareSession(with: lens)
        }
    }

    func selectFormat(_ format: VideoRecordingFormatOption) async throws {
        guard recordingState == .idle else { return }
        selectedFormat = format
        guard !isSimulatedCapture, let lens = selectedLens, let device = AVCaptureDevice(uniqueID: lens.id) else {
            return
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            sessionQueue.async {
                do {
                    try Self.applyFormat(format, to: device)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Recording Controls (with iOS 18 Pause / Resume)

    func startRecording(to outputURL: URL) throws {
        guard recordingState == .idle else { return }

        if isSimulatedCapture {
            simulatedOutputURL = outputURL
            simulatedStartDate = Date()
            recordingState = .recording
            return
        }

        recordingState = .starting
        let output = self.movieOutput
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if let connection = output.connection(with: .video),
               connection.isVideoRotationAngleSupported(90) {
                connection.videoRotationAngle = 90
            }
            output.startRecording(to: outputURL, recordingDelegate: self)
        }
    }

    func pauseRecording() {
        guard recordingState == .recording else { return }
        if isSimulatedCapture {
            recordingState = .paused
            return
        }
        let output = self.movieOutput
        sessionQueue.async { [weak self] in
            if output.isRecording && !output.isRecordingPaused {
                output.pauseRecording()
                Task { @MainActor [weak self] in
                    self?.recordingState = .paused
                }
            }
        }
    }

    func resumeRecording() {
        guard recordingState == .paused else { return }
        if isSimulatedCapture {
            recordingState = .recording
            return
        }
        let output = self.movieOutput
        sessionQueue.async { [weak self] in
            if output.isRecordingPaused {
                output.resumeRecording()
                Task { @MainActor [weak self] in
                    self?.recordingState = .recording
                }
            }
        }
    }

    func stopRecording() {
        guard recordingState == .recording || recordingState == .paused else { return }
        recordingState = .stopping

        if isSimulatedCapture {
            guard let outputURL = simulatedOutputURL else {
                recordingState = .idle
                return
            }
            let elapsed = max(2.0, min(12.0, Date().timeIntervalSince(simulatedStartDate ?? Date())))
            Task {
                do {
                    try await SimulatedCourtVideoGenerator.writeSampleCourtVideo(to: outputURL, durationSeconds: elapsed)
                    self.recordingState = .idle
                    self.delegate?.cameraServiceDidFinishRecording(outputURL: outputURL, error: nil)
                } catch {
                    self.recordingState = .idle
                    self.delegate?.cameraServiceDidFinishRecording(outputURL: outputURL, error: error)
                }
            }
            return
        }

        let output = self.movieOutput
        sessionQueue.async {
            if output.isRecording {
                output.stopRecording()
            }
        }
    }
}

extension CameraService: AVCaptureFileOutputRecordingDelegate {
    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didStartRecordingTo fileURL: URL,
        from connections: [AVCaptureConnection]
    ) {
        Task { @MainActor [weak self] in
            self?.recordingState = .recording
        }
    }

    nonisolated func fileOutput(
        _ output: AVCaptureFileOutput,
        didFinishRecordingTo outputFileURL: URL,
        from connections: [AVCaptureConnection],
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.recordingState = .idle
            self.delegate?.cameraServiceDidFinishRecording(outputURL: outputFileURL, error: error)
        }
    }
}

// MARK: - Simulator & UI Test Valid MP4 Court Video Generator

enum SimulatedCourtVideoGenerator {
    static func writeSampleCourtVideo(to outputURL: URL, durationSeconds: Double) async throws {
        if FileManager.default.fileExists(atPath: outputURL.path) {
            try? FileManager.default.removeItem(at: outputURL)
        }

        let width = 1280
        let height = 720
        let fps: Int32 = 30
        let totalFrames = max(30, Int(durationSeconds * Double(fps)))

        let writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        let videoSettings: [String: Any] = [
            AVVideoCodecKey: AVVideoCodecType.h264,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ]
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: videoSettings)
        writerInput.expectsMediaDataInRealTime = false

        let pixelBufferAttributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
            kCVPixelBufferWidthKey as String: width,
            kCVPixelBufferHeightKey as String: height
        ]
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: pixelBufferAttributes
        )

        guard writer.canAdd(writerInput) else {
            throw CameraServiceError.recordingFailed("Cannot configure simulated video writer.")
        }
        writer.add(writerInput)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        for frameIndex in 0..<totalFrames {
            while !writerInput.isReadyForMoreMediaData {
                try await Task.sleep(nanoseconds: 5_000_000)
            }
            if let pool = adaptor.pixelBufferPool {
                var pixelBufferOut: CVPixelBuffer?
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBufferOut)
                if let buffer = pixelBufferOut {
                    drawSimulatedCourtFrame(into: buffer, frame: frameIndex, totalFrames: totalFrames, width: width, height: height)
                    let presentationTime = CMTime(value: CMTimeValue(frameIndex), timescale: fps)
                    adaptor.append(buffer, withPresentationTime: presentationTime)
                }
            }
        }

        writerInput.markAsFinished()
        await writer.finishWriting()
        if let err = writer.error {
            throw err
        }
    }

    private static func drawSimulatedCourtFrame(
        into pixelBuffer: CVPixelBuffer,
        frame: Int,
        totalFrames: Int,
        width: Int,
        height: Int
    ) {
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(pixelBuffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(pixelBuffer)
        let colorSpace = CGColorSpaceCreateDeviceRGB()

        guard let context = CGContext(
            data: baseAddress,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
        ) else { return }

        // Hardcourt outer surface
        context.setFillColor(UIColor(red: 0.08, green: 0.24, blue: 0.18, alpha: 1).cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        // Inner court rectangle
        let courtRect = CGRect(x: 160, y: 90, width: width - 320, height: height - 180)
        context.setFillColor(UIColor(red: 0.12, green: 0.42, blue: 0.65, alpha: 1).cgColor)
        context.fill(courtRect)

        // White court lines
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(4)
        context.stroke(courtRect)
        context.move(to: CGPoint(x: width / 2, y: 90))
        context.addLine(to: CGPoint(x: width / 2, y: height - 90))
        context.strokePath()

        // Animated optic-yellow tennis ball trajectory across the court
        let progress = Double(frame % 60) / 60.0
        let ballX = 200.0 + progress * Double(width - 400)
        let ballY = Double(height) * 0.5 + sin(progress * .pi * 2) * 140.0
        context.setFillColor(UIColor(red: 0.78, green: 0.95, blue: 0.22, alpha: 1).cgColor)
        context.fillEllipse(in: CGRect(x: ballX - 12, y: ballY - 12, width: 24, height: 24))
    }
}

