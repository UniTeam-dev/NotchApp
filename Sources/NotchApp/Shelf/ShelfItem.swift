import AppKit

struct ShelfItem: Identifiable, Equatable {
    let id: UUID
    /// Путь к копии внутри Application Support.
    var url: URL
    var name: String
    var addedAt: Date
    var isDirectory: Bool

    var icon: NSImage {
        NSWorkspace.shared.icon(forFile: url.path)
    }

    var sizeText: String {
        if isDirectory { return "папка" }
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        let bytes = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
        return ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    static func == (lhs: ShelfItem, rhs: ShelfItem) -> Bool {
        lhs.id == rhs.id && lhs.url == rhs.url
    }
}
