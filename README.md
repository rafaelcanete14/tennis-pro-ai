# Tennis Pro AI — iOS Tennis Video Analysis & Match Performance App

**Tennis Pro AI** is a native SwiftUI iOS 18+ application designed primarily for the **iPhone 16 Pro Max**. It helps tennis players record matches from a courtside tripod, trim stroke highlights into categorized collections, score matches point-by-point with full undo, track career statistics via Swift Charts, run structured practice sessions, and perform privacy-preserving on-device computer vision pose analysis.

---

## 1. Architecture & Project Structure

```text
TennisProAI.xcodeproj           # Ready-to-open Xcode 16+ project (App + Unit Tests + UI Tests)
project.yml                     # Optional XcodeGen specification
AppStore/
├── AppIcon-1024.png            # Original 1024x1024 24-bit RGB App Store icon
├── APP_STORE_METADATA.md       # Draft App Store description, keywords & privacy nutrition labels
├── PRIVACY_POLICY.md           # Draft offline-first Privacy Policy
└── PromotionalBanner.svg       # Original vector promotional artwork
TennisProAI/
├── App/                        # App entry point, MainTabView (5 tabs), AppNavigationRouter
├── Models/                     # SwiftData @Model entities & Sendable value types
├── Persistence/                # SwiftData ModelContainer, JSON Backup, Keychain, Demo Preview separation
├── Components/                 # Reusable Design System (AppTheme, CourtCard, Courtside buttons, Empty states)
├── Services/
│   ├── CameraService.swift         # AVFoundation rear multi-lens recorder + iOS 18 pause/resume + Simulator MP4 fallback
│   ├── VideoStorageService.swift   # Managed Application Support storage, thumbnails, disk checks, Photos export
│   ├── VideoEditingService.swift   # AVMutableComposition + iOS 18 async AVAssetExportSession clip trimmer
│   ├── MatchScoringService.swift   # Pure TennisScoringEngine (Ad/No-Ad, 7-pt TB, 10-pt Super TB, Undo) & Validator
│   ├── StatisticsService.swift     # Date-filtered career analytics, surface/opponent H2H, match comparison
│   └── AIAnalysisService.swift     # On-device Apple Vision pose/motion analyzer + extensible Core ML protocol
├── ViewModels/                 # @Observable @MainActor ViewModels
├── Views/                      # Onboarding, Dashboard, Recording, VideoLibrary, VideoEditor, MatchScorecard, AIAnalysis, Statistics, Training, Profile
└── Resources/                  # Info.plist, PrivacyInfo.xcprivacy, Assets.xcassets
TennisProAITests/               # XCTest unit tests for scoring, tiebreaks, undo, stats, persistence & trim validation
TennisProAIUITests/             # XCUITest end-to-end flows with Simulator & Physical Device separation
```

---

## 2. Requirements & Installation (macOS + Xcode)

1. **Environment:** macOS Sequoia 15+ with **Xcode 16.0 or later** and the **iOS 18.0+ SDK**.
2. **Open Project:** Double-click `TennisProAI.xcodeproj` in Finder (or run `open TennisProAI.xcodeproj` in Terminal).
3. **Code Signing:**
   - Select the **TennisProAI** project in the Xcode Project Navigator.
   - Under **Signing & Capabilities** for the `TennisProAI` target, enable **Automatically manage signing** and select your Apple Developer Team.
   - Change `PRODUCT_BUNDLE_IDENTIFIER` (`com.tennisproai.app`) if your team requires a unique bundle ID suffix for physical device provisioning.
4. **Run:**
   - Select **iPhone 16 Pro Max** (Simulator or connected physical iPhone 16 Pro Max) from the Xcode run destination bar.
   - Press `Cmd + R` to build and launch.

---

## 3. Running Automated Tests

### In Xcode
Press `Cmd + U` on the `TennisProAI` scheme to run both `TennisProAITests` and `TennisProAIUITests`.

### Via Command Line (`xcodebuild` on macOS)
```bash
xcodebuild test \
  -project TennisProAI.xcodeproj \
  -scheme TennisProAI \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro Max'
```

### Simulator vs Physical Device Testing Notes
- **Simulator Testing:** When running on the iOS Simulator (or with `--uitesting`), `CameraService` automatically activates `SimulatedCourtVideoGenerator`, which uses `AVAssetWriter` to synthesize a real playable H.264 `.mp4` court animation clip. This allows you to test starting/stopping recording, playback, frame stepping, timeline trimming, highlight clip export, and library management end-to-end on Simulator.
- **Physical iPhone 16 Pro Max Required For:**
  - Real `AVCaptureDevice` hardware lens switching (`0.5x Ultra-Wide`, `1x Main`, `5x Telephoto`).
  - Hardware 4K60 / 1080p120 format negotiation and optical stabilization.
  - Real-world thermal pressure transitions (`ProcessInfo.thermalState`) and battery consumption under outdoor sunlight.
  - Evaluating `VNDetectHumanBodyPoseRequest` against live real-human tennis video footage.
  - `testPhysicalHardwareTripleLensCapture_RequiresPhysicalDevice` in `TennisProAIUITests` (automatically skipped via `XCTSkip` on Simulator).

---

