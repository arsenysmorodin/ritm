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
        let week = journal.week(containing: now)
        let suggestion = journal.suggestion(on: now)
        Page {
            PageHeader(title: "Сегодня", caption: Format.date(now)) {
                HStack(spacing: 6) {
                    Image(systemName: "waveform.path").foregroundStyle(Ink.lilac)
                    Text("Ритм").font(.system(.subheadline, design: .rounded, weight: .semibold))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(Ink.panel, in: Capsule())
                .accessibilityHidden(true)
            }
            weekPanel(week, goal: journal.weeklyGoal)
            VStack(alignment: .leading, spacing: 11) {
                SectionHeading(title: "Тренировка")
                hero(journal.activeWorkout, suggestion, program: journal.activeProgram?.name)
                if journal.activeWorkout == nil && suggestion != nil {
                    Button {
                        start(nil)
                    } label: {
                        HStack {
                            Image(systemName: "plus.circle").font(.title3).foregroundStyle(Ink.lilac)
                            Text("Свободная тренировка").font(.subheadline.weight(.medium))
                            Spacer()
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(Ink.muted)
                        }
                        .padding(.horizontal, 13).frame(minHeight: 49)
                        .background(Ink.panel, in: RoundedRectangle(cornerRadius: 13))
                    }.buttonStyle(PressStyle())
                }
            }
            if let latest = journal.records.first {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        SectionHeading(title: "Последняя запись")
                        Spacer()
                        Button("История", action: openHistory).font(.subheadline.weight(.medium))
                    }
                    Button { openRecord(latest.id) } label: { RecordRow(record: latest) }.buttonStyle(PressStyle())
                }
            } else if suggestion == nil {
                ActionButton(title: "Составить программу", icon: "square.stack", solid: false, action: programs)
            }
        }
    }

    private func weekPanel(_ week: [TrainingDay], goal: Int) -> some View {
        let total = week.reduce(0) { $0 + $1.count }
        return Panel {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Эта неделя").font(.headline).accessibilityAddTraits(.isHeader)
                    Spacer()
                    Text("\(total) из \(goal)").font(.system(.subheadline, design: .rounded, weight: .semibold))
                        .monospacedDigit().foregroundStyle(total >= goal ? Ink.peach : Ink.lilac)
                        .accessibilityLabel("\(Format.workouts(total)) из \(goal)")
                }
                HStack(spacing: 4) {
                    ForEach(week) { day in
                        VStack(spacing: 6) {
                            Text(day.weekday.short).font(.caption.weight(.medium))
                                .foregroundStyle(day.isToday ? Ink.lilac : Ink.muted)
                            ZStack {
                                Capsule().fill(day.count > 0 ? Ink.peach : day.isToday ? Ink.lilac.opacity(0.15) : Ink.raised)
                                if day.isToday { Capsule().strokeBorder(Ink.lilac.opacity(0.8), lineWidth: 1) }
                                if day.count > 0 {
                                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(Ink.onAccent)
                                } else if day.planned {
                                    Circle().fill(Ink.lilac).frame(width: 4, height: 4)
                                }
                            }.frame(height: 26)
                        }.frame(maxWidth: .infinity)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(day.weekday.short), \(day.isToday ? "сегодня, " : "")\(day.count > 0 ? Format.workouts(day.count) : day.planned ? "по плану" : "свободно")")
                    }
                }
            }
        }
    }

    private func hero(_ draft: ActiveWorkout?, _ routine: Routine?, program: String?) -> some View {
        let title = draft?.name ?? routine?.name ?? "Свободная тренировка"
        let kind = draft?.kind ?? routine?.kind ?? .strength
        let plannedToday = routine?.weekday?.rawValue == Calendar.current.component(.weekday, from: now)
        return VStack(alignment: .leading, spacing: 13) {
            VStack(alignment: .leading, spacing: 8) {
                Label(draft != nil ? "В процессе" : routine != nil ? kind.title : "Свой темп", systemImage: kind.icon)
                    .font(.subheadline.weight(.medium)).foregroundStyle(kind.color)
                    .padding(.horizontal, 9).padding(.vertical, 6)
                    .background(kind.color.opacity(0.11), in: Capsule())
                Text(title)
                    .font(.system(.largeTitle, weight: .semibold)).tracking(-1.2)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                if let draft {
                    Text("\(draft.marked) из \(draft.total) подходов").font(.subheadline).foregroundStyle(Ink.muted)
                } else if let routine {
                    Text("\(Format.exercises(routine.exercises.count)), \(Format.sets(routine.setCount))")
                        .font(.subheadline).foregroundStyle(Ink.muted)
                    if let program {
                        Text(plannedToday ? "По плану на сегодня" : program).font(.caption).foregroundStyle(Ink.lilac).fixedSize(horizontal: false, vertical: true)
                    }
                } else {
                    Text("Добавляйте упражнения по ходу занятия.").font(.subheadline).foregroundStyle(Ink.muted)
                }
            }
            .frame(maxWidth: textSize.isAccessibilitySize ? .infinity : 225, alignment: .leading)
            .padding(.top, 5)
            .frame(minHeight: 129, alignment: .topLeading)
            ActionButton(title: draft == nil ? "Начать тренировку" : "Продолжить тренировку",
                         icon: draft == nil ? "play.fill" : "arrow.right", color: Ink.peach) { start(routine) }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .topTrailing) {
            if !textSize.isAccessibilitySize {
                EffortDrawing().frame(width: 180, height: 157).padding(.trailing, 1).padding(.top, 4).accessibilityHidden(true)
            }
        }
        .background {
            LinearGradient(colors: [Ink.panel, Color(red: 0.21, green: 0.155, blue: 0.30)], startPoint: .leading, endPoint: .topTrailing)
        }
        .clipShape(RoundedRectangle(cornerRadius: 21))
        .overlay { RoundedRectangle(cornerRadius: 21).strokeBorder(Ink.lilac.opacity(0.17), lineWidth: 1).allowsHitTesting(false) }
    }
}

