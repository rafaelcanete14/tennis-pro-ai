import Foundation
import Observation

@MainActor
@Observable
final class AppNavigationRouter {
    var selectedTab: AppTab = .home
    var showNewMatchScorecardSheet: Bool = false
    var showTrainingHubSheet: Bool = false
    var showAIAnalysisLabSheet: Bool = false
    var preselectedRecordingForAI: VideoRecording? = nil
    var preselectedRecordingForEditor: VideoRecording? = nil

    func navigateToRecord() {
        selectedTab = .record
    }

    func navigateToVideos() {
        selectedTab = .videos
    }

    func navigateToStatistics() {
        selectedTab = .statistics
    }

    func openNewScorecard() {
        showNewMatchScorecardSheet = true
    }

    func openTrainingHub() {
        showTrainingHubSheet = true
    }

    func openAIAnalysis(for recording: VideoRecording? = nil) {
        preselectedRecordingForAI = recording
        showAIAnalysisLabSheet = true
    }
}

