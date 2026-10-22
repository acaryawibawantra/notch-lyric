import AppKit
import Combine
import SwiftUI

/// MORIS implementation. No NotchPrompter source code is incorporated.
@MainActor
final class PrompterModel: ObservableObject {
    static let shared = PrompterModel()
    @Published var script = "" {
        didSet {
            let limited = String(script.prefix(50_000))
            if script != limited { script = limited; return }
            reset()
            save()
        }
    }
    @Published var speed: Double = 30 {
        didSet {
            let limited = speed.isFinite ? min(100, max(10, speed)) : 30
            if speed != limited { speed = limited; return }
            save()
        }
    }
    @Published var fontSize: Double = 26 {
        didSet {
            let limited = fontSize.isFinite ? min(42, max(18, fontSize)) : 26
            if fontSize != limited { fontSize = limited; return }
            reset()
            save()
        }
    }
    @Published private(set) var offset: Double = 0
    @Published private(set) var maximumOffset: Double = 0
    @Published private(set) var isRunning = false
    @Published var isPresented = false
    @Published var presentationScreenID: String?
    @Published var isEditing = false
    private let storage: UserDefaults
    private let now: () -> Date
    private let schedulesTicks: Bool
    private var lastTick: Date?
    private var ticker: Task<Void, Never>?
    private let key = "moris.prompter.v1"
    private struct Snapshot: Codable {
        var script: String
        var speed: Double
        var fontSize: Double
    }

    init(storage: UserDefaults = .standard, now: @escaping () -> Date = Date.init, schedulesTicks: Bool = true) {
        self.storage = storage
        self.now = now
        self.schedulesTicks = schedulesTicks
        if let data = storage.data(forKey: key), let saved = try? JSONDecoder().decode(Snapshot.self, from: data) {
            script = String(saved.script.prefix(50_000))
            speed = saved.speed.isFinite ? min(100, max(10, saved.speed)) : 30
            fontSize = saved.fontSize.isFinite ? min(42, max(18, saved.fontSize)) : 26
        }
        // Restores a draft, never a running presentation.
    }

    var hasScript: Bool { !script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    var canPlay: Bool { hasScript && maximumOffset > 0 }
    var progress: Double { maximumOffset > 0 ? min(1, max(0, offset / maximumOffset)) : 0 }

    func setBounds(_ value: Double) {
        maximumOffset = value.isFinite ? max(0, value) : 0
        offset = min(offset, maximumOffset)
        if maximumOffset == 0 || offset >= maximumOffset { pause() }
    }

    func play() {
        guard canPlay, !isRunning else { return }
        if offset >= maximumOffset { offset = 0 }
        isRunning = true
        lastTick = now()
        guard schedulesTicks else { return }
        ticker = Task { @MainActor [weak self] in
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(1.0 / 30))
                    guard let self, self.isRunning else { return }
                    self.tick()
                }
            } catch { /* Closing, locking or pausing cancels scrolling. */ }
        }
    }

    func tick() {
        guard isRunning, let previous = lastTick else { return }
        let current = now()
        // Do not jump across a script after sleep or a long main-thread stall.
        guard current.timeIntervalSince(previous) >= 0, current.timeIntervalSince(previous) < 2 else { pause(); return }
        offset = min(maximumOffset, offset + current.timeIntervalSince(previous) * speed)
        lastTick = current
        if offset >= maximumOffset { pause() }
    }

    func pause() {
        isRunning = false
        lastTick = nil
        ticker?.cancel()
        ticker = nil
    }

    func reset() { pause(); offset = 0 }
    func seek(_ value: Double) {
        pause()
        offset = value.isFinite ? min(maximumOffset, max(0, value)) : 0
    }

    private func save() {
        if let data = try? JSONEncoder().encode(Snapshot(script: script, speed: speed, fontSize: fontSize)) {
            storage.set(data, forKey: key)
        }
    }
}

// MARK: - Presentation

@MainActor
final class PrompterPanelController: NSObject {
    static let shared = PrompterPanelController(model: .shared)
    static let readingSize = CGSize(width: 640, height: 310)
    private final class Source {
        weak var window: NSWindow?
        weak var viewModel: BoringViewModel?
        init(window: NSWindow, viewModel: BoringViewModel) { self.window = window; self.viewModel = viewModel }
    }
    private var sources: [ObjectIdentifier: Source] = [:]
    private var activeSource: Source?
    private var previousHidesOnDeactivate: Bool?
    private var keyMonitor: Any?
    private var lockObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private let model: PrompterModel
    private let activateWindow: @MainActor (NSWindow) -> Void

