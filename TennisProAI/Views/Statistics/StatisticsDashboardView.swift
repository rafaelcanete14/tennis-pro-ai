import SwiftUI
import SwiftData
import Charts

struct StatisticsDashboardView: View {
    @Environment(AppNavigationRouter.self) private var router
    @Query(sort: \MatchRecord.matchDate, order: .forward) private var matches: [MatchRecord]

    @State private var selectedRange: DateFilterRange = .allTime

    private var stats: AggregatedPlayerStatistics {
        StatisticsService.calculateStatistics(matches: matches, range: selectedRange)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    // Date Filter Picker
                    Picker("Date Range", selection: $selectedRange) {
                        ForEach(DateFilterRange.allCases) { range in
                            Text(range.rawValue).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("statistics.dateRangePicker")

                    if !stats.hasSufficientData {
                        EmptyStateCardView(
                            icon: "chart.bar.xaxis",
                            title: "No Match Statistics for \(selectedRange.rawValue)",
                            message: "Statistics are calculated exclusively from your real stored matches. Start a live match scorecard or log manual match stats to populate charts.",
                            buttonTitle: "Open Match Scorecards",
                            buttonIcon: "plus.circle.fill"
                        ) {
                            router.openNewScorecard()
                        }
                    } else {
                        summaryKPIsGrid

                        firstServeProgressChart

                        winnersVsErrorsChart

                        acesAndDoubleFaultsChart

                        matchDurationTrendChart

                        surfaceBreakdownSection

                        opponentHeadToHeadSection
                    }
                }
                .padding(AppSpacing.md)
            }
            .background(AppTheme.primaryBackground.ignoresSafeArea())
            .navigationTitle("Statistics")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        router.openNewScorecard()
                    } label: {
                        Label("Log Match", systemImage: "plus.circle.fill")
                    }
                }
            }
        }
    }

    // MARK: - Summary Cards

    private var summaryKPIsGrid: some View {
        let cols = [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)]
        return LazyVGrid(columns: cols, spacing: 12) {
            StatMetricCard(
                title: "Total Matches",
                value: "\(stats.totalMatches)",
                subtitle: "\(stats.wins)W – \(stats.losses)L",
                systemImage: "trophy.fill",
                accent: AppTheme.courtGreen
            )

            StatMetricCard(
                title: "Win Percentage",
                value: stats.winPercentage.map { String(format: "%.1f%%", $0) } ?? "—",
                subtitle: "\(stats.completedMatches) decided",
                systemImage: "percent",
                accent: AppTheme.opticLime
            )

            StatMetricCard(
                title: "First-Serve %",
                value: stats.overallFirstServePercentage.map { String(format: "%.1f%%", $0) } ?? "—",
                subtitle: "Weighted across attempts",
                systemImage: "arrow.up.right.circle.fill",
                accent: AppTheme.hardcourtBlue
            )

            StatMetricCard(
                title: "Aces / Double Faults",
                value: String(
                    format: "%.1f / %.1f",
                    stats.acesPerMatch ?? 0,
                    stats.doubleFaultsPerMatch ?? 0
                ),
                subtitle: "Average per match",
                systemImage: "bolt.fill",
                accent: AppTheme.clayAmber
            )

            StatMetricCard(
                title: "Total Winners",
                value: "\(stats.totalWinners)",
                subtitle: "Clean winners hit",
                systemImage: "star.fill",
                accent: AppTheme.courtGreen
            )

            StatMetricCard(
                title: "Unforced Errors",
                value: "\(stats.totalUnforcedErrors)",
                subtitle: "Diff: \(stats.totalWinners - stats.totalUnforcedErrors)",
                systemImage: "exclamationmark.circle.fill",
                accent: AppTheme.clayAmber
            )
        }
    }

    // MARK: - Swift Charts Sections

    @ViewBuilder
    private var firstServeProgressChart: some View {
        let servePoints = stats.chronologicalTrend.compactMap { pt -> (String, Double)? in
            guard let pct = pt.firstServePercentage else { return nil }
            return (pt.shortLabel, pct)
        }

        if !servePoints.isEmpty {
            CourtCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text("First-Serve % Progress Over Time")
                        .font(.headline.weight(.bold))

                    Chart(Array(servePoints.enumerated()), id: \.offset) { _, entry in
                        AreaMark(
                            x: .value("Match", entry.0),
                            y: .value("1st Serve %", entry.1)
                        )
                        .foregroundStyle(AppTheme.courtGreen.opacity(0.18))

                        LineMark(
                            x: .value("Match", entry.0),
                            y: .value("1st Serve %", entry.1)
                        )
                        .foregroundStyle(AppTheme.courtGreen)
                        .interpolationMethod(.catmullRom)

                        PointMark(
                            x: .value("Match", entry.0),
                            y: .value("1st Serve %", entry.1)
                        )
                        .foregroundStyle(AppTheme.opticLime)
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 180)
                }
            }
        }
    }

    private var winnersVsErrorsChart: some View {
        CourtCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Winners vs Unforced Errors")
                    .font(.headline.weight(.bold))

                Chart(stats.chronologicalTrend) { pt in
                    BarMark(
                        x: .value("Match", pt.shortLabel),
                        y: .value("Count", pt.winners)
                    )
                    .foregroundStyle(AppTheme.courtGreen)
                    .position(by: .value("Type", "Winners"))

                    BarMark(
                        x: .value("Match", pt.shortLabel),
                        y: .value("Count", pt.unforcedErrors)
                    )
                    .foregroundStyle(AppTheme.clayAmber)
                    .position(by: .value("Type", "Unforced Errors"))
                }
                .frame(height: 180)
            }
        }
    }

    private var acesAndDoubleFaultsChart: some View {
        CourtCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Aces & Double Faults per Match")
                    .font(.headline.weight(.bold))

                Chart(stats.chronologicalTrend) { pt in
                    BarMark(
                        x: .value("Match", pt.shortLabel),
                        y: .value("Count", pt.aces)
                    )
                    .foregroundStyle(AppTheme.opticLime)
                    .position(by: .value("Metric", "Aces"))

                    BarMark(
                        x: .value("Match", pt.shortLabel),
                        y: .value("Count", pt.doubleFaults)
                    )
                    .foregroundStyle(AppTheme.liveRecordRed)
                    .position(by: .value("Metric", "Double Faults"))
                }
                .frame(height: 170)
            }
        }
    }

    private var matchDurationTrendChart: some View {
        CourtCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Match Duration Trends (Minutes)")
                        .font(.headline.weight(.bold))
                    Spacer()
                    if let avg = stats.averageMatchDurationMinutes {
                        Text(String(format: "Avg %.0f min", avg))
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.hardcourtBlue)
                    }
                }

                Chart(stats.chronologicalTrend) { pt in
                    BarMark(
                        x: .value("Match", pt.shortLabel),
                        y: .value("Minutes", pt.durationMinutes)
                    )
                    .foregroundStyle(AppTheme.hardcourtBlue)
                }
                .frame(height: 160)
            }
        }
    }

    private var surfaceBreakdownSection: some View {
        CourtCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Performance by Court Surface")
                    .font(.headline.weight(.bold))

                if stats.surfaceBreakdowns.isEmpty {
                    Text("Complete at least one match to compare court surfaces.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(stats.surfaceBreakdowns) { item in
                        HStack {
                            Label(item.surface.rawValue, systemImage: item.surface.iconName)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(item.wins)W – \(item.losses)L")
                                .font(.caption.weight(.bold).monospacedDigit())
                            BadgePill(text: String(format: "%.0f%%", item.winPercentage))
                        }
                    }
                }
            }
        }
    }

    private var opponentHeadToHeadSection: some View {
        CourtCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Performance by Opponent")
                    .font(.headline.weight(.bold))

                if stats.opponentBreakdowns.isEmpty {
                    Text("Complete matches to build head-to-head records.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(stats.opponentBreakdowns) { opp in
                        HStack {
                            Text(opp.opponentName)
                                .font(.subheadline.weight(.semibold))
                            Spacer()
                            Text("\(opp.wins)W – \(opp.losses)L")
                                .font(.caption.weight(.bold).monospacedDigit())
                            BadgePill(
                                text: String(format: "%.0f%%", opp.winPercentage),
                                color: opp.winPercentage >= 50 ? AppTheme.courtGreen : AppTheme.clayAmber
                            )
                        }
                    }
                }
            }
        }
    }
}

