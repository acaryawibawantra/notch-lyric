import SwiftUI
import AppKit
import Defaults

enum ShelfFilter: String, CaseIterable, Identifiable {
    case all = "All", files = "Files", links = "Links", notes = "Notes", pinned = "Pinned"
    var id: String { rawValue }

    @MainActor func includes(_ item: ShelfItem) -> Bool {
        switch self {
        case .all: true
        case .pinned: item.isPinned
        case .files: if case .file = item.kind { true } else { false }
        case .links: if case .link = item.kind { true } else { false }
        case .notes: if case .text = item.kind { true } else { false }
        }
    }
}

struct ShelfView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var tvm = ShelfStateViewModel.shared
    @ObservedObject var selection = ShelfSelectionModel.shared
    @StateObject private var quickLookService = QuickLookService()
    @Default(.toolsAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var search = ""
    @State private var filter: ShelfFilter = .all
    @State private var status = ""
    @State private var confirmClear = false
    @State private var clearInteractionActive = false
    @State private var processing = false
    @FocusState private var searching: Bool

    private var filtered: [ShelfItem] {
        let matches = tvm.items.filter { filter.includes($0) && (search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search)) }
        return matches.filter(\.isPinned) + matches.filter { !$0.isPinned }
    }
    private var selected: [ShelfItem] { selection.selectedItems(in: filtered) }
    private var previewURLs: [URL] { selected.compactMap { $0.fileURL } }
    private var allPinned: Bool { !selected.isEmpty && selected.allSatisfy(\.isPinned) }
    private var selectedImages: [URL] { previewURLs.filter { ImageProcessingService.shared.isImageFile($0) } }
    private var canConvert: Bool { !selected.isEmpty && selectedImages.count == selected.count && !processing }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HStack(spacing: 10) {
                TextField("Search shelf…", text: $search).textFieldStyle(.roundedBorder)
                    .focused($searching).onExitCommand { searching = false }
                Picker("Filter", selection: $filter) {
                    ForEach(ShelfFilter.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().pickerStyle(.segmented).tint(.gray).frame(width: 280)
            }
            HStack(spacing: 10) {
                FileShareView().frame(width: 82, height: 126).environmentObject(vm)
                dropPanel
            }
            quickActions
        }
        .padding(12).toolCard()
        .tint(accent.color)
        .background(ShelfKeyboardBridge(onKey: handleKey))
        .quickLookPresenter(using: quickLookService)
        .onChange(of: search) { _, _ in refreshSelection() }
        .onChange(of: filter) { _, _ in refreshSelection() }
        .onChange(of: tvm.items) { _, _ in refreshSelection() }
        .onChange(of: tvm.dropFeedback) { _, message in
            status = message
            if !tvm.items.isEmpty { search = ""; filter = .all }
        }
        .task(id: status) {
            guard !status.isEmpty else { return }
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            guard !Task.isCancelled else { return }
            status = ""
        }
        .onChange(of: searching) { _, value in selection.isEditingSearch = value }
        .onChange(of: quickLookService.isQuickLookOpen) { _, showing in selection.isPreviewing = showing }
        .onChange(of: quickLookService.selectedURL) { _, url in
            if url == nil && quickLookService.isQuickLookOpen { quickLookService.hide() }
        }
        .onChange(of: selection.selectedIDs) { _, _ in
            if quickLookService.isQuickLookOpen {
                if previewURLs.isEmpty { quickLookService.hide() }
                else { quickLookService.updateSelection(urls: previewURLs) }
            }
        }
        .onAppear { refreshSelection(); tvm.cleanupInvalidItems() }
        .onDisappear {
            selection.isEditingSearch = false
            selection.isPreviewing = false
            quickLookService.hide()
            selection.setVisibleItems(nil)
            endClearInteraction()
        }
        .onChange(of: confirmClear) { _, showing in if !showing { endClearInteraction() } }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            if notification.object is BoringNotchSkyLightWindow { searching = false }
        }
        .confirmationDialog("Clear unpinned shelf items?", isPresented: $confirmClear) {
            Button("Remove unpinned items", role: .destructive) {
                let removable = tvm.items.filter { !$0.isPinned }
                for item in removable { tvm.remove(item) }
                selection.clear()
                status = "Unpinned entries removed. Source files are unchanged."
            }
        } message: {
            Text("Pinned items stay. Files you added remain in their original locations. App-created temporary copies may be cleaned up.")
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: selection.selectedIDs)
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        guard vm.notchState == .open, !searching, !processing, !confirmClear,
              !selection.isDragging, !SharingStateManager.shared.preventNotchClose else { return false }
        let modifiers = event.modifierFlags.intersection([.command, .shift, .option, .control])
        if modifiers == .command {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "a": selection.selectAll(filtered); return true
            case "c":
                guard !selected.isEmpty else { return false }
                status = "Copied \(ShelfActionService.copyItems(selected)) item(s)."
                return true
            default: return false
            }
        }
        guard modifiers.isEmpty else { return false }
        switch event.keyCode {
        case 123, 126: selection.moveSelection(by: -1, in: filtered); return true
        case 124, 125: selection.moveSelection(by: 1, in: filtered); return true
        case 49:
            if quickLookService.isQuickLookOpen { quickLookService.hide() }
            else if !previewURLs.isEmpty { quickLookService.show(urls: previewURLs) }
            else { return false }
            return true
        case 36, 76:
            guard !selected.isEmpty else { return false }
            for item in selected { ShelfActionService.open(item) }
            return true
        case 53:
            if quickLookService.isQuickLookOpen { quickLookService.hide() }
            else { selection.clear(); vm.close() }
            return true
        default: return false
        }
    }

    private var quickActions: some View {
        HStack(spacing: 8) {
            Menu {
                Button("PNG · Preserve transparency") { processImages(format: .png) }
                Button("JPEG · Quality 90%") { processImages(format: .jpeg) }
                Button("HEIC · Quality 90%") { processImages(format: .heic) }
            } label: {
                Label("Convert", systemImage: "arrow.triangle.2.circlepath")
            }
            .menuStyle(.borderlessButton).fixedSize()
            .disabled(!canConvert)
            .help("Select image files to convert offline. Originals stay unchanged.")
            Button("Make PDF", systemImage: "doc.richtext") { processImages(format: nil) }
                .toolButton(compact: true).disabled(!canConvert)
                .help("Combine selected images into a PDF in shelf order")
            Button("Copy", systemImage: "doc.on.doc") {
                let count = ShelfActionService.copyItems(selected)
                status = count > 0 ? "Copied \(count) item(s)." : "Could not copy selected items."
            }
            .toolButton(compact: true).disabled(selected.isEmpty || processing)
            Spacer(minLength: 0)
            if processing || tvm.isLoading { ProgressView().controlSize(.mini) }
            Text(processing ? "Creating files…" : tvm.isLoading ? "Adding files…" : status.isEmpty ? "← → Select · Space Preview · ↵ Open" : status)
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                .help(status.isEmpty ? "⌘ click to select more. Double-click to open. Originals stay in place." : status)
        }
        .frame(height: 24)
    }

    /// A nil format combines images into one PDF. Outputs are app-owned copies.
    private func processImages(format: ImageConversionOptions.ImageFormat?) {
        guard canConvert else { return }
        let urls = selectedImages
        processing = true
        SharingStateManager.shared.beginInteraction()
        Task { @MainActor in
            defer {
                processing = false
                SharingStateManager.shared.endInteraction()
            }
            var outputs: [ShelfItem] = []
            var failures = 0
            @MainActor func collect(_ url: URL?) throws {
                guard let url else { failures += 1; return }
                let bookmark = try Bookmark(url: url)
                outputs.append(ShelfItem(kind: .file(bookmark: bookmark.data), isTemporary: true))
            }
            if let format {
                for url in urls {
                    do {
                        let result = try await url.accessSecurityScopedResource { source in
                            try await ImageProcessingService.shared.convertImage(from: source, options: ImageConversionOptions(
                                format: format, compressionQuality: 0.9, maxDimension: nil, removeMetadata: true))
                        }
                        try collect(result)
                    } catch { failures += 1 }
                    await Task.yield()
                }
            } else {
                do {
                    let result = try await urls.accessSecurityScopedResources { sources in
                        try await ImageProcessingService.shared.createPDF(from: sources)
                    }
                    try collect(result)
                } catch { failures += 1 }
            }
            if !outputs.isEmpty {
                filter = .files
                search = ""
                tvm.add(outputs)
                refreshSelection()
                selection.selectAll(outputs)
            }
            status = outputs.isEmpty ? "Could not create files. Check file access and image formats."
                : "Created \(outputs.count) file(s)\(failures > 0 ? "; \(failures) failed" : ""). Originals unchanged."
        }
    }

    private var header: some View {
        HStack(spacing: 7) {
            Label("File Shelf", systemImage: "tray.full.fill").font(.headline)
            Text(selected.isEmpty ? (tvm.items.count == 1 ? "1 item" : "\(tvm.items.count) items") : "\(selected.count) selected")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            if !selected.isEmpty {
                if !previewURLs.isEmpty {
                    Button { quickLookService.show(urls: previewURLs) } label: { Image(systemName: "eye") }
                        .toolButton(compact: true).help("Preview selected files").accessibilityLabel("Preview selected files")
                }
                Button {
                    tvm.setPinned(!allPinned, ids: Set(selected.map(\.id)))
                } label: { Image(systemName: allPinned ? "pin.slash" : "pin") }
                    .toolButton(compact: true).help(allPinned ? "Unpin selected" : "Pin selected")
                    .accessibilityLabel(allPinned ? "Unpin selected" : "Pin selected")
                ShelfShareSelectionButton(items: selected).frame(width: 58, height: 22)
            }
            Button("Add", systemImage: "plus") { addFiles() }.toolButton(prominent: selected.isEmpty, compact: true)
            Menu {
                Button("Select all visible") { selection.selectAll(filtered) }.disabled(filtered.isEmpty)
                Button("Deselect") { selection.clear() }.disabled(selected.isEmpty)
                Divider()
                Button("Open selected") { for item in selected { ShelfActionService.open(item) } }.disabled(selected.isEmpty)
                Button("Show in Finder") { for item in selected { ShelfActionService.reveal(item) } }.disabled(previewURLs.isEmpty)
                Button("Copy selected") {
                    let count = ShelfActionService.copyItems(selected)
                    status = count == 0 ? "Could not copy selected items." : "Copied \(count) item(s). Paste into Finder or another app."
                }.disabled(selected.isEmpty)
                Button("Copy file paths") {
                    let paths = previewURLs.map(\.path)
                    if !paths.isEmpty {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(paths.joined(separator: "\n"), forType: .string)
                        status = "File paths copied."
                    }
                }.disabled(previewURLs.isEmpty)
                Divider()
                Button("Remove selected from shelf", role: .destructive) {
                    for item in selected { tvm.remove(item) }
                    selection.clear()
                    status = "Removed from shelf. Source files are unchanged."
                }.disabled(selected.isEmpty)
                Button("Clear unpinned…", role: .destructive) {
                    SharingStateManager.shared.beginInteraction()
                    clearInteractionActive = true
                    confirmClear = true
                }
                    .disabled(!tvm.items.contains { !$0.isPinned })
            } label: { Image(systemName: "ellipsis") }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28)
                .help("More shelf actions").accessibilityLabel("More shelf actions")
        }
    }

    private var dropPanel: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 13)
                .fill(accent.color.opacity(vm.dragDetectorTargeting ? 0.15 : 0.025))
                .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: vm.dragDetectorTargeting)
            if filtered.isEmpty {
                VStack(spacing: 5) {
                    Image(systemName: tvm.isEmpty ? "tray.and.arrow.down.fill" : "magnifyingglass").font(.title2)
                    Text(tvm.isEmpty ? "Drop files, links, or text" : "No matching items").font(.callout.weight(.medium))
                    Text(tvm.isEmpty ? "Or use Add to choose files and folders" : "Try another filter or search")
                        .font(.caption).foregroundStyle(.secondary)
                }.foregroundStyle(.secondary)
            } else {
                ScrollViewReader { proxy in
                ScrollView(.horizontal) {
                    HStack(spacing: 5) {
                        ForEach(filtered) { item in
                            ShelfItemView(item: item).environmentObject(quickLookService).id(item.id)
                        }
                    }.padding(6)
                }.scrollIndicators(.visible)
                .onChange(of: selection.selectedIDs) { _, _ in
                    guard let first = selected.first else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.18)) { proxy.scrollTo(first.id) }
                }
                .onChange(of: tvm.recentIDs) { _, ids in
                    guard let newest = filtered.last(where: { ids.contains($0.id) }) else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.2)) { proxy.scrollTo(newest.id) }
                }
                }
            }
            if vm.anyDropZoneTargeting && !selection.isDragging {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 24, weight: .medium))
                    let count = NSPasteboard(name: .drag).pasteboardItems?.count ?? 0
                    Text(count > 1 ? "Release to keep \(count) items" : "Release to keep on Shelf")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Original files stay in place").font(.caption).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black.opacity(0.92), in: RoundedRectangle(cornerRadius: 13))
                .foregroundStyle(accent.color)
                .allowsHitTesting(false)
                .transition(.opacity)
            }
        }
        .frame(height: 126)
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
            guard !selection.isDragging else { return false }
            vm.dropEvent = true
            tvm.load(providers)
            status = ""
            return true
        }
    }

    private func refreshSelection() { selection.setVisibleItems(filtered) }

    private func endClearInteraction() {
        guard clearInteractionActive else { return }
        clearInteractionActive = false
        SharingStateManager.shared.endInteraction()
    }

    private func addFiles() {
        SharingStateManager.shared.beginInteraction()
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = "Add to Shelf"
        panel.begin { response in
            defer { SharingStateManager.shared.endInteraction() }
            guard response == .OK else { return }
            var added: [ShelfItem] = []
            for url in panel.urls {
                let access = url.startAccessingSecurityScopedResource()
                if let bookmark = try? Bookmark(url: url) { added.append(ShelfItem(kind: .file(bookmark: bookmark.data))) }
                if access { url.stopAccessingSecurityScopedResource() }
            }
            tvm.add(added)
            status = added.count == panel.urls.count ? "Added to shelf. Source files stay in place." : "Some items could not be added. Check file access."
        }
    }
}

