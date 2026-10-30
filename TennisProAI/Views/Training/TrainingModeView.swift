import SwiftUI
import SwiftData

struct TrainingModeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @Query(sort: \TrainingSession.sessionDate, order: .reverse) private var sessions: [TrainingSession]
    @Query(sort: \VideoRecording.recordedAt, order: .reverse) private var videos: [VideoRecording]

    @State private var showCreateSheet = false
    @State private var activeDrillSession: TrainingSession? = nil

    private var completedCount: Int {
        sessions.filter(\.isCompleted).count
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    // Progress Header
                    CourtCard {
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Practice & Drill Tracker")
                                    .font(.headline.weight(.bold))
                                Text("\(completedCount) of \(sessions.count) sessions completed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            PrimaryCourtButton("New Session", systemImage: "plus") {
                                showCreateSheet = true
                            }
                            .frame(maxWidth: 165)
                            .accessibilityIdentifier("training.newSessionButton")
                        }
                    }

                    if sessions.isEmpty {
                        EmptyStateCardView(
                            icon: "target",
                            title: "No Practice Sessions Scheduled",
                            message: "Create structured drills for Serve practice, Forehand/Backhand drills, Volleys, Footwork, Rally consistency, or Match simulation.",
                            buttonTitle: "Create Practice Session",
                            buttonIcon: "plus.circle.fill"
                        ) {
                            showCreateSheet = true
                        }
                    } else {
                        ForEach(sessions) { session in
                            Button {
                                activeDrillSession = session
                            } label: {
                                sessionRowCard(session)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(AppSpacing.md)
            }
            .background(AppTheme.primaryBackground.ignoresSafeArea())
            .navigationTitle("Training Mode")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showCreateSheet) {
                NewTrainingSessionSheet(videos: videos)
            }
            .sheet(item: $activeDrillSession) { session in
                LiveDrillExecutionSheet(session: session, videos: videos)
            }
        }
    }

    private func sessionRowCard(_ session: TrainingSession) -> some View {
        CourtCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    BadgePill(
                        text: session.drillType.rawValue,
                        icon: session.drillType.iconName,
                        color: session.isCompleted ? AppTheme.courtGreen : AppTheme.hardcourtBlue
                    )
                    if session.isCompleted {
                        BadgePill(text: "COMPLETED", icon: "checkmark", color: AppTheme.opticLime)
                    }
                    Spacer()
                    Text("\(session.plannedDurationMinutes) min")
                        .font(.caption.weight(.bold).monospacedDigit())
                        .foregroundStyle(.secondary)
                }

                Text(session.name)
                    .font(.headline.weight(.bold))
                    .foregroundStyle(.primary)

                Text(session.objective)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)

                HStack(spacing: 16) {
                    Text("Reps: \(session.completedRepetitions)/\(session.targetRepetitions)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                    Text("Score: \(session.achievedScore)/\(session.targetScore)")
                        .font(.caption2.weight(.bold).monospacedDigit())
                    if session.linkedVideoID != nil {
                        Label("Video Linked", systemImage: "video.fill")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(AppTheme.courtGreen)
                    }
                }
                .foregroundStyle(.secondary)

                ProgressView(value: session.repetitionProgress)
                    .tint(AppTheme.courtGreen)
            }
        }
    }
}

private struct NewTrainingSessionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let videos: [VideoRecording]

    @State private var name: String = ""
    @State private var drillType: TrainingDrillType = .servePractice
    @State private var objective: String = TrainingDrillType.servePractice.defaultObjective
    @State private var durationMinutes: Int = 45
    @State private var targetReps: Int = 60
    @State private var targetScore: Int = 40
    @State private var notes: String = ""
    @State private var linkedVideoID: UUID? = nil

    var body: some View {
        NavigationStack {
            Form {
                Section("Drill Focus") {
                    Picker("Practice Category", selection: $drillType) {
                        ForEach(TrainingDrillType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .onChange(of: drillType) { _, newValue in
                        if name.isEmpty {
                            objective = newValue.defaultObjective
                        }
                    }

                    TextField("Session Name (e.g. Morning First-Serve Targets)", text: $name)
                        .accessibilityIdentifier("training.sessionNameField")
                    TextField("Training Objective", text: $objective, axis: .vertical)
                        .lineLimit(2...4)
                }

                Section("Targets") {
                    Stepper("Duration: \(durationMinutes) min", value: $durationMinutes, in: 10...240, step: 5)
                    Stepper("Target Repetitions: \(targetReps)", value: $targetReps, in: 5...1000, step: 5)
                    Stepper("Target Score: \(targetScore)", value: $targetScore, in: 1...1000, step: 5)
                }

                if !videos.isEmpty {
                    Section("Associate Training Video (Optional)") {
                        Picker("Video", selection: $linkedVideoID) {
                            Text("None").tag(UUID?.none)
                            ForEach(videos) { v in
                                Text(v.title).tag(UUID?.some(v.id))
                            }
                        }
                    }
                }

                Section("Notes") {
                    TextField("Drill setup or coach instructions...", text: $notes, axis: .vertical)
                        .lineLimit(2...5)
                }
            }
            .navigationTitle("New Practice Session")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
                        let session = TrainingSession(
                            name: cleanName.isEmpty ? drillType.rawValue : cleanName,
                            drillType: drillType,
                            objective: objective,
                            plannedDurationMinutes: durationMinutes,
                            targetRepetitions: targetReps,
                            targetScore: targetScore,
                            notes: notes,
                            linkedVideoID: linkedVideoID
                        )
                        modelContext.insert(session)
                        try? modelContext.save()
                        dismiss()
                    }
                    .accessibilityIdentifier("training.confirmCreateButton")
                }
            }
        }
    }
}

private struct LiveDrillExecutionSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Bindable var session: TrainingSession
    let videos: [VideoRecording]

    var body: some View {
        NavigationStack {
            Form {
                Section("Objective") {
                    Text(session.objective)
                        .font(.subheadline)
                }

                Section("Live Progress Tracking") {
                    Stepper("Completed Reps: \(session.completedRepetitions) / \(session.targetRepetitions)", value: $session.completedRepetitions, in: 0...2000)
                    HStack(spacing: 10) {
                        Button("+5 Reps") { session.completedRepetitions += 5 }
                            .buttonStyle(.bordered)
                        Button("+10 Reps") { session.completedRepetitions += 10 }
                            .buttonStyle(.bordered)
                    }

                    Stepper("Achieved Score: \(session.achievedScore) / \(session.targetScore)", value: $session.achievedScore, in: 0...2000)
                    Stepper("Actual Minutes: \(session.actualDurationMinutes)", value: $session.actualDurationMinutes, in: 0...300, step: 5)
                    Toggle("Session Completed", isOn: $session.isCompleted)
                        .tint(AppTheme.courtGreen)
                }

                Section("Associated Training Video") {
                    Picker("Training Video", selection: $session.linkedVideoID) {
                        Text("None").tag(UUID?.none)
                        ForEach(videos) { v in
                            Text(v.title).tag(UUID?.some(v.id))
                        }
                    }
                }

                Section("Session Notes") {
                    TextField("Notes...", text: $session.notes, axis: .vertical)
                        .lineLimit(2...5)
                }

                Section {
                    Button("Delete Practice Session", role: .destructive) {
                        modelContext.delete(session)
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
            .navigationTitle(session.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if session.isCompleted && session.actualDurationMinutes == 0 {
                            session.actualDurationMinutes = session.plannedDurationMinutes
                        }
                        try? modelContext.save()
                        dismiss()
                    }
                }
            }
        }
    }
}

