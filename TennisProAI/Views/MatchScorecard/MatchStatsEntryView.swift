import SwiftUI
import SwiftData

/// Manual Match Performance Analysis & Validated Score Editor (Section 7).
struct MatchStatsEntryView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let existingMatch: MatchRecord?
    let defaultPlayerName: String

    @State private var playerName: String = ""
    @State private var opponentName: String = ""
    @State private var partnerName: String = ""
    @State private var opponentPartnerName: String = ""
    @State private var isDoubles: Bool = false
    @State private var matchDate: Date = Date()
    @State private var location: String = ""
    @State private var surface: CourtSurface = .hard
    @State private var bestOfSets: Int = 3
    @State private var tiebreakAtSixAll: Bool = true
    @State private var durationMinutes: Int = 90
    @State private var matchStatus: MatchStatus = .completed
    @State private var notes: String = ""

    @State private var editableSets: [SetScoreSnapshot] = [
        SetScoreSnapshot(setNumber: 1, playerGames: 6, opponentGames: 4, winner: .player),
        SetScoreSnapshot(setNumber: 2, playerGames: 6, opponentGames: 4, winner: .player)
    ]
    @State private var stats = MatchStatisticsData()
    @State private var validationErrorMessage: String? = nil

    var body: some View {
        NavigationStack {
            Form {
                if let err = validationErrorMessage {
                    Section {
                        Text(err)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(AppTheme.liveRecordRed)
                    }
                }

                Section("Match Participants & Surface") {
                    Toggle("Doubles Match", isOn: $isDoubles)
                    TextField("Player Name", text: $playerName)
                    if isDoubles {
                        TextField("Partner Name", text: $partnerName)
                    }
                    TextField("Opponent Name", text: $opponentName)
                        .accessibilityIdentifier("manualStats.opponentField")
                    if isDoubles {
                        TextField("Opponent Partner Name", text: $opponentPartnerName)
                    }
                    DatePicker("Match Date", selection: $matchDate, displayedComponents: [.date])
                    TextField("Location", text: $location)
                    Picker("Court Surface", selection: $surface) {
                        ForEach(CourtSurface.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }
                    Stepper("Duration: \(durationMinutes) min", value: $durationMinutes, in: 5...600, step: 5)
                }

                Section("Format & Validated Set Scores") {
                    Picker("Format", selection: $bestOfSets) {
                        Text("Best of 3 Sets").tag(3)
                        Text("Best of 5 Sets").tag(5)
                    }
                    Toggle("7-Point Tiebreak at 6–6", isOn: $tiebreakAtSixAll)
                    Picker("Match Status", selection: $matchStatus) {
                        ForEach(MatchStatus.allCases) { st in
                            Text(st.rawValue).tag(st)
                        }
                    }

                    ForEach($editableSets) { $setItem in
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Set \(setItem.setNumber)")
                                .font(.caption.weight(.bold))
                            HStack {
                                Stepper("You: \(setItem.playerGames)", value: $setItem.playerGames, in: 0...20)
                                Stepper("Opp: \(setItem.opponentGames)", value: $setItem.opponentGames, in: 0...20)
                            }
                            .font(.caption.monospacedDigit())
                        }
                    }

                    HStack {
                        if editableSets.count < bestOfSets {
                            Button("Add Set") {
                                editableSets.append(SetScoreSnapshot(setNumber: editableSets.count + 1, playerGames: 6, opponentGames: 4))
                            }
                        }
                        Spacer()
                        if editableSets.count > 1 {
                            Button("Remove Last Set", role: .destructive) {
                                _ = editableSets.popLast()
                            }
                        }
                    }
                }

                Section("Serve Performance") {
                    Stepper("First Serves Made: \(stats.firstServesMade)", value: $stats.firstServesMade, in: 0...500)
                    Stepper("First Serve Attempts: \(stats.firstServeAttempts)", value: $stats.firstServeAttempts, in: 0...500)
                    HStack {
                        Text("Calculated First-Serve %")
                        Spacer()
                        Text(stats.firstServePercentage.map { String(format: "%.1f%%", $0) } ?? "— (Enter attempts)")
                            .fontWeight(.bold)
                            .foregroundStyle(AppTheme.courtGreen)
                    }
                    Stepper("Second Serves Made: \(stats.secondServesMade)", value: $stats.secondServesMade, in: 0...300)
                    Stepper("Second Serve Attempts: \(stats.secondServeAttempts)", value: $stats.secondServeAttempts, in: 0...300)
                    Stepper("Aces: \(stats.aces)", value: $stats.aces, in: 0...150)
                    Stepper("Double Faults: \(stats.doubleFaults)", value: $stats.doubleFaults, in: 0...150)
                }

                Section("Shotmaking, Net & Break Points") {
                    Stepper("Winners: \(stats.winners)", value: $stats.winners, in: 0...300)
                    Stepper("Unforced Errors: \(stats.unforcedErrors)", value: $stats.unforcedErrors, in: 0...300)
                    Stepper("Forehand Errors: \(stats.forehandErrors)", value: $stats.forehandErrors, in: 0...300)
                    Stepper("Backhand Errors: \(stats.backhandErrors)", value: $stats.backhandErrors, in: 0...300)
                    Stepper("Net Points Won: \(stats.netPointsWon)", value: $stats.netPointsWon, in: 0...200)
                    Stepper("Net Approaches: \(stats.netPointsApproached)", value: $stats.netPointsApproached, in: 0...200)
                    Stepper("Break Points Converted: \(stats.breakPointsConverted)", value: $stats.breakPointsConverted, in: 0...100)
                    Stepper("Break Point Chances: \(stats.breakPointOpportunities)", value: $stats.breakPointOpportunities, in: 0...100)
                    Stepper("Break Points Saved: \(stats.breakPointsSaved)", value: $stats.breakPointsSaved, in: 0...100)
                    Stepper("Break Points Faced: \(stats.breakPointsFaced)", value: $stats.breakPointsFaced, in: 0...100)
                    Stepper("Total Points Won: \(stats.totalPointsWon)", value: $stats.totalPointsWon, in: 0...600)
                    Stepper("Opponent Points Won: \(stats.opponentTotalPointsWon)", value: $stats.opponentTotalPointsWon, in: 0...600)
                }

                Section("Notes") {
                    TextField("Post-match analysis notes...", text: $notes, axis: .vertical)
                        .lineLimit(3...6)
                }
            }
            .navigationTitle(existingMatch == nil ? "Log Match Analysis" : "Edit Match Analysis")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveValidatedMatch()
                    }
                    .accessibilityIdentifier("manualStats.saveButton")
                }
            }
            .onAppear(perform: loadExistingIfPresent)
        }
    }

    private func loadExistingIfPresent() {
        guard let m = existingMatch else {
            playerName = defaultPlayerName
            return
        }
        playerName = m.playerName
        partnerName = m.partnerName
        opponentName = m.opponentName
        opponentPartnerName = m.opponentPartnerName
        isDoubles = m.isDoubles
        matchDate = m.matchDate
        location = m.location
        surface = m.surface
        bestOfSets = m.format.bestOfSets
        tiebreakAtSixAll = m.format.tiebreakAtSixAll
        durationMinutes = max(5, Int((m.durationSeconds / 60.0).rounded()))
        matchStatus = m.status
        notes = m.notes
        if !m.sets.isEmpty {
            editableSets = m.sets
        }
        stats = m.statistics
    }

    private func saveValidatedMatch() {
        let format = MatchFormatConfig(
            bestOfSets: bestOfSets,
            tiebreakAtSixAll: tiebreakAtSixAll,
            finalSetSuperTiebreak: false,
            noAdScoring: false
        )

        do {
            let validatedWinner = try MatchScoreValidator.validate(
                sets: editableSets,
                format: format,
                status: matchStatus
            )

            // Sync games won from set scores
            stats.totalGamesWon = editableSets.reduce(0) { $0 + $1.playerGames }
            stats.opponentTotalGamesWon = editableSets.reduce(0) { $0 + $1.opponentGames }
            stats.firstServesMade = min(stats.firstServesMade, max(stats.firstServesMade, stats.firstServeAttempts))
            if stats.firstServeAttempts < stats.firstServesMade {
                stats.firstServeAttempts = stats.firstServesMade
            }

            let finalizedSets = editableSets.map { s -> SetScoreSnapshot in
                var copy = s
                if copy.playerGames > copy.opponentGames { copy.winner = .player }
                else if copy.opponentGames > copy.playerGames { copy.winner = .opponent }
                if copy.playerGames == 7 && copy.opponentGames == 6 {
                    copy.isTiebreakSet = true
                    copy.tiebreakPlayerPoints = copy.tiebreakPlayerPoints ?? 7
                    copy.tiebreakOpponentPoints = copy.tiebreakOpponentPoints ?? 5
                } else if copy.opponentGames == 7 && copy.playerGames == 6 {
                    copy.isTiebreakSet = true
                    copy.tiebreakPlayerPoints = copy.tiebreakPlayerPoints ?? 5
                    copy.tiebreakOpponentPoints = copy.tiebreakOpponentPoints ?? 7
                }
                return copy
            }

            let summary = finalizedSets.map(\.displayScore).joined(separator: ", ")
            let cleanPlayer = playerName.trimmingCharacters(in: .whitespacesAndNewlines)
            let cleanOpponent = opponentName.trimmingCharacters(in: .whitespacesAndNewlines)

            if let target = existingMatch {
                target.playerName = cleanPlayer.isEmpty ? defaultPlayerName : cleanPlayer
                target.partnerName = partnerName
                target.opponentName = cleanOpponent.isEmpty ? "Opponent" : cleanOpponent
                target.opponentPartnerName = opponentPartnerName
                target.isDoubles = isDoubles
                target.matchDate = matchDate
                target.location = location
                target.surface = surface
                target.format = format
                target.status = matchStatus
                target.isPlayerWinner = validatedWinner.map { $0 == .player }
                target.sets = finalizedSets
                target.finalScoreSummary = summary
                target.durationSeconds = Double(durationMinutes * 60)
                target.statistics = stats
                target.notes = notes
            } else {
                let record = MatchRecord(
                    playerName: cleanPlayer.isEmpty ? defaultPlayerName : cleanPlayer,
                    partnerName: partnerName,
                    opponentName: cleanOpponent.isEmpty ? "Opponent" : cleanOpponent,
                    opponentPartnerName: opponentPartnerName,
                    isDoubles: isDoubles,
                    matchDate: matchDate,
                    location: location,
                    surface: surface,
                    status: matchStatus,
                    isPlayerWinner: validatedWinner.map { $0 == .player },
                    finalScoreSummary: summary,
                    durationSeconds: Double(durationMinutes * 60),
                    notes: notes,
                    format: format,
                    sets: finalizedSets,
                    statistics: stats
                )
                modelContext.insert(record)
            }

            try? modelContext.save()
            dismiss()
        } catch {
            validationErrorMessage = error.localizedDescription
        }
    }
}

