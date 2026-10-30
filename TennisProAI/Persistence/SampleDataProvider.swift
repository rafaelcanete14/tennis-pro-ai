import Foundation

/// Read-only demonstration models displayed strictly on the Home Dashboard when the user has zero recorded matches and zero videos.
/// Never persisted to SwiftData and never included in Statistics calculations.
struct DemoDashboardData: Sendable {
    struct MatchPreview: Identifiable, Sendable {
        let id = UUID()
        let opponent: String
        let score: String
        let surface: CourtSurface
        let isWin: Bool
        let firstServePct: Int
        let winners: Int
        let relativeDateLabel: String
    }

    struct HighlightPreview: Identifiable, Sendable {
        let id = UUID()
        let title: String
        let category: HighlightCategory
        let durationLabel: String
        let matchLabel: String
    }

    struct TrendPoint: Identifiable, Sendable {
        let id = UUID()
        let sessionLabel: String
        let firstServePct: Double
        let winnerRatioPct: Double
    }

    let totalPlayHoursLabel: String = "6.5 hrs"
    let totalMatchesLabel: String = "4"
    let winLossLabel: String = "3W – 1L"
    let weeklyGoalMinutesDone: Int = 125
    let weeklyGoalMinutesTarget: Int = 180

    let recentMatches: [MatchPreview] = [
        MatchPreview(
            opponent: "M. Takahashi",
            score: "6-4, 3-6, 7-6(5)",
            surface: .hard,
            isWin: true,
            firstServePct: 67,
            winners: 28,
            relativeDateLabel: "Sample • 2d ago"
        ),
        MatchPreview(
            opponent: "D. Kowalski",
            score: "6-3, 6-2",
            surface: .clay,
            isWin: true,
            firstServePct: 71,
            winners: 19,
            relativeDateLabel: "Sample • 5d ago"
        ),
        MatchPreview(
            opponent: "S. Lindqvist",
            score: "4-6, 5-7",
            surface: .indoorHard,
            isWin: false,
            firstServePct: 58,
            winners: 21,
            relativeDateLabel: "Sample • 9d ago"
        )
    ]

    let recentHighlights: [HighlightPreview] = [
        HighlightPreview(
            title: "Inside-Out Forehand Winner",
            category: .forehand,
            durationLabel: "00:14",
            matchLabel: "vs M. Takahashi"
        ),
        HighlightPreview(
            title: "Slice Serve Wide Ace (Deuce)",
            category: .serve,
            durationLabel: "00:09",
            matchLabel: "vs D. Kowalski"
        ),
        HighlightPreview(
            title: "24-Shot Baseline Exchange",
            category: .rally,
            durationLabel: "00:38",
            matchLabel: "vs M. Takahashi"
        )
    ]

    let performanceTrend: [TrendPoint] = [
        TrendPoint(sessionLabel: "M1", firstServePct: 56, winnerRatioPct: 48),
        TrendPoint(sessionLabel: "M2", firstServePct: 58, winnerRatioPct: 51),
        TrendPoint(sessionLabel: "M3", firstServePct: 71, winnerRatioPct: 60),
        TrendPoint(sessionLabel: "M4", firstServePct: 67, winnerRatioPct: 58)
    ]

    static let shared = DemoDashboardData()
}

