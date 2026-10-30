# Privacy Policy — Tennis Pro AI (Draft)

**Effective Date:** October 30, 2026  
**Application:** Tennis Pro AI for iOS

## 1. Overview
Tennis Pro AI is designed with an **offline-first, on-device privacy architecture**. We do not require you to create an account, and we do not operate cloud servers that collect, store, or monetize your personal information or tennis videos.

## 2. Information Stored Locally on Your Device
All data you create in Tennis Pro AI is stored locally on your iPhone inside the application's sandboxed storage (`SwiftData` and `Application Support`):
- **Player Profile:** Display name, playing level, dominant hand, backhand style, preferred court surface, and training goals.
- **Video Recordings & Highlight Clips:** Match and practice videos captured with your camera, trimmed highlight clips, generated thumbnails, tags, and coaching notes.
- **Scorecards, Statistics & Training Logs:** Match scores, point-by-point logs, manual performance metrics, and practice drill records.
- **On-Device Computer Vision Observations:** Body-pose joint landmarks and candidate active play timestamps computed locally on your iPhone using Apple's built-in Vision framework.

## 3. Device Permissions
Tennis Pro AI requests iOS hardware permissions only when needed for features you initiate:
- **Camera (`NSCameraUsageDescription`):** Used solely to record your tennis matches and practice sessions onto your device.
- **Microphone (`NSMicrophoneUsageDescription`):** Used solely during video recording so court and ball-strike audio are included in your video files.
- **Photos Library (`NSPhotoLibraryAddUsageDescription` / `NSPhotoLibraryUsageDescription`):** Used only when you explicitly tap **Save to Photos** to export a full recording or highlight clip.

## 4. Video Processing & Computer Vision
All video playback, timeline trimming (`AVFoundation`), and body-pose / motion inspections (`Apple Vision`) run **100% locally on your iPhone**. Private videos are never uploaded to external servers by Tennis Pro AI.

## 5. Third-Party Analytics, Advertising & Tracking
- Tennis Pro AI contains **zero** third-party advertising SDKs, **zero** cross-app tracking (`NSPrivacyTracking = false`), and **zero** behavioral telemetry SDKs.

## 6. Data Export, Retention & Deletion
You retain complete control over your data at all times:
- **Individual Deletion:** Delete any video, highlight clip, match scorecard, or training session directly inside the app.
- **Portable Backup:** Export a JSON archive of your profile, match statistics, and training history from **Profile > Generate Portable JSON Data Backup**.
- **Full Data Wipe:** Permanently erase all stored videos, clips, thumbnails, scorecards, and profile settings at any time via **Profile > Delete All My Data & Videos**, or by uninstalling Tennis Pro AI from your iPhone.

## 7. Contact
Before publishing to the App Store, replace this section with your support email address and publisher contact URL:
- **Support Email:** `support@yourdomain.example`
- **Website:** `https://yourdomain.example/privacy`

