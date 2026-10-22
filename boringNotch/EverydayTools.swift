import AppKit
import Combine
import Defaults
import EventKit
import KeyboardShortcuts
import SwiftUI

struct FocusTask: Codable, Identifiable {
    var id = UUID()
    var title: String
    var completed = false
}

@MainActor
final class FocusTaskStore: ObservableObject {
    static let shared = FocusTaskStore()
    @Published private(set) var tasks: [FocusTask] = []
    @Published var isEditing = false
    private let storage: UserDefaults
    private let key = "notchLyric.focusTasks.v1"

    init(storage: UserDefaults = .standard) {
        self.storage = storage
        if let data = storage.data(forKey: key), let saved = try? JSONDecoder().decode([FocusTask].self, from: data) {
            tasks = saved
        }
    }

    func add(_ title: String) {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, tasks.count < 100 else { return }
        tasks.append(FocusTask(title: String(trimmed.prefix(200))))
        save()
    }

    func toggle(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].completed.toggle()
        save()
    }

    func complete(_ id: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
        tasks[index].completed = true
        save()
    }

    func remove(_ id: UUID) { tasks.removeAll { $0.id == id }; save() }

    private func save() {
        if let data = try? JSONEncoder().encode(tasks) { storage.set(data, forKey: key) }
    }
}

struct FocusTaskList: View {
    @Default(.toolsAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ObservedObject private var calendar = CalendarManager.shared
    @ObservedObject private var timer = FocusTimerModel.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("Up next", systemImage: "checklist").font(.headline)
                Spacer()
                Text("\(calendar.nativeReminders.count)").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                Text("Apple Reminders").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.reminders") {
                        NSWorkspace.shared.open(url)
                    }
                } label: { Image(systemName: "arrow.up.forward.app") }
                    .buttonStyle(.plain).help("Open Apple Reminders to add or edit tasks")
            }
            if calendar.reminderAuthorizationStatus != .fullAccess {
                Button("Connect Reminders") { Task { await calendar.checkReminderAuthorization() } }
                    .toolButton(prominent: true, compact: true)
                if calendar.reminderAuthorizationStatus == .denied {
                    Button("Privacy settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")!)
                    }.toolButton(compact: true)
                }
            }
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if calendar.nativeReminders.isEmpty {
                        Text("Add a reminder in Apple Reminders, then select it here to focus.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    ForEach(calendar.nativeReminders) { task in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: timer.selectedReminderID == task.id ? "target" : "circle")
                                .foregroundStyle(accent.color)
                            Button {
                                timer.selectReminder(id: task.id, title: task.title)
                            } label: {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(task.title).font(.caption).lineLimit(2)
                                    Text(task.list).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .buttonStyle(.plain)
                            .disabled(timer.pendingReminderID != nil || (timer.isVisible && !timer.isFinished))
                            .help("Use as focus goal")
                        }
                        .padding(6)
                        .background(timer.selectedReminderID == task.id ? accent.color.opacity(0.15) : Color.primary.opacity(0.035), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
            }
            .frame(height: 110)
            if timer.pendingReminderID != nil {
                Text(calendar.syncError ?? "Completing reminder…").font(.caption2).foregroundStyle(.secondary).lineLimit(2)
                Button("Retry sync") { Task { await timer.syncCompletedReminder() } }
                    .toolButton(compact: true).disabled(timer.isSyncingReminder)
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: calendar.nativeReminders.map(\.id))
        .task { await calendar.reloadCalendarAndReminderLists(); await timer.syncCompletedReminder() }
    }
}

extension FocusTimerModel {
    static let shared = FocusTimerModel(completeReminder: { id in
        await CalendarManager.shared.completeNativeReminder(id)
    })
}

