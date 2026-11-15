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
            Section(Format.exercises(results.count)) {
                ForEach(results) { entry in
                    NavigationLink {
                        ExerciseDetailView(entry: entry, select: select.map { action in
                            { action(entry); dismiss() }
                        })
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(entry.name).font(.headline)
                            Text(entry.equipment.title).font(.caption).foregroundStyle(Ink.muted)
                        }
                    }
                }
                if results.isEmpty {
                    Text("Попробуйте другой запрос или сбросьте фильтры.").foregroundStyle(Ink.muted)
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
        Page {
            PageHeader(title: entry.name, caption: entry.equipment.title) { EmptyView() }
            Panel {
                VStack(alignment: .leading, spacing: 14) {
                    SectionHeading(title: "Какие мышцы работают")
                    HStack(spacing: 12) {
                        MuscleFigure(rear: false, primary: entry.primary, secondary: entry.secondary)
                        MuscleFigure(rear: true, primary: entry.primary, secondary: entry.secondary)
                    }
                    keys("Основные", entry.primary, Ink.peach)
                    if !entry.secondary.isEmpty { keys("Также работают", entry.secondary, Ink.lilac) }
                }
            }
            Panel {
                VStack(alignment: .leading, spacing: 8) {
                    SectionHeading(title: "Техника")
                    Text(entry.hint).font(.subheadline).foregroundStyle(Ink.muted)
                }
            }
            if let select {
                ActionButton(title: "Выбрать упражнение", icon: "plus", action: select)
            }
        }
    }

    private func keys(_ title: String, _ muscles: [Muscle], _ tint: Color) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Circle().fill(tint).frame(width: 8, height: 8).padding(.top, 4)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.caption.weight(.semibold)).foregroundStyle(Ink.primary)
                Text(muscles.map(\.title).joined(separator: ", ")).font(.caption).foregroundStyle(Ink.muted)
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
            (.quads, [(54,82),(63,73),(67,82),(68,95),(65,108),(60,114),(55,102)]),
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
                    context.fill(path(silhouette, mirrored: mirror), with: .color(Ink.raised))
                    for (muscle, points) in regions {
                        var color = Ink.lilac.opacity(0.13)
                        if primary.contains(muscle) { color = Ink.peach }
                        else if secondary.contains(muscle) { color = Ink.lilac.opacity(0.77) }
                        context.fill(path(points, mirrored: mirror), with: .color(color))
                    }
                }
                let head = CGRect(x: left + 42 * scale, y: 3 * scale, width: 16 * scale, height: 22 * scale)
                context.fill(Path(ellipseIn: head), with: .color(Ink.raised))
            }
            .frame(height: 159)
            Text(rear ? "Сзади" : "Спереди").font(.caption2).foregroundStyle(Ink.muted)
        }
        .accessibilityHidden(true)
    }
}
