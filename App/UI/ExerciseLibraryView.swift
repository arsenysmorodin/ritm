import SwiftUI

struct ExerciseLibraryView: View {
    var select: ((ExercisePreset) -> Void)? = nil
    @State private var search = ""
    @State private var equipment: Equipment?
    @State private var muscle: Muscle?
    @Environment(\.dismiss) private var dismiss

    private var results: [ExercisePreset] {
        let query = ExerciseCatalog.normalize(search)
        return ExerciseCatalog.all.filter { entry in
            (equipment == nil || entry.equipment == equipment) &&
            (muscle.map { entry.primary.contains($0) || entry.secondary.contains($0) } ?? true) &&
            (query.isEmpty || ExerciseCatalog.normalize(entry.name + " " + entry.equipment.title).contains(query))
        }
    }

    var body: some View {
        List {
            Section {
                Picker("Инвентарь", selection: $equipment) {
                    Text("Любой").tag(nil as Equipment?)
                    ForEach(Equipment.allCases) { Text($0.title).tag(Optional($0)) }
                }
                Picker("Мышцы", selection: $muscle) {
                    Text("Все группы").tag(nil as Muscle?)
                    ForEach(Muscle.allCases) { Text($0.title).tag(Optional($0)) }
                }
            }
            if results.isEmpty {
                Section {
                    ContentUnavailableView {
                        Label("Упражнения не найдены", systemImage: "magnifyingglass")
                    } description: {
                        Text("Попробуйте другое название или измените фильтры.")
                    } actions: {
                        Button("Очистить поиск и фильтры") {
                            search = ""
                            equipment = nil
                            muscle = nil
                        }
                        .frame(minHeight: Theme.touch)
                    }
                }
            } else {
                Section(Format.exercises(results.count)) {
                    ForEach(results) { entry in
                        NavigationLink {
                            ExerciseDetailView(entry: entry, select: select.map { action in
                                { action(entry); dismiss() }
                            })
                        } label: {
                            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                                Text(entry.name).font(.headline)
                                Text(entry.equipment.title).font(.subheadline).foregroundStyle(Theme.secondary)
                            }
                            .frame(minHeight: Theme.touch, alignment: .leading)
                        }
                    }
                }
            }
        }
        .formTint()
        .searchable(text: $search, prompt: "Название упражнения")
        .navigationTitle("Каталог")
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Закрыть") { dismiss() } } }
    }
}

struct ExerciseDetailView: View {
    let entry: ExercisePreset
    var select: (() -> Void)? = nil

    var body: some View {
        ExerciseGuide(name: entry.name, preset: entry,
                      muscles: MuscleSelection(primary: entry.primary, secondary: entry.secondary), select: select)
    }
}

struct ExercisePlanDetailView: View {
    let plan: ExercisePlan

    var body: some View {
        ExerciseGuide(name: plan.name, preset: ExerciseCatalog.find(plan),
                      muscles: plan.muscles, note: plan.techniqueNote)
    }
}

private struct ExerciseGuide: View {
    let name: String
    let preset: ExercisePreset?
    let muscles: MuscleSelection
    var note: String? = nil
    var select: (() -> Void)? = nil

    var body: some View {
        Page {
            PageHeader(title: name, caption: preset?.equipment.title ?? "Своё упражнение") { EmptyView() }
            if let preset {
                TechniqueCard(preset: preset)
            }
            if let note, !note.isEmpty {
                Panel {
                    VStack(alignment: .leading, spacing: 9) {
                        SectionHeading(title: "Заметка о технике")
                        Text(note).font(.subheadline).foregroundStyle(Theme.secondary)
                    }
                }
            }
            MuscleMap(muscles: muscles)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let select {
                ActionDock {
                    ActionButton(title: "Выбрать упражнение", icon: "plus", action: select)
                }
            }
        }
    }
}

struct MuscleMap: View {
    let muscles: MuscleSelection
    var title = "Какие мышцы работают"

    var body: some View {
        Panel {
            VStack(alignment: .leading, spacing: 14) {
                SectionHeading(title: title)
                if muscles.isEmpty {
                    Text("Группы мышц ещё не указаны.").font(.subheadline).foregroundStyle(Theme.secondary)
                } else {
                    HStack(spacing: 12) {
                        MuscleFigure(rear: false, primary: muscles.primary, secondary: muscles.secondary)
                        MuscleFigure(rear: true, primary: muscles.primary, secondary: muscles.secondary)
                    }
                    if !muscles.primary.isEmpty { keys("Основные", muscles.primary, Theme.accent) }
                    if !muscles.secondary.isEmpty { keys("Также работают", muscles.secondary, Theme.reference) }
                }
            }
        }
    }