struct ClipboardEntry: Identifiable {
    let id = UUID()
    let text: String
    var pinned = false
}

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    static let shared = ClipboardHistoryStore()
    @Published var enabled = UserDefaults.standard.bool(forKey: "notchLyric.clipboardEnabled") {
        didSet {
            UserDefaults.standard.set(enabled, forKey: "notchLyric.clipboardEnabled")
            if !enabled { entries = []; lastCopiedID = nil }
            configure()
        }
    }
    @Published private(set) var entries: [ClipboardEntry] = []
    @Published var isEditing = false
    @Published private(set) var pasteStatus = ""
    @Published private(set) var isPasting = false
    @Published private(set) var lastCopiedID: UUID?
    private var lastTarget: NSRunningApplication?
    private var ticker: AnyCancellable?
    private var lastChange = NSPasteboard.general.changeCount
    private var sessionActive = true
    private var observers: [AnyCancellable] = []

    init() {
        rememberTarget(NSWorkspace.shared.frontmostApplication)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didActivateApplicationNotification)
            .sink { [weak self] notification in MainActor.assumeIsolated {
                self?.rememberTarget(notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)
            } }.store(in: &observers)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidResignActiveNotification)
            .sink { [weak self] _ in MainActor.assumeIsolated { self?.sessionActive = false } }
            .store(in: &observers)
        NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.sessionDidBecomeActiveNotification)
            .sink { [weak self] _ in MainActor.assumeIsolated {
                self?.lastChange = NSPasteboard.general.changeCount
                self?.sessionActive = true
            } }.store(in: &observers)
        configure()
    }

    private func configure() {
        ticker?.cancel(); ticker = nil
        lastChange = NSPasteboard.general.changeCount
        guard enabled else { return }
        ticker = Timer.publish(every: 0.75, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
    }

    private func poll() {
        let board = NSPasteboard.general
        guard board.changeCount != lastChange else { return }
        lastChange = board.changeCount
        lastCopiedID = nil
        guard sessionActive else { return }
        let blocked = ["org.nspasteboard.ConcealedType", "org.nspasteboard.TransientType", "org.nspasteboard.AutoGeneratedType"]
        guard !blocked.contains(where: { board.types?.contains(NSPasteboard.PasteboardType($0)) == true }) else { return }
        let app = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
        guard !["com.1password.1password", "com.agilebits.onepassword7", "com.apple.Passwords", "com.bitwarden.desktop"].contains(app),
              let text = board.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              text.utf8.count <= 32_768 else { return }
        guard !entries.contains(where: { $0.text == text }) else { return }
        entries.insert(ClipboardEntry(text: text), at: 0)
        while entries.count > 50 {
            if let index = entries.lastIndex(where: { !$0.pinned }) { entries.remove(at: index) } else { entries.removeLast() }
        }
    }

    @discardableResult
    func copy(_ entry: ClipboardEntry) -> Bool {
        NSPasteboard.general.clearContents()
        let copied = NSPasteboard.general.setString(entry.text, forType: .string)
        lastChange = NSPasteboard.general.changeCount
        lastCopiedID = copied ? entry.id : nil
        return copied
    }

    private func rememberTarget(_ app: NSRunningApplication?) {
        guard let app, app.processIdentifier != ProcessInfo.processInfo.processIdentifier,
              app.activationPolicy == .regular else { return }
        lastTarget = app
    }

    func rememberDestination() { rememberTarget(NSWorkspace.shared.frontmostApplication) }

    @discardableResult
    func paste(_ entry: ClipboardEntry) async -> Bool {
        guard !isPasting else { return false }
        isPasting = true
        defer { isPasting = false }
        let destination = lastTarget
        guard copy(entry) else { pasteStatus = "Could not copy text."; return false }
        guard let target = destination, !target.isTerminated else {
            pasteStatus = "Copied. Open a destination app first."
            return false
        }
        guard await XPCHelperClient.shared.postEventAccess() else {
            pasteStatus = "macOS denied paste access for this build. Text copied; use ⌘V."
            return false
        }
        NSApp.keyWindow?.resignKey()
        // A nonactivating panel can leave keyboard focus in our search field
        // even while the destination is still the frontmost application.
        NSApp.deactivate()
        target.activate(options: [])
        for _ in 0..<16 {
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier { break }
            do { try await Task.sleep(for: .milliseconds(50)) } catch { return false }
        }
        // Allow the destination's first responder to regain keyboard focus.
        do { try await Task.sleep(for: .milliseconds(150)) } catch { return false }
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
            pasteStatus = "Copied. Could not return to the destination app."
            return false
        }
        let sent = await XPCHelperClient.shared.pasteIntoApplication(target.processIdentifier)
        pasteStatus = sent ? "Paste sent to \(target.localizedName ?? "app")" : "Copied. Paste was not available; use Command-V."
        return sent
    }

    func pin(_ id: UUID) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        entries[index].pinned.toggle()
    }

    func clear() { entries = []; lastCopiedID = nil }
}

enum EverydayReminder: String { case water = "Time for water", eyes = "Rest your eyes" }

