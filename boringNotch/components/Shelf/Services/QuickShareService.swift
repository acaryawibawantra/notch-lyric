//
//  QuickShareService.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import AppKit
import Foundation
import UniformTypeIdentifiers

/// Dynamic representation of a sharing provider discovered at runtime
struct QuickShareProvider: Identifiable, Hashable, Sendable {
    var id: String
    var imageData: Data?
    var supportsRawText: Bool
    var displayImage: NSImage? {
        if id == "AirDrop", let symbol = NSImage(systemSymbolName: "airdrop", accessibilityDescription: nil) {
            return symbol
        }
        return imageData.flatMap { NSImage(data: $0) }
            ?? NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: "Share")
    }
}

@MainActor
struct ShareDropPayload {
    var items: [Any] = []
    var temporaryURLs: [URL] = []
}

@MainActor
enum ShareDropLoader {
    static func load(_ providers: [NSItemProvider], supportsRawText: Bool) async -> ShareDropPayload {
        var payload = ShareDropPayload()
        for provider in providers {
            // A Finder file may advertise URL and plain text as well: prefer the file.
            if let file = await provider.extractFileURL() {
                payload.items.append(file)
            } else if let url = await provider.extractURL() {
                payload.items.append(url)
            } else if let text = await provider.extractText() {
                if let url = ShelfDropService.webURL(from: text) {
                    payload.items.append(url)
                } else if supportsRawText {
                    payload.items.append(text)
                } else if let url = await TemporaryFileStorageService.shared.createTempFile(for: .text(text)) {
                    payload.temporaryURLs.append(url)
                    payload.items.append(url)
                }
            } else if let file = await provider.extractItem() {
                payload.items.append(file)
            } else if let data = await provider.loadData(),
                      let url = await TemporaryFileStorageService.shared.createTempFile(for: .data(data, suggestedName: provider.suggestedName)) {
                payload.temporaryURLs.append(url)
                payload.items.append(url)
            }
        }
        return payload
    }
}

class QuickShareService: ObservableObject {
    static let shared = QuickShareService()
    
    @Published var availableProviders: [QuickShareProvider] = []
    @Published var isPickerOpen = false
    @Published private(set) var isSharing = false
    var isBusy: Bool { isPickerOpen || isSharing }
    @Published private(set) var feedback = ""
    private var cachedServices: [String: NSSharingService] = [:]
    // Hold security-scoped URLs during sharing
    private var sharingAccessingURLs: [URL] = []
    private var lifecycleDelegate: SharingLifecycleDelegate?
    private var activePicker: NSSharingServicePicker?
    private var activeService: NSSharingService?
    private var filePanel: NSOpenPanel?
    private var temporaryShareURLs: [URL] = []
   
    init() {
        Task {
            await discoverAvailableProviders()
        }
    }
    
    // MARK: - Provider Discovery
    
    @MainActor
    func discoverAvailableProviders() async {
        let finder = ShareServiceFinder()

        // Use simple test items without creating actual temp files
        // This avoids issues with the Share Sheet retaining references to deleted files
        let testItems: [Any] = [
            URL(string:"http://example.com") ?? URL(fileURLWithPath: "/"),
            "Test Text" as NSString
        ]

        let services = await finder.findApplicableServices(for: testItems)

        var providers: [QuickShareProvider] = []

        for svc in services {
            let title = svc.title
            let imgData = svc.image.tiffRepresentation
            let supportsRawText = svc.canPerform(withItems: ["Test Text"])
            let provider = QuickShareProvider(id: title, imageData: imgData, supportsRawText: supportsRawText)
            if !providers.contains(provider) {
                providers.append(provider)
                cachedServices[title] = svc
            }
        }

        // AirDrop must not depend on discovery using an arbitrary URL + text batch,
        // or on matching its localized display title.
        if let airDrop = NSSharingService(named: .sendViaAirDrop) {
            providers.removeAll { $0.id == "AirDrop" }
            providers.insert(QuickShareProvider(id: "AirDrop", imageData: airDrop.image.tiffRepresentation,
                                               supportsRawText: false), at: 0)
            cachedServices["AirDrop"] = airDrop
        }
        
        if let idx = providers.firstIndex(where: { $0.id == "AirDrop" }) {
            let ad = providers.remove(at: idx)
            providers.insert(ad, at: 0)
        }

        if !providers.contains(where: { $0.id == "System Share Menu" }) {
            providers.append(QuickShareProvider(id: "System Share Menu", imageData: nil, supportsRawText: true))
        }

        self.availableProviders = providers

    }
    
    // MARK: - File Picker
    @MainActor
    func showFilePicker(for provider: QuickShareProvider, from view: NSView?) async {
        guard !isBusy else {
            feedback = "Finish or cancel the open file picker or share window first."
            return
        }

        isPickerOpen = true
        SharingStateManager.shared.beginInteraction()

        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        panel.title = "Select Files for \(provider.id)"
        panel.message = "Choose files to share via \(provider.id)"

        // The notch lives above mainMenu. A normal modal panel can end up behind
        // it; a standalone async panel must explicitly live above that window.
        panel.level = NSWindow.Level(rawValue: max(NSWindow.Level.modalPanel.rawValue,
                                                   (view?.window?.level.rawValue ?? 0) + 1))
        panel.hidesOnDeactivate = false
        filePanel = panel
        feedback = "Choose files in the file picker, or Cancel to return to Shelf."
        NSApp.activate(ignoringOtherApps: true)
        let response = await withCheckedContinuation { continuation in
            panel.begin { continuation.resume(returning: $0) }
            panel.makeKeyAndOrderFront(nil)
        }
        let urls = panel.urls
        filePanel = nil
        isPickerOpen = false
        defer { SharingStateManager.shared.endInteraction() }
        guard response == .OK, !urls.isEmpty else {
            feedback = "File selection cancelled. You can drag a file onto AirDrop instead."
            return
        }
        await shareFilesOrText(urls, using: provider, from: view)
    }
    
