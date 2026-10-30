import SwiftUI
import SwiftData

@main
struct TennisProAIApp: App {
    @State private var router = AppNavigationRouter()
    private let persistence = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            MainTabView()
                .environment(router)
                .modelContainer(persistence.container)
        }
    }
}