    init(model: PrompterModel, activateWindow: @escaping @MainActor (NSWindow) -> Void = {
        $0.makeKeyAndOrderFront(nil)
        $0.makeFirstResponder(nil)
    }) {
        self.model = model
        self.activateWindow = activateWindow
        super.init()
    }

    func bind(_ window: NSWindow, to viewModel: BoringViewModel) {
        let key = ObjectIdentifier(viewModel)
        if sources[key]?.window !== window { sources[key] = Source(window: window, viewModel: viewModel) }
        sources = sources.filter { $0.value.window != nil && $0.value.viewModel != nil }
    }

    func canPresent(on screen: NSScreen) -> Bool {
        sources.values.contains { $0.window?.screen === screen && $0.viewModel != nil }
    }

    func present(on screen: NSScreen? = nil, source: BoringViewModel? = nil) {
        guard model.hasScript else { return }
        let preferred = screen ?? NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) }) ?? NSScreen.main
        let selected = source.flatMap { sources[ObjectIdentifier($0)] }
            ?? sources.values.first(where: { $0.window?.screen === preferred && $0.viewModel != nil })
            ?? sources.values.first(where: { $0.window?.isVisible == true && $0.viewModel != nil })
        guard let selected, let window = selected.window, let viewModel = selected.viewModel else { return }
        if activeSource?.viewModel !== viewModel { dismiss() }
        model.pause()
        activeSource = selected
        if let panel = window as? NSPanel {
            if previousHidesOnDeactivate == nil { previousHidesOnDeactivate = panel.hidesOnDeactivate }
            panel.hidesOnDeactivate = false
        }
        model.isEditing = false
        model.presentationScreenID = viewModel.screenUUID
        model.isPresented = true
        viewModel.open()
        viewModel.notchSize = Self.readingSize
        activateWindow(window)
        installObservers()
    }

    func position(on screen: NSScreen?) {
        guard let screen, canPresent(on: screen) else { return }
        present(on: screen)
    }

    func dismiss() {
        model.pause()
        model.isPresented = false
        model.presentationScreenID = nil
        let previous = activeSource?.viewModel
        if let panel = activeSource?.window as? NSPanel, let saved = previousHidesOnDeactivate {
            panel.hidesOnDeactivate = saved
        }
        previousHidesOnDeactivate = nil
        activeSource = nil
        previous?.close()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
        if let lockObserver { DistributedNotificationCenter.default().removeObserver(lockObserver); self.lockObserver = nil }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver); self.screenObserver = nil }
    }

    func editScript() {
        let source = activeSource
        dismiss()
        BoringViewCoordinator.shared.currentView = .prompter
        source?.viewModel?.open()
        if let window = source?.window { activateWindow(window) }
    }

    private func installObservers() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.activeSource?.window,
                  NSApp.keyWindow === window, event.window === window,
                  event.modifierFlags.intersection([.command, .option, .control]).isEmpty else { return event }
            switch event.keyCode {
            case 53: self.dismiss(); return nil
            case 49:
                if self.model.isRunning { self.model.pause() } else { self.model.play() }
                return nil
            case 126: self.model.seek(self.model.offset - self.model.fontSize * 2); return nil
            case 125: self.model.seek(self.model.offset + self.model.fontSize * 2); return nil
            default: return event
            }
        }
        lockObserver = DistributedNotificationCenter.default().addObserver(
            forName: NSNotification.Name("com.apple.screenIsLocked"), object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.dismiss() }
            }
        screenObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.dismiss() }
            }
    }
}

/// Binds presentation to MORIS's own notch window, never a second floating card.
struct PrompterNotchAnchor: NSViewRepresentable {
    let viewModel: BoringViewModel
    func makeNSView(context: Context) -> Anchor { Anchor(viewModel: viewModel) }
    func updateNSView(_ view: Anchor, context: Context) { view.bindWindow() }
    final class Anchor: NSView {
        let viewModel: BoringViewModel
        init(viewModel: BoringViewModel) { self.viewModel = viewModel; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); bindWindow() }
        func bindWindow() {
            if let window { PrompterPanelController.shared.bind(window, to: viewModel) }
        }
    }
}

