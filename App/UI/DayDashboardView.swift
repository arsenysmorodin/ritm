import SwiftUI

struct DayDashboardView: View {
    let journal: JournalStore
    let health: HealthConnection
    let store: HealthOSStore
    let bridge: HealthOSBridge
    let openSettings: () -> Void
    let openTraining: () -> Void
    let resumeTraining: () -> Void
    var date = Date.now

    var body: some View {
        NavigationStack {
            Page {
                PageHeader(title: "Сегодня", caption: "\(Format.date(date)) · здоровье и ресурс на день") {
                    Button(action: openSettings) { IconBadge(icon: "gearshape") }
                        .buttonStyle(PressStyle()).accessibilityLabel("Настройки")
                }
                HealthOSHome(store: store, journal: journal, bridge: bridge)
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeading(title: "Движение")
                    if let workout = journal.journal.activeWorkout {
                        Text(workout.name).font(.subheadline).foregroundStyle(Theme.secondary)
                        ActionButton(title: "Продолжить тренировку", icon: "play.fill", solid: false, action: resumeTraining)
                    }
                    Button(action: openTraining) {
                        HealthRouteRow(title: "Тренировки", subtitle: "Программы, занятия и история", icon: "figure.strengthtraining.traditional")
                    }.buttonStyle(PressStyle()).accessibilityIdentifier("today.training")
                }
            }
            .refreshable {
                await health.refresh(journal)
                await bridge.refresh(journal, daily: store, force: true)
            }
        }
    }
}

struct DailyResourcePanel: View {
    let store: HealthOSStore
    @State private var checkIn = false
    private var latest: HealthEvent? { HealthOSLogic.events(store.events, on: .now, kind: .checkIn).first }
    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(title: "Ресурс на день")
                if let latest {
                    ViewThatFits(in: .horizontal) {
                        HStack(alignment: .top, spacing: 18) { values(latest) }
                        VStack(alignment: .leading, spacing: 12) { values(latest) }
                    }
                    Text("Ваша оценка в \(latest.date.formatted(date: .omitted, time: .shortened))")
                        .font(.caption).foregroundStyle(Theme.secondary)
                    Button("Обновить самочувствие") { checkIn = true }.font(.subheadline).frame(minHeight: 44)
                } else {
                    Text("Отметьте энергию, сонливость и стресс — это поможет сопоставить режим с самочувствием и работоспособностью.")
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                    ActionButton(title: "Оценить самочувствие", icon: "face.smiling", solid: false) { checkIn = true }
                }
            }
        }.sheet(isPresented: $checkIn) { HealthEventEditor(store: store, kind: .checkIn) }
    }
    @ViewBuilder private func values(_ event: HealthEvent) -> some View {
        ForEach(["energy", "sleepiness", "stress"], id: \.self) { key in
            VStack(alignment: .leading, spacing: 4) {
                Text(ratingTitle(key)).font(.caption).foregroundStyle(Theme.secondary)
                Text(event.ratings[key].map { "\($0)/5" } ?? "—").font(Theme.number)
            }.accessibilityElement(children: .combine)
        }
    }
}
