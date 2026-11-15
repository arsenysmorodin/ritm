import AppKit
import SwiftUI

@main struct Render {
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
        .padding(22)
        .background(Color(red: 0.09, green: 0.082, blue: 0.13))
        .tint(Ink.lilac).foregroundStyle(Ink.primary)
        .environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: layout)
        renderer.scale = 1.5
        guard let image = renderer.nsImage, let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        try png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
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
            content().frame(height: 682, alignment: .top).clipped()
            Divider().overlay(Ink.line)
            HStack(spacing: 0) {
                ForEach([( "Сегодня", "house" ), ( "Программы", "square.stack" ), ( "История", "clock.arrow.circlepath" ), ( "Здоровье", "heart" )], id: \.0) { item in
                    VStack(spacing: 5) {
                        Image(systemName: item.1).font(.system(size: 17, weight: .medium))
                        Text(item.0).font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(tab == item.0 ? Ink.lilac : Ink.muted)
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 43)
            Capsule().fill(Ink.primary).frame(width: 105, height: 4).padding(.top, 7).padding(.bottom, 6)
        }
        .frame(width: 360).background(Ink.paper)
        .clipShape(RoundedRectangle(cornerRadius: 29))
        .overlay { RoundedRectangle(cornerRadius: 29).strokeBorder(Ink.lilac.opacity(0.19), lineWidth: 1) }
    }
}