@MainActor
final class EverydayReminderStore: ObservableObject {
    static let shared = EverydayReminderStore()
    @Published var waterEnabled = false { didSet { reschedule() } }
    @Published var eyesEnabled = false { didSet { reschedule() } }
    @Published var waterMinutes = 45 { didSet { reschedule() } }
    @Published var eyesMinutes = 20 { didSet { reschedule() } }
    @Published var displaySeconds = 5 { didSet { reschedule() } }
    @Published private(set) var pending: EverydayReminder?
    @Published private(set) var remainingSeconds = 0
    private var presentationDeadline: Date?
    private var presentationOwners: Set<UUID> = []
    private var presentationTicker: AnyCancellable?
    private var isPreview = false
    private var waterDue: Date?
    private var eyesDue: Date?
    private var ticker: AnyCancellable?
    private let storage: UserDefaults
    private let now: () -> Date

    init(storage: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.storage = storage; self.now = now
        waterEnabled = storage.bool(forKey: "notchLyric.waterEnabled")
        eyesEnabled = storage.bool(forKey: "notchLyric.eyesEnabled")
        waterMinutes = max(5, min(120, storage.object(forKey: "notchLyric.waterMinutes") as? Int ?? 45))
        eyesMinutes = max(5, min(120, storage.object(forKey: "notchLyric.eyesMinutes") as? Int ?? 20))
        displaySeconds = max(5, min(30, storage.object(forKey: "notchLyric.reminderDisplaySeconds") as? Int ?? 5))
        reschedule()
    }

    private func reschedule() {
        storage.set(waterEnabled, forKey: "notchLyric.waterEnabled")
        storage.set(eyesEnabled, forKey: "notchLyric.eyesEnabled")
        storage.set(waterMinutes, forKey: "notchLyric.waterMinutes")
        storage.set(eyesMinutes, forKey: "notchLyric.eyesMinutes")
        storage.set(displaySeconds, forKey: "notchLyric.reminderDisplaySeconds")
        stopPresentation()
        pending = nil
        waterDue = waterEnabled ? now().addingTimeInterval(Double(waterMinutes * 60)) : nil
        eyesDue = eyesEnabled ? now().addingTimeInterval(Double(eyesMinutes * 60)) : nil
        ticker?.cancel(); ticker = nil
        if waterEnabled || eyesEnabled {
            ticker = Timer.publish(every: 15, on: .main, in: .common).autoconnect().sink { [weak self] _ in
                MainActor.assumeIsolated { self?.check() }
            }
        }
    }

    func check() {
        if pending != nil {
            if let presentationDeadline {
                remainingSeconds = max(0, Int(ceil(presentationDeadline.timeIntervalSince(now()))))
                if remainingSeconds == 0 { acknowledge() }
            }
            return
        }
        if let waterDue, now() >= waterDue { enqueue(.water) }
        else if let eyesDue, now() >= eyesDue { enqueue(.eyes) }
    }

    private func enqueue(_ reminder: EverydayReminder, preview: Bool = false) {
        stopPresentation()
        isPreview = preview
        remainingSeconds = max(5, min(30, displaySeconds))
        pending = reminder
    }

    func preview(_ reminder: EverydayReminder) {
        guard pending == nil else { return }
        enqueue(reminder, preview: true)
    }

