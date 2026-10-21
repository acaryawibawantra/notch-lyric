import Foundation
import AppKit
import Combine

// No access to the app's bookmarks, shelf persistence, or source files.
struct Bookmark {
    let data: Data
    var refreshedData: Data? { nil }
    func resolveURL() -> URL? { nil }
}
@MainActor final class ShelfStateViewModel {
    static let shared = ShelfStateViewModel()
    var items: [ShelfItem] = []
    func resolveFileURL(for item: ShelfItem) -> URL? { nil }
}
final class TemporaryFileStorageService {
    static let shared = TemporaryFileStorageService()
    func removeTemporaryFileIfNeeded(at url: URL) { preconditionFailure("Tests must not delete files") }
}