/// Local events only: hovering never steals keyboard focus from another app.
private struct ShelfKeyboardBridge: NSViewRepresentable {
    let onKey: (NSEvent) -> Bool
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.view = view
        context.coordinator.onKey = onKey
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown]) { [weak coordinator = context.coordinator] event in
            guard let coordinator, let view = coordinator.view, let window = view.window,
                  event.window === window else { return event }
            if event.type == .leftMouseDown {
                if view.bounds.contains(view.convert(event.locationInWindow, from: nil)) { window.makeKey() }
                return event
            }
            guard NSApp.keyWindow === window, !(window.firstResponder is NSTextView),
                  !(window.firstResponder is NSTextField), NSApp.modalWindow == nil else { return event }
            return coordinator.onKey?(event) == true ? nil : event
        }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) { context.coordinator.onKey = onKey }
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor) }
        coordinator.monitor = nil
        coordinator.onKey = nil
    }
    @MainActor final class Coordinator {
        weak var view: NSView?
        var monitor: Any?
        var onKey: ((NSEvent) -> Bool)?
    }
}

private struct ShelfShareSelectionButton: NSViewRepresentable {
    let items: [ShelfItem]
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSButton {
        let button = NSButton(title: "Share", target: context.coordinator, action: #selector(Coordinator.share(_:)))
        button.bezelStyle = .rounded
        button.controlSize = .small
        button.image = NSImage(systemSymbolName: "square.and.arrow.up", accessibilityDescription: nil)
        button.imagePosition = .imageLeading
        button.toolTip = "Share selected items"
        return button
    }
    func updateNSView(_ button: NSButton, context: Context) {
        context.coordinator.items = items
        button.isEnabled = !items.isEmpty
    }
    @MainActor final class Coordinator: NSObject {
        var items: [ShelfItem] = []
        @objc func share(_ sender: NSButton) {
            let payload: [Any] = items.compactMap { item in
                switch item.kind {
                case .file: item.fileURL as Any?
                case .link(let url): url as Any
                case .text(let text): text as Any
                }
            }
            guard !payload.isEmpty else { return }
            Task {
                await QuickShareService.shared.shareFilesOrText(payload,
                    using: QuickShareProvider(id: "System Share Menu", imageData: nil, supportsRawText: true), from: sender)
            }
        }
    }
}