    private func keys(_ title: String, _ muscles: [Muscle], _ tint: Color) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Circle().fill(tint).frame(width: 8, height: 8).padding(.top, 4).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.weight(.semibold)).foregroundStyle(Theme.primary)
                Text(muscles.map(\.title).joined(separator: ", ")).font(.subheadline).foregroundStyle(Theme.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

private struct MuscleFigure: View {
    let rear: Bool
    let primary: [Muscle]
    let secondary: [Muscle]

    // Coordinates for the right half of a schematic human figure, mirrored across x=50.
    private typealias Region = (Muscle, [(Double, Double)])
    private var regions: [Region] {
        let shared: [Region] = [
            (.shoulders, [(65,33),(72,35),(77,43),(76,49),(67,46)]),
            (.forearms, [(75,63),(81,63),(85,78),(81,80),(76,73)])
        ]
        if rear {
            return shared + [
                (.upperBack, [(51,27),(59,33),(65,33),(68,46),(58,53),(51,49)]),
                (.lats, [(58,53),(68,46),(63,60),(59,67),(54,59)]),
                (.lowerBack, [(51,50),(56,57),(60,66),(56,73),(51,72)]),
                (.triceps, [(69,47),(76,50),(80,61),(74,63),(70,56)]),
                (.glutes, [(51,74),(61,68),(66,73),(67,84),(61,90),(54,87),(51,83)]),
                (.hamstrings, [(55,89),(61,92),(68,86),(67,101),(64,112),(57,108)]),
                (.calves, [(58,117),(65,114),(67,125),(65,135),(61,138),(57,128)])
            ]
        }
        return shared + [
            (.chest, [(51,34),(64,34),(67,46),(59,50),(51,48)]),
            (.biceps, [(68,47),(76,49),(80,60),(75,62),(70,56)]),
            (.abs, [(51,50),(57,51),(59,62),(55,74),(51,72)]),
            (.obliques, [(60,51),(66,48),(62,60),(63,69),(57,74),(60,62)]),
            (.quads, [(57,85),(65,78),(67,85),(68,95),(65,108),(61,114),(58,100)]),
            (.hipFlexors, [(53,74),(62,69),(66,74),(60,82),(54,83)]),
            (.adductors, [(51,84),(55,84),(57,99),(59,110),(57,114),(54,101)]),
            (.calves, [(59,118),(65,116),(66,126),(63,136),(61,132)])
        ]
    }

    var body: some View {
        VStack(spacing: 4) {
            Canvas { context, size in
                let scale = min(size.width / 100, size.height / 154)
                let left = (size.width - 100 * scale) / 2
                func path(_ points: [(Double, Double)], mirrored: Bool) -> Path {
                    Path { shape in
                        for (index, point) in points.enumerated() {
                            let x = mirrored ? 100 - point.0 : point.0
                            let value = CGPoint(x: left + x * scale, y: point.1 * scale)
                            if index == 0 { shape.move(to: value) } else { shape.addLine(to: value) }
                        }
                        shape.closeSubpath()
                    }
                }
                let silhouette: [(Double, Double)] = [(50,22),(57,22),(58,29),(66,32),(74,35),(79,45),(81,58),(86,74),(88,83),(84,88),(79,84),(78,76),(73,65),(68,51),(65,62),(67,74),(70,88),(68,104),(65,115),(68,127),(65,141),(70,147),(67,151),(57,151),(56,146),(57,137),(55,124),(56,114),(53,100),(50,88)]
                for mirror in [false, true] {
                    context.fill(path(silhouette, mirrored: mirror), with: .color(Theme.elevated))
                    for (muscle, points) in regions {
                        var color = Theme.border
                        if primary.contains(muscle) { color = Theme.accent }
                        else if secondary.contains(muscle) { color = Theme.reference }
                        context.fill(path(points, mirrored: mirror), with: .color(color))
                    }
                }
                let head = CGRect(x: left + 42 * scale, y: 3 * scale, width: 16 * scale, height: 22 * scale)
                context.fill(Path(ellipseIn: head), with: .color(Theme.elevated))
            }
            .frame(height: 159)
            Text(rear ? "Сзади" : "Спереди").font(.caption2).foregroundStyle(Theme.secondary)
        }
        .accessibilityHidden(true)
    }
}
