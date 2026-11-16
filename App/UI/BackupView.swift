import SwiftUI
import UniformTypeIdentifiers

struct BackupView: View {
    let store: JournalStore
    @State private var document: BackupDocument?
    @State private var pending: JournalBackup?
    @State private var exporting = false
    @State private var importing = false
    @State private var confirmRestore = false
    @State private var status: String?

    var body: some View {
        Page {
            PageHeader(title: "Резервная копия", caption: "Локальный журнал") { EmptyView() }
            Panel {
                VStack(alignment: .leading, spacing: Theme.Space.md) {
                    Text("Файл содержит программы, свои упражнения, историю, черновик и сохранённые цели. Данные сна, питания и восстановления загружаются из Apple «Здоровья».")
                        .font(.subheadline).foregroundStyle(Theme.secondary)
                    ActionButton(title: "Сохранить копию в Файлы", icon: "square.and.arrow.up") {
                        export()
                    }.disabled(!store.isReadable)
                    ActionButton(title: "Восстановить из файла", icon: "arrow.down.document", solid: false) {
                        importing = true
                    }
                }
            }
            if let status { Text(status).font(.subheadline).foregroundStyle(Theme.secondary).accessibilityAddTraits(.updatesFrequently) }
        }
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "Ritm-backup") { result in
            switch result {
            case .success: status = "Копия сохранена."
            case .failure: status = "Не удалось сохранить копию."
            }
            document = nil
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json], onCompletion: read)
        .alert("Восстановить журнал?", isPresented: $confirmRestore, presenting: pending) { backup in
            Button("Отмена", role: .cancel) { pending = nil }
            Button("Заменить журнал", role: .destructive) {
                status = store.restore(backup) ? "Журнал восстановлен." : store.error
                pending = nil
            }
        } message: { backup in
            Text("Копия от \(Format.date(backup.createdAt, year: true)). Программы: \(backup.journal.programs.count). Тренировки: \(backup.journal.records.count). Текущий журнал будет заменён.")
        }
        .storageAlert(store)
    }

    private func export() {
        do {
            let data = try JSONEncoder().encode(JournalBackup(journal: store.journal))
            document = BackupDocument(data: data)
            exporting = true
        } catch {
            status = "Не удалось подготовить журнал для сохранения."
        }
    }

    private func read(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            pending = try JournalBackup.decode(Data(contentsOf: url))
            confirmRestore = true
        } catch {
            status = "Не удалось открыть файл. Выберите резервную копию «Ритма»."
        }
    }
}

private struct BackupDocument: FileDocument {
    static let readableContentTypes: [UTType] = [.json]
    let data: Data

    init(data: Data) { self.data = data }

    init(configuration: ReadConfiguration) throws {
        guard let bytes = configuration.file.regularFileContents else { throw CocoaError(.fileReadCorruptFile) }
        data = bytes
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
