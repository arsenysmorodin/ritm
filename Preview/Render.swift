import AppKit
import SwiftUI

@main struct Render {
    private static let appearance: ColorScheme = ProcessInfo.processInfo.environment["RITM_PREVIEW_APPEARANCE"] == "light" ? .light : .dark
    private static let largeText = ProcessInfo.processInfo.environment["RITM_PREVIEW_TEXT_SIZE"] == "accessibility"

    @MainActor static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "RitmPreview-\(UUID())")
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = JournalStore(url: directory.appending(path: "journal.json"))
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 14, hour: 11, minute: 30))!
        if let monday = calendar.date(byAdding: .day, value: -5, to: now), let routine = store.journal.activeProgram?.routines.first {
            store.start(routine, at: monday)
            store.updateWorkout { $0.exercises[0].sets[0].complete = true }
            _ = store.finish(at: monday.addingTimeInterval(1240))
        }

        let layout = HStack(spacing: 20) {
            preview(tab: "Сегодня") {
                TodayView(store: store, start: { _ in }, programs: {}, openHistory: {}, openRecord: { _ in }, now: now)
            }
            preview(tab: "Программы") {
                ProgramsView(store: store, start: { _ in })
            }
        }
        let output = URL(fileURLWithPath: CommandLine.arguments[1])
        try write(layout, to: output)
        if CommandLine.arguments.count > 2, let entry = ExerciseCatalog.all.first(where: { $0.id == "dumbbell-row" }) {
            let values = [89, 94, 107, 118, 120, 112, 108, 126, 131, 120, 111, 106]
            let points = values.enumerated().map { index, bpm in
                PulsePoint(date: now.addingTimeInterval(Double(index) * 30), bpm: bpm)
            }
            let detail = HStack(spacing: 20) {
                preview(tab: "Программы") { ExerciseDetailView(entry: entry, select: {}) }
                preview(tab: "История") {
                    Page {
                        PageHeader(title: "Всё тело", caption: "История тренировки") { IconBadge(icon: "dumbbell") }
                        PulsePanel(points: points)
                    }
                }
            }
            try write(detail, to: URL(fileURLWithPath: CommandLine.arguments[2]))
        }
    }

    @MainActor private static func write<V: View>(_ layout: V, to output: URL) throws {
        let styled = layout.padding(22)
            .background(Theme.elevated)
            .tint(Theme.accent).foregroundStyle(Theme.primary)
            .environment(\.colorScheme, appearance)
            .environment(\.dynamicTypeSize, largeText ? .accessibility3 : .large)
        let renderer = ImageRenderer(content: styled)
        renderer.scale = 1.5
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: output)
    }

    @MainActor private static func preview<Content: View>(tab: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(spacing: 0) {
            HStack {
                Text("9:41").fontWeight(.semibold)
                Spacer()
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.100percent")
            }
            .font(.system(size: 13)).padding(.horizontal, 26).frame(height: 39)
            content().frame(height: largeText ? 1320 : 750, alignment: .top).clipped()
            Divider().overlay(Theme.border)
            HStack(spacing: 0) {
                ForEach([( "Сегодня", "house" ), ( "Программы", "square.stack" ), ( "История", "clock.arrow.circlepath" ), ( "Здоровье", "heart" )], id: \.0) { item in
                    VStack(spacing: 5) {
                        Image(systemName: item.1).font(.system(size: 17, weight: .medium))
                        Text(item.0).font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(tab == item.0 ? Theme.accent : Theme.secondary)
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 43)
            Capsule().fill(Theme.primary).frame(width: 105, height: 4).padding(.top, 7).padding(.bottom, 6)
        }
        .frame(width: largeText ? 320 : 360).background(Theme.background)
        .clipShape(RoundedRectangle(cornerRadius: 29))
        .overlay { RoundedRectangle(cornerRadius: 29).strokeBorder(Theme.border) }
    }
}
