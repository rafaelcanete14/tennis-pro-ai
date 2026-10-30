import SwiftUI
import SwiftData

struct MatchScorecardListView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \PlayerProfile.createdAt) private var profiles: [PlayerProfile]
    @Query(sort: \MatchRecord.matchDate, order: .reverse) private var matches: [MatchRecord]
    @Query(sort: \VideoRecording.recordedAt, order: .reverse) private var videos: [VideoRecording]

    @State private var showCreateLiveMatch = false
    @State private var showManualMatchEntry = false
    @State private var activeMatchToOpen: MatchRecord? = nil

    private var defaultPlayerName: String {
        profiles.first?.name ?? "Player"
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    HStack(spacing: 10) {
                        PrimaryCourtButton("Live Scorecard", systemImage: "play.fill") {
                            showCreateLiveMatch = true
                        }
                        .accessibilityIdentifier("scorecardList.newLiveButton")

                        SecondaryCourtButton("Log Manual Stats", systemImage: "square.and.pencil") {
                            showManualMatchEntry = true
                        }
                        .accessibilityIdentifier("scorecardList.newManualButton")
                    }

                    if matches.isEmpty {
                        EmptyStateCardView(
                            icon: "sportscourt.fill",
                            title: "No Match Scorecards Yet",
                            message: "Track live points courtside (Love, 15, 30, 40, Deuce, Ad, Tiebreaks) or log manual match statistics from a completed match."
                        )
                    } else {
                        ForEach(matches) { match in
                            NavigationLink {
                                LiveScorecardView(matchRecord: match)
                            } label: {
                                matchHistoryRow(match)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(AppSpacing.md)
            }
            .background(AppTheme.primaryBackground.ignoresSafeArea())
            .navigationTitle("Match Scorecards")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showCreateLiveMatch) {
                NewLiveMatchSetupSheet(defaultPlayerName: defaultPlayerName, videos: videos) { created in
                    activeMatchToOpen = created
                }
            }
            .sheet(isPresented: $showManualMatchEntry) {
                MatchStatsEntryView(existingMatch: nil, defaultPlayerName: defaultPlayerName)
            }
            .navigationDestination(item: $activeMatchToOpen) { match in
                LiveScorecardView(matchRecord: match)
            }
        }
    }

    private func matchHistoryRow(_ match: MatchRecord) -> some View {
        CourtCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    BadgePill(
                        text: match.resultBadgeText,
                        color: match.isPlayerWinner == true
                            ? AppTheme.courtGreen
                            : (match.status == .inProgress ? AppTheme.hardcourtBlue : AppTheme.clayAmber)
                    )
                    BadgePill(text: match.isDoubles ? "Doubles" : "Singles", color: AppTheme.hardcourtBlue)
                    Text(match.surface.rawValue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(match.matchDate.formatted(date: .abbreviated, time: .omitted))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(match.playerTeamDisplayName)
                            .font(.subheadline.weight(.bold))
                            .foregroundStyle(.primary)
                        Text("vs \(match.opponentTeamDisplayName)")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(match.finalScoreSummary)
                        .font(.title3.weight(.heavy).monospacedDigit())
                        .foregroundStyle(.primary)
                }

                if !match.location.isEmpty || match.linkedVideoID != nil {
                    HStack(spacing: 10) {
                        if !match.location.isEmpty {
                            Label(match.location, systemImage: "mappin.and.ellipse")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        if match.linkedVideoID != nil {
                            Label("Video Linked", systemImage: "video.fill")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(AppTheme.courtGreen)
                        }
                    }
                }
            }
        }
    }
}

private struct NewLiveMatchSetupSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let defaultPlayerName: String
    let videos: [VideoRecording]
    let onCreated: (MatchRecord) -> Void

    @State private var playerName: String = ""
    @State private var partnerName: String = ""
    @State private var opponentName: String = ""
    @State private var opponentPartnerName: String = ""
    @State private var isDoubles: Bool = false
    @State private var matchDate: Date = Date()
    @State private var location: String = ""
    @State private var surface: CourtSurface = .hard
    @State private var bestOfSets: Int = 3
    @State private var tiebreakAtSixAll: Bool = true
    @State private var finalSetSuperTB: Bool = false
    @State private var noAdScoring: Bool = false
    @State private var linkedVideoID: UUID? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Match Type & Players") {
                    Toggle("Doubles Match", isOn: $isDoubles)
                    TextField("Your Name", text: $playerName)
                        .accessibilityIdentifier("newMatch.playerNameField")
                    if isDoubles {
                        TextField("Your Partner's Name", text: $partnerName)
                    }
                    TextField("Opponent Name", text: $opponentName)
                        .accessibilityIdentifier("newMatch.opponentNameField")
                    if isDoubles {
                        TextField("Opponent Partner's Name", text: $opponentPartnerName)
                    }
                }

                Section("Venue & Surface") {
                    DatePicker("Match Date", selection: $matchDate, displayedComponents: [.date, .hourAndMinute])
                    TextField("Court / Club Location", text: $location)
                    Picker("Court Surface", selection: $surface) {
                        ForEach(CourtSurface.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                }

                Section("Scoring Format") {
                    Picker("Match Length", selection: $bestOfSets) {
                        Text("Best of 3 Sets").tag(3)
                        Text("Best of 5 Sets").tag(5)
                    }
                    Toggle("7-Point Tiebreak at 6–6", isOn: $tiebreakAtSixAll)
                    Toggle("Final Set 10-Point Match Tiebreak", isOn: $finalSetSuperTB)
                    Toggle("No-Ad Scoring (Sudden Death Deuce)", isOn: $noAdScoring)
                }

                if !videos.isEmpty {
                    Section("Link Match Video (Optional)") {
                        Picker("Video Recording", selection: $linkedVideoID) {
                            Text("None").tag(UUID?.none)
                            ForEach(videos) { v in
                                Text(v.title).tag(UUID?.some(v.id))
                            }
                        }
                    }
                }
            }
            .navigationTitle("Start Match Scorecard")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start") {
                        let pName = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let oName = opponentName.trimmingCharacters(in: .whitespacesAndNewlines)
                        let format = MatchFormatConfig(
                            bestOfSets: bestOfSets,
                            tiebreakAtSixAll: tiebreakAtSixAll,
                            finalSetSuperTiebreak: finalSetSuperTB,
                            noAdScoring: noAdScoring
                        )
                        let record = MatchRecord(
                            playerName: pName.isEmpty ? defaultPlayerName : pName,
                            partnerName: partnerName.trimmingCharacters(in: .whitespacesAndNewlines),
                            opponentName: oName.isEmpty ? "Opponent" : oName,
                            opponentPartnerName: opponentPartnerName.trimmingCharacters(in: .whitespacesAndNewlines),
                            isDoubles: isDoubles,
                            matchDate: matchDate,
                            location: location.trimmingCharacters(in: .whitespacesAndNewlines),
                            surface: surface,
                            status: .inProgress,
                            linkedVideoID: linkedVideoID,
                            format: format
                        )
                        modelContext.insert(record)
                        try? modelContext.save()
                        dismiss()
                        onCreated(record)
                    }
                    .accessibilityIdentifier("newMatch.confirmStartButton")
                }
            }
            .onAppear {
                playerName = defaultPlayerName
            }
        }
    }
}

