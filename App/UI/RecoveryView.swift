import Charts
import SwiftUI

enum RecoverySection: String, CaseIterable, Identifiable {
    case overview, sleep, vitals, regularity

    var id: Self { self }
    var title: String {
        switch self {
        case .overview: "Восстановление"
        case .sleep: "Сон"
        case .vitals: "Показатели"
        case .regularity: "Режим"
        }
    }
}

struct RecoveryView: View {
    let store: JournalStore
    let health: HealthConnection
    @Environment(\.ritmAccent) private var accent
    @State private var section: RecoverySection
    @State private var trendMetric: RecoveryMetric = .hrv
    @State private var trendDays = 7
    @State private var showGoal = false

    init(store: JournalStore, health: HealthConnection, section: RecoverySection) {
        self.store = store
        self.health = health
        _section = State(initialValue: section)
    }

    var body: some View {
        Page {
            PageHeader(title: section.title, caption: "Данные Apple «Здоровья»") {
                Button { showGoal = true } label: { IconBadge(icon: "target") }
                    .buttonStyle(PressStyle()).accessibilityLabel("Цель сна")
            }
            Picker("Раздел восстановления", selection: $section) {
                ForEach(RecoverySection.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.menu)
            .frame(minHeight: Theme.touch, alignment: .leading)

            if let error = health.recoveryError { Panel { StatusMessage(text: error) } }
            if !store.journal.healthEnabled || !health.isAvailable || health.additionalPermissionsPending {
                connection
            }

            if store.journal.healthEnabled && health.isAvailable {
                if let snapshot = health.recoverySnapshot, !snapshot.days.isEmpty {
                    sections(snapshot)
                } else if health.isReadingRecovery {
                    Panel { StatusMessage(text: "Загружаем сон и ночные показатели…", loading: true) }
                } else if health.recoveryError == nil {
                    HintPanel(icon: "moon.zzz", title: "Пока нет данных",
                              text: "Ночи и показатели появятся после синхронизации с Apple «Здоровьем». Проверьте разрешения на чтение сна и ночных замеров.")
                }
            }

            if section == .overview,
               !store.journal.healthEnabled || !health.isAvailable || health.recoverySnapshot?.days.isEmpty != false {
                checkIn
            }
        }
        .task { await health.refreshRecovery(store) }
        .refreshable { await health.refresh(store) }
        .sheet(isPresented: $showGoal) { SleepGoalEditor(store: store) }
    }

    private var connection: some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionHeading(title: "Apple «Здоровье»")
                Text(health.isAvailable
                     ? "Сон и ночные показатели появятся с разрешения на чтение."
                     : health.availabilityMessage)
                    .font(.subheadline).foregroundStyle(Theme.secondary)
                if health.isAvailable {
                    ActionButton(title: store.journal.healthEnabled ? "Разрешить данные сна" : "Подключить «Здоровье»",
                                 icon: "heart.text.square") {
                        Task { await health.connect(store) }
                    }.disabled(health.isBusy)
                }
            }
        }
    }

    @ViewBuilder private func sections(_ snapshot: RecoverySnapshot) -> some View {
        let now = Date.now
        switch section {
        case .overview:
            overview(snapshot, at: now)
        case .sleep:
            if let day = snapshot.recentNight(at: now), let night = day.sleep {
                sleepPanel(night)
            } else { missingNight }
            durationHistory(snapshot, at: now)
        case .vitals:
            vitalsPanel(snapshot, day: snapshot.recentNight(at: now) ?? snapshot.recentDay(at: now), metrics: RecoveryMetric.allCases)
            trends(snapshot, at: now)
        case .regularity:
            schedulePanel(snapshot.schedule(endingAt: now))
        }
    }

    private func overview(_ snapshot: RecoverySnapshot, at now: Date) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.md) {
            if let recent = snapshot.recentNight(at: now)?.sleep {
                Panel {
                    VStack(alignment: .leading, spacing: Theme.Space.sm) {
                        SectionHeading(title: "Последний сон")
                        Text(Format.date(recent.day)).font(.subheadline).foregroundStyle(Theme.secondary)
                        MetricValue(title: "Продолжительность", value: SleepText.duration(recent.sleptSeconds), prominence: true)
                        sleepTarget(recent)
                    }
                }
            } else { missingNight }
            checkIn
            vitalsPanel(snapshot, day: snapshot.recentDay(at: now), metrics: [.hrv, .restingPulse, .respiration])
            let cutoff = Calendar.current.date(byAdding: .day, value: -6, to: Calendar.current.startOfDay(for: now)) ?? now
            let sessions = store.journal.records.filter { (cutoff...now).contains($0.startedAt) }
            Panel {
                VStack(alignment: .leading, spacing: Theme.Space.xs) {
                    SectionHeading(title: "Тренировки за 7 дней")
                    Text(Format.workouts(sessions.count) + " · " + Format.sets(sessions.reduce(0) { $0 + $1.sets }))
                        .font(.subheadline).monospacedDigit()
                }
            }
        }
    }

    private func sleepPanel(_ night: SleepNight) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                SectionHeading(title: Format.date(night.day))
                MetricValue(title: "Всего сна", value: SleepText.duration(night.sleptSeconds), prominence: true)
                Text("Засыпание и подъём · " + SleepText.period(night))
                    .font(.subheadline).foregroundStyle(Theme.secondary)
                sleepTarget(night)
                if night.stagedSeconds > 0 {
                    SleepPhaseChart(night: night, accent: accent, secondary: Theme.secondary)
                        .frame(height: 140)
                    ForEach(SleepPhase.allCases.filter { $0 != .inBed }) { phase in
                        if phase != .unspecified || night.phaseSeconds(.unspecified) != nil {
                            detail(phase.title, value: night.phaseSeconds(phase).map(SleepText.duration) ?? "Нет данных")
                        }
                    }
                } else {
                    Text("Источник записал длительность сна без фаз.").font(.subheadline).foregroundStyle(Theme.secondary)
                }
                if let inBed = night.inBedSeconds { detail("В постели", value: SleepText.duration(inBed)) }
                if let efficiency = night.efficiency {
                    detail("Доля сна в постели", value: efficiency.formatted(.percent.precision(.fractionLength(0))))
                }
                Text("Источник · \(night.sourceName). Фазы — оценка устройства.")
                    .font(.footnote).foregroundStyle(Theme.secondary)
            }
        }
        .privacySensitive()
    }

    private func sleepTarget(_ night: SleepNight) -> some View {
        let goal = Double(store.journal.sleepGoal) * 60
        return VStack(alignment: .leading, spacing: Theme.Space.xs) {
            SwiftUI.ProgressView(value: min(night.sleptSeconds, goal), total: goal).tint(accent)
                .accessibilityLabel("Прогресс цели сна")
            Text("Цель · " + SleepText.duration(minutes: store.journal.sleepGoal))
                .font(.footnote).foregroundStyle(Theme.secondary)
        }
    }

    private var missingNight: some View {
        HintPanel(icon: "bed.double", title: "Нет недавней записи сна",
                  text: "Запишите сон на Apple Watch или другим источником, который сохраняет сон в Apple «Здоровье».")
    }

    @ViewBuilder private func durationHistory(_ snapshot: RecoverySnapshot, at now: Date) -> some View {
        let days = snapshot.recentDays(7, endingAt: now).compactMap(\.sleep)
        if !days.isEmpty {
            Panel {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    SectionHeading(title: "Сон за неделю")
                    ForEach(days.reversed()) { night in
                        detail(Format.date(night.day), value: SleepText.duration(night.sleptSeconds))
                    }
                }
            }
            .privacySensitive()
        }
    }

    private func vitalsPanel(_ snapshot: RecoverySnapshot, day: RecoveryDay?, metrics: [RecoveryMetric]) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                SectionHeading(title: "Показатели восстановления")
                if let day {
                    Text(Format.date(day.date)).font(.subheadline).foregroundStyle(Theme.secondary)
                    ForEach(metrics) { metric in
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            if let current = day.readings[metric] {
                                detail(metric.title, value: metric.formatted(current.value))
                                if metric != .oxygen {
                                    rangeDescription(snapshot, metric: metric, day: day, current: current)
                                }
                            } else {
                                detail(metric.title, value: "Нет данных")
                            }
                        }
                    }
                    DisclosureGroup("Как строится сравнение") {
                        Text("Личный диапазон охватывает значения между 10-м и 90-м процентилями за предыдущие 28 дней. Для сравнения нужно семь дней и больше с одного источника.")
                            .font(.footnote).foregroundStyle(Theme.secondary)
                            .padding(.top, Theme.Space.xs)
                    }
                    .font(.subheadline)
                } else {
                    Text("Нет недавних замеров. Историю можно посмотреть за 7 и 30 дней.")
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                }
            }
        }
        .privacySensitive()
    }

    private func rangeDescription(_ snapshot: RecoverySnapshot, metric: RecoveryMetric, day: RecoveryDay,
                                  current: RecoveryReading) -> some View {
        let range = snapshot.range(for: metric, on: day)
        let count = range?.count ?? snapshot.historyCount(for: metric, on: day)
        let description = range.map {
            "\($0.position(for: current.value).title) · \(metric.formatted($0.lower)) — \(metric.formatted($0.upper))"
        } ?? "Для сравнения · \(count) из \(RecoveryRange.minimumDays) дней"
        return Text(description)
            .font(.caption).foregroundStyle(Theme.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func trends(_ snapshot: RecoverySnapshot, at now: Date) -> some View {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: now)
        let start = calendar.date(byAdding: .day, value: 1 - trendDays, to: today) ?? today
        let end = calendar.date(byAdding: .day, value: 1, to: today) ?? now
        let readings = snapshot.recentDays(trendDays, endingAt: now).filter { $0.readings[trendMetric] != nil }
        return Panel {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                SectionHeading(title: "Динамика")
                Picker("Показатель", selection: $trendMetric) {
                    ForEach(RecoveryMetric.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.menu)
                Picker("Период", selection: $trendDays) {
                    Text("7 дней").tag(7)
                    Text("30 дней").tag(30)
                }.pickerStyle(.segmented)
                if readings.isEmpty {
                    Text("Нет замеров за выбранный период.").font(.subheadline).foregroundStyle(Theme.secondary)
                } else {
                    Chart(readings) { day in
                        if let reading = day.readings[trendMetric] {
                            PointMark(x: .value("День", day.date), y: .value(trendMetric.unit, reading.value))
                                .foregroundStyle(accent)
                                .accessibilityLabel(Format.date(day.date))
                                .accessibilityValue(trendMetric.formatted(reading.value))
                        }
                    }
                    .chartXScale(domain: start...end)
                    .chartYScale(domain: .automatic(includesZero: false))
                    .trendAxes()
                    .frame(height: 156)
                    .accessibilityLabel(trendMetric.title + " за \(trendDays) дней")
                    Text("Дней с замерами · \(readings.count) из \(trendDays)")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                }
            }
        }
        .privacySensitive()
    }

    private func schedulePanel(_ schedule: SleepSchedule) -> some View {
        Panel {
            VStack(alignment: .leading, spacing: Theme.Space.md) {
                SectionHeading(title: "Последние 7 дней")
                if schedule.nights == 0 {
                    Text("За неделю нет записей сна.").font(.subheadline).foregroundStyle(Theme.secondary)
                } else {
                    SleepScheduleChart(schedule: schedule, accent: accent, secondary: Theme.secondary)
                        .frame(height: 170)
                    Text("Столбец показывает время от засыпания до подъёма. Точка — день без записи.")
                        .font(.footnote).foregroundStyle(Theme.secondary)
                    detail("Ночей с записью", value: "\(schedule.nights) из 7")
                    detail("Разброс засыпания", value: schedule.onsetSpread.map(SleepText.duration(minutes:)) ?? "Нужны 2 ночи")
                    detail("Разброс подъёма", value: schedule.wakeSpread.map(SleepText.duration(minutes:)) ?? "Нужны 2 ночи")
                    ForEach(schedule.days.reversed()) { day in
                        detail(Format.date(day.date), value: day.sleep.map(SleepText.period) ?? "Нет записи")
                    }
                }
            }
        }
        .privacySensitive()
    }

    private var checkIn: some View {
        let day = Calendar.current.startOfDay(for: .now)
        return Panel {
            VStack(alignment: .leading, spacing: Theme.Space.sm) {
                SectionHeading(title: "Самочувствие")
                Picker("Сегодня", selection: feeling(for: day)) {
                    Text("Без отметки").tag(Optional<RecoveryFeeling>.none)
                    ForEach(RecoveryFeeling.allCases) { Text($0.title).tag(Optional($0)) }
                }
                .pickerStyle(.menu)
                .frame(minHeight: Theme.touch)
                if let recent = store.journal.recoveryCheckIns?.filter({ $0.date < day }).suffix(6), !recent.isEmpty {
                    ForEach(recent.reversed()) { entry in
                        detail(Format.date(entry.date), value: entry.feeling.title)
                    }
                }
            }
        }
        .privacySensitive()
    }

    private func feeling(for day: Date) -> Binding<RecoveryFeeling?> {
        Binding {
            store.journal.recoveryCheckIns?.first { $0.date == day }?.feeling
        } set: { new in
            store.change { journal in
                var entries = (journal.recoveryCheckIns ?? []).filter { $0.date != day }
                if let new { entries.append(RecoveryCheckIn(date: day, feeling: new)) }
                journal.recoveryCheckIns = entries.sorted { $0.date < $1.date }
            }
        }
    }

    private func detail(_ title: String, value: String) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).foregroundStyle(Theme.secondary)
                Spacer(minLength: Theme.Space.sm)
                Text(value).fontWeight(.semibold).monospacedDigit()
            }.fixedSize(horizontal: true, vertical: false).frame(maxWidth: .infinity)
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(title).foregroundStyle(Theme.secondary)
                Text(value).fontWeight(.semibold).monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.subheadline)
        .accessibilityElement(children: .combine)
    }
}

private struct SleepGoalEditor: View {
    let store: JournalStore
    @Environment(\.dismiss) private var dismiss
    @State private var minutes: Int

    init(store: JournalStore) {
        self.store = store
        _minutes = State(initialValue: store.journal.sleepGoal)
    }

    var body: some View {
        NavigationStack {
            Form {
                Stepper(SleepText.duration(minutes: minutes), value: $minutes, in: RecoverySnapshot.sleepGoalRange, step: 15)
                    .accessibilityLabel("Продолжительность сна")
            }
            .navigationTitle("Цель сна")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Отмена") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Сохранить") { if store.change({ $0.sleepGoalMinutes = minutes }) { dismiss() } }
                }
            }
            .storageAlert(store)
        }
    }
}
