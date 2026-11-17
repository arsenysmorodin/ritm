import SwiftUI
import WidgetKit

struct RecoveryEntry: TimelineEntry {
    let date: Date
    let snapshot: RecoverySnapshot?
    let palette: WidgetPalette
    let sleepGoal: Int

    static func live(at date: Date = .now) -> Self {
        Self(date: date, snapshot: WidgetStorage.load(RecoverySnapshot.self, file: RecoverySnapshot.file),
             palette: WidgetPalette(selection: widgetAccent()), sleepGoal: WidgetTargets.load().sleepMinutes)
    }
}

struct RecoveryTimeline: TimelineProvider {
    func placeholder(in context: Context) -> RecoveryEntry {
        let calendar = Calendar.current
        let now = Date.now
        let today = calendar.startOfDay(for: now)
        let morning = calendar.date(bySettingHour: 7, minute: 30, second: 0, of: now) ?? now
        let reference = morning <= now ? today : (calendar.date(byAdding: .day, value: -1, to: today) ?? today)
        let days = (-11...0).compactMap { offset -> RecoveryDay? in
            guard let day = calendar.date(byAdding: .day, value: offset, to: reference) else { return nil }
            let end = day.addingTimeInterval(Double(400 + (offset * offset % 80)) * 60)
            let phases: [(SleepPhase, Int)] = [(.core, 50), (.deep, 54), (.core, 76), (.rem, 46), (.awake, 12),
                                             (.core, 115 + offset % 8), (.deep, 25), (.core, 48), (.rem, 49)]
            let minutes = phases.reduce(0) { $0 + $1.1 }
            var start = end.addingTimeInterval(Double(-60 * minutes))
            let spans = phases.map { phase, length in
                let stop = start.addingTimeInterval(Double(length * 60))
                defer { start = stop }
                return SleepSpan(start: start, end: stop, phase: phase)
            }
            let night = SleepNight(day: day, sourceID: "example", sourceName: "Пример", spans: spans, inBedSeconds: Double((minutes + 22) * 60))
            let values: [RecoveryMetric: Double] = [.hrv: 48 + Double((offset + 4) % 7), .restingPulse: 59 + Double(offset % 4),
                                                     .sleepingPulse: 55, .respiration: 14.4, .oxygen: 97, .wristTemperature: 34.8]
            let readings = values.mapValues {
                RecoveryReading(date: end, value: $0, sourceID: "example", sourceName: "Пример", count: 1)
            }
            return RecoveryDay(date: day, sleep: night, readings: readings)
        }
        return RecoveryEntry(date: now, snapshot: RecoverySnapshot(days: days),
                             palette: WidgetPalette(selection: widgetAccent()), sleepGoal: WidgetTargets.load().sleepMinutes)
    }

    func getSnapshot(in context: Context, completion: @escaping (RecoveryEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : .live())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RecoveryEntry>) -> Void) {
        let current = RecoveryEntry.live()
        let calendar = Calendar.current
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: current.date))
            ?? current.date.addingTimeInterval(3600)
        let rollover = RecoveryEntry(date: midnight, snapshot: current.snapshot, palette: current.palette, sleepGoal: current.sleepGoal)
        completion(Timeline(entries: [current, rollover], policy: .after(min(midnight, current.date.addingTimeInterval(3600)))))
    }
}

extension RecoveryWidgetKind {
    fileprivate var title: String {
        switch self {
        case .recovery: "Восстановление"
        case .stages: "Сон · Продолжительность и фазы"
        case .measurements: "Сон · Показатели"
        case .schedule: "Сон · Регулярность"
        }
    }

    fileprivate var label: String {
        switch self {
        case .stages: "Сон и фазы"
        case .schedule: "Режим сна"
        case .measurements: "Показатели сна"
        case .recovery: title
        }
    }