    func beginPresentation(owner: UUID) {
        guard pending != nil else { return }
        presentationOwners.insert(owner)
        guard presentationDeadline == nil else { return }
        presentationDeadline = now().addingTimeInterval(Double(max(1, remainingSeconds)))
        presentationTicker = Timer.publish(every: 0.25, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
    }

    func endPresentation(owner: UUID) {
        presentationOwners.remove(owner)
        guard presentationOwners.isEmpty else { return }
        if let presentationDeadline { remainingSeconds = max(1, Int(ceil(presentationDeadline.timeIntervalSince(now())))) }
        presentationDeadline = nil
        presentationTicker?.cancel(); presentationTicker = nil
    }

    private func stopPresentation() {
        presentationDeadline = nil
        presentationTicker?.cancel(); presentationTicker = nil
        presentationOwners.removeAll()
        remainingSeconds = 0
    }

    func acknowledge(snooze: Bool = false) {
        guard let pending else { return }
        if !isPreview {
            if pending == .water { waterDue = now().addingTimeInterval(Double(snooze ? 300 : waterMinutes * 60)) }
            else { eyesDue = now().addingTimeInterval(Double(snooze ? 300 : eyesMinutes * 60)) }
        }
        stopPresentation()
        isPreview = false
        self.pending = nil
    }
}

struct EverydayToolsView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @Default(.toolsAccent) private var accent
    @Default(.toolsRed) private var red
    @Default(.toolsGreen) private var green
    @Default(.toolsBlue) private var blue
    @ObservedObject private var clipboard = ClipboardHistoryStore.shared
    @ObservedObject private var reminders = EverydayReminderStore.shared
    @State private var search = ""
    @FocusState private var searching: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var filteredEntries: [ClipboardEntry] {
        clipboard.entries.filter { search.isEmpty || $0.text.localizedCaseInsensitiveContains(search) }
            .sorted { $0.pinned && !$1.pinned }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Clipboard", systemImage: "doc.on.clipboard").font(.headline)
                    Spacer()
                    Button { ClipboardPanelController.shared.present() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                        .buttonStyle(.plain).help("Open searchable clipboard panel · Shortcut in Settings")
                    Toggle("Capture", isOn: $clipboard.enabled).toggleStyle(.switch).controlSize(.mini)
                }
                if clipboard.enabled {
                    TextField("Search copied text", text: $search).textFieldStyle(.roundedBorder)
                        .focused($searching).onExitCommand { searching = false }
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            if filteredEntries.isEmpty { Text("Copied text appears here.").font(.caption).foregroundStyle(.secondary) }
                            ForEach(filteredEntries) { entry in
                                HStack {
                                    Button {
                                        Task {
                                            if await clipboard.paste(entry) {
                                                searching = false
                                                clipboard.isEditing = false
                                                vm.close()
                                            }
                                        }
                                    } label: {
                                        Text(entry.text).font(.caption).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                                    }.buttonStyle(.plain).help("Copy text; paste into the last app when permitted")
                                    .disabled(clipboard.isPasting)
                                    if clipboard.lastCopiedID == entry.id {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                            .help("Copied to clipboard").accessibilityLabel("Copied to clipboard")
                                    }
                                    Button { clipboard.pin(entry.id) } label: { Image(systemName: entry.pinned ? "pin.fill" : "pin") }
                                        .buttonStyle(.plain).help("Pin copied text")
                                }
                                .contextMenu {
                                    Button("Copy only") { clipboard.copy(entry) }
                                }
                                .padding(7).background(.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                            }
                        }
                    }.frame(height: 174)
                } else {
                    Text("Enable to keep up to 50 recent text copies in memory. Clipboard contents may include private information.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity).toolCard()
            VStack(alignment: .leading, spacing: 10) {
                VStack(alignment: .leading, spacing: 7) {
                Label("Take a moment", systemImage: "leaf").font(.headline)
                if let pending = reminders.pending {
                    Text(pending.rawValue).font(.headline)
                    HStack {
                        Button("Done") { reminders.acknowledge() }.toolButton(prominent: true, compact: true)
                        Button("5 min") { reminders.acknowledge(snooze: true) }.toolButton(compact: true)
                    }
                } else {
                    Toggle("Water reminder", isOn: $reminders.waterEnabled)
                    Toggle("Eye break", isOn: $reminders.eyesEnabled)
                }
                }.frame(maxWidth: .infinity, alignment: .leading).toolCard()
                TodayActivityView()
            }.frame(width: 210)
        }
        .onChange(of: searching) { _, value in clipboard.isEditing = value }
        .tint(accent.color)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: clipboard.lastCopiedID)
        .onDisappear { clipboard.isEditing = false }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didResignKeyNotification)) { notification in
            if notification.object is BoringNotchSkyLightWindow { searching = false }
        }
    }
}

struct EverydayToolsSettings: View {
    @ObservedObject private var clipboard = ClipboardHistoryStore.shared
    @ObservedObject private var reminders = EverydayReminderStore.shared
    @State private var confirmClear = false

