# App Store Preparation & Metadata — Tennis Pro AI

> **Important Notice:** This document is a preparation draft for Apple App Store Connect submission. Tennis Pro AI has not been submitted to or approved by Apple. Review all legal and privacy disclosures prior to publishing.

---

## 1. App Identity & Build Configuration

| Field | Value |
|---|---|
| **App Name** | Tennis Pro AI |
| **Subtitle (30 chars max)** | Match Video, Clips & Scorecard |
| **Bundle Identifier** | `com.tennisproai.app` |
| **SKU** | `TENNISPROAI-IOS-001` |
| **Marketing Version** | `1.0.0` |
| **Build Number** | `1` |
| **Minimum iOS Version** | iOS 18.0 |
| **Primary Device Optimization** | iPhone 16 Pro Max (6.9" Super Retina XDR) & Universal iPhone |
| **Primary Category** | Sports |
| **Secondary Category** | Health & Fitness |
| **Age Rating** | 4+ (No objectionable content, no unrestricted web access, no gambling) |
| **Export Compliance** | `ITSAppUsesNonExemptEncryption = NO` (Standard OS HTTPS/local encryption only) |

---

## 2. Draft Promotional Text (170 characters max)

Record your tennis matches courtside, cut stroke highlights in seconds, track point-by-point scorecards, and inspect body-pose technique privately on your iPhone.

---

## 3. Draft App Store Description

**Tennis Pro AI** turns your iPhone into a courtside tennis video recorder, highlight cutter, match scorecard, and performance tracker—built from the ground up for serious club, collegiate, and tournament players.

### Courtside Tripod Video Recording
- Record matches and practice sessions in supported high-frame-rate HD and 4K formats.
- Switch between available rear iPhone lenses (`0.5x Court Ultra-Wide`, `1x Main`, `5x Telephoto`) for tight baseline fences or back-curtain mounts.
- Native iOS 18 **Pause & Resume** recording between changeovers into a single video file.
- Optional **Court Alignment Guides** and **Tripod OLED Dimmer** to conserve battery and help manage device heat during long outdoor sets.

### Fast Video Trimming & Stroke Highlight Collections
- Scrub match footage with filmstrip previews, slow-motion (`0.25x`, `0.5x`), and single-frame stepping (`-1f` / `+1f`).
- Trim and export multiple clips from a single match recording.
- Organize clips into 10 dedicated collections: **Forehand, Backhand, Serve, Volley, Smash, Rally, Winner, Unforced Error, Footwork, and Training Drill**.
- Save clips directly to your iPhone Photos library or share via AirDrop and Messages.

### Interactive Tennis Scorecard & Match Analytics
- Track Singles and Doubles matches with Best-of-3 or Best-of-5 sets, standard Advantage or No-Ad scoring, 7-point Set Tiebreaks, and 10-point Final Set Match Tiebreaks.
- Full point-by-point undo across games, tiebreaks, and sets.
- Log or review 16 match metrics including First-Serve %, Aces, Double Faults, Winners, Forehand/Backhand Errors, Net Points Won, and Break Points Converted/Saved.
- Visualize progress over 7 days, 30 days, 90 days, or All Time using native charts, surface breakdowns, and opponent head-to-head records.

### On-Device Vision Pose Inspection & Training Mode
- Inspect video frames locally using Apple's on-device Vision framework for player detection, 2D body-pose skeletal landmarks, elbow/knee angles, and active rally interval suggestions—without uploading private match videos to the cloud.
- Plan and track structured practice sessions for serves, groundstrokes, volleys, footwork, rally consistency, and match simulation.

### Private & Offline-First
All recordings, clips, scorecards, and training logs are stored locally on your iPhone. No account sign-up is required, and your videos are never uploaded without your explicit action.

---

## 4. Keywords (100 characters max)

`tennis,video,scorecard,highlights,trimmer,stats,serve,forehand,coach,practice,drills,court,pose`

---

## 5. App Store Privacy Disclosures ("Nutrition Labels")

Based on the actual implemented offline-first codebase:
- **Data Used to Track You:** None (`NSPrivacyTracking = false`).
- **Data Linked to You:** None (no external servers, accounts, or analytics SDKs).
- **Data Not Linked to You:** None collected off-device. All camera recordings, SwiftData match records, and Vision pose inspections remain strictly on the user's device unless the user manually shares a file via the iOS Share Sheet or exports to Photos.
- **Required Reason APIs Declared in `PrivacyInfo.xcprivacy`:**
  - `NSPrivacyAccessedAPICategoryDiskSpace` (`E174.1`) — Checks free disk capacity before recording/exporting large video files.
  - `NSPrivacyAccessedAPICategoryFileTimestamp` (`C617.1`) — Displays timestamps and sizes of user-recorded videos inside the app container.
  - `NSPrivacyAccessedAPICategoryUserDefaults` (`CA92.1`) — System/app local preference persistence.

---

## 6. Recommended iPhone 16 Pro Max Screenshot Sequence (6.9" — 1320 x 2868 px)

1. **Home Dashboard (Dark Theme):** Show player skill badge, Quick Start Court Recording CTA, KPI summary cards, and Winners vs Unforced Errors chart.
2. **Courtside Tripod Recorder:** Show court baseline alignment guides, `0.5x / 1x / 5x` lens selector, `4K • 60 fps` badge, and high-contrast Start/Pause/Stop controls.
3. **Highlight Cutter & Collections:** Show filmstrip timeline trimmer with Forehand / Serve / Rally collection pills.
4. **Live Broadcast Scorecard:** Show set-by-set games, `AD / 40` point display, point-by-point undo, and live match stats.
5. **AI Tennis Vision Lab & Statistics:** Show on-device Apple Vision skeletal pose landmarks on a serve trophy frame alongside Swift Charts progress trends.

