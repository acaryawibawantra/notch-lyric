//
//  NSItemProvider+LoadHelpers.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//


import AppKit
import Foundation
import UniformTypeIdentifiers

/// Providers can fail to call their completion handler. Resume exactly once,
/// including when a late callback races the deadline.
private final class ProviderItemGate: @unchecked Sendable {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<NSSecureCoding?, Never>?
    init(_ continuation: CheckedContinuation<NSSecureCoding?, Never>) { self.continuation = continuation }
    func finish(_ item: NSSecureCoding?) {
        lock.lock()
        let pending = continuation
        continuation = nil
        lock.unlock()
        pending?.resume(returning: item)
    }
}

extension NSItemProvider {
    func boundedItem(typeIdentifier: String, timeout: TimeInterval = 8) async -> NSSecureCoding? {
        await withCheckedContinuation { continuation in
            let gate = ProviderItemGate(continuation)
            DispatchQueue.global(qos: .userInitiated).asyncAfter(deadline: .now() + max(0.01, timeout)) {
                gate.finish(nil)
            }
            loadItem(forTypeIdentifier: typeIdentifier, options: nil) { item, error in
                gate.finish(error == nil ? item : nil)
            }
        }
    }
    
    func extractItem() async -> URL? {
        return await loadFileURL(typeIdentifier: UTType.item.identifier)
    }

    
    /// Detects if this is a file dragged from the filesystem
    func extractFileURL() async -> URL? {
        if hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            return await loadFileURL(typeIdentifier: UTType.fileURL.identifier)
        }
        return nil
    }
    
    /// Loads raw data for the given type identifier
    func loadData() async -> Data? {
        guard hasItemConformingToTypeIdentifier(UTType.data.identifier) else { return nil }
        guard let item = await boundedItem(typeIdentifier: UTType.data.identifier) else { return nil }
        if let url = item as? URL {
            guard url.absoluteString.contains("com.apple.SwiftUI.filePromises") else { return nil }
            suggestedName = suggestedName ?? url.lastPathComponent
            // Read a copy, never delete a file owned by the provider.
            return try? Data(contentsOf: url)
        }
        return item as? Data
    }

    /// Attempts to extract a URL (web link) from the provider
    func extractURL() async -> URL? {
        if self.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = await loadURL(typeIdentifier: UTType.url.identifier) {
                //Validate URL
                guard url.scheme != nil else { return nil }
                return url
            }
        }

        return nil
    }

    func extractText() async -> String? {
        let textTypes = [UTType.utf8PlainText.identifier, UTType.plainText.identifier]

        for typeIdentifier in textTypes where self.hasItemConformingToTypeIdentifier(typeIdentifier) {
            if let text = await loadText(typeIdentifier: typeIdentifier) {
                return text
            }
        }

        return nil
    }

    /// Loads a file URL from the provider for the given type identifier.
    func loadFileURL(typeIdentifier: String) async -> URL? {
        guard let item = await boundedItem(typeIdentifier: typeIdentifier) else { return nil }
        var resolvedURL: URL?
        if let url = item as? URL {
            resolvedURL = url
        } else if let data = item as? Data {
            // Prefer the UTF-8 file URL/path before attempting bookmark decoding.
            if let string = String(data: data, encoding: .utf8) {
                if string.hasPrefix("/") { resolvedURL = URL(fileURLWithPath: string) }
                else if let url = URL(string: string), url.isFileURL { resolvedURL = url }
            }
            if resolvedURL == nil { resolvedURL = Bookmark(data: data).resolveURL() }
        } else if let string = item as? String {
            if string.hasPrefix("/") { resolvedURL = URL(fileURLWithPath: string) }
            else if let url = URL(string: string), url.isFileURL { resolvedURL = url }
        }
        return resolvedURL?.isFileURL == true ? resolvedURL : nil
    }

    /// Loads a URL from the provider for the given type identifier.
    func loadURL(typeIdentifier: String) async -> URL? {
        guard let item = await boundedItem(typeIdentifier: typeIdentifier) else { return nil }
        if let url = item as? URL { return url }
        let string = (item as? String) ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
        guard let string else { return nil }
        return string.hasPrefix("/") ? URL(fileURLWithPath: string) : URL(string: string)
    }

    /// Loads text from the provider for the given type identifier.
    func loadText(typeIdentifier: String) async -> String? {
        guard let item = await boundedItem(typeIdentifier: typeIdentifier) else { return nil }
        return (item as? String) ?? (item as? Data).flatMap { String(data: $0, encoding: .utf8) }
    }
}