    var body: some View {
        Form {
            Section("Clipboard history") {
                Toggle("Capture copied text", isOn: $clipboard.enabled)
                KeyboardShortcuts.Recorder("Open clipboard search:", name: .clipboardHistoryPanel)
                Text("Search as you type. ↑ ↓ select, Return copies and attempts paste, Shift-Return copies only, and Escape closes. A green check confirms copying; auto-paste requires macOS Accessibility access.")
                    .font(.caption).foregroundStyle(.secondary)
                if !clipboard.pasteStatus.isEmpty {
                    Text(clipboard.pasteStatus).font(.caption).foregroundStyle(.secondary)
                }
                Text("Text only, up to 50 items. History and pins stay in memory and clear when you quit. Disabling capture clears history. Capture skips password-manager apps and clipboard content marked confidential.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Clear history", role: .destructive) { confirmClear = true }.disabled(clipboard.entries.isEmpty)
                Button("Enable auto-paste access") {
                    Task { _ = await XPCHelperClient.shared.postEventAccess(prompt: true) }
                }
                Button("Open Accessibility settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                }
                Button("Reveal this app in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([Bundle.main.bundleURL])
                }
                Text("If access is enabled but pasting still fails after rebuilding: quit this app, remove its old Accessibility entry, add this exact app again, then relaunch. Local ad-hoc builds may need permission again after code changes.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Reminders") {
                Toggle("Water reminder", isOn: $reminders.waterEnabled)
                Stepper("Every \(reminders.waterMinutes) min", value: $reminders.waterMinutes, in: 5...120, step: 5).disabled(!reminders.waterEnabled)
                Toggle("Eye break reminder", isOn: $reminders.eyesEnabled)
                Stepper("Every \(reminders.eyesMinutes) min", value: $reminders.eyesMinutes, in: 5...120, step: 5).disabled(!reminders.eyesEnabled)
                Stepper("Show notification for \(reminders.displaySeconds) seconds", value: $reminders.displaySeconds, in: 5...30, step: 5)
                HStack {
                    Button("Preview water") { reminders.preview(.water) }.disabled(reminders.pending != nil)
                    Button("Preview eye break") { reminders.preview(.eyes) }.disabled(reminders.pending != nil)
                }
                Text("Large animated reminders appear automatically without taking keyboard focus, then dismiss after the countdown. Skip dismisses; Later snoozes for 5 minutes. Alerts wait while you edit in the notch, drag, preview files, or share. Preview does not enable reminders or change their schedule. Intervals restart when settings change or the app restarts.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("File shelf") {
                Text("Use the tray tab or drag files onto the notch to stage files between apps. Shelf preferences are available in Settings → Shelf.")
            }
        }
        .navigationTitle("Everyday tools")
        .confirmationDialog("Clear clipboard history?", isPresented: $confirmClear) {
            Button("Clear history", role: .destructive) { clipboard.clear() }
        }
    }
}

@MainActor
final class ClipboardPanelSelection: ObservableObject {
    @Published var presentationID = UUID()
    @Published var search = ""
    @Published var selectedID: UUID?

    func items(from entries: [ClipboardEntry]) -> [ClipboardEntry] {
        // Stable ordering: pinned first, newest first within each group.
        let matches = entries.filter { search.isEmpty || $0.text.localizedCaseInsensitiveContains(search) }
        return matches.filter(\.pinned) + matches.filter { !$0.pinned }
    }

    func move(_ delta: Int, in entries: [ClipboardEntry]) {
        let matches = items(from: entries)
        guard !matches.isEmpty else { selectedID = nil; return }
        let current = matches.firstIndex { $0.id == selectedID } ?? 0
        selectedID = matches[min(matches.count - 1, max(0, current + delta))].id
    }

    func reconcile(_ entries: [ClipboardEntry]) {
        let matches = items(from: entries)
        if !matches.contains(where: { $0.id == selectedID }) { selectedID = matches.first?.id }
    }
}

private final class ClipboardFloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class ClipboardPanelController: NSObject, NSWindowDelegate {
    static let shared = ClipboardPanelController()
    private var panel: ClipboardFloatingPanel?
    private var keyMonitor: Any?
    private let selection = ClipboardPanelSelection()
    private let clipboard = ClipboardHistoryStore.shared

    func toggle() {
        if panel?.isVisible == true { dismiss() } else { present() }
    }

    func present() {
        clipboard.rememberDestination()
        selection.presentationID = UUID()
        selection.search = ""
        selection.selectedID = nil
        selection.reconcile(clipboard.entries)
        if panel == nil {
            let window = ClipboardFloatingPanel(contentRect: NSRect(x: 0, y: 0, width: 470, height: 390),
                styleMask: [.titled, .fullSizeContentView, .nonactivatingPanel], backing: .buffered, defer: false)
            window.title = "Clipboard"
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.standardWindowButton(.closeButton)?.isHidden = true
            window.isReleasedWhenClosed = false
            window.isFloatingPanel = true
            window.level = .floating
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = true
            window.delegate = self
            window.contentView = NSHostingView(rootView: ClipboardPanelView(selection: selection,
                paste: { [weak self] entry in self?.choose(entry) },
                copyOnly: { [weak self] entry in self?.choose(entry, copyOnly: true) },
                dismiss: { [weak self] in self?.dismiss() }))
            panel = window
        }
        if let screen = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main,
           let panel {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(x: frame.midX - panel.frame.width / 2,
                                         y: frame.midY - panel.frame.height / 2 + min(120, frame.height * 0.12)))
        }
        panel?.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func dismiss() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        panel?.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) { dismiss() }

    private func choose(_ entry: ClipboardEntry, copyOnly: Bool = false) {
        if copyOnly { clipboard.copy(entry) }
        else {
            Task { if await clipboard.paste(entry) { dismiss() } }
        }
    }

    private func installKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, NSApp.keyWindow === self.panel else { return event }
            // Do not consume input-method composition or text-editing shortcuts.
            if let editor = self.panel?.firstResponder as? NSTextView, editor.hasMarkedText() { return event }
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            switch event.keyCode {
            case 53: self.dismiss(); return nil
            case 125: self.selection.move(1, in: self.clipboard.entries); return nil
            case 126: self.selection.move(-1, in: self.clipboard.entries); return nil
            case 36, 76:
                self.selection.reconcile(self.clipboard.entries)
                if let item = self.clipboard.entries.first(where: { $0.id == self.selection.selectedID }) {
                    self.choose(item, copyOnly: event.modifierFlags.contains(.shift))
                }
                return nil
            default: return event
            }
        }
    }
}

