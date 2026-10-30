import SwiftUI
import SwiftData

struct MainTabView: View {
    @Environment(AppNavigationRouter.self) private var router
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \PlayerProfile.createdAt) private var profiles: [PlayerProfile]

    @State private var showOnboarding: Bool = false

    private var activeProfile: PlayerProfile {
        profiles.first ?? PersistenceController.ensurePrimaryProfile(in: modelContext)
    }

    var body: some View {
        @Bindable var nav = router

        TabView(selection: $nav.selectedTab) {
            DashboardView()
                .tabItem {
                    Label(AppTab.home.title, systemImage: AppTab.home.systemImage)
                }
                .tag(AppTab.home)

            RecordingView()
                .tabItem {
                    Label(AppTab.record.title, systemImage: AppTab.record.systemImage)
                }
                .tag(AppTab.record)

            VideoLibraryView()
                .tabItem {
                    Label(AppTab.videos.title, systemImage: AppTab.videos.systemImage)
                }
                .tag(AppTab.videos)

            StatisticsDashboardView()
                .tabItem {
                    Label(AppTab.statistics.title, systemImage: AppTab.statistics.systemImage)
                }
                .tag(AppTab.statistics)

            ProfileView()
                .tabItem {
                    Label(AppTab.profile.title, systemImage: AppTab.profile.systemImage)
                }
                .tag(AppTab.profile)
        }
        .tint(AppTheme.courtGreen)
        .preferredColorScheme(activeProfile.themePreference.colorScheme)
        .onAppear {
            let profile = PersistenceController.ensurePrimaryProfile(in: modelContext)
            if !profile.hasCompletedOnboarding {
                showOnboarding = true
            }
        }
        .fullScreenCover(isPresented: $showOnboarding) {
            OnboardingView(profile: activeProfile) {
                showOnboarding = false
            }
        }
        .sheet(isPresented: $nav.showNewMatchScorecardSheet) {
            MatchScorecardListView()
        }
        .sheet(isPresented: $nav.showTrainingHubSheet) {
            TrainingModeView()
        }
        .sheet(isPresented: $nav.showAIAnalysisLabSheet) {
            AIVideoAnalysisView(initialRecording: router.preselectedRecordingForAI)
        }
    }
}

