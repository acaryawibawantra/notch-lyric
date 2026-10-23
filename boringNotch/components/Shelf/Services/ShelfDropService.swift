//
//  ShelfDropService.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-26.
//

import AppKit
import Foundation
import UniformTypeIdentifiers
import ImageIO

struct ShelfDropService {
    /// Only explicit user paste reads the clipboard; no background clipboard watching.
    static func providers(from pasteboard: NSPasteboard) -> [NSItemProvider] {
        (pasteboard.pasteboardItems ?? []).compactMap { item in
            if let string = item.string(forType: .fileURL), let url = URL(string: string), url.isFileURL {
                return NSItemProvider(item: url as NSURL, typeIdentifier: UTType.fileURL.identifier)
            }
            // Copied browser/Preview images may include a source URL too. Prefer
            // the actual bitmap, but never replace an original Finder file URL.
            if let imageData = item.data(forType: .png) ?? item.data(forType: .tiff) {
                return imageProvider(from: imageData)
            }
            if let string = item.string(forType: .URL), let url = URL(string: string), url.scheme != nil {
                return NSItemProvider(item: url as NSURL, typeIdentifier: UTType.url.identifier)
            }
            if let string = item.string(forType: .string), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return NSItemProvider(item: string as NSString, typeIdentifier: UTType.utf8PlainText.identifier)
            }
            return nil
        }
    }

    private static func imageProvider(from data: Data) -> NSItemProvider? {
        // Bound transient decoding memory for an always-available utility.
        guard data.count <= 32 * 1024 * 1024,
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              let metadata = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = metadata[kCGImagePropertyPixelWidth] as? NSNumber,
              let height = metadata[kCGImagePropertyPixelHeight] as? NSNumber,
              width.doubleValue > 0, height.doubleValue > 0,
              width.doubleValue * height.doubleValue <= 25_000_000,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { return nil }
        let provider = NSItemProvider(item: png as NSData, typeIdentifier: UTType.png.identifier)
        provider.suggestedName = "Pasted image.png"
        return provider
    }

    static func webURL(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let url = URL(string: trimmed), ["https", "http"].contains(url.scheme?.lowercased() ?? ""),
              let host = url.host, !host.isEmpty else { return nil }
        return url
    }

    static func items(from providers: [NSItemProvider]) async -> [ShelfItem] {
        var results: [ShelfItem] = []

        for provider in providers {
            if let item = await processProvider(provider) {
                results.append(item)
            }
        }

        return results
    }
    
    private static func processProvider(_ provider: NSItemProvider) async -> ShelfItem? {
        if let actualFileURL = await provider.extractFileURL() {
            if let bookmark = createBookmark(for: actualFileURL) {
                return await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: false)
            }
            return nil
        }
        
        if let url = await provider.extractURL() {
            if url.isFileURL {
                if let bookmark = createBookmark(for: url) {
                    return await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: false)
                }
            } else {
                return await ShelfItem(kind: .link(url: url), isTemporary: false)
            }
            return nil
        }
        
        if let text = await provider.extractText() {
            if let url = webURL(from: text) {
                return await ShelfItem(kind: .link(url: url), isTemporary: false)
            }
            return await ShelfItem(kind: .text(string: text), isTemporary: false)
        }
        
        if let data = await provider.loadData() {
            if let tempDataURL = await TemporaryFileStorageService.shared.createTempFile(for: .data(data, suggestedName: provider.suggestedName)),
               let bookmark = createBookmark(for: tempDataURL) {
                return await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: true)
            }
            return nil
        }
        
        if let fileURL = await provider.extractItem() {
            if let bookmark = createBookmark(for: fileURL) {
                return await ShelfItem(kind: .file(bookmark: bookmark), isTemporary: false)
            }
        }
        
        return nil
    }
    
    private static func createBookmark(for url: URL) -> Data? {
        guard url.isFileURL else { return nil }
        return url.accessSecurityScopedResource { accessibleURL in
            (try? Bookmark(url: accessibleURL))?.data
        }
    }
}

