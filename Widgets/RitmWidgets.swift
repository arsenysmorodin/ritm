import ActivityKit
import SwiftUI
import WidgetKit

private struct RitmEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
    let accent = widgetAccent()
}

func widgetAccent() -> RitmAccent {
    WidgetStorage.preferences.string(forKey: RitmAccent.widgetKey).flatMap(RitmAccent.init(rawValue:)) ?? .lime
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
            VStack(alignment: .leading, spacing: 7) {
                Label(entry.snapshot?.activeWorkout == nil ? "Тренировка" : "В процессе", systemImage: "dumbbell.fill")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(entry.snapshot?.activeWorkout == nil ? Theme.secondary : entry.accent.color)
                Spacer(minLength: 4)
                Text(entry.snapshot?.activeWorkout ?? entry.snapshot?.suggestion(at: entry.date) ?? "Открыть «Ритм»")
                    .font(.title3.weight(.semibold)).minimumScaleFactor(0.7).lineLimit(3)
                    .privacySensitive()
                if let summary = entry.snapshot, summary.activeWorkout != nil {
                    Text("\(summary.completedSets) из \(summary.totalSets) подходов").font(.caption2).foregroundStyle(Theme.secondary)
                    if summary.totalSets > 0 {
                        ProgressView(value: Double(summary.completedSets), total: Double(summary.totalSets))
                            .tint(entry.accent.color).accessibilityHidden(true)
                    }
                } else {
                    Text("Перейти к тренировке").font(.caption2).foregroundStyle(Theme.secondary)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .foregroundStyle(Theme.primary)
            .containerBackground(Theme.surface, for: .widget)
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
            let values = entry.snapshot?.week(at: entry.date) ?? Array(repeating: 0, count: 7)
            let total = values.reduce(0, +)
            VStack(alignment: .leading, spacing: 8) {
                Label("Эта неделя", systemImage: "calendar").font(.caption.weight(.semibold)).foregroundStyle(Theme.secondary)
                Spacer(minLength: 0)
                if let snapshot = entry.snapshot {
                    Text("\(total) из \(snapshot.weeklyGoal)").font(Theme.metric)
                    HStack(spacing: 3) {
                        ForEach(Array(values.enumerated()), id: \.offset) { offset, count in
                            VStack(spacing: 3) {
                                Capsule().fill(count > 0 ? entry.accent.color : Theme.elevated).frame(height: 8)
                                Text(["Пн", "Вт", "Ср", "Чт", "Пт", "Сб", "Вс"][offset]).font(.system(size: 8)).foregroundStyle(Theme.secondary)
                            }
                        }
                    }.accessibilityHidden(true)
                } else {
                    Text("Открыть журнал").font(.headline)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            .foregroundStyle(Theme.primary)
            .containerBackground(Theme.surface, for: .widget)
            .widgetURL(URL(string: "ritm://history"))
        }
        .configurationDisplayName("Неделя «Ритм»")
        .description("Завершённые домашние тренировки и недельная цель.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

private struct RestTimerActivity: Widget {
    // The Lock Screen host and widget content can resolve different appearances.
    private let lockSurface = Color(red: 22 / 255, green: 27 / 255, blue: 33 / 255)
    private let lockText = Color(red: 244 / 255, green: 245 / 255, blue: 247 / 255)
    private let lockAccent = Color(red: 185 / 255, green: 231 / 255, blue: 107 / 255)
    private let lockWarning = Color(red: 242 / 255, green: 185 / 255, blue: 111 / 255)

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            HStack(spacing: Theme.Space.md) {
                Label {
                    Text(context.isStale ? "Отдых завершён" : "Отдых")
                        .font(.headline)
                } icon: {
                    Image(systemName: context.isStale ? "checkmark.circle.fill" : "timer")
                        .foregroundStyle(context.isStale ? lockAccent : lockWarning)
                }
                Spacer(minLength: Theme.Space.sm)
                if !context.isStale {
                    countdown(context).font(Theme.timer).multilineTextAlignment(.trailing)
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
        RestTimerActivity()
    }
}