private struct ClipboardPanelView: View {
    @ObservedObject var selection: ClipboardPanelSelection
    let paste: (ClipboardEntry) -> Void
    let copyOnly: (ClipboardEntry) -> Void
    let dismiss: () -> Void
    @ObservedObject private var clipboard = ClipboardHistoryStore.shared
    @Default(.toolsAccent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var searching: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Clipboard", systemImage: "doc.on.clipboard").font(.headline)
                Text("\(selection.items(from: clipboard.entries).count)").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button(action: dismiss) { Image(systemName: "xmark") }.buttonStyle(.plain).help("Close · Esc")
            }
            if clipboard.enabled {
                TextField("Search copied text…", text: $selection.search)
                    .textFieldStyle(.roundedBorder).focused($searching)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 6) {
                            if selection.items(from: clipboard.entries).isEmpty {
                                VStack(spacing: 8) {
                                    Image(systemName: "doc.text.magnifyingglass").font(.title2)
                                    Text(selection.search.isEmpty ? "Copy text to get started" : "No matching copies")
                                    Text(selection.search.isEmpty ? "History stays on this Mac, in memory." : "Try a shorter search.")
                                        .font(.caption).foregroundStyle(.secondary)
                                }.frame(maxWidth: .infinity).padding(.vertical, 35)
                            }
                            ForEach(selection.items(from: clipboard.entries)) { entry in
                                HStack(spacing: 10) {
                                    Button { paste(entry) } label: {
                                        Text(entry.text).font(.system(size: 12)).lineLimit(3)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .contentShape(Rectangle())
                                    }.buttonStyle(.plain).disabled(clipboard.isPasting)
                                    if clipboard.lastCopiedID == entry.id {
                                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                                            .help("Copied to clipboard").accessibilityLabel("Copied to clipboard")
                                    }
                                    Button { clipboard.pin(entry.id) } label: {
                                        Image(systemName: entry.pinned ? "pin.fill" : "pin")
                                    }.buttonStyle(.plain).help(entry.pinned ? "Unpin" : "Pin")
                                }
                                .padding(10)
                                .background(selection.selectedID == entry.id ? accent.color.opacity(0.2) : Color.primary.opacity(0.04),
                                            in: RoundedRectangle(cornerRadius: 10))
                                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(selection.selectedID == entry.id ? accent.color.opacity(0.6) : .clear))
                                .id(entry.id)
                                .contextMenu { Button("Copy only") { copyOnly(entry) } }
                                .accessibilityAddTraits(selection.selectedID == entry.id ? .isSelected : [])
                            }
                        }
                    }
                    .onChange(of: selection.selectedID) { _, id in
                        if let id {
                            withAnimation(reduceMotion ? nil : .easeOut(duration: 0.12)) { proxy.scrollTo(id) }
                        }
                    }
                }
                Text("↑ ↓ Select     ⏎ Copy / paste     ⇧⏎ Copy only     Esc Close")
                    .font(.caption2).foregroundStyle(.secondary)
            } else {
                Spacer()
                Label("Clipboard history is off", systemImage: "hand.raised").font(.headline)
                Text("Opt in to capture up to 50 recent text copies. Turning it off clears history.")
                    .font(.caption).foregroundStyle(.secondary)
                Button("Enable clipboard history") { clipboard.enabled = true; searching = true }
                    .toolButton(prominent: true)
                Spacer()
            }
        }
        .padding(18).frame(width: 470, height: 390)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .tint(accent.color)
        .task(id: selection.presentationID) {
            searching = false
            await Task.yield()
            searching = true
        }
        .onChange(of: selection.search) { _, _ in
            selection.selectedID = nil
            selection.reconcile(clipboard.entries)
        }
        .onChange(of: clipboard.entries.map(\.id)) { _, _ in selection.reconcile(clipboard.entries) }
    }
}

