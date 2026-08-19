import AppKit
import Combine

/// Полка: файлы живут между Spaces и мониторами в пределах одного мака.
///
/// Файл **копируется** в `~/Library/Application Support/NotchApp/shelf/<uuid>/`.
/// Это сознательно: карточка должна остаться рабочей, даже если оригинал
/// переместили или удалили.
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [ShelfItem] = []

    func load() {
        let manager = FileManager.default
        try? manager.createDirectory(at: Paths.shelf, withIntermediateDirectories: true)

        guard let folders = try? manager.contentsOfDirectory(
            at: Paths.shelf,
            includingPropertiesForKeys: [.creationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return }

        var loaded: [ShelfItem] = []

        for folder in folders {
            guard let id = UUID(uuidString: folder.lastPathComponent) else { continue }
            guard let contents = try? manager.contentsOfDirectory(
                at: folder,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ), let file = contents.first else { continue }

            let values = try? file.resourceValues(forKeys: [.isDirectoryKey])
            let created = (try? folder.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()

            loaded.append(
                ShelfItem(
                    id: id,
                    url: file,
                    name: file.lastPathComponent,
                    addedAt: created,
                    isDirectory: values?.isDirectory ?? false
                )
            )
        }

        items = loaded.sorted { $0.addedAt > $1.addedAt }
    }

    // MARK: - Приём

    @discardableResult
    func add(from pasteboard: NSPasteboard) -> Bool {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: nil) as? [URL] ?? []
        let fileURLs = urls.filter(\.isFileURL)
        guard !fileURLs.isEmpty else { return false }

        for url in fileURLs { add(url: url) }
        return true
    }

    @discardableResult
    func add(url: URL) -> ShelfItem? {
        let manager = FileManager.default
        let id = UUID()
        let folder = Paths.shelf.appendingPathComponent(id.uuidString, isDirectory: true)
        let destination = folder.appendingPathComponent(url.lastPathComponent)

        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)
            if manager.fileExists(atPath: destination.path) {
                try manager.removeItem(at: destination)
            }
            try manager.copyItem(at: url, to: destination)
        } catch {
            Log.shelf.error("не удалось положить на полку: \(error.localizedDescription, privacy: .public)")
            try? manager.removeItem(at: folder)
            return nil
        }

        let values = try? destination.resourceValues(forKeys: [.isDirectoryKey])
        let item = ShelfItem(
            id: id,
            url: destination,
            name: destination.lastPathComponent,
            addedAt: Date(),
            isDirectory: values?.isDirectory ?? false
        )

        items.insert(item, at: 0)
        return item
    }

    // MARK: - Удаление

    func remove(_ item: ShelfItem) {
        let folder = Paths.shelf.appendingPathComponent(item.id.uuidString, isDirectory: true)
        try? FileManager.default.removeItem(at: folder)
        items.removeAll { $0.id == item.id }
    }

    func clear() {
        for item in items { remove(item) }
    }

    // MARK: - Выдача

    func reveal(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func open(_ item: ShelfItem) {
        NSWorkspace.shared.open(item.url)
    }

    /// Элемент пастборда для вытаскивания карточки наружу.
    /// `.fileURL` пишем из `absoluteString`, а не из `path`: приёмники ждут URL.
    func pasteboardItem(for item: ShelfItem) -> NSPasteboardItem {
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(item.url.absoluteString, forType: .fileURL)
        pasteboardItem.setString(item.name, forType: .string)
        return pasteboardItem
    }
}
