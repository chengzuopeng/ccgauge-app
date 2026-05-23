// OverviewPage.swift — the default popover body.
//
// Stack (per design §6.2):
//   ProviderRow (68pt) → RangeBar (28pt) → KpiGrid (84pt × 4) → Trend (~108pt chart)
//   → DistributionRow (flex 1)

import SwiftUI

struct OverviewPage: View {
    @ObservedObject var viewModel: PopoverViewModel

    var body: some View {
        VStack(spacing: 10) {
            ProviderRowView(viewModel: viewModel)
            RangeBarView(viewModel: viewModel)
            KpiGridView(viewModel: viewModel)
            TrendChartView(viewModel: viewModel)
            DistributionRowView(viewModel: viewModel)
        }
    }
}