    fileprivate var description: String {
        switch self {
        case .recovery: "Сон, ночная ВСР и пульс в покое с личными диапазонами."
        case .stages: "Продолжительность последнего сна, время подъёма и фазы."
        case .measurements: "Ночные замеры пульса, ВСР, дыхания, кислорода и температуры запястья."
        case .schedule: "Время засыпания и подъёма за семь дней."
        }
    }

    fileprivate var icon: String {
        switch self {
        case .recovery: "heart.text.square"
        case .stages: "bed.double"
        case .measurements: "waveform.path.ecg"
        case .schedule: "moon.stars"
        }
    }

    fileprivate var url: URL? {
        switch self {
        case .recovery: URL(string: "ritm://recovery")
        case .stages: URL(string: "ritm://sleep")
        case .measurements: URL(string: "ritm://sleep-vitals")
        case .schedule: URL(string: "ritm://sleep-schedule")
        }
    }
}

struct RecoveryWidget: Widget {
    var body: some WidgetConfiguration { recoveryConfiguration(.recovery) }
}

struct SleepStagesWidget: Widget {
    var body: some WidgetConfiguration { recoveryConfiguration(.stages) }
}

struct SleepMeasurementsWidget: Widget {
    var body: some WidgetConfiguration { recoveryConfiguration(.measurements) }
}

struct SleepScheduleWidget: Widget {
    var body: some WidgetConfiguration { recoveryConfiguration(.schedule) }
}

private func recoveryConfiguration(_ kind: RecoveryWidgetKind) -> some WidgetConfiguration {
    StaticConfiguration(kind: kind.rawValue, provider: RecoveryTimeline()) { entry in
        WidgetCard(palette: entry.palette) { RecoveryTileView(kind: kind, entry: entry) }
            .widgetURL(kind.url)
    }
    .configurationDisplayName(kind.title)
    .description(kind.description)
    .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
}

private struct RecoveryTileView: View {
    @Environment(\.widgetFamily) private var family
    let kind: RecoveryWidgetKind
    let entry: RecoveryEntry

    private var small: Bool { family == .systemSmall }
    private var large: Bool { family == .systemLarge }
    private var palette: WidgetPalette { entry.palette }

    var body: some View {
        VStack(alignment: .leading, spacing: large ? 11 : 5) {
            WidgetHeader(title: kind.label, icon: kind.icon, palette: palette)
            if let snapshot = entry.snapshot {
                switch kind {
                case .recovery: recovery(snapshot)
                case .stages: stages(snapshot.recentNight(at: entry.date)?.sleep)
                case .measurements: vitals(snapshot.recentNight(at: entry.date))
                case .schedule: schedule(snapshot.schedule(endingAt: entry.date))
                }
            } else {
                empty("Подключите Apple «Здоровье» в «Ритме».")
            }
        }
        .privacySensitive()
    }

    @ViewBuilder private func recovery(_ snapshot: RecoverySnapshot) -> some View {
        if let day = snapshot.recentDay(at: entry.date) {
            HStack(alignment: .firstTextBaseline) {
                Text(SleepText.shortDate(day.date)).font(.caption2).foregroundStyle(palette.secondary)
                if !small, let night = day.sleep {
                    Spacer(minLength: 5)
                    Text("Сон · " + SleepText.duration(night.sleptSeconds))
                        .font(.subheadline.weight(.semibold)).lineLimit(1).minimumScaleFactor(0.7)
                }
            }
            if let night = day.sleep {
                if small {
                    WidgetNumber(value: SleepText.duration(night.sleptSeconds), palette: palette, size: .title2)
                } else {
                    goalProgress(night, showLabel: large)
                }
            } else {
                Text("Нет записи сна").font(.caption2).foregroundStyle(palette.secondary)
            }

            Spacer(minLength: 0)
            if small {
                compactMetric("ВСР", metric: .hrv, day: day)
                compactMetric("Пульс в покое", metric: .restingPulse, day: day)
            } else {
                HStack(alignment: .top, spacing: 10) {
                    comparable(.hrv, day: day, snapshot: snapshot)
                    comparable(.restingPulse, day: day, snapshot: snapshot)
                }
                if large {
                    WidgetRule(palette: palette)
                    comparable(.respiration, day: day, snapshot: snapshot)
                    Text("Диапазоны по предыдущим 28 дням · минимум 7 дней с одного источника.")
                        .font(.caption).foregroundStyle(palette.secondary)
                }
            }
            Spacer(minLength: 0)
        } else {
            empty("Нет недавней записи сна или пульса в покое.")
        }
    }

