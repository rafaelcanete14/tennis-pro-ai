import Foundation
import SwiftData

@Model
final class TrainingSession {
    @Attribute(.unique) var id: UUID
    var name: String
    var drillTypeRaw: String
    var objective: String
    var plannedDurationMinutes: Int
    var actualDurationMinutes: Int
    var targetRepetitions: Int
    var completedRepetitions: Int
    var targetScore: Int
    var achievedScore: Int
    var notes: String
    var isCompleted: Bool
    var sessionDate: Date
    var linkedVideoID: UUID?

    init(
        id: UUID = UUID(),
        name: String,
        drillType: TrainingDrillType = .forehandDrills,
        objective: String = "",
        plannedDurationMinutes: Int = 45,
        actualDurationMinutes: Int = 0,
        targetRepetitions: Int = 50,
        completedRepetitions: Int = 0,
        targetScore: Int = 40,
        achievedScore: Int = 0,
        notes: String = "",
        isCompleted: Bool = false,
        sessionDate: Date = Date(),
        linkedVideoID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.drillTypeRaw = drillType.rawValue
        self.objective = objective.isEmpty ? drillType.defaultObjective : objective
        self.plannedDurationMinutes = plannedDurationMinutes
        self.actualDurationMinutes = actualDurationMinutes
        self.targetRepetitions = targetRepetitions
        self.completedRepetitions = completedRepetitions
        self.targetScore = targetScore
        self.achievedScore = achievedScore
        self.notes = notes
        self.isCompleted = isCompleted
        self.sessionDate = sessionDate
        self.linkedVideoID = linkedVideoID
    }

    var drillType: TrainingDrillType {
        get { TrainingDrillType(rawValue: drillTypeRaw) ?? .forehandDrills }
        set { drillTypeRaw = newValue.rawValue }
    }

    var repetitionProgress: Double {
        guard targetRepetitions > 0 else { return isCompleted ? 1.0 : 0.0 }
        return min(1.0, Double(completedRepetitions) / Double(targetRepetitions))
    }

    var scoreProgress: Double {
        guard targetScore > 0 else { return isCompleted ? 1.0 : 0.0 }
        return min(1.0, Double(achievedScore) / Double(targetScore))
    }
}

