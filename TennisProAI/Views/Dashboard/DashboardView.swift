import SwiftUI
import SwiftData
import Charts

struct DashboardView: View {
    @Environment(AppNavigationRouter.self) private var router
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \PlayerProfile.createdAt) private var profiles: [PlayerProfile]
    @Query(sort: \MatchRecord.matchDate, order: .reverse) private var matches: [MatchRecord]
    @Query(sort: \VideoRecording.recordedAt, order: .reverse) private var recordings: [VideoRecording]
    @Query(sort: \VideoClip.createdAt, order: .reverse) private var clips: [VideoClip]
    @Query(sort: \TrainingSession.sessionDate, order: .reverse) private var trainingSessions: [TrainingSession]

    @State private var selectedMatchForDetail: MatchRecord? = nil
    @State private var selectedClipRecording: VideoRecording? = nil

    private var profile: PlayerProfile {
        profiles.first ?? PersistenceController.ensurePrimaryProfile(in: modelContext)
    }

    private var hasAnyRealUserActivity: Bool {
        !matches.isEmpty || !recordings.isEmpty || !trainingSessions.isEmpty
    }

    private var shouldShowDemoPreview: Bool {
        !hasAnyRealUserActivity && profile.showDemoDataWhenEmpty
    }

    private var statsAllTime: AggregatedPlayerStatistics {
        StatisticsService.calculateStatistics(matches: matches, range: .allTime)
    }

    private var totalCombinedPlayHours: String {
        let matchSecs = matches.reduce(0.0) { $0 + $1.durationSeconds }
        let videoSecs = recordings.reduce(0.0) { $0 + $1.durationSeconds }
        let trainingSecs = Double(trainingSessions.filter(\.isCompleted).reduce(0) { $0 + ($1.actualDurationMinutes * 60) })
        let totalHours = (matchSecs + videoSecs + trainingSecs) / 3600.0
        return String(format: "%.1f hrs", totalHours)
    }

    private var weeklyCompletedTrainingMinutes: Int {
        let weekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        return trainingSessions
            .filter { $0.isCompleted && $0.sessionDate >= weekAgo }
            .reduce(0) { $0 + max($1.actualDurationMinutes, $1.plannedDurationMinutes) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    welcomeHeroSection

                    if shouldShowDemoPreview {
                        DemoDataNoticeBanner {
                            profile.showDemoDataWhenEmpty = false
                            try? modelContext.save()
                        }
                    }

                    quickActionsGrid

                    kpiMetricsSection

                    trainingProgressCard

                    performanceTrendSection

                    recentHighlightsSection

                    recentMatchesSection
                }
                .padding(.horizontal, AppSpacing.md)
                .padding(.vertical, AppSpacing.sm)
            }
            .background(AppTheme.primaryBackground.ignoresSafeArea())
            .navigationTitle("Tennis Pro AI")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.openAIAnalysis(for: recordings.first)
                    } label: {
                        Label("AI Vision Lab", systemImage: "viewfinder.circle.fill")
                            .foregroundStyle(AppTheme.courtGreen)
                    }
                    .accessibilityIdentifier("dashboard.aiLabToolbarButton")
                }
            }
            .sheet(item: $selectedMatchForDetail) { match in
                NavigationStack {
                    LiveScorecardView(matchRecord: match)
                }
            }
            .sheet(item: $selectedClipRecording) { video in
                NavigationStack {
                    VideoDetailPlayerView(recording: video)
                }
            }
        }
    }

    // MARK: - Subviews

    private var welcomeHeroSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                ZStack {
                    Circle()
                        .fill(AppTheme.opticLime.opacity(0.20))
                        .frame(width: 54, height: 54)
                    Image(systemName: "figure.tennis")
                        .font(.title2.weight(.bold))
                        .foregroundStyle(AppTheme.opticLime)
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Ready for Court, \(profile.name)")
                        .font(.title3.weight(.heavy))
                        .foregroundStyle(.white)
                    HStack(spacing: 8) {
                        BadgePill(text: profile.skillLevel.shortLabel, icon: "medal.fill", color: AppTheme.opticLime)
                        Text("\(profile.dominantHand.rawValue) • \(profile.preferredSurface.rawValue)")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(1)
                    }
                }
                Spacer()
            }

            PrimaryCourtButton(
                "Quick Start Court Recording",
                systemImage: "record.circle.fill",
                tint: AppTheme.courtGreen
            ) {
                router.navigateToRecord()
            }
            .accessibilityIdentifier("dashboard.quickStartRecordingButton")
        }
        .padding(AppSpacing.lg)
        .background(AppTheme.heroGradient)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(AppTheme.courtGreen.opacity(0.35), lineWidth: 1)
        )
    }

    private var quickActionsGrid: some View {
        HStack(spacing: 10) {
            quickActionTile(
                title: "Scorecard",
                subtitle: "Track Points",
                icon: "list.number",
                tint: AppTheme.courtGreen
            ) {
                router.openNewScorecard()
            }
            .accessibilityIdentifier("dashboard.scorecardQuickButton")

            quickActionTile(
                title: "AI Pose Lab",
                subtitle: "Vision Scan",
                icon: "figure.walk.motion",
                tint: AppTheme.hardcourtBlue
            ) {
                router.openAIAnalysis(for: recordings.first)
            }
            .accessibilityIdentifier("dashboard.aiAnalysisQuickButton")

            quickActionTile(
                title: "Training",
                subtitle: "Drills & Reps",
                icon: "target",
                tint: AppTheme.clayAmber
            ) {
                router.openTrainingHub()
            }
            .accessibilityIdentifier("dashboard.trainingQuickButton")
        }
    }

    private func quickActionTile(
        title: String,
        subtitle: String,
        icon: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticsManager.impact(.light)
            action()
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: icon)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 88, alignment: .leading)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(AppTheme.subtleBorder, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var kpiMetricsSection: some View {
        let demo = DemoDashboardData.shared
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]

        return LazyVGrid(columns: cols, spacing: 12) {
            StatMetricCard(
                title: "Total Playing Time",
                value: shouldShowDemoPreview ? demo.totalPlayHoursLabel : totalCombinedPlayHours,
                subtitle: shouldShowDemoPreview ? "Demo Preview" : "\(recordings.count) saved videos",
                systemImage: "clock.fill",
                accent: AppTheme.courtGreen
            )

            StatMetricCard(
                title: "Matches Played",
                value: shouldShowDemoPreview ? demo.totalMatchesLabel : "\(statsAllTime.totalMatches)",
                subtitle: shouldShowDemoPreview ? "Demo Preview" : "All-time logged",
                systemImage: "trophy.fill",
                accent: AppTheme.hardcourtBlue
            )

            StatMetricCard(
                title: "Win / Loss Record",
                value: shouldShowDemoPreview ? demo.winLossLabel : "\(statsAllTime.wins)W – \(statsAllTime.losses)L",
                subtitle: shouldShowDemoPreview
                    ? "75% (Sample)"
                    : (statsAllTime.winPercentage.map { String(format: "%.0f%% win rate", $0) } ?? "No completed matches"),
                systemImage: "chart.bar.fill",
                accent: AppTheme.opticLime
            )

            StatMetricCard(
                title: "Highlight Clips",
                value: shouldShowDemoPreview ? "3" : "\(clips.count)",
                subtitle: shouldShowDemoPreview ? "Demo Preview" : "Cut from matches",
                systemImage: "scissors",
                accent: AppTheme.clayAmber
            )
        }
    }

    private var trainingProgressCard: some View {
        let demo = DemoDashboardData.shared
        let done = shouldShowDemoPreview ? demo.weeklyGoalMinutesDone : weeklyCompletedTrainingMinutes
        let goal = max(30, shouldShowDemoPreview ? demo.weeklyGoalMinutesTarget : profile.weeklyTrainingGoalMinutes)
        let progress = min(1.0, Double(done) / Double(goal))

        return CourtCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Weekly Training Progress", systemImage: "flame.fill")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.primary)
                    Spacer()
                    Button("Open Drills") {
                        router.openTrainingHub()
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.courtGreen)
                }

                HStack {
                    Text("\(done) / \(goal) min this week")
                        .font(.subheadline.weight(.semibold).monospacedDigit())
                    Spacer()
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(AppTheme.courtGreen)
                }

                ProgressView(value: progress)
                    .tint(AppTheme.courtGreen)
            }
        }
    }

    @ViewBuilder
    private var performanceTrendSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderView(title: "Performance Trends", actionTitle: "Full Stats") {
                router.navigateToStatistics()
            }

            if shouldShowDemoPreview {
                CourtCard {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("First-Serve % Trend (Sample Preview)")
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            BadgePill(text: "SAMPLE", color: AppTheme.opticLime)
                        }
                        Chart(DemoDashboardData.shared.performanceTrend) { point in
                            LineMark(
                                x: .value("Match", point.sessionLabel),
                                y: .value("1st Serve %", point.firstServePct)
                            )
                            .foregroundStyle(AppTheme.courtGreen)
                            .interpolationMethod(.catmullRom)
                            PointMark(
                                x: .value("Match", point.sessionLabel),
                                y: .value("1st Serve %", point.firstServePct)
                            )
                            .foregroundStyle(AppTheme.opticLime)
                        }
                        .chartYScale(domain: 0...100)
                        .frame(height: 150)
                    }
                }
            } else if statsAllTime.chronologicalTrend.count >= 2 {
                CourtCard {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Winners vs Unforced Errors Across Recent Matches")
                            .font(.subheadline.weight(.semibold))
                        Chart(statsAllTime.chronologicalTrend.suffix(6)) { pt in
                            BarMark(
                                x: .value("Match", pt.shortLabel),
                                y: .value("Winners", pt.winners)
                            )
                            .foregroundStyle(AppTheme.courtGreen)
                            .position(by: .value("Metric", "Winners"))

                            BarMark(
                                x: .value("Match", pt.shortLabel),
                                y: .value("Unforced Errors", pt.unforcedErrors)
                            )
                            .foregroundStyle(AppTheme.clayAmber)
                            .position(by: .value("Metric", "Errors"))
                        }
                        .frame(height: 165)
                    }
                }
            } else {
                EmptyStateCardView(
                    icon: "chart.line.uptrend.xyaxis",
                    title: "Record 2+ Matches for Trend Charts",
                    message: "Log match scorecards or manual match statistics to track your serve efficiency and winner-to-error trajectory.",
                    buttonTitle: "Log Match Scorecard",
                    buttonIcon: "plus.circle.fill"
                ) {
                    router.openNewScorecard()
                }
            }
        }
    }

    @ViewBuilder
    private var recentHighlightsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderView(title: "Recent Video Highlights", actionTitle: "Library") {
                router.navigateToVideos()
            }

            if shouldShowDemoPreview {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(DemoDashboardData.shared.recentHighlights) { item in
                            CourtCard(padding: 14) {
                                VStack(alignment: .leading, spacing: 8) {
                                    HStack {
                                        BadgePill(text: item.category.rawValue, icon: item.category.iconName)
                                        Spacer()
                                        Text("SAMPLE")
                                            .font(.caption2.weight(.heavy))
                                            .foregroundStyle(AppTheme.opticLime)
                                    }
                                    Text(item.title)
                                        .font(.subheadline.weight(.bold))
                                        .lineLimit(2)
                                    Text("\(item.matchLabel) • \(item.durationLabel)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .frame(width: 220)
                            }
                        }
                    }
                }
            } else if !clips.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 12) {
                        ForEach(clips.prefix(8)) { clip in
                            Button {
                                if let parent = clip.recording ?? recordings.first(where: { $0.id == clip.parentRecordingID }) {
                                    selectedClipRecording = parent
                                } else {
                                    router.navigateToVideos()
                                }
                            } label: {
                                CourtCard(padding: 14) {
                                    VStack(alignment: .leading, spacing: 8) {
                                        HStack {
                                            BadgePill(text: clip.category.rawValue, icon: clip.category.iconName)
                                            Spacer()
                                            Text(clip.formattedDuration)
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(.secondary)
                                        }
                                        Text(clip.title)
                                            .font(.subheadline.weight(.bold))
                                            .foregroundStyle(.primary)
                                            .lineLimit(1)
                                        Text("Trim \(clip.formattedTrimRange)")
                                            .font(.caption2)
                                            .foregroundStyle(.secondary)
                                    }
                                    .frame(width: 220)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            } else {
                EmptyStateCardView(
                    icon: "scissors",
                    title: "No Highlight Clips Yet",
                    message: "Record a match or practice session, then open the Video Editor to trim forehands, serves, and rallies.",
                    buttonTitle: "Record Tennis Video",
                    buttonIcon: "video.fill"
                ) {
                    router.navigateToRecord()
                }
            }
        }
    }

    @ViewBuilder
    private var recentMatchesSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            SectionHeaderView(title: "Recent Matches", actionTitle: "All Scorecards") {
                router.openNewScorecard()
            }

            if shouldShowDemoPreview {
                ForEach(DemoDashboardData.shared.recentMatches) { sample in
                    CourtCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    BadgePill(
                                        text: sample.isWin ? "WIN (DEMO)" : "LOSS (DEMO)",
                                        color: sample.isWin ? AppTheme.courtGreen : AppTheme.clayAmber
                                    )
                                    Text(sample.surface.rawValue)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Text("vs \(sample.opponent)")
                                    .font(.headline.weight(.bold))
                                Text(sample.relativeDateLabel)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            VStack(alignment: .trailing, spacing: 4) {
                                Text(sample.score)
                                    .font(.headline.weight(.bold).monospacedDigit())
                                Text("1st Srv \(sample.firstServePct)% • \(sample.winners) W")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else if !matches.isEmpty {
                ForEach(matches.prefix(5)) { match in
                    Button {
                        selectedMatchForDetail = match
                    } label: {
                        CourtCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    HStack(spacing: 8) {
                                        BadgePill(
                                            text: match.resultBadgeText,
                                            color: match.isPlayerWinner == true
                                                ? AppTheme.courtGreen
                                                : (match.status == .inProgress ? AppTheme.hardcourtBlue : AppTheme.clayAmber)
                                        )
                                        Text(match.surface.rawValue)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                    Text("vs \(match.opponentTeamDisplayName)")
                                        .font(.headline.weight(.bold))
                                        .foregroundStyle(.primary)
                                    Text(match.matchDate.formatted(date: .abbreviated, time: .omitted))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(match.finalScoreSummary)
                                        .font(.headline.weight(.bold).monospacedDigit())
                                        .foregroundStyle(.primary)
                                    Image(systemName: "chevron.right")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            } else {
                EmptyStateCardView(
                    icon: "list.clipboard",
                    title: "No Matches Logged Yet",
                    message: "Start a live point-by-point scorecard courtside or enter completed match statistics.",
                    buttonTitle: "New Match Scorecard",
                    buttonIcon: "plus"
                ) {
                    router.openNewScorecard()
                }
            }
        }
    }
}

