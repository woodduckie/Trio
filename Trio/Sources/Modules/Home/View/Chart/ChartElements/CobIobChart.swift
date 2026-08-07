import Charts
import Foundation
import SwiftUI

extension MainChartCanvas {
    var cobIobChart: some View {
        Chart {
            drawCurrentTimeMarker()
            drawCOBIOBChart()
            drawIobProjection()
        }
        .chartLegend(.hidden)
        .frame(width: canvasWidth, height: cobIobHeight)
        .chartXScale(domain: windowStart ... windowEnd)
        .chartXAxis { basalChartXAxis }
        .chartYAxis { cobIobChartYAxis }
        .chartYScale(domain: combinedYDomain())
    }

    func combinedYDomain() -> ClosedRange<Double> {
        MainChartHelper.cobIobYDomain(
            minCob: state.minValueCobChart,
            maxCob: state.maxValueCobChart,
            minIob: state.minValueIobChart,
            maxIob: state.maxValueIobChart
        )
    }

    func drawCOBIOBChart() -> some ChartContent {
        // Filter out duplicate entries by `deliverAt`,
        // We sometimes get two determinations when editing carbs, one without the entry-to-be-edited and then another one after editing the entry.
        // We are fetching determinations in descending order, so the first one is the latter determination (with correct amounts), so keeping the first one encountered.
        var seenDates = Set<Date>()
        let filteredDeterminations = windowedDeterminations.filter { item in
            if let date = item.deliverAt {
                if seenDates.contains(date) {
                    // Already seen this date – filter it out.
                    return false
                } else {
                    seenDates.insert(date)
                    return true
                }
            }
            return true
        }

        return ForEach(filteredDeterminations) { item in

            // MARK: - COB line and area mark

            let amountCOB = Int(item.cob)
            let date: Date = item.deliverAt ?? Date()

            // Fixed styles + explicit series identity replace foregroundStyle(by:)/
            // position(by:), which dragged every mark through scale resolution.
            LineMark(x: .value("Time", date), y: .value("Value", amountCOB), series: .value("Series", "COB"))
                .foregroundStyle(Color.orange)
            AreaMark(
                x: .value("Time", date),
                y: .value("Value", amountCOB),
                series: .value("Series", "COB"),
                stacking: .unstacked
            )
            .foregroundStyle(Color.orange)
            .opacity(0.2)

            // MARK: - IOB line and area mark

            let rawAmount = item.iob?.doubleValue ?? 0
            let amountIOB: Double = MainChartHelper.scaledIobAmount(rawAmount)

            AreaMark(
                x: .value("Time", date),
                y: .value("Amount", amountIOB),
                series: .value("Series", "IOB"),
                stacking: .unstacked
            )
            .foregroundStyle(Color.darkerBlue)
            .opacity(0.2)
            LineMark(x: .value("Time", date), y: .value("Amount", amountIOB), series: .value("Series", "IOB"))
                .foregroundStyle(Color.darkerBlue)
        }
    }

    // MARK: - Projected IOB decay (dashed, from latest determination into the future)

    func drawIobProjection() -> some ChartContent {
        // stale projections (older than the newest determination) render nothing
        let anchor = state.enactedAndNonEnactedDeterminations.first?.deliverAt ?? state.timerDate

        return ForEach(state.iobProjection.filter { $0.date >= anchor && $0.date <= windowEnd }) { point in
            let amount = MainChartHelper.scaledIobAmount(point.iob)

            AreaMark(
                x: .value("Time", point.date),
                y: .value("Amount", amount),
                series: .value("Series", "IOBProjection"),
                stacking: .unstacked
            )
            .foregroundStyle(Color.darkerBlue)
            .opacity(0.1)
            LineMark(
                x: .value("Time", point.date),
                y: .value("Amount", amount),
                series: .value("Series", "IOBProjection")
            )
            .foregroundStyle(Color.darkerBlue.opacity(0.8))
            .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
        }
    }
}