    @ViewBuilder private func stages(_ night: SleepNight?) -> some View {
        if let night {
            let layout = small ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 8))
            layout {
                WidgetNumber(value: SleepText.duration(night.sleptSeconds), palette: palette, size: small ? .title3 : .title2)
                Text(SleepText.shortDate(night.day) + " · " + SleepText.period(night))
                    .font(.caption2).foregroundStyle(palette.secondary).lineLimit(1).minimumScaleFactor(0.7)
            }
            if small {
                Spacer(minLength: 0)
                if night.stagedSeconds > 0 {
                    phaseRow(.deep, night: night)
                    phaseRow(.rem, night: night, label: "REM")
                } else {
                    Text("Без разбивки по фазам").font(.caption2).foregroundStyle(palette.secondary)
                }
                Spacer(minLength: 0)
            } else if night.stagedSeconds > 0 {
                WidgetRule(palette: palette)
                SleepPhaseChart(night: night, accent: palette.accent, secondary: palette.secondary)
                    .frame(maxHeight: .infinity)
                if large {
                    ForEach([SleepPhase.deep, .core, .rem, .awake]) { phase in phaseRow(phase, night: night) }
                    goalProgress(night)
                }
            } else {
                empty("Источник записал длительность сна без фаз.")
            }
        } else {
            empty("Нет недавней записи сна.")
        }
    }

    @ViewBuilder private func vitals(_ day: RecoveryDay?) -> some View {
        if let day {
            Text(SleepText.shortDate(day.date)).font(.caption2).foregroundStyle(palette.secondary)
            Spacer(minLength: 0)
            if small {
                compactMetric("ВСР", metric: .hrv, day: day)
                compactMetric("Пульс во сне", metric: .sleepingPulse, day: day)
                compactMetric("Дыхание", metric: .respiration, day: day)
            } else {
                let columns = Array(repeating: GridItem(.flexible(), spacing: 6, alignment: .leading), count: large ? 2 : 3)
                LazyVGrid(columns: columns, alignment: .leading, spacing: large ? 14 : 5) {
                    metricCell("Ночная ВСР", metric: .hrv, day: day)
                    metricCell("Пульс во сне", metric: .sleepingPulse, day: day)
                    metricCell("Дыхание", metric: .respiration, day: day)
                    metricCell("Кислород", metric: .oxygen, day: day)
                    metricCell("Темп. запястья", metric: .wristTemperature, day: day)
                    metricCell("Пульс в покое", metric: .restingPulse, day: day)
                }
                if large, let night = day.sleep {
                    WidgetRule(palette: palette)
                    if let awake = night.phaseSeconds(.awake) {
                        phaseRow(.awake, night: night)
                            .accessibilityLabel("Записанное бодрствование")
                            .accessibilityValue(SleepText.duration(awake))
                    }
                    if let efficiency = night.efficiency {
                        HStack {
                            Text("Доля сна в постели")
                            Spacer(minLength: 5)
                            Text(efficiency.formatted(.percent.precision(.fractionLength(0)))).fontWeight(.semibold)
                        }.font(.subheadline).accessibilityElement(children: .combine)
                    }
                    Text("Показатели доступны по мере записи устройством.")
                        .font(.caption).foregroundStyle(palette.secondary)
                }
            }
            Spacer(minLength: 0)
        } else {
            empty("Ночные замеры появятся вместе с записью сна.")
        }
    }

    @ViewBuilder private func schedule(_ schedule: SleepSchedule) -> some View {
        if schedule.nights > 0 {
            Text("\(schedule.nights) из 7 с записью").font(.caption2).foregroundStyle(palette.secondary)
            WidgetRule(palette: palette)
            SleepScheduleChart(schedule: schedule, accent: palette.accent, secondary: palette.secondary, compact: small)
                .frame(maxHeight: .infinity)
            if !small {
                if large {
                    spread("Разброс засыпания", value: schedule.onsetSpread)
                    spread("Разброс подъёма", value: schedule.wakeSpread)
                    Text("Столбец — от засыпания до подъёма. Точка — без записи.")
                        .font(.caption).foregroundStyle(palette.secondary)
                } else {
                    Text("От засыпания до подъёма").font(.caption2).foregroundStyle(palette.secondary)
                }
            }
        } else {
            empty("За последние семь дней нет записей сна.")
        }
    }

    private func comparable(_ metric: RecoveryMetric, day: RecoveryDay, snapshot: RecoverySnapshot) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            metricCell(metric.shortTitle, metric: metric, day: day)
            if let reading = day.readings[metric] {
                let range = snapshot.range(for: metric, on: day)
                Text(range.map { $0.position(for: reading.value).title } ?? "Мало данных для сравнения")
                    .font(.caption2).foregroundStyle(palette.secondary).lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private func metricCell(_ label: String, metric: RecoveryMetric, day: RecoveryDay) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(palette.secondary).lineLimit(1).minimumScaleFactor(0.7)
            WidgetNumber(value: day.readings[metric].map { metric.formatted($0.value) } ?? "—",
                         palette: palette, size: large ? .title3 : .subheadline)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue(day.readings[metric].map { metric.formatted($0.value) } ?? "Нет данных")
    }

    private func compactMetric(_ label: String, metric: RecoveryMetric, day: RecoveryDay) -> some View {
        HStack(spacing: 4) {
            Text(label).foregroundStyle(palette.secondary)
            Spacer(minLength: 0)
            Text(day.readings[metric].map { metric.formatted($0.value) } ?? "—").fontWeight(.semibold).monospacedDigit()
        }
        .font(.caption2).lineLimit(1).minimumScaleFactor(0.65)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(metric.title)
        .accessibilityValue(day.readings[metric].map { metric.formatted($0.value) } ?? "Нет данных")
    }

    private func phaseRow(_ phase: SleepPhase, night: SleepNight, label: String? = nil) -> some View {
        HStack(spacing: 5) {
            Text(label ?? phase.title).foregroundStyle(palette.secondary)
            Spacer(minLength: 0)
            Text(night.phaseSeconds(phase).map(SleepText.duration) ?? "—").fontWeight(.semibold).monospacedDigit()
        }
        .font(large ? .subheadline : .caption2).lineLimit(1).minimumScaleFactor(0.7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(phase.title)
        .accessibilityValue(night.phaseSeconds(phase).map(SleepText.duration) ?? "Нет данных")
    }

    private func spread(_ label: String, value: Int?) -> some View {
        HStack {
            Text(label).foregroundStyle(palette.secondary)
            Spacer(minLength: 5)
            Text(value.map(SleepText.duration(minutes:)) ?? "Нужны 2 ночи").fontWeight(.semibold)
        }
        .font(.subheadline).accessibilityElement(children: .combine)
    }

    private func goalProgress(_ night: SleepNight, showLabel: Bool = true) -> some View {
        let goal = max(1, Double(entry.sleepGoal) * 60)
        return VStack(alignment: .leading, spacing: 2) {
            WidgetProgressStrip(value: night.sleptSeconds, total: goal, palette: palette)
            if showLabel {
                Text("Цель · " + SleepText.duration(minutes: entry.sleepGoal))
                    .font(.caption).foregroundStyle(palette.secondary)
            }
        }
    }

    private func empty(_ text: String) -> some View {
        WidgetEmpty(text: text, palette: palette)
    }
}
