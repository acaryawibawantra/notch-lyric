//
//  FileShareView.swift
//  boringNotch
//
//  Created by Alexander on 2025-09-24.
//

import AppKit
import Defaults
import SwiftUI
import UniformTypeIdentifiers

struct FileShareView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @StateObject private var quickShare = QuickShareService.shared
    @Default(.quickShareProvider) var quickShareProvider: String

    @State private var isProcessing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    
    private var selectedProvider: QuickShareProvider {
        quickShare.availableProviders.first(where: { $0.id == quickShareProvider }) ??
            QuickShareProvider(id: quickShareProvider == "AirDrop" ? "AirDrop" : "System Share Menu", imageData: nil, supportsRawText: quickShareProvider != "AirDrop")
    }

    var body: some View {
        dropArea
            .overlay(ShareDropTarget(enabled: !isProcessing && !quickShare.isBusy, onTarget: { vm.dropZoneTargeting = $0 }, onDrop: { providers, view in
                guard !isProcessing && !quickShare.isBusy else { return false }
                let shelfItems = ShelfSelectionModel.shared.isDragging
                    ? ShelfSelectionModel.shared.draggedItems : []
                vm.dropEvent = true
                isProcessing = true
                SharingStateManager.shared.beginInteraction()
                Task { await handleDrop(providers, from: view, shelfItems: shelfItems) }
                return true
            }, onClick: { view in
                Task { await quickShare.showFilePicker(for: selectedProvider, from: view) }
            }))
    }

    private var dropArea: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(colors: [Color.accentColor.opacity(vm.dropZoneTargeting ? 0.16 : 0.035), .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                )
                .shadow(color: Color.black.opacity(0.6), radius: 6, x: 0, y: 2)

            // Content
            VStack(spacing: 5) {
                ZStack {
                    Circle()
                        .fill(Color.white.opacity(
                            vm.dropZoneTargeting ? 0.11 : 0.09
                        ))
                        .frame(width: 50, height: 50)
                    Group {
                        if isProcessing {
                            ProgressView().controlSize(.small).tint(.white)
                        } else if let nsImg = selectedProvider.displayImage {
                            Image(nsImage: nsImg)
                                .resizable()
                                .aspectRatio(contentMode: .fit)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                        }
                    }
                    .frame(width: 34, height: 34)
                        .foregroundStyle(
                            vm.dropZoneTargeting ? Color.accentColor : Color.white.opacity(0.8)
                        )
                        .scaleEffect(
                            vm.dropZoneTargeting ? 1.06 : 1.0
                        )
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: vm.dropZoneTargeting)
                }

                Text(selectedProvider.id)
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.white.opacity(0.8))
                    .lineLimit(1).minimumScaleFactor(0.65)

                Text(isProcessing ? "Preparing…" : quickShare.isPickerOpen ? "Choose files…" : quickShare.isSharing ? "Sharing window open" : vm.dropZoneTargeting ? "Release to share" : "Drop to send")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
                    .lineLimit(2).multilineTextAlignment(.center)

            }
            .padding(12)
            
        }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .help("Drop files or links here to share. Drop in the tray to keep them on Shelf.")
    }

    // MARK: - Actions

    private func handleDrop(_ providers: [NSItemProvider], from view: NSView, shelfItems: [ShelfItem]) async {
        defer {
            isProcessing = false
            SharingStateManager.shared.endInteraction()
        }
        await quickShare.shareDroppedFiles(providers, using: selectedProvider, from: view, shelfItems: shelfItems)
    }
}

/// A real AppKit destination wins hit-testing over the ancestor SwiftUI Shelf
/// drop target, including drags originating in this same application.
private struct ShareDropTarget: NSViewRepresentable {
    let enabled: Bool
    let onTarget: (Bool) -> Void
    let onDrop: ([NSItemProvider], NSView) -> Bool
    let onClick: (NSView) -> Void
    func makeNSView(context: Context) -> ShareDropView { ShareDropView() }
    func updateNSView(_ view: ShareDropView, context: Context) {
        view.enabled = enabled
        view.onTarget = onTarget
        view.onDrop = onDrop
        view.onClick = onClick
    }
    static func dismantleNSView(_ view: ShareDropView, coordinator: ()) {
        view.unregisterDraggedTypes()
        view.onDrop = nil
        view.onClick = nil
        view.onTarget = nil
    }
}

final class ShareDropView: NSView {
    var enabled = true
    var onTarget: ((Bool) -> Void)?
    var onDrop: (([NSItemProvider], NSView) -> Bool)?
    var onClick: ((NSView) -> Void)?
    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL, .URL, .string, .png, .tiff])
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { if enabled { onClick?(self) } }
    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let accepted = enabled && sender.draggingPasteboard.canReadItem(withDataConformingToTypes: [UTType.fileURL.identifier, UTType.url.identifier, UTType.utf8PlainText.identifier, UTType.image.identifier])
        onTarget?(accepted)
        return accepted ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { draggingEntered(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { onTarget?(false) }
    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool { enabled }
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        onTarget?(false)
        return acceptPasteboard(sender.draggingPasteboard)
    }
    func acceptPasteboard(_ pasteboard: NSPasteboard) -> Bool {
        guard enabled else { return false }
        // Snapshot promised representations while the pasteboard still belongs to
        // this drag. Our own providers no longer depend on the source app callback.
        let providers = ShelfDropService.providers(from: pasteboard)
        guard !providers.isEmpty else { return false }
        return onDrop?(providers, self) ?? false
    }
}
