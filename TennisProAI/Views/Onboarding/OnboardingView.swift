import SwiftUI
import SwiftData

struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var profile: PlayerProfile
    let onComplete: () -> Void

    @State private var enteredName: String = ""
    @State private var selectedSkill: SkillLevel = .intermediate
    @State private var selectedHand: DominantHand = .right
    @State private var selectedBackhand: BackhandStyle = .twoHanded
    @State private var selectedSurface: CourtSurface = .hard

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.lg) {
                    // Hero Banner
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "figure.tennis")
                                .font(.system(size: 34, weight: .bold))
                                .foregroundStyle(AppTheme.opticLime)
                            Spacer()
                            BadgePill(text: "ON-DEVICE PRIVACY", icon: "lock.shield.fill", color: AppTheme.opticLime)
                        }

                        Text("Welcome to Tennis Pro AI")
                            .font(.largeTitle.weight(.heavy))
                            .foregroundStyle(.white)

                        Text("Record matches from your tripod, cut stroke highlights, track point-by-point scorecards, and inspect biomechanics locally on your iPhone.")
                            .font(.subheadline)
                            .foregroundStyle(.white.opacity(0.86))
                    }
                    .padding(AppSpacing.lg)
                    .background(AppTheme.heroGradient)
                    .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

                    // Player Setup Form
                    CourtCard {
                        VStack(alignment: .leading, spacing: 16) {
                            Text("Player Profile Setup")
                                .font(.headline.weight(.bold))

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Player Name")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                TextField("e.g. Jordan Taylor", text: $enteredName)
                                    .textFieldStyle(.roundedBorder)
                                    .accessibilityIdentifier("onboarding.nameField")
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Playing Level")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Picker("Playing Level", selection: $selectedSkill) {
                                    ForEach(SkillLevel.allCases) { level in
                                        Text(level.rawValue).tag(level)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(AppTheme.courtGreen)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Dominant Hand")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Picker("Dominant Hand", selection: $selectedHand) {
                                    ForEach(DominantHand.allCases) { hand in
                                        Text(hand.rawValue).tag(hand)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Backhand Technique")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Picker("Backhand Style", selection: $selectedBackhand) {
                                    ForEach(BackhandStyle.allCases) { style in
                                        Text(style.rawValue).tag(style)
                                    }
                                }
                                .pickerStyle(.segmented)
                            }

                            VStack(alignment: .leading, spacing: 6) {
                                Text("Primary Court Surface")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(.secondary)
                                Picker("Primary Court Surface", selection: $selectedSurface) {
                                    ForEach(CourtSurface.allCases) { surface in
                                        Text(surface.rawValue).tag(surface)
                                    }
                                }
                                .pickerStyle(.menu)
                                .tint(AppTheme.courtGreen)
                            }
                        }
                    }

                    // Permissions Explanation
                    CourtCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("Transparent Permissions", systemImage: "checkmark.shield.fill")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(AppTheme.courtGreen)
                            Text("Camera & Microphone access are requested only when you open the Record tab. Photos access is requested only when you export a video or highlight clip. Your videos remain on your iPhone.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }

                    PrimaryCourtButton("Step Onto the Court", systemImage: "arrow.right.circle.fill") {
                        let trimmed = enteredName.trimmingCharacters(in: .whitespacesAndNewlines)
                        profile.name = trimmed.isEmpty ? "Player" : trimmed
                        profile.skillLevel = selectedSkill
                        profile.dominantHand = selectedHand
                        profile.backhandStyle = selectedBackhand
                        profile.preferredSurface = selectedSurface
                        profile.hasCompletedOnboarding = true
                        try? modelContext.save()
                        onComplete()
                    }
                    .accessibilityIdentifier("onboarding.completeButton")
                }
                .padding(AppSpacing.md)
            }
            .background(AppTheme.primaryBackground.ignoresSafeArea())
            .onAppear {
                if profile.name != "Player" {
                    enteredName = profile.name
                }
                selectedSkill = profile.skillLevel
                selectedHand = profile.dominantHand
                selectedBackhand = profile.backhandStyle
                selectedSurface = profile.preferredSurface
            }
        }
    }
}

