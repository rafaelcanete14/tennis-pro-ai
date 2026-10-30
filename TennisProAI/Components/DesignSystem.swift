import SwiftUI
import UIKit

// MARK: - Tennis Pro AI Design System

enum AppTheme {
    /// Championship emerald court green — readable in both dark and light mode.
    static let courtGreen = Color(red: 0.12, green: 0.68, blue: 0.42)
    /// High-visibility optic tennis ball accent for active states and highlights.
    static let opticLime = Color(red: 0.69, green: 0.91, blue: 0.20)
    /// Deep championship hardcourt teal-blue for secondary charts/badges.
    static let hardcourtBlue = Color(red: 0.16, green: 0.56, blue: 0.88)
    /// Clay terracotta accent.
    static let clayAmber = Color(red: 0.89, green: 0.46, blue: 0.24)
    /// Alert crimson for live REC indicators and destructive confirmations.
    static let liveRecordRed = Color(red: 0.94, green: 0.23, blue: 0.26)

    /// Adaptive background color supporting Dark (primary) and Light (optional) modes.
    static var primaryBackground: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.045, green: 0.075, blue: 0.090, alpha: 1.0)
                : UIColor(red: 0.955, green: 0.972, blue: 0.962, alpha: 1.0)
        })
    }

    static var cardBackground: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.085, green: 0.130, blue: 0.155, alpha: 1.0)
                : UIColor.white
        })
    }

    static var elevatedCardBackground: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(red: 0.120, green: 0.180, blue: 0.212, alpha: 1.0)
                : UIColor(red: 0.920, green: 0.948, blue: 0.932, alpha: 1.0)
        })
    }

    static var subtleBorder: Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor.white.withAlphaComponent(0.10)
                : UIColor.black.withAlphaComponent(0.08)
        })
    }

    static var heroGradient: LinearGradient {
        LinearGradient(
            colors: [
                Color(red: 0.08, green: 0.34, blue: 0.23),
                Color(red: 0.05, green: 0.16, blue: 0.18)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

enum AppSpacing {
    static let xs: CGFloat = 6
    static let sm: CGFloat = 10
    static let md: CGFloat = 16
    static let lg: CGFloat = 22
    static let xl: CGFloat = 30
    static let cardCornerRadius: CGFloat = 20
    static let buttonCornerRadius: CGFloat = 16
    /// Minimum courtside touch target height (exceeds Apple HIG 44pt minimum).
    static let courtsideTouchHeight: CGFloat = 54
}

enum HapticsManager {
    @MainActor
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .medium) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred()
    }

    @MainActor
    static func notification(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        let generator = UINotificationFeedbackGenerator()
        generator.prepare()
        generator.notificationOccurred(type)
    }
}

