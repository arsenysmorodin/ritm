import SwiftUI

struct TodayView: View {
    let store: JournalStore
    var start: (Routine?) -> Void
    var programs: () -> Void
    var openHistory: () -> Void
    var openRecord: (UUID) -> Void
    var now = Date.now
    @Environment(\.dynamicTypeSize) private var textSize

    var body: some View {
        let journal = store.journal
        let suggestion = journal.suggestion(on: now)
        Page {
            PageHeader(title: "Сегодня", caption: Format.date(now)) { EmptyView() }

            workoutPanel(journal.activeWorkout, suggestion, program: journal.activeProgram?.name)
            if journal.activeWorkout == nil, suggestion != nil {
                Button {
                    start(nil)
                } label: {
                    Label("Свободная тренировка", systemImage: "plus.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: Theme.touch, alignment: .leading)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressStyle())
            }

            weekPanel(journal.week(containing: now), goal: journal.weeklyGoal)

            if let latest = journal.records.first {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    ViewThatFits(in: .horizontal) {
                        HStack {
                            SectionHeading(title: "Последняя тренировка")
                            Spacer(minLength: Theme.Space.sm)
                            allHistory
                        }.fixedSize(horizontal: true, vertical: false)
                        VStack(alignment: .leading, spacing: Theme.Space.xs) {
                            SectionHeading(title: "Последняя тренировка")
                            allHistory
                        }
                    }
                    Button { openRecord(latest.id) } label: { RecordRow(record: latest) }
                        .buttonStyle(PressStyle())
                }
            } else if suggestion == nil {
                ActionButton(title: "Составить программу", icon: "square.stack", solid: false, action: programs)
            }
        }
    }

    private var allHistory: some View {
        Button("Вся история", action: openHistory)
            .font(.subheadline.weight(.semibold))
            .frame(minHeight: Theme.touch)
    }

    private func workoutPanel(_ draft: ActiveWorkout?, _ routine: Routine?, program: String?) -> some View {
        let title = draft?.name ?? routine?.name ?? "Свободная тренировка"
        let kind = draft?.kind ?? routine?.kind ?? .strength
        let plannedToday = routine?.weekday?.rawValue == Calendar.current.component(.weekday, from: now)

        return Panel {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                VStack(alignment: .leading, spacing: Theme.Space.sm) {
                    Label(draft != nil ? "В процессе" : plannedToday ? "По плану на сегодня" : "Тренировка",
                          systemImage: draft != nil ? "play.circle.fill" : kind.icon)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(draft != nil ? Theme.accent : Theme.secondary)
                    Text(title).font(Theme.screenTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                    if let draft {
                        let hasDrops = draft.exercises.contains { $0.plan.drops?.isEmpty == false }
                        Text("\(draft.marked) из \(draft.total) \(hasDrops ? "этапов" : "подходов")")
                            .font(Theme.number)
                        if draft.total > 0 {
                            SwiftUI.ProgressView(value: Double(draft.marked), total: Double(draft.total))
                                .accessibilityHidden(true)
                        }
                    } else if let routine {
                        Text([Format.exercises(routine.exercises.count), Format.sets(routine.setCount)].joined(separator: "  ·  "))
                            .font(.subheadline.weight(.semibold)).foregroundStyle(Theme.primary)
                        if let program {
                            Text(program).font(.subheadline).foregroundStyle(Theme.secondary)
                        }
                    } else {
                        Text("Добавляйте упражнения по ходу занятия.").font(.subheadline).foregroundStyle(Theme.secondary)
                    }
                }
                ActionButton(title: draft == nil ? "Начать тренировку" : "Продолжить тренировку",
                             icon: "play.fill") { start(routine) }
            }
        }
    }

    private func weekPanel(_ week: [TrainingDay], goal: Int) -> some View {
        let total = week.reduce(0) { $0 + $1.count }
        let columns = Array(repeating: GridItem(.flexible(), spacing: Theme.Space.xs), count: textSize.isAccessibilitySize ? 4 : 7)
        return Panel {
            VStack(alignment: .leading, spacing: Theme.Space.lg) {
                MetricValue(title: "Тренировки за неделю", value: "\(total) из \(goal)", prominence: total > 0)
                LazyVGrid(columns: columns, spacing: Theme.Space.sm) {
                    ForEach(week) { day in
                        VStack(spacing: Theme.Space.xs) {
                            Text(day.weekday.short).font(.caption.weight(day.isToday ? .bold : .medium))
                                .foregroundStyle(day.isToday ? Theme.primary : Theme.secondary)
                            ZStack {
                                RoundedRectangle(cornerRadius: 6)
                                    .fill(day.count > 0 ? Theme.accent : Theme.elevated)
                                    .overlay {
                                        if day.isToday {
                                            RoundedRectangle(cornerRadius: 6)
                                                .strokeBorder(day.count > 0 ? Theme.onAccent : Theme.accent, lineWidth: 2)
                                        }
                                    }
                                if day.count > 0 {
                                    Image(systemName: "checkmark").font(.caption2.bold()).foregroundStyle(Theme.onAccent)
                                } else if day.planned {
                                    Circle().fill(Theme.secondary).frame(width: 5, height: 5)
                                }
                            }.frame(height: 26)
                        }
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(day.weekday.short), \(day.isToday ? "сегодня, " : "")\(day.count > 0 ? Format.workouts(day.count) : day.planned ? "по плану" : "свободно")")
                    }
                }
            }
        }
    }
}
