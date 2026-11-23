import ActivityKit
import SwiftUI
import WidgetKit

private struct RitmEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let palette = WidgetPalette(selection: widgetAccent())
}

private struct RitmProvider: TimelineProvider {
    func placeholder(in context: Context) -> RitmEntry {
        RitmEntry(date: .now, snapshot: WidgetSnapshot(activeWorkout: nil, completedSets: 0,
            totalSets: 0, routines: [.init(id: UUID(), title: "Всё тело", weekday: nil)], completions: [], weeklyGoal: 3))
    }

    func getSnapshot(in context: Context, completion: @escaping (RitmEntry) -> Void) {
        completion(context.isPreview ? placeholder(in: context) : RitmEntry(date: .now, snapshot: WidgetSnapshot.load()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<RitmEntry>) -> Void) {
        let now = Date.now
        let snapshot = WidgetSnapshot.load()
        let tomorrow = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0), matchingPolicy: .nextTime) ?? now.addingTimeInterval(3600)
        completion(Timeline(entries: [.init(date: now, snapshot: snapshot), .init(date: tomorrow, snapshot: snapshot)], policy: .atEnd))
    }
}

private struct NextWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.workoutKind, provider: RitmProvider()) { entry in
            let palette = entry.palette
            let active = entry.snapshot?.activeWorkout != nil
            WidgetCard(palette: palette) {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetHeader(title: active ? "В процессе" : "Тренировка", icon: "dumbbell", palette: palette)
                    WidgetRule(palette: palette)
                    Spacer(minLength: 2)
                    Text(entry.snapshot?.activeWorkout ?? entry.snapshot?.suggestion(at: entry.date) ?? "Открыть «Ритм»")
                        .font(.title2.weight(.semibold)).minimumScaleFactor(0.7).lineLimit(3)
                        .privacySensitive()
                    if let summary = entry.snapshot, active {
                        Text("\(summary.completedSets) из \(summary.totalSets) подходов").font(.caption2).foregroundStyle(palette.secondary)
                        WidgetProgressStrip(value: Double(summary.completedSets), total: Double(summary.totalSets), palette: palette)
                    } else if entry.snapshot?.suggestion(at: entry.date) != nil {
                        Text("По вашей программе").font(.caption2).foregroundStyle(palette.secondary)
                    }
                }
            }
            .widgetURL(URL(string: "ritm://today"))
        }
        .configurationDisplayName("Тренировка «Ритм»")
        .description("Следующая тренировка из вашей программы и прогресс текущей.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct TrainingWeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetSnapshot.weekKind, provider: RitmProvider()) { entry in
            let palette = entry.palette
            let values = entry.snapshot?.week(at: entry.date) ?? Array(repeating: 0, count: 7)
            let total = values.reduce(0, +)
            WidgetCard(palette: palette) {
                VStack(alignment: .leading, spacing: 6) {
                    WidgetHeader(title: "Эта неделя", icon: "calendar", palette: palette)
                    Spacer(minLength: 0)
                    if let snapshot = entry.snapshot {
                        WidgetNumber(value: "\(total)", unit: "из \(snapshot.weeklyGoal)", palette: palette)
                        WidgetRule(palette: palette)
                        HStack(alignment: .bottom, spacing: 3) {
                            ForEach(Array(values.enumerated()), id: \.offset) { offset, count in
                                VStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 2)
                                        .fill(count > 0 ? palette.accent : palette.secondary.opacity(0.25))
                                        .frame(height: count > 0 ? 19 : 3)
                                        .widgetAccentable(count > 0)
                                    Text(["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"][offset]).font(.system(size: 8))
                                        .foregroundStyle(palette.secondary)
                                }
                            }
                        }.accessibilityHidden(true)
                    } else {
                        WidgetEmpty(text: "Откройте журнал в «Ритме».", palette: palette)
                    }
                }
                .accessibilityElement(children: .combine)
            }
            .widgetURL(URL(string: "ritm://history"))
        }
        .configurationDisplayName("Неделя «Ритм»")
        .description("Завершённые домашние тренировки и недельная цель.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct RestTimerActivity: Widget {
    // The Lock Screen host and widget content can resolve different appearances.
    private let lockSurface = Color(red: 19 / 255, green: 25 / 255, blue: 32 / 255)
    private let lockText = Color(red: 244 / 255, green: 245 / 255, blue: 247 / 255)
    private let lockAccent = Color(red: 185 / 255, green: 231 / 255, blue: 107 / 255)
    private let lockWarning = Color(red: 242 / 255, green: 185 / 255, blue: 111 / 255)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            HStack(spacing: 12) {
                Label {
                    Text(context.isStale ? "Отдых завершён" : "Отдых")
                        .font(.headline)
                } icon: {
                    let color = context.isStale ? lockAccent : lockWarning
                    Image(systemName: context.isStale ? "checkmark.circle.fill" : "timer")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(color)
                        .frame(width: 30, height: 30)
                        .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 7))
                }
                Spacer(minLength: Theme.Space.sm)
                if !context.isStale {
                    countdown(context).font(.system(.title, design: .monospaced, weight: .semibold))
                        .minimumScaleFactor(0.65).lineLimit(1).multilineTextAlignment(.trailing)
                }
            }
            .padding(Theme.Space.lg)
            .foregroundStyle(lockText)
            .activityBackgroundTint(lockSurface)
            .activitySystemActionForegroundColor(lockText)
            .widgetURL(URL(string: "ritm://today"))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label(context.isStale ? "Отдых завершён" : "Отдых", systemImage: context.isStale ? "checkmark.circle" : "timer")
                        .font(.headline)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !context.isStale { countdown(context).font(.title2.monospacedDigit()) }
                }
            } compactLeading: {
                Image(systemName: context.isStale ? "checkmark" : "timer").accessibilityLabel(context.isStale ? "Отдых завершён" : "Отдых")
            } compactTrailing: {
                if !context.isStale {
                    countdown(context)
                        .font(.caption.monospacedDigit())
                        .frame(maxWidth: 43)
                }
            } minimal: {
                Image(systemName: context.isStale ? "checkmark" : "timer").accessibilityLabel(context.isStale ? "Отдых завершён" : "Отдых")
            }
            .widgetURL(URL(string: "ritm://today"))
        }
    }

    private func countdown(_ context: ActivityViewContext<RestActivityAttributes>) -> some View {
        let end = context.attributes.endsAt
        return Text(timerInterval: min(context.state.startedAt, end)...end, countsDown: true, showsHours: false)
            .monospacedDigit()
    }
}

@main struct RitmWidgetBundle: WidgetBundle {
    var body: some Widget {
        NextWorkoutWidget()
        TrainingWeekWidget()
        HeartWidget()
        NutritionWidget()
        RecoveryWidget()
        SleepStagesWidget()
        SleepMeasurementsWidget()
        SleepScheduleWidget()
        HealthTodayWidget()
        StepsWidget()
        ActiveEnergyWidget()
        BodyWeightWidget()
        RestingPulseWidget()
        WeeklySleepDurationWidget()
        WaterWidget()
        SupplementsWidget()
        CaffeineWidget()
        DayTimelineWidget()
        DailyResourceWidget()
        DaylightWidget()
        FiberWidget()
        ProteinWidget()
        WaterWeekWidget()
        ExperimentWidget()
        SleepGoalWidget()
        LastMealWidget()
        RestTimerActivity()
    }
}
