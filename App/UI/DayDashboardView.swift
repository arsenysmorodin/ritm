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
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.ritmAccent) private var accent
    @State private var entry: HealthEventKind?
    private var columns: [GridItem] {
        typeSize.isAccessibilitySize ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: 145), spacing: 12, alignment: .top)]
    }
    private var night: DailyHealth? {
        store.days.last { $0.date <= date && date.timeIntervalSince($0.date) < 3 * 86400 && $0.values[.sleepMinutes] != nil }
    }
    private var today: DailyHealth? { store.days.last { Calendar.current.isDate($0.date, inSameDayAs: date) } }

    var body: some View {
        NavigationStack {
            Page(spacing: 12) {
                PageHeader(title: "Сегодня", caption: Format.date(date)) {
                    Button(action: openSettings) { IconBadge(icon: "slider.horizontal.3") }
                        .buttonStyle(PressStyle()).accessibilityLabel("Настройки")
                        .accessibilityIdentifier("today.settings")
                }.padding(.bottom, 8)
                if store.isReadable {
                    DailyResourcePanel(store: store)
                    LazyVGrid(columns: columns, spacing: 12) {
                        metric(.sleepMinutes, title: "Сон", icon: "moon.zzz.fill", day: night)
                        metric(.hrv, title: "Ночная ВСР", icon: "waveform.path.ecg", day: night)
                    }
                    WaterInstrument(store: store, compact: true)
                    LazyVGrid(columns: columns, spacing: 12) {
                        NavigationLink { SupplementsView(store: store) } label: {
                            routeCard(title: "Добавки", icon: "pills.fill", value: supplementValue,
                                      detail: supplementDetail, raised: true)
                        }.accessibilityIdentifier("health.supplements")
                        Button { entry = .caffeine } label: {
                            routeCard(title: "Кофеин", icon: "cup.and.saucer.fill",
                                      value: store.total(.caffeine) > 0 ? "\(HealthEvent.number(store.total(.caffeine))) мг" : "Добавить",
                                      detail: "Время и количество")
                        }
                        metric(.daylightMinutes, title: "Дневной свет", icon: "sun.max.fill", day: today)
                        metric(.steps, title: "Шаги", icon: "figure.walk", day: today)
                    }.buttonStyle(PressStyle())
                    NavigationLink { ExperimentsView(store: store) } label: {
                        BentoCard(emphasis: .raised) {
                            HStack(alignment: .top, spacing: 12) {
                                Image(systemName: "flask.fill").font(.title2).foregroundStyle(accent).accessibilityHidden(true)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text("Эксперименты").font(.headline)
                                    if let experiment = store.experiments.first(where: { !$0.finished && $0.assignment(on: date) != nil }),
                                       let assignment = experiment.assignment(on: date) {
                                        Text(experiment.title).font(.title3.weight(.semibold))
                                        Text("Сегодня: \(assignment.isB ? experiment.conditionB : experiment.conditionA)")
                                            .font(.subheadline).foregroundStyle(Theme.secondary)
                                    } else {
                                        Text("Что влияет на ваш день?").font(.title3.weight(.semibold))
                                        Text("Сравните режим с самочувствием").font(.subheadline).foregroundStyle(Theme.secondary)
                                    }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                                Image(systemName: "arrow.up.right").foregroundStyle(Theme.secondary).accessibilityHidden(true)
                            }.frame(minHeight: 80, alignment: .topLeading)
                        }
                    }.buttonStyle(PressStyle()).accessibilityIdentifier("health.experiments")
                    LazyVGrid(columns: columns, spacing: 12) {
                        NavigationLink { DayTimelineView(store: store, journal: journal) } label: {
                            routeCard(title: "Лента дня", icon: "list.bullet.rectangle", value: "Всё по времени", detail: "Еда, привычки и события")
                        }.accessibilityIdentifier("health.timeline")
                        NavigationLink { HealthInsightsView(store: store, journal: journal) } label: {
                            routeCard(title: "Закономерности", icon: "chart.xyaxis.line", value: "Динамика", detail: "Сравнение и связи")
                        }.accessibilityIdentifier("health.insights")
                    }.buttonStyle(PressStyle())
                    quickActions
                    if bridge.busy { StatusMessage(text: "Обновляем историю здоровья…", loading: true) }
                    if let issue = bridge.issue { StatusMessage(text: issue) }
                    if journal.journal.healthEnabled {
                        Button("Доступ к воде, кофеину и дневному свету") {
                            Task { await bridge.authorize(journal, daily: store) }
                        }.font(.subheadline).frame(minHeight: 44).disabled(bridge.busy)
                    }
                } else {
                    HintPanel(icon: "externaldrive.badge.exclamationmark", title: "Health OS недоступен",
                              text: store.error ?? "Попробуйте открыть журнал ещё раз.")
                    Button("Повторить") { store.reload() }.frame(minHeight: 44)
                }
                movement.padding(.top, 8)
            }
            .refreshable {
                await health.refresh(journal)
                await bridge.refresh(journal, daily: store, force: true)
            }
            .sheet(item: $entry) { kind in HealthEventEditor(store: store, kind: kind) }
        }
    }

    private func metric(_ metric: HealthMeasure, title: String, icon: String, day: DailyHealth?) -> some View {
        NavigationLink { HealthMetricDetail(store: store, metric: metric) } label: {
            BentoCard {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: icon).foregroundStyle(accent).accessibilityHidden(true)
                        Text(title).font(.subheadline.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                    }
                    if let value = day?.values[metric] {
                        Text(metric == .sleepMinutes ? "\(Int(value) / 60)ч \(Int(value) % 60)м" : HealthEvent.number(value))
                            .font(.system(.title, design: .monospaced, weight: .semibold)).tracking(-1)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(metric == .sleepMinutes ? "Ночь · \(day!.date.formatted(.dateTime.day().month(.twoDigits)))" :
                             "\(metric.unit) · \(Calendar.current.isDate(day!.date, inSameDayAs: date) ? "сегодня" : Format.date(day!.date))")
                            .font(.caption).foregroundStyle(Theme.secondary).fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("—").font(Theme.metric)
                        Text("Нет данных").font(.caption).foregroundStyle(Theme.secondary)
                    }
                }.frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
            }
        }.buttonStyle(PressStyle()).accessibilityElement(children: .combine)
    }

    private func routeCard(title: String, icon: String, value: String, detail: String, raised: Bool = false) -> some View {
        BentoCard(emphasis: raised ? .raised : .standard) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: icon).foregroundStyle(accent).accessibilityHidden(true)
                    Text(title).font(.subheadline.weight(.semibold))
                }
                Text(value).font(.title3.weight(.semibold)).fixedSize(horizontal: false, vertical: true)
                Text(detail).font(.caption).foregroundStyle(Theme.secondary)
            }.frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        }.multilineTextAlignment(.leading)
    }

    private var supplementValue: String {
        let slots = store.supplements.flatMap { product in product.slots(on: date).map { (product, $0) } }
        let done = slots.filter { HealthOSLogic.completedSlot($0.1, supplement: $0.0.id, events: store.events) }.count
        return slots.isEmpty ? "Свой план" : "\(done) из \(slots.count)"
    }
    private var supplementDetail: String {
        store.supplements.isEmpty ? "Состав и расписание" : "Приёмов отмечено сегодня"
    }
    private var quickActions: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Отметить").font(Theme.sectionTitle).accessibilityAddTraits(.isHeader)
            LazyVGrid(columns: columns, spacing: 8) {
                ForEach([HealthEventKind.meal, .context, .measurement]) { kind in
                    Button { entry = kind } label: {
                        Label(kind.title, systemImage: kind.icon).font(.subheadline.weight(.semibold))
                            .frame(maxWidth: .infinity, minHeight: 52).padding(.horizontal, 8)
                            .background(Theme.elevated, in: RoundedRectangle(cornerRadius: 12))
                    }.buttonStyle(PressStyle())
                }
            }
        }.padding(.top, 8)
    }
    private var movement: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let workout = journal.journal.activeWorkout {
                Text(workout.name).font(.subheadline).foregroundStyle(Theme.secondary)
                ActionButton(title: "Продолжить тренировку", icon: "play.fill", solid: false, action: resumeTraining)
            }
            Button(action: openTraining) {
                HealthRouteRow(title: "Тренировки", subtitle: "Движение — часть вашего дня", icon: "figure.strengthtraining.traditional")
            }.buttonStyle(PressStyle()).accessibilityIdentifier("today.training")
        }
    }
}