private struct WellnessGlassShape: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX * 0.83, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.maxX * 0.17, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

struct WellnessReminderBanner: View {
    let reminder: EverydayReminder
    @ObservedObject private var reminders = EverydayReminderStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var startedAt = Date()
    private var tint: Color { reminder == .water ? .cyan : .mint }

    var body: some View {
        HStack(spacing: 22) {
            ZStack {
                Circle().stroke(.white.opacity(0.1), lineWidth: 2)
                Circle().trim(from: 0, to: Double(reminders.remainingSeconds) / Double(max(1, reminders.displaySeconds)))
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .animation(reduceMotion ? nil : .linear(duration: 0.25), value: reminders.remainingSeconds)
                if reduceMotion {
                    illustration(elapsed: 1, animated: false)
                } else {
                    TimelineView(.animation(minimumInterval: 1.0 / 15)) { context in
                        illustration(elapsed: context.date.timeIntervalSince(startedAt), animated: true)
                    }
                }
            }.frame(width: 80, height: 80).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 7) {
                Text(reminder == .water ? "Time to hydrate" : "Look around")
                    .font(.system(size: 22, weight: .semibold)).foregroundStyle(.white)
                Text(reminder == .water ? "Take a sip of water." : "Give your eyes a moment away from the screen.")
                    .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Label(reminder == .water ? "A small pause for you" : "A little pause for your eyes",
                      systemImage: reminder == .water ? "drop.fill" : "leaf")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(tint)
            }
            Spacer(minLength: 6)
            VStack(spacing: 8) {
                Text("\(reminders.remainingSeconds)s").font(.system(size: 23, weight: .semibold))
                    .monospacedDigit().foregroundStyle(.white).contentTransition(.numericText())
                HStack(spacing: 6) {
                    Button("Skip") { reminders.acknowledge() }
                    Button("Later") { reminders.acknowledge(snooze: true) }.help("Remind me again in 5 minutes")
                }.buttonStyle(.bordered).controlSize(.small).tint(tint)
            }
        }
        .frame(minHeight: 104)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(reminder == .water ? "Water reminder" : "Eye break reminder")
        .onChange(of: reminder) { startedAt = Date() }
    }

    private func illustration(elapsed: TimeInterval, animated: Bool) -> some View {
        WellnessCatMascot(isHydrating: reminder == .water, elapsed: elapsed, animated: animated)
    }
}

/// Both previews and scheduled reminders share MORIS's palette and resting eyes.
private struct WellnessCatMascot: View {
    let isHydrating: Bool
    let elapsed: TimeInterval
    let animated: Bool
    @Default(.catEyePalette) private var palette

    var body: some View {
        ZStack {
            ZStack {
                WellnessCatHead()
                    .fill(LinearGradient(colors: palette.colors.map { $0.opacity(0.16) }, startPoint: .top, endPoint: .bottom))
                WellnessCatHead().stroke(palette.colors[0].opacity(0.6), lineWidth: 1)
                RestingCatEyes(cameraGap: 0, height: 30, isActive: animated)
                    .scaleEffect(0.74).offset(y: 1)
                Image(systemName: "triangle.fill")
                    .resizable().scaledToFit().frame(width: 5, height: 4)
                    .rotationEffect(.degrees(180)).foregroundStyle(palette.colors[0])
                    .offset(y: 13)
                Path { path in
                    path.move(to: CGPoint(x: 0, y: 0))
                    path.addQuadCurve(to: CGPoint(x: 6, y: 0), control: CGPoint(x: 3, y: 5))
                    path.addQuadCurve(to: CGPoint(x: 12, y: 0), control: CGPoint(x: 9, y: 5))
                }.stroke(palette.colors[0].opacity(0.65), lineWidth: 1)
                    .frame(width: 12, height: 4).offset(y: 19)
            }
            .frame(width: 58, height: 52)
            .rotationEffect(.degrees(animated && isHydrating ? sin(elapsed * 1.8) * 3 : 0))
            .offset(x: isHydrating ? -5 : 0, y: -3)

            if isHydrating {
                ZStack(alignment: .bottom) {
                    WellnessGlassShape().fill(.black)
                    Rectangle()
                        .fill(LinearGradient(colors: [.cyan.opacity(0.9), .mint.opacity(0.6)], startPoint: .top, endPoint: .bottom))
                        .frame(height: animated ? 7 + 9 * min(1, max(0, elapsed / 4)) : 13)
                        .clipShape(WellnessGlassShape())
                    WellnessGlassShape().stroke(.white.opacity(0.8), lineWidth: 1)
                }
                .frame(width: 18, height: 25)
                .rotationEffect(.degrees(-8)).offset(x: 23, y: 20)
            }
        }
        .frame(width: 76, height: 76)
        .allowsHitTesting(false)
    }
}

