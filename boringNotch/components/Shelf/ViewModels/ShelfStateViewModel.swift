//
//  ShelfStateViewModel.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-09.

import Foundation
import AppKit

@MainActor
final class ShelfStateViewModel: ObservableObject {
    static let shared = ShelfStateViewModel()

    @Published private(set) var items: [ShelfItem] = [] {
        didSet { ShelfPersistenceService.shared.save(items) }
    }

    @Published var isLoading: Bool = false
    @Published private(set) var dropFeedback = ""
    private var pendingDrops = 0
    @Published private(set) var recentIDs: Set<UUID> = []
    private var recentTask: Task<Void, Never>?

    var isEmpty: Bool { items.isEmpty }

    // Queue for deferred bookmark updates to avoid publishing during view updates
    private var pendingBookmarkUpdates: [ShelfItem.ID: Data] = [:]
    private var updateTask: Task<Void, Never>?

    private init() {
        items = ShelfPersistenceService.shared.load()
    }


    func add(_ newItems: [ShelfItem]) {
        guard !newItems.isEmpty else { return }
        var merged = items
        // Deduplicate by identityKey while preserving order (existing first)
        var seen: Set<String> = Set(merged.map { $0.identityKey })
        for it in newItems {
            let key = it.identityKey
            if !seen.contains(key) {
                merged.append(it)
                seen.insert(key)
            }
        }
        let addedIDs = Set(merged.map(\.id)).subtracting(items.map(\.id))
        items = merged
        if !addedIDs.isEmpty {
            recentTask?.cancel()
            recentIDs = addedIDs
            recentTask = Task { @MainActor [weak self] in
                do { try await Task.sleep(for: .seconds(4)) } catch { return }
                self?.recentIDs = []
            }
        }
    }

    func remove(_ item: ShelfItem) {
        item.cleanupStoredData()
        items.removeAll { $0.id == item.id }
    }

    func setPinned(_ pinned: Bool, ids: Set<UUID>) {
        var updated = items
        for index in updated.indices where ids.contains(updated[index].id) { updated[index].pinned = pinned }
        items = updated
    }

    func updateBookmark(for item: ShelfItem, bookmark: Data) {
        guard let idx = items.firstIndex(where: { $0.id == item.id }) else { return }
        if case .file = items[idx].kind {
            items[idx].kind = .file(bookmark: bookmark)
        }
    }

    private func scheduleDeferredBookmarkUpdate(for item: ShelfItem, bookmark: Data) {
        pendingBookmarkUpdates[item.id] = bookmark
        
        // Cancel existing task and schedule a new one
        updateTask?.cancel()
        updateTask = Task { @MainActor [weak self] in
            await Task.yield()
            
            guard let self = self else { return }
            
            for (itemID, bookmarkData) in self.pendingBookmarkUpdates {
                if let idx = self.items.firstIndex(where: { $0.id == itemID }),
                   case .file = self.items[idx].kind {
                    self.items[idx].kind = .file(bookmark: bookmarkData)
                }
            }
            
            self.pendingBookmarkUpdates.removeAll()
        }
    }


    func load(_ providers: [NSItemProvider]) {
        guard !providers.isEmpty else { return }
        pendingDrops += 1
        isLoading = true
        Task { [weak self] in
            let dropped = await ShelfDropService.items(from: providers)
            await MainActor.run {
                guard let self else { return }
                let before = self.items.count
                self.add(dropped)
                let added = self.items.count - before
                self.dropFeedback = dropped.isEmpty ? "Could not add files. Check file access or try Add."
                    : added == 0 ? "Already on your shelf. Originals stay in place."
                    : "Added \(added) item(s)\(dropped.count < providers.count ? "; some could not be added" : ""). Originals stay in place."
                self.pendingDrops -= 1
                self.isLoading = self.pendingDrops > 0
            }
        }
    }

    func cleanupInvalidItems() {
        Task { [weak self] in
            guard let self else { return }
            var invalid: [UUID: ShelfItemKind] = [:]
            for item in self.items {
                // Preserve pins when a removable drive is temporarily unavailable.
                if item.isPinned { continue }
                switch item.kind {
                case .file(let data):
                    let bookmark = Bookmark(data: data)
                    if !(await bookmark.validate()) { invalid[item.id] = item.kind }
                default:
                    break
                }
            }
            // Do not overwrite items added or refreshed while validation awaited.
            let removed = self.items.filter { !$0.isPinned && invalid[$0.id] == $0.kind }
            let removedIDs = Set(removed.map(\.id))
            self.items.removeAll { removedIDs.contains($0.id) }
            for item in removed { item.cleanupStoredData() }
        }
    }


    func resolveFileURL(for item: ShelfItem) -> URL? {
        guard case .file(let bookmarkData) = item.kind else { return nil }
        let bookmark = Bookmark(data: bookmarkData)
        let result = bookmark.resolve()
        if let refreshed = result.refreshedData, refreshed != bookmarkData {
            NSLog("Bookmark for \(item) stale; refreshing")
            scheduleDeferredBookmarkUpdate(for: item, bookmark: refreshed)
        }
        return result.url
    }

    func resolveAndUpdateBookmark(for item: ShelfItem) -> URL? {
        guard case .file(let bookmarkData) = item.kind else { return nil }
        let bookmark = Bookmark(data: bookmarkData)
        let result = bookmark.resolve()
        if let refreshed = result.refreshedData, refreshed != bookmarkData {
            NSLog("Bookmark for \(item) stale; refreshing")
            updateBookmark(for: item, bookmark: refreshed)
        }
        return result.url
    }

    func resolveFileURLs(for items: [ShelfItem]) -> [URL] {
        var urls: [URL] = []
        for it in items {
            if let u = resolveFileURL(for: it) { urls.append(u) }
        }
        return urls
    }
}