/// The same parallel lines used in the icon describe the plates and their axis.
struct EffortDrawing: View {
    var body: some View {
        Canvas { context, size in
            let sx = size.width / 180, sy = size.height / 157
            func pt(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * sx, y: y * sy) }
            func line(_ points: [CGPoint], color: Color, width: CGFloat = 1) {
                guard let first = points.first else { return }
                var path = Path(); path.move(to: first)
                for p in points.dropFirst() { path.addLine(to: p) }
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round))
            }
            for index in 0..<9 {
                let x = Double(index) * 16 + 27
                line([pt(x, 15), pt(x, 139)], color: Ink.lilac.opacity(0.068), width: 0.7)
            }
            for index in 0..<8 {
                let y = Double(index) * 16 + 17
                line([pt(34, y), pt(168, y)], color: Ink.lilac.opacity(0.068), width: 0.7)
            }
            let axisX = 0.80, axisY = -0.60
            func location(_ offset: Double, _ radius: Double, _ angle: Double) -> CGPoint {
                let a = radius * cos(angle), b = radius * sin(angle) * 0.42
                return pt(99 + offset * axisX + a * 0.60 + b * axisX,
                          78 + offset * axisY + a * 0.80 + b * axisY)
            }
            func sleeve(_ start: Double, _ end: Double, _ radius: Double, emphasis: Bool) {
                let count = 48
                let front = (0...count).map { location(end, radius, Double($0) / Double(count) * .pi * 2) }
                let back = (0...count).map { location(start, radius, Double($0) / Double(count) * .pi * 2) }
                var silhouette = Path(); silhouette.move(to: front[0]); silhouette.addLines(Array(front[1...24]))
                silhouette.addLines(Array(back[24...48])); silhouette.closeSubpath()
                context.fill(silhouette, with: .color(emphasis ? Color(red: 0.32, green: 0.236, blue: 0.47) : Ink.raised))
                line(back, color: Ink.lilac.opacity(emphasis ? 0.55 : 0.36))
                for i in stride(from: 0, through: 24, by: 3) {
                    line([front[i], back[i]], color: Ink.lilac.opacity(0.22), width: 0.75)
                }
                var face = Path(); face.addLines(front); face.closeSubpath()
                context.fill(face, with: .color(emphasis ? Color(red: 0.43, green: 0.32, blue: 0.61) : Ink.raised))
                line(front, color: Ink.lilac.opacity(emphasis ? 0.86 : 0.61), width: 1.25)
                if emphasis {
                    line((0...count).map { location(end, radius * 0.72, Double($0) / Double(count) * .pi * 2) }, color: Ink.lilac.opacity(0.62))
                }
            }
            sleeve(-61, -47, 7, emphasis: false)
            sleeve(-49, -35, 29, emphasis: true)
            sleeve(-35, -24, 26, emphasis: true)
            sleeve(-25, 27, 8, emphasis: false)
            sleeve(23, 37, 29, emphasis: true)
            sleeve(37, 51, 26, emphasis: true)
            sleeve(51, 63, 7, emphasis: false)
            for (x,y) in [(145.0, 109.0), (63, 26), (159, 86)] {
                line([pt(x - 4, y), pt(x + 4, y)], color: Ink.peach.opacity(0.83))
                line([pt(x, y - 4), pt(x, y + 4)], color: Ink.peach.opacity(0.83))
            }
        }
        .mask { LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.32)], startPoint: .leading, endPoint: .trailing) }
    }
}