private struct WellnessCatHead: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            let w = rect.width
            let h = rect.height
            path.move(to: CGPoint(x: w * 0.08, y: h * 0.42))
            path.addLine(to: CGPoint(x: w * 0.08, y: h * 0.02))
            path.addQuadCurve(to: CGPoint(x: w * 0.32, y: h * 0.22), control: CGPoint(x: w * 0.19, y: h * 0.04))
            path.addQuadCurve(to: CGPoint(x: w * 0.68, y: h * 0.22), control: CGPoint(x: w * 0.5, y: h * 0.14))
            path.addQuadCurve(to: CGPoint(x: w * 0.92, y: h * 0.02), control: CGPoint(x: w * 0.81, y: h * 0.04))
            path.addLine(to: CGPoint(x: w * 0.92, y: h * 0.42))
            path.addCurve(to: CGPoint(x: w * 0.5, y: h * 0.98),
                          control1: CGPoint(x: w * 1.06, y: h * 0.83), control2: CGPoint(x: w * 0.8, y: h * 0.98))
            path.addCurve(to: CGPoint(x: w * 0.08, y: h * 0.42),
                          control1: CGPoint(x: w * 0.2, y: h * 0.98), control2: CGPoint(x: -w * 0.06, y: h * 0.83))
            path.closeSubpath()
        }
    }
}

struct TodayActivityView: View {
    @ObservedObject private var calendar = CalendarManager.shared

    private var todaysEvents: [EventModel] {
        calendar.events.filter { event in
            if case .reminder = event.type { return false }
            return Calendar.current.isDateInToday(event.start) ||
                (event.start < Calendar.current.startOfDay(for: Date()) && event.end > Calendar.current.startOfDay(for: Date()))
        }.sorted { $0.start < $1.start }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("Today activity", systemImage: "calendar").font(.headline)
                Spacer(minLength: 2)
                Button { Task { await calendar.updateCurrentDate(Date()) } } label: {
                    Image(systemName: "arrow.clockwise")
                }.buttonStyle(.plain).help("Refresh Apple Calendar")
            }
            if calendar.calendarAuthorizationStatus == .fullAccess {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        if todaysEvents.isEmpty {
                            Text("No events today.").font(.caption).foregroundStyle(.secondary)
                        }
                        ForEach(todaysEvents) { event in
                            HStack(alignment: .top, spacing: 6) {
                                RoundedRectangle(cornerRadius: 2).fill(Color.accentColor.opacity(0.8)).frame(width: 3)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title).font(.caption.weight(.medium)).lineLimit(2)
                                    if event.isAllDay { Text("All day").font(.caption2).foregroundStyle(.secondary) }
                                    else {
                                        HStack(spacing: 3) {
                                            Text(event.start, style: .time)
                                            Text("–")
                                            Text(event.end, style: .time)
                                        }.font(.caption2).foregroundStyle(.secondary)
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(5).background(.white.opacity(0.04), in: RoundedRectangle(cornerRadius: 7))
                        }
                    }
                }.frame(height: 82)
            } else {
                Text("Your events from Apple Calendar.").font(.caption).foregroundStyle(.secondary)
                Button("Connect Calendar") { Task { await calendar.checkCalendarAuthorization() } }
                    .toolButton(prominent: true, compact: true)
                if calendar.calendarAuthorizationStatus == .denied {
                    Button("Privacy settings") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")!)
                    }.buttonStyle(.plain).font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).toolCard()
        .task { await calendar.reloadCalendarAndReminderLists(); await calendar.updateCurrentDate(Date()) }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged)) { _ in
            Task { await calendar.updateCurrentDate(Date()) }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            Task { await calendar.updateCurrentDate(Date()) }
        }
    }
}
