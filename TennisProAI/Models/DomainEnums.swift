import Foundation
import SwiftUI

// MARK: - App Theme & Navigation

enum AppThemePreference: String, Codable, CaseIterable, Identifiable, Sendable {
    case dark = "dark"
    case light = "light"
    case system = "system"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .dark: return "Courtside Dark (Recommended)"
        case .light: return "Daylight Light"
        case .system: return "Match iOS System"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .dark: return .dark
        case .light: return .light
        case .system: return nil
        }
    }
}

enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case home = "home"
    case record = "record"
    case videos = "videos"
    case statistics = "statistics"
    case profile = "profile"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .record: return "Record"
        case .videos: return "Videos"
        case .statistics: return "Statistics"
        case .profile: return "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "figure.tennis"
        case .record: return "video.badge.plus"
        case .videos: return "film.stack"
        case .statistics: return "chart.xyaxis.line"
        case .profile: return "person.crop.circle"
        }
    }
}

// MARK: - Player Profile Enums

enum SkillLevel: String, Codable, CaseIterable, Identifiable, Sendable {
    case beginner = "Beginner (NTRP 1.5 - 2.5)"
    case intermediate = "Intermediate (NTRP 3.0 - 3.5)"
    case clubAdvanced = "Club Competitive (NTRP 4.0 - 4.5)"
    case tournament = "Tournament / Collegiate (NTRP 5.0+)"
    case pro = "Tour / Semi-Pro"

    var id: String { rawValue }

    var shortLabel: String {
        switch self {
        case .beginner: return "NTRP 2.0"
        case .intermediate: return "NTRP 3.5"
        case .clubAdvanced: return "NTRP 4.5"
        case .tournament: return "NTRP 5.0+"
        case .pro: return "Tour Pro"
        }
    }
}

enum DominantHand: String, Codable, CaseIterable, Identifiable, Sendable {
    case right = "Right-Handed"
    case left = "Left-Handed"

    var id: String { rawValue }
}

enum BackhandStyle: String, Codable, CaseIterable, Identifiable, Sendable {
    case twoHanded = "Two-Handed"
    case oneHanded = "One-Handed"

    var id: String { rawValue }
}

// MARK: - Court & Match Enums

enum CourtSurface: String, Codable, CaseIterable, Identifiable, Sendable {
    case hard = "Hard Court"
    case clay = "Clay"
    case grass = "Grass"
    case indoorHard = "Indoor Hard"
    case carpet = "Carpet / Synthetic"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .hard: return "square.split.2x2"
        case .clay: return "circle.grid.cross"
        case .grass: return "leaf.fill"
        case .indoorHard: return "building.2.fill"
        case .carpet: return "rectangle.grid.2x2"
        }
    }
}

enum MatchStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case inProgress = "In Progress"
    case completed = "Completed"
    case retired = "Retired"

    var id: String { rawValue }
}

enum MatchParticipantSide: String, Codable, Sendable {
    case player = "player"
    case opponent = "opponent"
}

enum PointOutcomeTag: String, Codable, CaseIterable, Identifiable, Sendable {
    case standardRally = "Rally Point"
    case ace = "Ace"
    case serviceWinner = "Service Winner"
    case forehandWinner = "Forehand Winner"
    case backhandWinner = "Backhand Winner"
    case netWinner = "Volley / Smash Winner"
    case doubleFault = "Double Fault"
    case forehandUnforcedError = "Forehand Unforced Error"
    case backhandUnforcedError = "Backhand Unforced Error"
    case forcedError = "Forced Error"

    var id: String { rawValue }
}

// MARK: - Video & Highlight Enums

enum SessionType: String, Codable, CaseIterable, Identifiable, Sendable {
    case match = "Match"
    case practice = "Practice"
    case serveSession = "Serve Practice"
    case drill = "Training Drill"
    case matchSimulation = "Match Simulation"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .match: return "trophy.fill"
        case .practice: return "tennisball.fill"
        case .serveSession: return "arrow.up.right.circle.fill"
        case .drill: return "target"
        case .matchSimulation: return "flag.checkered"
        }
    }
}

