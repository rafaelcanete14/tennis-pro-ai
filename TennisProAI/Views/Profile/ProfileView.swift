import SwiftUI
import SwiftData

struct ProfileView: View {
    @Environment(AppNavigationRouter.self) private var router
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \PlayerProfile.createdAt) private var profiles: [PlayerProfile]
    @Query private var recordings: [VideoRecording]
    @Query private var clips: [VideoClip]
    @Query private var matches: [MatchRecord]
    @Query private var trainings: [TrainingSession]

    @State private var backupShareURL: URL? = nil
    @State private var showDeleteAllDataDialog: Bool = false
    @State private var statusBanner: String? = nil
    @State private var errorMessage: String? = nil

    private var profile: PlayerProfile {
        profiles.first ?? PersistenceController.ensurePrimaryProfile(in: modelContext)
    }

    private var formattedStorageUsed: String {
        let bytes = VideoStorageService.shared.totalManagedStorageBytes()
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    var body: some View {
        @Bindable var boundProfile = profile

        NavigationStack {
            Form {
                if let banner = statusBanner {
                    Section {
                        Label(banner, systemImage: "checkmark.circle.fill")
                            .foregroundStyle(AppTheme.courtGreen)
                            .font(.caption.weight(.semibold))
                    }
                }

                if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundStyle(AppTheme.liveRecordRed)
                            .font(.caption)
                    }
                }

                Section("Player Identity") {
                    TextField("Player Name", text: $boundProfile.name)
                        .onChange(of: boundProfile.name) { _, _ in try? modelContext.save() }

                    Picker("Skill Level", selection: Binding(
                        get: { profile.skillLevel },
                        set: { profile.skillLevel = $0; try? modelContext.save() }
                    )) {
                        ForEach(SkillLevel.allCases) { level in
                            Text(level.rawValue).tag(level)
                        }
                    }

                    Picker("Dominant Hand", selection: Binding(
                        get: { profile.dominantHand },
                        set: { profile.dominantHand = $0; try? modelContext.save() }
                    )) {
                        ForEach(DominantHand.allCases) { hand in
                            Text(hand.rawValue).tag(hand)
                        }
                    }

                    Picker("Backhand Style", selection: Binding(
                        get: { profile.backhandStyle },
                        set: { profile.backhandStyle = $0; try? modelContext.save() }
                    )) {
                        ForEach(BackhandStyle.allCases) { bh in
                            Text(bh.rawValue).tag(bh)
                        }
                    }

                    Picker("Preferred Surface", selection: Binding(
                        get: { profile.preferredSurface },
                        set: { profile.preferredSurface = $0; try? modelContext.save() }
                    )) {
                        ForEach(CourtSurface.allCases) { s in
                            Text(s.rawValue).tag(s)
                        }
                    }

                    Stepper(
                        "Weekly Goal: \(boundProfile.weeklyTrainingGoalMinutes) min",
                        value: $boundProfile.weeklyTrainingGoalMinutes,
                        in: 30...1200,
                        step: 15
                    )
                    .onChange(of: boundProfile.weeklyTrainingGoalMinutes) { _, _ in try? modelContext.save() }
                }

                Section("Appearance & Dashboard Preferences") {
                    Picker("Theme", selection: Binding(
                        get: { profile.themePreference },
                        set: { profile.themePreference = $0; try? modelContext.save() }
                    )) {
                        ForEach(AppThemePreference.allCases) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }

                    Toggle("Show Sample Preview When Empty", isOn: $boundProfile.showDemoDataWhenEmpty)
                        .tint(AppTheme.courtGreen)
                        .onChange(of: boundProfile.showDemoDataWhenEmpty) { _, _ in try? modelContext.save() }
                }

                Section("Modules") {
                    Button {
                        router.openNewScorecard()
                    } label: {
                        Label("Match Scorecards (\(matches.count))", systemImage: "list.number")
                    }

                    Button {
                        router.openTrainingHub()
                    } label: {
                        Label("Training Mode (\(trainings.count))", systemImage: "target")
                    }

                    Button {
                        router.openAIAnalysis(for: recordings.first)
                    } label: {
                        Label("AI Tennis Vision Lab", systemImage: "viewfinder.circle")
                    }
                }

                Section("Local Storage, Backup & Privacy") {
                    HStack {
                        Text("Managed Video & Clip Storage")
                        Spacer()
                        Text(formattedStorageUsed)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }

                    HStack {
                        Text("Stored Records")
                        Spacer()
                        Text("\(recordings.count) videos • \(clips.count) clips • \(matches.count) matches")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Button {
                        do {
                            backupShareURL = try DataBackupService.exportBackupFile(context: modelContext)
                            statusBanner = "Backup JSON generated. Tap Share Backup below to export."
                        } catch {
                            errorMessage = error.localizedDescription
                        }
                    } label: {
                        Label("Generate Portable JSON Data Backup", systemImage: "arrow.down.doc.fill")
                    }

                    if let backupShareURL {
                        ShareLink(item: backupShareURL) {
                            Label("Share Backup Archive", systemImage: "square.and.arrow.up")
                        }
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Label("Offline-First & Private by Design", systemImage: "hand.raised.fill")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AppTheme.courtGreen)
                        Text("All match recordings, trimmed highlights, Vision pose analyses, and scorecards stay locally on your iPhone. No private videos are uploaded to external servers.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)

                    Button(role: .destructive) {
                        showDeleteAllDataDialog = true
                    } label: {
                        Label("Delete All My Data & Videos...", systemImage: "trash.fill")
                    }
                    .accessibilityIdentifier("profile.deleteAllDataButton")
                }
            }
            .navigationTitle("Profile & Settings")
            .confirmationDialog(
                "Delete All Data Permanently?",
                isPresented: $showDeleteAllDataDialog,
                titleVisibility: .visible
            ) {
                Button("Delete All Videos, Clips, Matches & Profile", role: .destructive) {
                    do {
                        try PersistenceController.deleteAllUserData(
                            in: modelContext,
                            videoStorage: VideoStorageService.shared
                        )
                        backupShareURL = nil
                        statusBanner = "All local data and video files were permanently deleted."
                    } catch {
                        errorMessage = error.localizedDescription
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently erases every managed match video, highlight clip, scorecard, and training record on this iPhone.")
            }
        }
    }
}

