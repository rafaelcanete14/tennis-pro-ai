import Foundation
import SwiftData

@Model
final class PlayerProfile {
    @Attribute(.unique) var id: UUID
    var name: String
    var skillLevelRaw: String
    var dominantHandRaw: String
    var backhandStyleRaw: String
    var preferredSurfaceRaw: String
    var weeklyTrainingGoalMinutes: Int
    var themePreferenceRaw: String
    var showDemoDataWhenEmpty: Bool
    var hasCompletedOnboarding: Bool
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        name: String = "Player",
        skillLevel: SkillLevel = .intermediate,
        dominantHand: DominantHand = .right,
        backhandStyle: BackhandStyle = .twoHanded,
        preferredSurface: CourtSurface = .hard,
        weeklyTrainingGoalMinutes: Int = 180,
        themePreference: AppThemePreference = .dark,
        showDemoDataWhenEmpty: Bool = true,
        hasCompletedOnboarding: Bool = false,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.skillLevelRaw = skillLevel.rawValue
        self.dominantHandRaw = dominantHand.rawValue
        self.backhandStyleRaw = backhandStyle.rawValue
        self.preferredSurfaceRaw = preferredSurface.rawValue
        self.weeklyTrainingGoalMinutes = weeklyTrainingGoalMinutes
        self.themePreferenceRaw = themePreference.rawValue
        self.showDemoDataWhenEmpty = showDemoDataWhenEmpty
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    var skillLevel: SkillLevel {
        get { SkillLevel(rawValue: skillLevelRaw) ?? .intermediate }
        set {
            skillLevelRaw = newValue.rawValue
            updatedAt = Date()
        }
    }

    var dominantHand: DominantHand {
        get { DominantHand(rawValue: dominantHandRaw) ?? .right }
        set {
            dominantHandRaw = newValue.rawValue
            updatedAt = Date()
        }
    }

    var backhandStyle: BackhandStyle {
        get { BackhandStyle(rawValue: backhandStyleRaw) ?? .twoHanded }
        set {
            backhandStyleRaw = newValue.rawValue
            updatedAt = Date()
        }
    }

    var preferredSurface: CourtSurface {
        get { CourtSurface(rawValue: preferredSurfaceRaw) ?? .hard }
        set {
            preferredSurfaceRaw = newValue.rawValue
            updatedAt = Date()
        }
    }

    var themePreference: AppThemePreference {
        get { AppThemePreference(rawValue: themePreferenceRaw) ?? .dark }
        set {
            themePreferenceRaw = newValue.rawValue
            updatedAt = Date()
        }
    }
}