struct DailyResourcePanel: View {
    let store: HealthOSStore
    @State private var checkIn = false
    @Environment(\.ritmAccent) private var accent
    @Environment(\.dynamicTypeSize) private var typeSize
    private var latest: HealthEvent? { HealthOSLogic.events(store.events, on: .now, kind: .checkIn).first }
    var body: some View {
        BentoCard(emphasis: .accent) {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Ресурс на день").font(.headline).fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Image(systemName: "bolt.fill").font(.title3).accessibilityHidden(true)
                }
                if let latest {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(latest.ratings["energy"].map(String.init) ?? "—")
                            .font(.system(.largeTitle, design: .monospaced, weight: .bold)).fontWidth(.expanded)
                        Text("/ 5 энергии").font(.subheadline.weight(.medium)).fixedSize(horizontal: false, vertical: true)
                    }
                    ViewThatFits(in: .horizontal) {
                        HStack(spacing: 16) { rating("stress", event: latest); rating("sleepiness", event: latest) }
                        VStack(alignment: .leading, spacing: 8) { rating("stress", event: latest); rating("sleepiness", event: latest) }
                    }
                    Text("Оценка в \(latest.date.formatted(date: .omitted, time: .shortened))").font(.caption)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Как вы сегодня?").font(.system(.title, weight: .bold)).fontWidth(.expanded)
                        .fixedSize(horizontal: false, vertical: true)
                    if !typeSize.isAccessibilitySize {
                        Text("Энергия, сонливость и стресс").font(.subheadline.weight(.medium))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Button { checkIn = true } label: {
                    HStack(spacing: 10) {
                        Text(latest == nil ? (typeSize.isAccessibilitySize ? "Оценить" : "Оценить самочувствие") : "Обновить")
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        Image(systemName: "arrow.up.right")
                    }.font(.subheadline.weight(.semibold))
                        .padding(.horizontal, 14).padding(.vertical, 10).frame(minHeight: 48)
                        .foregroundStyle(accent).background(Theme.onAccent, in: RoundedRectangle(cornerRadius: 12))
                }.buttonStyle(PressStyle()).accessibilityIdentifier("today.checkIn")
                    .accessibilityLabel(latest == nil ? "Оценить самочувствие" : "Обновить самочувствие")
                    .accessibilityHint("Энергия, сонливость и стресс")
            }
        }.sheet(isPresented: $checkIn) { HealthEventEditor(store: store, kind: .checkIn) }
    }
    private func rating(_ key: String, event: HealthEvent) -> some View {
        Text("\(ratingTitle(key)): \(event.ratings[key].map { "\($0)/5" } ?? "—")").font(.subheadline.weight(.medium))
            .fixedSize(horizontal: false, vertical: true)
    }
}
