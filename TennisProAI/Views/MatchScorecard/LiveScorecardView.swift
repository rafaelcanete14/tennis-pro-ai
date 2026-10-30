import SwiftUI
import SwiftData

struct LiveScorecardView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \VideoRecording.recordedAt, order: .reverse) private var videos: [VideoRecording]
    @Query(sort: \MatchRecord.matchDate, order: .reverse) private var allMatches: [MatchRecord]

    @State private var viewModel: ScorecardViewModel
    @State private var showManualStatsEditor = false
    @State private var showComparisonSheet = false
    @State private var showDeleteDialog = false
    @Environment(\.dismiss) private var dismiss

    init(matchRecord: MatchRecord) {
        _viewModel = State(initialValue: ScorecardViewModel(matchRecord: matchRecord))
    }

    private var otherMatchesForComparison: [MatchRecord] {
        allMatches.filter { $0.id != viewModel.matchRecord.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: AppSpacing.md) {
                scoreboardCard

                if viewModel.matchRecord.status == .inProgress {
                    livePointControlsCard
                }

                statisticsSummaryCard

                matchNotesAndVideoLinkCard

                pointHistoryCard
            }
            .padding(AppSpacing.md)
        }
        .background(AppTheme.primaryBackground.ignoresSafeArea())
        .navigationTitle("Scorecard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    showManualStatsEditor = true
                } label: {
                    Label("Edit Stats", systemImage: "slider.horizontal.3")
                }
                .accessibilityIdentifier("liveScorecard.editStatsButton")

                if !otherMatchesForComparison.isEmpty {
                    Button {
                        showComparisonSheet = true
                    } label: {
                        Label("Compare", systemImage: "arrow.left.arrow.right")
                    }
                }

                Button(role: .destructive) {
                    showDeleteDialog = true
                } label: {
                    Image(systemName: "trash")
                }
            }
        }
        .onAppear {
            viewModel.startMatchClockIfNeeded()
        }
        .onDisappear {
            viewModel.pauseMatchClock()
        }
        .sheet(isPresented: $showManualStatsEditor) {
            MatchStatsEntryView(existingMatch: viewModel.matchRecord, defaultPlayerName: viewModel.matchRecord.playerName)
        }
        .sheet(isPresented: $showComparisonSheet) {
            MatchComparisonView(primaryMatch: viewModel.matchRecord, candidateMatches: otherMatchesForComparison)
        }
        .confirmationDialog("Delete Match Scorecard?", isPresented: $showDeleteDialog, titleVisibility: .visible) {
            Button("Delete Match Record", role: .destructive) {
                modelContext.delete(viewModel.matchRecord)
                try? modelContext.save()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: -Broadcast-Style Tennis Scoreboard

    private var scoreboardCard: some View {
        CourtCard(padding: 16) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    BadgePill(
                        text: viewModel.situationBanner,
                        icon: "tennisball.fill",
                        color: viewModel.matchRecord.status == .completed ? AppTheme.opticLime : AppTheme.courtGreen
                    )
                    Spacer()
                    Text(TimeFormatters.clockString(from: viewModel.elapsedSeconds))
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                // Player Row
                scoreboardParticipantRow(
                    name: viewModel.matchRecord.playerTeamDisplayName,
                    isServing: viewModel.engineState.currentServer == .player && viewModel.matchRecord.status == .inProgress,
                    isWinner: viewModel.matchRecord.isPlayerWinner == true,
                    sets: viewModel.matchRecord.sets.map { $0.isSuperTiebreakOnly ? ($0.tiebreakPlayerPoints ?? 0) : $0.playerGames },
                    currentPointText: viewModel.playerPointText
                )

                Divider()

                // Opponent Row
                scoreboardParticipantRow(
                    name: viewModel.matchRecord.opponentTeamDisplayName,
                    isServing: viewModel.engineState.currentServer == .opponent && viewModel.matchRecord.status == .inProgress,
                    isWinner: viewModel.matchRecord.isPlayerWinner == false,
                    sets: viewModel.matchRecord.sets.map { $0.isSuperTiebreakOnly ? ($0.tiebreakOpponentPoints ?? 0) : $0.opponentGames },
                    currentPointText: viewModel.opponentPointText
                )

                Text(viewModel.matchRecord.format.summaryDescription)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func scoreboardParticipantRow(
        name: String,
        isServing: Bool,
        isWinner: Bool,
        sets: [Int],
        currentPointText: String
    ) -> some View {
        HStack(spacing: 10) {
            Circle()
                .fill(isServing ? AppTheme.opticLime : Color.clear)
                .frame(width: 10, height: 10)
                .accessibilityLabel(isServing ? "Serving" : "")

            Text(name)
                .font(.headline.weight(isWinner ? .heavy : .semibold))
                .foregroundStyle(isWinner ? AppTheme.opticLime : .primary)
                .lineLimit(1)

            Spacer()

            ForEach(Array(sets.enumerated()), id: \.offset) { _, games in
                Text("\(games)")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .frame(width: 28)
            }

            if viewModel.matchRecord.status == .inProgress {
                Text(currentPointText)
                    .font(.title3.weight(.heavy).monospacedDigit())
                    .foregroundStyle(.black)
                    .frame(width: 48, height: 38)
                    .background(AppTheme.opticLime)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    // MARK: - Live Point-by-Point Entry & Undo

    private var livePointControlsCard: some View {
        CourtCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Point-by-Point Controls")
                        .font(.headline.weight(.bold))
                    Spacer()
                    Button {
                        viewModel.undoPreviousPoint(in: modelContext)
                    } label: {
                        Label("Undo Point", systemImage: "arrow.uturn.backward")
                            .font(.caption.weight(.bold))
                    }
                    .buttonStyle(.bordered)
                    .disabled(!viewModel.canUndo)
                    .accessibilityIdentifier("liveScorecard.undoButton")
                }

                // Serve & Outcome Tag Modifiers
                HStack {
                    Toggle("1st Serve In", isOn: $viewModel.firstServeWasIn)
                        .font(.caption.weight(.semibold))
                        .tint(AppTheme.courtGreen)

                    Spacer()

                    Picker("Shot Outcome", selection: $viewModel.selectedOutcomeTag) {
                        ForEach(PointOutcomeTag.allCases) { tag in
                            Text(tag.rawValue).tag(tag)
                        }
                    }
                    .pickerStyle(.menu)
                    .font(.caption)
                }

                // Big Courtside Point Award Buttons
                HStack(spacing: 12) {
                    PrimaryCourtButton(
                        "Point \(viewModel.matchRecord.playerName)",
                        systemImage: "plus.circle.fill",
                        tint: AppTheme.courtGreen
                    ) {
                        viewModel.awardPoint(to: .player, in: modelContext)
                    }
                    .accessibilityIdentifier("liveScorecard.pointPlayerButton")

                    PrimaryCourtButton(
                        "Point \(viewModel.matchRecord.opponentName)",
                        systemImage: "plus.circle.fill",
                        tint: AppTheme.hardcourtBlue
                    ) {
                        viewModel.awardPoint(to: .opponent, in: modelContext)
                    }
                    .accessibilityIdentifier("liveScorecard.pointOpponentButton")
                }

                // Quick Serve Outcome Shortcuts
                HStack(spacing: 10) {
                    if viewModel.engineState.currentServer == .player {
                        SecondaryCourtButton("Player Ace", systemImage: "bolt.fill", tint: AppTheme.opticLime) {
                            viewModel.recordQuickAce(by: .player, in: modelContext)
                        }
                    }
                    SecondaryCourtButton("Double Fault", systemImage: "xmark.octagon.fill", tint: AppTheme.clayAmber) {
                        viewModel.recordQuickDoubleFault(in: modelContext)
                    }
                }
            }
        }
    }

    // MARK: - Match Statistics Breakdown

    private var statisticsSummaryCard: some View {
        let s = viewModel.matchRecord.statistics
        return CourtCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Match Performance Metrics")
                        .font(.headline.weight(.bold))
                    Spacer()
                    Button("Full Manual Edit") {
                        showManualStatsEditor = true
                    }
                    .font(.caption.weight(.bold))
                    .foregroundStyle(AppTheme.courtGreen)
                }

                Divider()

                statRow("First Serves Made", value: "\(s.firstServesMade) / \(s.firstServeAttempts)")
                statRow("First-Serve %", value: s.firstServePercentage.map { String(format: "%.1f%%", $0) } ?? "—")
                statRow("Second Serves Made", value: "\(s.secondServesMade) / \(s.secondServeAttempts)")
                statRow("Aces / Double Faults", value: "\(s.aces) / \(s.doubleFaults)")
                statRow("Winners / Unforced Errors", value: "\(s.winners) / \(s.unforcedErrors)")
                statRow("Forehand / Backhand Errors", value: "\(s.forehandErrors) / \(s.backhandErrors)")
                statRow("Net Points Won", value: "\(s.netPointsWon) / \(s.netPointsApproached)")
                statRow("Break Points Converted", value: "\(s.breakPointsConverted) / \(s.breakPointOpportunities)")
                statRow("Break Points Saved", value: "\(s.breakPointsSaved) / \(s.breakPointsFaced)")
                statRow("Total Points Won", value: "\(s.totalPointsWon)")
                statRow("Total Games Won", value: "\(s.totalGamesWon)")
            }
        }
    }

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
        }
    }

    private var matchNotesAndVideoLinkCard: some View {
        @Bindable var record = viewModel.matchRecord

        return CourtCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Linked Video & Match Notes")
                    .font(.headline.weight(.bold))

                Picker("Linked Match Recording", selection: $record.linkedVideoID) {
                    Text("No Linked Video").tag(UUID?.none)
                    ForEach(videos) { v in
                        Text(v.title).tag(UUID?.some(v.id))
                    }
                }
                .onChange(of: record.linkedVideoID) { _, _ in
                    try? modelContext.save()
                }

                TextField("Tactical match notes...", text: $record.notes, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2...5)
                    .onChange(of: record.notes) { _, _ in
                        try? modelContext.save()
                    }
            }
        }
    }

    private var pointHistoryCard: some View {
        let history = viewModel.matchRecord.pointHistory
        return CourtCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("Point-by-Point Log (\(history.count))")
                    .font(.headline.weight(.bold))

                if history.isEmpty {
                    Text("Points tracked live will appear here in chronological order.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(history.suffix(15).reversed()) { entry in
                        HStack {
                            BadgePill(
                                text: entry.winner == .player ? viewModel.matchRecord.playerName : viewModel.matchRecord.opponentName,
                                color: entry.winner == .player ? AppTheme.courtGreen : AppTheme.hardcourtBlue
                            )
                            Text(entry.outcomeTag.rawValue)
                                .font(.caption)
                            Spacer()
                            Text(entry.scoreCallAfterPoint)
                                .font(.caption2.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

