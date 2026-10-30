import SwiftUI

// MARK: - Reusable Court Card Container

struct CourtCard<Content: View>: View {
    let padding: CGFloat
    @ViewBuilder let content: Content

    init(padding: CGFloat = AppSpacing.md, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppTheme.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.cardCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.cardCornerRadius, style: .continuous)
                    .strokeBorder(AppTheme.subtleBorder, lineWidth: 1)
            )
    }
}

// MARK: - Courtside Large Touch Buttons

struct PrimaryCourtButton: View {
    let title: String
    let systemImage: String?
    var tint: Color = AppTheme.courtGreen
    var isDisabled: Bool = false
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        tint: Color = AppTheme.courtGreen,
        isDisabled: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.isDisabled = isDisabled
        self.action = action
    }

    var body: some View {
        Button {
            HapticsManager.impact(.medium)
            action()
        } label: {
            HStack(spacing: 10) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.headline.weight(.semibold))
                }
                Text(title)
                    .font(.headline.weight(.bold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, minHeight: AppSpacing.courtsideTouchHeight)
            .padding(.horizontal, AppSpacing.md)
            .background(isDisabled ? Color.gray.opacity(0.45) : tint)
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.buttonCornerRadius, style: .continuous))
        }
        .disabled(isDisabled)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}

struct SecondaryCourtButton: View {
    let title: String
    let systemImage: String?
    var tint: Color = AppTheme.courtGreen
    let action: () -> Void

    init(
        _ title: String,
        systemImage: String? = nil,
        tint: Color = AppTheme.courtGreen,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
        self.action = action
    }

    var body: some View {
        Button {
            HapticsManager.impact(.light)
            action()
        } label: {
            HStack(spacing: 8) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                }
                Text(title)
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: 48)
            .padding(.horizontal, AppSpacing.md)
            .background(tint.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: AppSpacing.buttonCornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppSpacing.buttonCornerRadius, style: .continuous)
                    .strokeBorder(tint.opacity(0.35), lineWidth: 1)
            )
        }
        .accessibilityElement(children: .combine)
    }
}

// MARK: - Stat Metric Summary Card

struct StatMetricCard: View {
    let title: String
    let value: String
    let subtitle: String?
    let systemImage: String
    var accent: Color = AppTheme.courtGreen

    var body: some View {
        CourtCard(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: systemImage)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(accent)
                        .frame(width: 30, height: 30)
                        .background(accent.opacity(0.15))
                        .clipShape(Circle())
                    Spacer()
                }

                Text(value)
                    .font(.title2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.primary)
                    .minimumScaleFactor(0.75)
                    .lineLimit(1)

                Text(title)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(accent)
                        .lineLimit(1)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title): \(value). \(subtitle ?? "")")
    }
}

// MARK: - Badges, Section Headers, Demo Banner & Empty States

struct BadgePill: View {
    let text: String
    var icon: String? = nil
    var color: Color = AppTheme.courtGreen

    var body: some View {
        HStack(spacing: 4) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2.weight(.bold))
            }
            Text(text)
                .font(.caption2.weight(.bold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.16))
        .clipShape(Capsule())
    }
}

struct SectionHeaderView: View {
    let title: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.title3.weight(.bold))
                .foregroundStyle(.primary)
            Spacer()
            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Text(actionTitle)
                        Image(systemName: "chevron.right")
                            .font(.caption.weight(.bold))
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppTheme.courtGreen)
                    .frame(minHeight: 44)
                }
            }
        }
    }
}

struct DemoDataNoticeBanner: View {
    let onDismissDemo: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "sparkles.rectangle.stack.fill")
                .font(.title3)
                .foregroundStyle(AppTheme.opticLime)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("DEMONSTRATION PREVIEW")
                    .font(.caption.weight(.heavy))
                    .foregroundStyle(AppTheme.opticLime)
                Text("Sample activity is shown because you haven't recorded a match or video yet. Sample items never affect your actual statistics.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 4)

            Button("Hide", action: onDismissDemo)
                .font(.caption.weight(.bold))
                .foregroundStyle(AppTheme.courtGreen)
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Hide demonstration preview data")
        }
        .padding(14)
        .background(AppTheme.elevatedCardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppTheme.opticLime.opacity(0.45), lineWidth: 1)
        )
    }
}

struct EmptyStateCardView: View {
    let icon: String
    let title: String
    let message: String
    var buttonTitle: String? = nil
    var buttonIcon: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        CourtCard(padding: AppSpacing.lg) {
            VStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.system(size: 38, weight: .semibold))
                    .foregroundStyle(AppTheme.courtGreen)
                    .frame(width: 72, height: 72)
                    .background(AppTheme.courtGreen.opacity(0.14))
                    .clipShape(Circle())

                Text(title)
                    .font(.headline.weight(.bold))
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let buttonTitle, let action {
                    PrimaryCourtButton(buttonTitle, systemImage: buttonIcon, action: action)
                        .padding(.top, 4)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

struct ErrorRecoveryBanner: View {
    let message: String
    let recoverySuggestion: String?
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(AppTheme.liveRecordRed)
                .font(.title3)

            VStack(alignment: .leading, spacing: 4) {
                Text(message)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                if let recoverySuggestion, !recoverySuggestion.isEmpty {
                    Text(recoverySuggestion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            if let onDismiss {
                Button(action: onDismiss) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                        .frame(width: 44, height: 44)
                }
                .accessibilityLabel("Dismiss error banner")
            }
        }
        .padding(14)
        .background(AppTheme.liveRecordRed.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(AppTheme.liveRecordRed.opacity(0.45), lineWidth: 1)
        )
    }
}

