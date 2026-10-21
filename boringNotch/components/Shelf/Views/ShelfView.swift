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
    @FocusState private var searching: Bool

    private var filtered: [ShelfItem] {
        let matches = tvm.items.filter { filter.includes($0) && (search.isEmpty || $0.displayName.localizedCaseInsensitiveContains(search)) }
        return matches.filter(\.isPinned) + matches.filter { !$0.isPinned }
    }
    private var selected: [ShelfItem] { selection.selectedItems(in: filtered) }
    private var previewURLs: [URL] { selected.compactMap { $0.fileURL } }
    private var allPinned: Bool { !selected.isEmpty && selected.allSatisfy(\.isPinned) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            HStack(spacing: 10) {
                TextField("Search shelf…", text: $search).textFieldStyle(.roundedBorder)
                    .focused($searching).onExitCommand { searching = false }
                Picker("Filter", selection: $filter) {
                    ForEach(ShelfFilter.allCases) { Text($0.rawValue).tag($0) }
                }.labelsHidden().pickerStyle(.segmented).frame(width: 310)
            }
            HStack(spacing: 10) {
                FileShareView().frame(width: 82, height: 126).environmentObject(vm)
                dropPanel
            }
            HStack {
                if tvm.isLoading { ProgressView().controlSize(.mini); Text("Adding items…") }
                else { Text(status.isEmpty ? "⌘ click: multi-select · Double-click: open · Drag to another app" : status) }
                Spacer(minLength: 4)
                Text("Remove leaves source files untouched.")
            }.font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
        .padding(12).toolCard()
        .tint(accent.color)
        .quickLookPresenter(using: quickLookService)
        .onChange(of: search) { _, _ in refreshSelection() }
        .onChange(of: filter) { _, _ in refreshSelection() }
        .onChange(of: tvm.items) { _, _ in refreshSelection() }
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

    private var header: some View {
        HStack(spacing: 7) {
            Label("File Shelf", systemImage: "tray.full.fill").font(.headline)
            Text(selected.isEmpty ? "\(tvm.items.count) items" : "\(selected.count) selected")
                .font(.caption).foregroundStyle(.secondary)
            Spacer(minLength: 0)
            Button("Add", systemImage: "plus") { addFiles() }.toolButton(compact: true)
            Button("Preview", systemImage: "eye") { quickLookService.show(urls: previewURLs) }
                .toolButton(compact: true).disabled(previewURLs.isEmpty)
            Button {
                tvm.setPinned(!allPinned, ids: Set(selected.map(\.id)))
            } label: { Image(systemName: allPinned ? "pin.slash" : "pin") }
                .toolButton(compact: true).disabled(selected.isEmpty).help(allPinned ? "Unpin selected" : "Pin selected")
            ShelfShareSelectionButton(items: selected).frame(width: 58, height: 22)
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
            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 25)
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
                ScrollView(.horizontal) {
                    HStack(spacing: 5) {
                        ForEach(filtered) { item in
                            ShelfItemView(item: item).environmentObject(quickLookService)
                        }
                    }.padding(6)
                }.scrollIndicators(.visible)
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
