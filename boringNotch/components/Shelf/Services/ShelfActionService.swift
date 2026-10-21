//
//  ShelfActionService.swift
//  boringNotch
//
//  Created by Alexander on 2025-10-07.
//

import AppKit
import Foundation

/// A service providing common actions for `ShelfItem`s, such as opening, revealing, or copying paths.
@MainActor
enum ShelfActionService {
    private static var copiedAccess: [URL] = []
    private static var copyMonitor: Task<Void, Never>?

    /// Keeps file access alive until another clipboard write replaces this copy.
    static func copyItems(_ items: [ShelfItem]) -> Int {
        copyMonitor?.cancel()
        releaseCopiedAccess()
        var writers: [NSPasteboardWriting] = []
        for item in items {
            switch item.kind {
            case .file:
                if let url = item.fileURL {
                    if url.startAccessingSecurityScopedResource() { copiedAccess.append(url) }
                    writers.append(url as NSURL)
                }
            case .text(let text): writers.append(text as NSString)
            case .link(let url): writers.append(url as NSURL)
            }
        }
        guard !writers.isEmpty else { return 0 }
        let board = NSPasteboard.general
        board.clearContents()
        guard board.writeObjects(writers) else { releaseCopiedAccess(); return 0 }
        let marker = board.changeCount
        if !copiedAccess.isEmpty {
            copyMonitor = Task { @MainActor in
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(1)) } catch { return }
                    if board.changeCount != marker { releaseCopiedAccess(); return }
                }
            }
        }
        return writers.count
    }

    private static func releaseCopiedAccess() {
        for url in copiedAccess { url.stopAccessingSecurityScopedResource() }
        copiedAccess.removeAll()
    }

    static func open(_ item: ShelfItem) {
        switch item.kind {
        case .file(let bookmark):
            handleBookmarkedFile(bookmark) { url in
                NSWorkspace.shared.open(url)
            }
        case .link(let url):
            NSWorkspace.shared.open(url)
        case .text(let string):
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(string, forType: .string)
        }
    }

    static func reveal(_ item: ShelfItem) {
        guard case .file(let bookmark) = item.kind else { return }
        handleBookmarkedFile(bookmark) { url in
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    static func copyPath(_ item: ShelfItem) {
        guard case .file(let bookmark) = item.kind else { return }
        handleBookmarkedFile(bookmark) { url in
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(url.path, forType: .string)
        }
    }

    static func remove(_ item: ShelfItem) {
        ShelfStateViewModel.shared.remove(item)
    }

    private static func handleBookmarkedFile(_ bookmarkData: Data, action: @escaping @Sendable (URL) -> Void) {
        Task {
            let bookmark = Bookmark(data: bookmarkData)
            if let url = bookmark.resolveURL() {
                url.accessSecurityScopedResource { accessibleURL in
                    action(accessibleURL)
                }
            }
        }
    }
}