struct PrompterEditorView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var model = PrompterModel.shared
    @FocusState private var editing: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label("Your script", systemImage: "text.alignleft").font(.headline)
                    Spacer()
                    Text("\(model.script.count) / 50,000").font(.caption2).foregroundStyle(.secondary)
                }
                TextEditor(text: $model.script)
                    .font(.system(size: 14)).scrollContentBackground(.hidden)
                    .padding(8).background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 12))
                    .focused($editing).accessibilityLabel("Teleprompter script")
                    .background(PrompterEditorKeyboardBridge())
                Text("Draft saved only on this Mac. Clear removes it.").font(.caption2).foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                Label("MORIS Prompter", systemImage: "text.viewfinder").font(.headline)
                Text("Read your script near the camera while recording or presenting.")
                    .font(.caption).foregroundStyle(.secondary)
                PrompterPreferences()
                Button(model.isPresented ? "Return to reading" : "Read in notch", systemImage: "text.viewfinder") {
                    editing = false
                    model.isEditing = false
                    PrompterPanelController.shared.present(on: NSScreen.screen(withUUID: vm.screenUUID ?? ""), source: vm)
                }.toolButton(prominent: true).disabled(!model.hasScript)
                HStack {
                    Button("Clear") {
                        model.script = ""
                        PrompterPanelController.shared.dismiss()
                    }.toolButton(compact: true).disabled(model.script.isEmpty)
                    if model.isPresented {
                        Button("Close reader") { PrompterPanelController.shared.dismiss() }.toolButton(compact: true)
                    }
                }
                Text("Floating panel may appear in screen recordings. No microphone access is used.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.frame(width: 230)
        }
        .onChange(of: editing) { model.isEditing = $0 }
        .onDisappear { model.isEditing = false }
    }
}

private struct PrompterPreferences: View {
    @ObservedObject private var model = PrompterModel.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack { Text("Scroll speed"); Spacer(); Text("\(Int(model.speed)) pt/s").monospacedDigit() }
            Slider(value: $model.speed, in: 10...100, step: 5).accessibilityLabel("Scroll speed")
            HStack { Text("Text size"); Spacer(); Text("\(Int(model.fontSize)) pt").monospacedDigit() }
            Slider(value: $model.fontSize, in: 18...42, step: 2).accessibilityLabel("Prompter text size")
        }.font(.caption)
    }
}

struct PrompterReadingPanel: View {
    @ObservedObject private var model = PrompterModel.shared
    @State private var settings = false
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                Label("MORIS Prompter", systemImage: "text.viewfinder").font(.caption.weight(.semibold))
                Text(model.isRunning ? "Reading" : "Paused")
                    .font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Button { PrompterPanelController.shared.editScript() } label: {
                    Image(systemName: "square.and.pencil").frame(width: 28, height: 28)
                }.buttonStyle(.plain).help("Edit script").accessibilityLabel("Edit script")
                Button { settings.toggle() } label: {
                    Image(systemName: "slider.horizontal.3").frame(width: 24, height: 24)
                }.buttonStyle(.plain).help("Reading settings and display")
                .accessibilityLabel("Reading settings and display")
                .popover(isPresented: $settings) {
                    VStack(alignment: .leading, spacing: 12) {
                        PrompterPreferences()
                        Divider()
                        ForEach(Array(NSScreen.screens.filter { PrompterPanelController.shared.canPresent(on: $0) }.enumerated()), id: \.offset) { _, screen in
                            Button("Move to \(screen.localizedName)") {
                                PrompterPanelController.shared.position(on: screen)
                                settings = false
                            }
                        }
                    }
                    .padding(16).frame(width: 240)
                }
                Button { PrompterPanelController.shared.dismiss() } label: {
                    Image(systemName: "xmark").frame(width: 24, height: 24)
                }.buttonStyle(.plain).accessibilityLabel("Close prompter")
            }
            PrompterTextViewport(model: model)
                .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.08),
                                             .init(color: .black, location: 0.88), .init(color: .clear, location: 1)],
                                     startPoint: .top, endPoint: .bottom))
            HStack(spacing: 12) {
                Button { model.reset() } label: { Image(systemName: "backward.end.fill") }
                    .buttonStyle(.plain).help("Back to beginning").accessibilityLabel("Back to beginning")
                Button(model.isRunning ? "Pause" : model.progress >= 1 ? "Replay" : "Play",
                       systemImage: model.isRunning ? "pause.fill" : "play.fill") {
                    if model.isRunning { model.pause() } else { model.play() }
                }.toolButton(prominent: true, compact: true).disabled(!model.canPlay)
                ProgressView(value: model.progress).frame(maxWidth: 140).accessibilityLabel("Reading progress")
                Spacer(minLength: 0)
                Text(model.canPlay ? "Space: play/pause · ↑ ↓ scroll" : "Script fits · scroll manually")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 30).padding(.top, 8).padding(.bottom, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white).preferredColorScheme(.dark)
    }
}