enum HighlightCategory: String, Codable, CaseIterable, Identifiable, Sendable {
    case forehand = "Forehand"
    case backhand = "Backhand"
    case serve = "Serve"
    case volley = "Volley"
    case smash = "Smash"
    case rally = "Rally"
    case winner = "Winner"
    case unforcedError = "Unforced error"
    case footwork = "Footwork"
    case trainingDrill = "Training drill"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .forehand: return "figure.tennis"
        case .backhand: return "arrow.turn.up.left"
        case .serve: return "arrow.up.forward.circle.fill"
        case .volley: return "bolt.horizontal.fill"
        case .smash: return "burst.fill"
        case .rally: return "arrow.left.arrow.right"
        case .winner: return "star.circle.fill"
        case .unforcedError: return "exclamationmark.triangle.fill"
        case .footwork: return "shoeprints.fill"
        case .trainingDrill: return "target"
        }
    }
}

enum VideoSortOption: String, CaseIterable, Identifiable, Sendable {
    case newest = "Newest First"
    case oldest = "Oldest First"
    case durationLongest = "Longest Duration"

    var id: String { rawValue }
}

enum DateFilterRange: String, CaseIterable, Identifiable, Sendable {
    case last7Days = "Last 7 days"
    case last30Days = "Last 30 days"
    case last90Days = "Last 90 days"
    case allTime = "All time"

    var id: String { rawValue }

    func startDate(relativeTo referenceDate: Date = Date()) -> Date? {
        let calendar = Calendar.current
        switch self {
        case .last7Days:
            return calendar.date(byAdding: .day, value: -7, to: referenceDate)
        case .last30Days:
            return calendar.date(byAdding: .day, value: -30, to: referenceDate)
        case .last90Days:
            return calendar.date(byAdding: .day, value: -90, to: referenceDate)
        case .allTime:
            return nil
        }
    }
}

// MARK: - Training Mode Enums

enum TrainingDrillType: String, Codable, CaseIterable, Identifiable, Sendable {
    case servePractice = "Serve practice"
    case forehandDrills = "Forehand drills"
    case backhandDrills = "Backhand drills"
    case volleyPractice = "Volley practice"
    case footwork = "Footwork"
    case rallyConsistency = "Rally consistency"
    case matchSimulation = "Match simulation"

    var id: String { rawValue }

    var iconName: String {
        switch self {
        case .servePractice: return "arrow.up.right.circle.fill"
        case .forehandDrills: return "figure.tennis"
        case .backhandDrills: return "arrow.uturn.left.circle.fill"
        case .volleyPractice: return "bolt.circle.fill"
        case .footwork: return "shoeprints.fill"
        case .rallyConsistency: return "repeat.circle.fill"
        case .matchSimulation: return "trophy.circle.fill"
        }
    }

    var defaultObjective: String {
        switch self {
        case .servePractice: return "Hit wide & T targets on first serve with consistent toss height."
        case .forehandDrills: return "Cross-court heavy topspin depth past the service line."
        case .backhandDrills: return "Consistent shoulder turn and early preparation down the line."
        case .volleyPractice: return "Split-step before opponent contact and crisp punch volleys."
        case .footwork: return "Spider drill & recovery split-steps after wide defensive balls."
        case .rallyConsistency: return "20-ball neutral rally streaks without unforced errors."
        case .matchSimulation: return "Play practice tiebreaks executing pre-point serve +1 patterns."
        }
    }
}

// MARK: - AI Analysis Enums

enum AnalysisEventType: String, Codable, CaseIterable, Identifiable, Sendable {
    case playerDetected = "Player Detection"
    case bodyPoseObservation = "Body-Pose Estimation"
    case elevatedContactCandidate = "Serve / Overhead Pose Candidate"
    case courtPositionObservation = "Court-Position Observation"
    case activePlayCandidate = "Active Play / Rally Candidate"
    case manualTechniqueNote = "Manual Technique Bookmark"
    case customCoreMLPrediction = "Core ML Shot Prediction"

    var id: String { rawValue }
}

enum AnalysisProcessingStatus: String, Codable, CaseIterable, Identifiable, Sendable {
    case pending = "Pending"
    case processing = "Processing"
    case completed = "Completed"
    case manualEntry = "Manual Observation"
    case awaitingModel = "Awaiting Core ML Model"
    case failed = "Failed"

    var id: String { rawValue }
}