## 4. Extending AI Video Analysis with a Custom Core ML Model

Per strict engineering integrity requirements, Tennis Pro AI **never fabricates AI predictions or confidence scores**:
- **Implemented Today (On-Device Apple Vision):** `AIAnalysisService` runs `VNDetectHumanRectanglesRequest` and `VNDetectHumanBodyPoseRequest` locally on video frames to detect players, compute skeletal elbow/knee flexion angles, flag overhead wrist elevation postures, estimate court zones, and propose active movement intervals for user review.
- **Plugging in a Custom Shot Classifier (`.mlmodelc`):**
  1. Train an Action Classifier in **Create ML** (using labeled pose windows for `Forehand`, `Backhand`, `Serve`, `Volley`, `Smash`).
  2. Drag the `.mlmodel` into the `TennisProAI` Xcode target.
  3. Implement `StrokeClassifierModelProtocol` (defined in `TennisProAI/Services/AIAnalysisService.swift`) wrapping the generated Core ML class and call `aiService.registerStrokeClassifier(yourModelWrapper)`. Once registered, candidate highlight segments automatically populate predicted shot categories and model confidence scores.

---

## 5. Archiving for TestFlight / App Store Connect

1. Connect a physical iOS device or select **Any iOS Device (arm64)** in Xcode.
2. Choose **Product > Archive** (`Release` configuration is preconfigured in `TennisProAI.xcscheme`).
3. In the **Xcode Organizer**, click **Validate App** to verify `Info.plist` usage strings, `PrivacyInfo.xcprivacy`, and the 1024x1024 non-alpha `AppIcon`.
4. Review and host `AppStore/PRIVACY_POLICY.md` at your public URL and paste metadata from `AppStore/APP_STORE_METADATA.md` into App Store Connect.

---

## 6. Implemented Features & Known Limitations

### Implemented Features
- **Design System & Accessibility:** Courtside Dark primary theme + optional Light/System modes, championship green & optic lime palette, large >=54pt courtside touch targets, VoiceOver labels, Dynamic Type support, haptic feedback, and destructive confirmation dialogs.
- **Home Dashboard:** Player greeting & skill badge, Quick Start Recording CTA, KPI summary cards, weekly training goal progress bar, Swift Charts trend preview, recent highlights carousel, recent matches list, and clearly badged, dismissible Demo Preview data shown *only* when user records are empty.
- **Court Video Recorder:** Rear camera `AVFoundation` capture, dynamic lens discovery (`0.5x`, `1x`, `5x`), dynamic resolution/FPS preset negotiation, iOS 18 native `pauseRecording()` / `resumeRecording()`, tripod court alignment reticle, OLED battery-saver dimmer overlay, thermal/interruption recovery banners, and post-recording metadata sheet with accidental-deletion safeguards.
- **Video Library & Player:** Async thumbnail generation & caching, search, session/date/favorite filters, sorting, `AVKit` playback with `0.25x` / `0.5x` / `1.0x` slow-motion and `-1f` / `+1f` frame stepping, metadata editing, Photos export, native Share Sheet, and graceful missing-file handling.
- **Video Cutter & Highlight Collections:** Filmstrip timeline preview, start/end trim sliders with `±0.5s` fine nudges, segment loop preview, `AVMutableComposition` + async `AVAssetExportSession` export with live progress & cancellation, multi-clip extraction per match, and all 10 required highlight category collections.
- **Match Scorecard & Performance Analysis:** Singles & Doubles, Best-of-3 & Best-of-5, Ad & No-Ad, 7-point Set Tiebreaks, 10-point Final Set Match Tiebreaks, unlimited point-by-point undo, live state persistence across app restarts, manual entry & format validation for all 16 tennis statistics, and side-by-side match comparison.
- **Player Statistics & Training Mode:** Swift Charts dashboards with `7d / 30d / 90d / All time` filters, surface & opponent breakdowns, plus 7-category Training Mode with live rep/score tracking and linked videos.
- **Offline Storage, Backup & Privacy:** SwiftData local persistence, Application Support relative media paths, portable JSON backup export, Keychain wrapper, `PrivacyInfo.xcprivacy`, and full local data wipe.

### Known Limitations
- ** compilation / Device Verification Environment:** This codebase and Xcode project were authored and statically verified in a Windows workspace where `xcodebuild` and physical iPhone hardware are unavailable; initial compilation and physical-device camera/thermal verification must be run in Xcode 16+ on macOS with an iPhone 16 Pro Max.
- **Custom Stroke Classification ML Model Not Bundled:** Apple's built-in `Vision` framework provides genuine human detection, 2D skeletal body pose landmarks, joint angles, and movement burst segmentation, but does not natively classify tennis shot types (e.g., distinguishing a forehand winner from a backhand unforced error). Automatic shot classification requires supplying a trained Core ML Action Classifier via `StrokeClassifierModelProtocol`; until provided, shot categories are assigned manually during highlight review.
- **Background Recording:** Per iOS platform restrictions, `AVCaptureMovieFileOutput` cannot continue recording video if the user locks the iPhone hardware power button or switches to another foreground app. Use the built-in **Tripod Power-Saver Dimmer** inside the Record screen to dim the OLED display while keeping the app active in the foreground.

