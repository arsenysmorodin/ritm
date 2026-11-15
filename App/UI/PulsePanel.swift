import Charts
import SwiftUI

struct PulsePanel: View {
    let points: [PulsePoint]
    var live = false
    var now = Date.now

    var body: some View {
        if let summary = PulseSummary(points) {
            Panel {
                VStack(alignment: .leading, spacing: 10) {
                    Label("Пульс", systemImage: "heart.fill").font(.headline).foregroundStyle(Ink.peach)
                    if live {
                        let fresh = points.last.map { now.timeIntervalSince($0.date) < 30 } ?? false
                        Text(fresh ? "\(summary.latest) уд/мин" : "Ожидаем свежий замер")
                            .font(.title2.weight(.semibold)).monospacedDigit()
                    }
                    HStack(spacing: 12) {
                        number("Средний", summary.average)
                        Spacer(minLength: 0)
                        number("Мин.", summary.minimum)
                        Spacer(minLength: 0)
                        number("Пик", summary.maximum)
                    }
                    Chart(points) { point in
                        LineMark(x: .value("Время", point.date), y: .value("Уд/мин", point.bpm)).foregroundStyle(Ink.peach)
                        if points.count == 1 {
                            PointMark(x: .value("Время", point.date), y: .value("Уд/мин", point.bpm)).foregroundStyle(Ink.peach)
                        }
                    }
                    .chartYScale(domain: (summary.minimum - 5)...(summary.maximum + 5))
                    .chartXAxis {
                        AxisMarks(values: .automatic(desiredCount: 4)) {
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.hour().minute(), collisionResolution: .greedy)
                        }
                    }
                    .frame(height: live ? 90 : 140)
                    .accessibilityLabel("График пульса в ударах в минуту")
                    Text("\(points.count) замеров · уд/мин").font(.caption).foregroundStyle(Ink.muted)
                }
                .privacySensitive()
            }
        }
    }

    private func number(_ title: String, _ bpm: Int) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption).foregroundStyle(Ink.muted)
            Text(bpm.formatted()).font(.headline).monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }
}