    // MARK: - Sharing
    @MainActor
    func shareFilesOrText(_ items: [Any], using provider: QuickShareProvider, from view: NSView?, temporaryURLs: [URL] = []) async {
        guard lifecycleDelegate == nil else {
            feedback = "Finish or cancel the current share before starting another."
            for url in temporaryURLs { TemporaryFileStorageService.shared.removeTemporaryFileIfNeeded(at: url) }
            return
        }
        guard !items.isEmpty else {
            feedback = "No shareable items. Try adding the file to Shelf first."
            return
        }
        let fileURLs = items.compactMap { $0 as? URL }.filter { $0.isFileURL }
        // Stop any previous sharing access
        stopSharingAccessingURLs()
        // Start security-scoped access for all file URLs
        sharingAccessingURLs = fileURLs.filter { $0.startAccessingSecurityScopedResource() }
        temporaryShareURLs = temporaryURLs

        // Setup lifecycle delegate to keep notch open during picker/service
        feedback = "Choose a recipient in \(provider.id)."
        let delegate = SharingStateManager.shared.makeDelegate(onFailure: { [weak self] _ in
            self?.feedback = "Sharing failed or was cancelled. Check AirDrop receiving, Wi-Fi and Bluetooth, then retry."
        }, onEnd: { [weak self] in
            if self?.feedback.hasPrefix("Choose a recipient") == true {
                self?.feedback = "Share window closed. Shelf items stay in place."
            }
            self?.lifecycleDelegate = nil
            self?.activePicker = nil
            self?.activeService = nil
            self?.isSharing = false
            self?.stopSharingAccessingURLs()
            for url in self?.temporaryShareURLs ?? [] {
                TemporaryFileStorageService.shared.removeTemporaryFileIfNeeded(at: url)
            }
            self?.temporaryShareURLs = []
        })
        lifecycleDelegate = delegate
        isSharing = true

        let service = provider.id == "AirDrop" ? NSSharingService(named: .sendViaAirDrop) : cachedServices[provider.id]
        if let svc = service, svc.canPerform(withItems: items) {
            // For direct service path, explicitly mark service interaction start
            delegate.markServiceBegan()
            svc.delegate = delegate
            activeService = svc
            // A drop from Finder does not activate this menu-bar application.
            // Bring the user-requested recipient UI to the foreground explicitly.
            NSApp.activate(ignoringOtherApps: true)
            svc.perform(withItems: items)
        } else {
            guard let view, view.window != nil else {
                // No picker was started, so release the registered delegate immediately.
                feedback = "Open Shelf and try Share again. The share window is not ready."
                delegate.cancelBeforePresentation()
                return
            }
            if provider.id == "AirDrop" { feedback = "AirDrop is unavailable for these items. Choose another sharing option." }
            let picker = NSSharingServicePicker(items: items)
            activePicker = picker
            picker.delegate = delegate
            delegate.markPickerBegan()
            picker.show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
        }
    }

    private func stopSharingAccessingURLs() {
        NSLog("Stopping sharing access to URLs")
        for url in sharingAccessingURLs {
            url.stopAccessingSecurityScopedResource()
        }
        sharingAccessingURLs.removeAll()
    }
// MARK: - SharingServiceDelegate

private class SharingServiceDelegate: NSObject {}
    
    @MainActor
    func shareDroppedFiles(_ providers: [NSItemProvider], using shareProvider: QuickShareProvider, from view: NSView?, shelfItems: [ShelfItem] = []) async {
        var payload = ShareDropPayload()
        if shelfItems.isEmpty {
            payload = await ShareDropLoader.load(providers, supportsRawText: shareProvider.supportsRawText)
        } else {
            // Resolve only the selected source items, not every bookmark on Shelf
            // (which could include offline disks or network volumes).
            for item in shelfItems {
                switch item.kind {
                case .file:
                    if let url = ShelfStateViewModel.shared.resolveAndUpdateBookmark(for: item) { payload.items.append(url) }
                case .link(let url): payload.items.append(url)
                case .text(let text):
                    if shareProvider.supportsRawText { payload.items.append(text) }
                    else if let url = await TemporaryFileStorageService.shared.createTempFile(for: .text(text)) {
                        payload.items.append(url)
                        payload.temporaryURLs.append(url)
                    }
                }
            }
        }
        await shareFilesOrText(payload.items, using: shareProvider, from: view, temporaryURLs: payload.temporaryURLs)
    }
}

// MARK: - App Storage Extension for Provider Selection

extension QuickShareProvider {
    static var defaultProvider: QuickShareProvider {
        let svc = QuickShareService.shared

        if let airdrop = svc.availableProviders.first(where: { $0.id == "AirDrop" }) {
            return airdrop
        }
        if let airdrop = NSSharingService(named: .sendViaAirDrop) {
            return QuickShareProvider(id: "AirDrop", imageData: airdrop.image.tiffRepresentation, supportsRawText: false)
        }
        return svc.availableProviders.first ?? QuickShareProvider(id: "System Share Menu", imageData: nil, supportsRawText: true)
    }
}
