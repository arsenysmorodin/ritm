import Charts
import SwiftUI

struct PulsePanel: View {
    let points: [PulsePoint]
    var live = false
    var now = Date.now
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        if let summary = PulseSummary(points) {
            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Пульс", systemImage: "heart").font(Theme.sectionTitle)
                        .accessibilityAddTraits(.isHeader)
                    if live {
                        let fresh = points.last.map { now.timeIntervalSince($0.date) < 30 } ?? false
                        Text(fresh ? "\(summary.latest) уд/мин" : "Ожидаем свежий замер")
                            .font(Theme.number)
                    }
                    let layout = textSize >= .xxxLarge
                        ? AnyLayout(VStackLayout(alignment: .leading, spacing: Theme.Space.sm)) : AnyLayout(HStackLayout(spacing: Theme.Space.md))
                    layout {
                        number("Средний", summary.average)
                        number("Мин.", summary.minimum)
                        number("Пик", summary.maximum)
                    }
                    Chart(points) { point in
                        LineMark(x: .value("Время", point.date), y: .value("Уд/мин", point.bpm)).foregroundStyle(Theme.reference)
                        if points.count == 1 {
                            PointMark(x: .value("Время", point.date), y: .value("Уд/мин", point.bpm)).foregroundStyle(Theme.reference)
                        }
                    }
                    .chartYScale(domain: (summary.minimum - 5)...(summary.maximum + 5))
                    .trendAxes(showsTime: true)
                    .frame(height: live ? 90 : 140)
                    .accessibilityLabel("График пульса в ударах в минуту")
                    Text("\(points.count) замеров · уд/мин").font(.caption).foregroundStyle(Theme.secondary)
                }
                .privacySensitive()
            }
        }
    }

    private func number(_ title: String, _ bpm: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(Theme.secondary)
            Text(bpm.formatted()).font(.headline).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
