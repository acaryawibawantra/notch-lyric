import AppKit
import Foundation

// Isolated bookmark/persistence adapters: never touch the app's actual shelf.
struct Bookmark {
    let data: Data
    init(data: Data) { self.data = data }
    init(url: URL) throws {
        guard url.isFileURL, FileManager.default.fileExists(atPath: url.path) else {
            throw CocoaError(.fileNoSuchFile)
        }
        data = Data(url.path.utf8)
    }
    func resolveURL() -> URL? {
        guard let path = String(data: data, encoding: .utf8), path.hasPrefix("/") else { return nil }
        return URL(fileURLWithPath: path)
    }
}
enum ShelfItemKind: Sendable {
    case file(bookmark: Data), text(string: String), link(url: URL)
}
@MainActor struct ShelfItem: Sendable {
    let kind: ShelfItemKind
    let isTemporary: Bool
}
enum TempFileType { case data(Data, suggestedName: String?) }
final class TemporaryFileStorageService {
    static let shared = TemporaryFileStorageService()
    func createTempFile(for type: TempFileType) async -> URL? {
        preconditionFailure("Finder URLs must stay references, not be imported as blobs")
    }
}
