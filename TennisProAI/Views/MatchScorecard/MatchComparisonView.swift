import SwiftUI

struct MatchComparisonView: View {
    @Environment(\.dismiss) private var dismiss

    let primaryMatch: MatchRecord
    let candidateMatches: [MatchRecord]

    @State private var selectedBaselineID: UUID? = nil

    private var baselineMatch: MatchRecord? {
        if let id = selectedBaselineID {
            return candidateMatches.first(where: { $0.id == id })
        }
        return candidateMatches.first
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    CourtCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Compare Current Match Against")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)

                            Picker("Baseline Match", selection: $selectedBaselineID) {
                                ForEach(candidateMatches) { match in
                                    Text("vs \(match.opponentTeamDisplayName) (\(match.matchDate.formatted(date: .abbreviated, time: .omitted))) • \(match.finalScoreSummary)")
                                        .tag(UUID?.some(match.id))
                                }
                            }
                            .pickerStyle(.menu)
                        }
                    }

                    if let baselineMatch {
                        let deltas = StatisticsService.compareMatch(primaryMatch, against: baselineMatch)

                        CourtCard {
                            VStack(spacing: 12) {
                                HStack {
                                    Text("Metric")
                                        .font(.caption.weight(.heavy))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("Current")
                                        .font(.caption.weight(.heavy))
                                        .frame(width: 72, alignment: .trailing)
                                    Text("Previous")
                                        .font(.caption.weight(.heavy))
                                        .foregroundStyle(.secondary)
                                        .frame(width: 72, alignment: .trailing)
                                }

                                Divider()

                                ForEach(deltas) { row in
                                    HStack {
                                        Text(row.metricName)
                                            .font(.subheadline.weight(.medium))
                                        Spacer()
                                        HStack(spacing: 4) {
                                            if let fav = row.isFavorable {
                                                Image(systemName: fav ? "arrow.up.circle.fill" : "arrow.down.circle.fill")
                                                    .font(.caption2)
                                                    .foregroundStyle(fav ? AppTheme.courtGreen : AppTheme.clayAmber)
                                            }
                                            Text(row.primaryDisplay)
                                                .font(.subheadline.weight(.bold).monospacedDigit())
                                        }
                                        .frame(width: 82, alignment: .trailing)

                                        Text(row.baselineDisplay)
                                            .font(.subheadline.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                            .frame(width: 72, alignment: .trailing)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(AppSpacing.md)
            }
            .background(AppTheme.primaryBackground.ignoresSafeArea())
            .navigationTitle("Match Comparison")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear {
                if selectedBaselineID == nil {
                    selectedBaselineID = candidateMatches.first?.id
                }
            }
        }
    }
}