private struct PrompterTextViewport: NSViewRepresentable {
    @ObservedObject var model: PrompterModel

    func makeCoordinator() -> Coordinator { Coordinator(model: model) }
    func makeNSView(context: Context) -> NSScrollView {
        let view = NSScrollView()
        view.drawsBackground = false
        view.hasVerticalScroller = false
        view.hasHorizontalScroller = false
        let text = NSTextView()
        text.isEditable = false
        text.isSelectable = false
        text.drawsBackground = false
        text.textContainerInset = NSSize(width: 16, height: 24)
        text.isVerticallyResizable = true
        text.isHorizontallyResizable = false
        view.documentView = text
        context.coordinator.observe(view)
        return view
    }

    func updateNSView(_ view: NSScrollView, context: Context) {
        guard let text = view.documentView as? NSTextView else { return }
        let width = max(1, view.contentSize.width)
        let coordinator = context.coordinator
        if coordinator.script != model.script || coordinator.fontSize != model.fontSize || abs(coordinator.width - width) > 0.5
            || abs(coordinator.height - view.contentSize.height) > 0.5 {
            coordinator.script = model.script
            coordinator.fontSize = model.fontSize
            coordinator.width = width
            coordinator.height = view.contentSize.height
            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 7
            paragraph.alignment = .center
            text.textStorage?.setAttributedString(NSAttributedString(string: model.script, attributes: [
                .font: NSFont.systemFont(ofSize: model.fontSize, weight: .medium), .foregroundColor: NSColor.white,
                .paragraphStyle: paragraph
            ]))
            text.textContainer?.widthTracksTextView = false
            text.textContainer?.containerSize = NSSize(width: max(1, width - 32), height: CGFloat.greatestFiniteMagnitude)
            if let container = text.textContainer, let layout = text.layoutManager {
                layout.ensureLayout(for: container)
                let height = max(view.contentSize.height, ceil(layout.usedRect(for: container).height) + 48)
                text.setFrameSize(NSSize(width: width, height: height))
                let maximum = max(0, height - view.contentSize.height)
                DispatchQueue.main.async { [weak model] in model?.setBounds(maximum) }
            }
        }
        view.contentView.scroll(to: NSPoint(x: 0, y: model.offset))
        view.reflectScrolledClipView(view.contentView)
    }

    static func dismantleNSView(_ view: NSScrollView, coordinator: Coordinator) { coordinator.stopObserving() }

    final class Coordinator {
        let model: PrompterModel
        var script: String?
        var fontSize: Double = 0
        var width: CGFloat = 0
        var height: CGFloat = 0
        private var observers: [NSObjectProtocol] = []
        init(model: PrompterModel) { self.model = model }
        func observe(_ view: NSScrollView) {
            observers.append(NotificationCenter.default.addObserver(forName: NSScrollView.willStartLiveScrollNotification,
                object: view, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.model.pause() }
                })
            observers.append(NotificationCenter.default.addObserver(forName: NSScrollView.didLiveScrollNotification,
                object: view, queue: .main) { [weak self, weak view] _ in
                    MainActor.assumeIsolated {
                        guard let self, let view else { return }
                        self.model.seek(view.contentView.bounds.origin.y)
                    }
                })
        }
        func stopObserving() { observers.forEach(NotificationCenter.default.removeObserver); observers = [] }
    }
}

/// Click to focus the script editor; hover never steals another app's keyboard.
private struct PrompterEditorKeyboardBridge: NSViewRepresentable {
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak view] event in
            if let view, let window = view.window, event.window === window,
               view.bounds.contains(view.convert(event.locationInWindow, from: nil)) {
                window.makeKey()
            }
            return event
        }
        return view
    }
    func updateNSView(_ view: NSView, context: Context) {}
    static func dismantleNSView(_ view: NSView, coordinator: Coordinator) {
        if let monitor = coordinator.monitor { NSEvent.removeMonitor(monitor); coordinator.monitor = nil }
    }
    final class Coordinator { var monitor: Any? }
}
