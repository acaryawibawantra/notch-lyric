//
//  ContentView.swift
//  boringNotchApp
//
//  Created by Harsh Vardhan Goswami  on 02/08/24
//  Modified by Richard Kunkli on 24/08/2024.
//

import AVFoundation
import Combine
import Defaults
import KeyboardShortcuts
import SwiftUI
import SwiftUIIntrospect
import UniformTypeIdentifiers

private struct CompactNotchWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

private struct TaperedLyricGlow: Shape {
    var topWidth: CGFloat

    func path(in rect: CGRect) -> Path {
        let halfTop = min(topWidth, rect.width - 32) / 2
        let halfBottom = halfTop * 0.78
        return Path { path in
            path.move(to: CGPoint(x: rect.midX - halfTop, y: rect.minY - 12))
            path.addLine(to: CGPoint(x: rect.midX + halfTop, y: rect.minY - 12))
            path.addCurve(
                to: CGPoint(x: rect.midX + halfBottom, y: rect.maxY),
                control1: CGPoint(x: rect.midX + halfTop, y: rect.height * 0.35),
                control2: CGPoint(x: rect.midX + halfBottom, y: rect.height * 0.65)
            )
            path.addLine(to: CGPoint(x: rect.midX - halfBottom, y: rect.maxY))
            path.addCurve(
                to: CGPoint(x: rect.midX - halfTop, y: rect.minY - 12),
                control1: CGPoint(x: rect.midX - halfBottom, y: rect.height * 0.65),
                control2: CGPoint(x: rect.midX - halfTop, y: rect.height * 0.35)
            )
            path.closeSubpath()
        }
    }
}

// A separate noninteractive panel lets lyrics float over other apps without
// extending the notch's hover target or intercepting clicks below the camera.
private struct FloatingLyricsPanel<Content: View>: NSViewRepresentable {
    let isVisible: Bool
    let topInset: CGFloat
    let width: CGFloat
    let content: Content
    let contrastSampler: LyricContrastSampler
    let adaptiveContrast: Bool

    func makeNSView(context: Context) -> LyricsPanelAnchor<Content> {
        LyricsPanelAnchor(content: content, contrastSampler: contrastSampler)
    }

    func updateNSView(_ view: LyricsPanelAnchor<Content>, context: Context) {
        view.host.rootView = content
        view.topInset = topInset
        view.panelWidth = width
        view.shouldShow = isVisible
        view.adaptiveContrast = adaptiveContrast
        view.updatePanel()
    }

    static func dismantleNSView(_ view: LyricsPanelAnchor<Content>, coordinator: ()) {
        view.dispose()
    }
}

private final class LyricsPanelAnchor<Content: View>: NSView {
    let host: NSHostingView<Content>
    private let panel: NSPanel
    var topInset: CGFloat = 0
    var panelWidth: CGFloat = 520
    var shouldShow = false
    var adaptiveContrast = false
    private let contrastSampler: LyricContrastSampler

    init(content: Content, contrastSampler: LyricContrastSampler) {
        self.contrastSampler = contrastSampler
        host = NSHostingView(rootView: content)
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 100),
            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false
        )
        super.init(frame: .zero)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.fullScreenAuxiliary, .ignoresCycle]
        panel.contentView = host
        for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
            NotificationCenter.default.addObserver(self, selector: #selector(parentWindowMoved(_:)), name: name, object: nil)
        }
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updatePanel()
    }

    func updatePanel() {
        guard shouldShow, let window else {
            contrastSampler.stop()
            panel.parent?.removeChildWindow(panel)
            panel.orderOut(nil)
            return
        }
        if panel.parent !== window {
            panel.parent?.removeChildWindow(panel)
            panel.level = window.level
            // The notch silhouette must occlude the glow, not be tinted by a
            // rectangular child panel. Its actual rounded corners form the seam.
            window.addChildWindow(panel, ordered: .below)
        }
        if abs(panel.frame.width - panelWidth) > 0.5 {
            panel.setContentSize(NSSize(width: panelWidth, height: 100))
        }
        positionPanel()
        if !panel.isVisible { panel.order(.below, relativeTo: window.windowNumber) }
    }

    @objc private func parentWindowMoved(_ notification: Notification) {
        guard let changedWindow = notification.object as? NSWindow, changedWindow === window else { return }
        positionPanel()
    }

    private func positionPanel() {
        guard let window else { return }
        panel.setFrameOrigin(NSPoint(
            x: window.frame.midX - panel.frame.width / 2,
            y: window.frame.maxY - topInset - panel.frame.height
        ))
        let sampleArea = NSRect(x: panel.frame.minX + panel.frame.width * 0.15,
                                y: panel.frame.maxY - 64, width: panel.frame.width * 0.7, height: 48)
        contrastSampler.configure(enabled: adaptiveContrast, screen: window.screen, area: sampleArea)
    }

    func dispose() {
        contrastSampler.stop()
        NotificationCenter.default.removeObserver(self)
        panel.parent?.removeChildWindow(panel)
        panel.close()
    }
}

enum FocusPhase: String, Codable { case focus, rest }

struct FocusSessionRecord: Codable, Identifiable {
    var id = UUID()
    let endedAt: Date
    let minutes: Int
    let goal: String
}

@MainActor
final class FocusTimerModel: ObservableObject {
    @Published var durationMinutes = 25 { didSet { save() } }
    @Published var breakMinutes = 5 { didSet { save() } }
    @Published var soundEnabled = true { didSet { save() } }
    @Published var goal = "" {
        didSet {
            if goal != selectedTaskTitle { selectedTaskID = nil; selectedReminderID = nil; selectedTaskTitle = nil }
            save()
        }
    }
    @Published private(set) var selectedTaskID: UUID?
    @Published private(set) var selectedReminderID: String?
    @Published private(set) var pendingReminderID: String?
    @Published private(set) var isSyncingReminder = false
    private var selectedTaskTitle: String?
    @Published private(set) var history: [FocusSessionRecord] = []
    @Published private(set) var phase: FocusPhase = .focus
    @Published var isEditingGoal = false
    @Published private(set) var remainingSeconds = 25 * 60
    @Published private(set) var isRunning = false
    @Published private(set) var isVisible = false
    @Published private(set) var isFinished = false
    @Published private(set) var showsCompletion = false
    private var completionUntil: Date?
    var hasCompactActivity: Bool { isVisible && (!isFinished || showsCompletion) }
    private var deadline: Date?
    private var ticker: AnyCancellable?
    private let storage: UserDefaults
    private let now: () -> Date
    private let completionSound: () -> Void
    private let completeTask: @MainActor (UUID) -> Void
    private let completeReminder: @MainActor (String) async -> Bool
    private let storageKey = "notchLyric.focusSession.v1"

    private struct Snapshot: Codable {
        var duration: Int
        var breakDuration: Int
        var sound: Bool
        var goal: String
        var remaining: Int
        var deadline: Date?
        var visible: Bool
        var finished: Bool
        var phase: FocusPhase
        var history: [FocusSessionRecord]
        var selectedTaskID: UUID?
        var selectedTaskTitle: String?
        var selectedReminderID: String?
        var pendingReminderID: String?
        var completionUntil: Date?
    }

    init(storage: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         completionSound: @escaping () -> Void = { NSSound(named: NSSound.Name("Glass"))?.play() },
         completeTask: @escaping @MainActor (UUID) -> Void = { FocusTaskStore.shared.complete($0) },
         completeReminder: @escaping @MainActor (String) async -> Bool = { _ in false }) {
        self.storage = storage
        self.now = now
        self.completionSound = completionSound
        self.completeTask = completeTask
        self.completeReminder = completeReminder
        if let data = storage.data(forKey: storageKey), let saved = try? JSONDecoder().decode(Snapshot.self, from: data) {
            durationMinutes = min(120, max(1, saved.duration))
            breakMinutes = min(30, max(1, saved.breakDuration))
            soundEnabled = saved.sound
            goal = saved.goal
            selectedTaskID = saved.selectedTaskID
            selectedTaskTitle = saved.selectedTaskTitle
            selectedReminderID = saved.selectedReminderID
            pendingReminderID = saved.pendingReminderID
            remainingSeconds = max(0, saved.remaining)
            deadline = saved.deadline
            isVisible = saved.visible
            isFinished = saved.finished
            completionUntil = saved.completionUntil
            showsCompletion = saved.finished && (saved.completionUntil.map { $0 > now() } ?? false)
            phase = saved.phase
            history = saved.history
            isRunning = deadline != nil
            if isRunning { updateRemainingTime() }
            if isRunning || showsCompletion { startTicker() }
        }
    }

    var completedSessions: Int {
        history.filter { Calendar.current.isDate($0.endedAt, inSameDayAs: now()) }.count
    }

    var focusedMinutesToday: Int {
        history.filter { Calendar.current.isDate($0.endedAt, inSameDayAs: now()) }.reduce(0) { $0 + $1.minutes }
    }

    var sessionMinutes: Int { phase == .focus ? durationMinutes : breakMinutes }

    var displayTime: String {
        isFinished ? (phase == .focus ? "Focus complete" : "Break complete") : String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60)
    }

    func start() {
        guard !isRunning else { return }
        if !isVisible || isFinished {
            remainingSeconds = sessionMinutes * 60
        }
        isFinished = false
        showsCompletion = false
        completionUntil = nil
        isVisible = true
        isRunning = true
        deadline = now().addingTimeInterval(Double(remainingSeconds))
        save()
        startTicker()
    }

    private func startTicker() {
        ticker?.cancel()
        ticker = Timer.publish(every: 1, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.updateRemainingTime() }
            }
    }

    func updateRemainingTime() {
        guard let deadline else {
            if showsCompletion, let completionUntil, now() >= completionUntil {
                showsCompletion = false
                self.completionUntil = nil
                ticker?.cancel()
                ticker = nil
                save()
            }
            return
        }
        remainingSeconds = max(0, Int(ceil(deadline.timeIntervalSince(now()))))
        if remainingSeconds == 0 {
            isRunning = false
            isFinished = true
            completionUntil = deadline.addingTimeInterval(5)
            showsCompletion = now() < deadline.addingTimeInterval(5)
            if phase == .focus {
                history.append(FocusSessionRecord(endedAt: deadline, minutes: durationMinutes, goal: goal))
                history = Array(history.suffix(500))
                if let selectedTaskID { completeTask(selectedTaskID) }
                if let selectedReminderID { pendingReminderID = selectedReminderID }
                selectedReminderID = nil
                selectedTaskID = nil
                selectedTaskTitle = nil
            }
            self.deadline = nil
            if !showsCompletion { ticker?.cancel(); ticker = nil }
            save()
            if pendingReminderID != nil { Task { await syncCompletedReminder() } }
            if soundEnabled { completionSound() }
        }
    }

    func pause() {
        updateRemainingTime()
        guard !isFinished else { return }
        isRunning = false
        deadline = nil
        ticker?.cancel()
        ticker = nil
        save()
    }

    func reset() {
        ticker?.cancel()
        ticker = nil
        deadline = nil
        isRunning = false
        isFinished = false
        isVisible = false
        showsCompletion = false
        completionUntil = nil
        phase = .focus
        remainingSeconds = durationMinutes * 60
        save()
    }

    func startBreak() {
        reset()
        phase = .rest
        start()
    }

    func selectTask(id: UUID, title: String) {
        guard !isVisible || isFinished else { return }
        goal = title
        selectedTaskID = id
        selectedReminderID = nil
        selectedTaskTitle = title
        save()
    }

    func selectReminder(id: String, title: String) {
        guard pendingReminderID == nil, !isVisible || isFinished else { return }
        goal = title
        selectedTaskID = nil
        selectedReminderID = id
        selectedTaskTitle = title
        save()
    }

    func syncCompletedReminder() async {
        guard !isSyncingReminder, let id = pendingReminderID else { return }
        isSyncingReminder = true
        let completed = await completeReminder(id)
        if completed, pendingReminderID == id { pendingReminderID = nil; save() }
        isSyncingReminder = false
    }

    private func save() {
        let snapshot = Snapshot(duration: durationMinutes, breakDuration: breakMinutes, sound: soundEnabled,
                                goal: goal, remaining: remainingSeconds, deadline: deadline,
                                visible: isVisible, finished: isFinished, phase: phase, history: history,
                                selectedTaskID: selectedTaskID, selectedTaskTitle: selectedTaskTitle,
                                selectedReminderID: selectedReminderID, pendingReminderID: pendingReminderID,
                                completionUntil: completionUntil)
        if let data = try? JSONEncoder().encode(snapshot) { storage.set(data, forKey: storageKey) }
    }
}

@MainActor
final class UtilityClockModel: ObservableObject {
    static let shared = UtilityClockModel()
    @Published var minutes = 5 {
        didSet {
            if !timerVisible || timerDone { selectedSeconds = minutes * 60 }
            save()
        }
    }
    @Published private(set) var selectedSeconds = 300
    @Published private(set) var remaining = 300
    @Published private(set) var timerVisible = false
    @Published private(set) var timerDone = false
    @Published private(set) var showsTimerCompletion = false
    private var completionUntil: Date?
    var hasCompactTimer: Bool { timerVisible && (!timerDone || showsTimerCompletion) }
    @Published private(set) var stopwatchSeconds = 0
    @Published private(set) var timerRunning = false
    @Published private(set) var stopwatchRunning = false
    private var deadline: Date?
    private var stopwatchStart: Date?
    private var accumulated: TimeInterval = 0
    private var ticker: AnyCancellable?
    private let storage: UserDefaults
    private let now: () -> Date
    private let completionSound: () -> Void
    private let key = "notchLyric.utilityClocks.v1"

    private struct Snapshot: Codable {
        var minutes: Int
        var durationSeconds: Int?
        var remaining: Int
        var visible: Bool
        var done: Bool
        var deadline: Date?
        var stopwatchStart: Date?
        var accumulated: TimeInterval
        var completionUntil: Date?
    }

    init(storage: UserDefaults = .standard, now: @escaping () -> Date = Date.init,
         completionSound: @escaping () -> Void = { NSSound(named: NSSound.Name("Glass"))?.play() }) {
        self.storage = storage
        self.now = now
        self.completionSound = completionSound
        if let data = storage.data(forKey: key), let saved = try? JSONDecoder().decode(Snapshot.self, from: data) {
            minutes = min(120, max(1, saved.minutes))
            selectedSeconds = min(7200, max(1, saved.durationSeconds ?? minutes * 60))
            remaining = max(0, saved.remaining)
            timerVisible = saved.visible
            timerDone = saved.done
            completionUntil = saved.completionUntil
            showsTimerCompletion = saved.done && (saved.completionUntil.map { $0 > now() } ?? false)
            deadline = saved.deadline
            stopwatchStart = saved.stopwatchStart
            accumulated = max(0, saved.accumulated)
            timerRunning = deadline != nil
            stopwatchRunning = stopwatchStart != nil
            tick()
            schedule()
        }
    }

    static func formatted(_ seconds: Int) -> String {
        seconds >= 3600
            ? String(format: "%d:%02d:%02d", seconds / 3600, seconds / 60 % 60, seconds % 60)
            : String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }

    func toggleTimer() {
        tick()
        if timerRunning {
            deadline = nil
            timerRunning = false
        } else {
            if !timerVisible || timerDone { remaining = selectedSeconds }
            timerVisible = true
            timerDone = false
            showsTimerCompletion = false
            completionUntil = nil
            timerRunning = true
            deadline = now().addingTimeInterval(Double(remaining))
        }
        save()
        schedule()
    }

    func resetTimer() {
        deadline = nil
        timerRunning = false
        timerVisible = false
        timerDone = false
        showsTimerCompletion = false
        completionUntil = nil
        remaining = selectedSeconds
        save()
        schedule()
    }

    func toggleStopwatch() {
        if let stopwatchStart {
            accumulated += max(0, now().timeIntervalSince(stopwatchStart))
            self.stopwatchStart = nil
            stopwatchRunning = false
        } else {
            stopwatchStart = now()
            stopwatchRunning = true
        }
        tick()
        save()
        schedule()
    }

    func startTimer(seconds: Int) {
        guard !timerVisible || timerDone else { return }
        selectedSeconds = min(7200, max(1, seconds))
        remaining = selectedSeconds
        timerVisible = false
        toggleTimer()
    }

    func resetStopwatch() {
        stopwatchStart = nil
        accumulated = 0
        stopwatchSeconds = 0
        stopwatchRunning = false
        save()
        schedule()
    }

    func stopStopwatch() {
        let hadSession = stopwatchRunning || accumulated > 0
        resetStopwatch()
        if hadSession { completionSound() }
    }

    func tick() {
        if let deadline {
            remaining = max(0, Int(ceil(deadline.timeIntervalSince(now()))))
            if remaining == 0 {
                self.deadline = nil
                timerRunning = false
                timerDone = true
                completionUntil = deadline.addingTimeInterval(5)
                showsTimerCompletion = now() < deadline.addingTimeInterval(5)
                save()
                completionSound()
            }
        }
        stopwatchSeconds = Int(accumulated + (stopwatchStart.map { max(0, now().timeIntervalSince($0)) } ?? 0))
        if showsTimerCompletion, let completionUntil, now() >= completionUntil {
            showsTimerCompletion = false
            self.completionUntil = nil
            save()
        }
        if !timerRunning && !stopwatchRunning && !showsTimerCompletion { ticker?.cancel(); ticker = nil }
    }

    private func schedule() {
        ticker?.cancel()
        ticker = nil
        guard timerRunning || stopwatchRunning || showsTimerCompletion else { return }
        ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect().sink { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
    }

    private func save() {
        let snapshot = Snapshot(minutes: minutes, durationSeconds: selectedSeconds, remaining: remaining, visible: timerVisible, done: timerDone,
                                deadline: deadline, stopwatchStart: stopwatchStart, accumulated: accumulated,
                                completionUntil: completionUntil)
        if let data = try? JSONEncoder().encode(snapshot) { storage.set(data, forKey: key) }
    }
}

private struct ToolButtonAppearance: ViewModifier {
    var prominent: Bool
    var compact: Bool
    @Default(.toolsAccent) private var accent
    @Default(.toolsRed) private var red
    @Default(.toolsGreen) private var green
    @Default(.toolsBlue) private var blue
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.isEnabled) private var enabled
    @State private var hovering = false

    @ViewBuilder func body(content: Content) -> some View {
        Group {
        if #available(macOS 26.0, *) {
            if prominent {
                content.buttonStyle(.glassProminent).tint(accent.color).controlSize(compact ? .small : .regular)
            } else {
                content.buttonStyle(.bordered).tint(.gray).controlSize(compact ? .small : .regular)
            }
        } else if prominent {
            content.buttonStyle(.borderedProminent).tint(accent.color).controlSize(compact ? .small : .regular)
        } else {
            content.buttonStyle(.bordered).tint(.gray).controlSize(compact ? .small : .regular)
        }
        }
        .font(.system(size: 12, weight: .medium))
        .brightness(hovering && enabled ? 0.035 : 0)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: hovering)
    }
}

private struct ToolCardSurface: ViewModifier {
    var emphasized = false
    @Default(.toolsAccent) private var accent
    @Default(.toolsRed) private var red
    @Default(.toolsGreen) private var green
    @Default(.toolsBlue) private var blue
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.padding(12)
            .background {
                if emphasized {
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(LinearGradient(colors: [accent.color.opacity(reduceTransparency ? 0.23 : 0.16),
                                                      accent.color.opacity(0.055), .white.opacity(0.018)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                        .overlay {
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(RadialGradient(colors: [.mint.opacity(0.07), .clear],
                                                     center: .bottomTrailing, startRadius: 0, endRadius: 230))
                        }
                        .mask {
                            // Feather the surface into the black notch; no outline.
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(LinearGradient(colors: [.black.opacity(0.55), .black, .black.opacity(0.7)],
                                                     startPoint: .top, endPoint: .bottom))
                        }
                } else {
                Rectangle()
                    .fill(RadialGradient(colors: [accent.color.opacity(reduceTransparency ? 0.16 : 0.10),
                                                  accent.color.opacity(0.025), .clear],
                                         center: .topLeading, startRadius: 0, endRadius: 650))
                    .mask {
                        LinearGradient(stops: [.init(color: .clear, location: 0),
                                               .init(color: .black, location: 0.13),
                                               .init(color: .black, location: 0.74),
                                               .init(color: .clear, location: 1)],
                                       startPoint: .leading, endPoint: .trailing)
                    }
                    .mask {
                        LinearGradient(stops: [.init(color: .clear, location: 0),
                                               .init(color: .black, location: 0.15),
                                               .init(color: .black, location: 0.68),
                                               .init(color: .clear, location: 1)],
                                       startPoint: .top, endPoint: .bottom)
                    }
                }
            }
    }
}

extension View {
    func toolCard(emphasized: Bool = false) -> some View { modifier(ToolCardSurface(emphasized: emphasized)) }
    func toolButton(prominent: Bool = false, compact: Bool = false) -> some View {
        modifier(ToolButtonAppearance(prominent: prominent, compact: compact))
    }
}

struct FocusTimerControls: View {
    @Default(.toolsAccent) private var accent
    @AppStorage("notchLyric.toolsSection") private var section = "Focus"
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TimeModePicker(selection: $section).frame(width: 210)
            HStack(alignment: .top, spacing: 20) {
                TimeToolContent(mode: TimeToolMode.resolve(section), compact: false)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                Divider()
                FocusTaskList().frame(width: 220)
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: section)
        .font(.system(.body))
        .tint(accent.color)
    }
}


struct FocusSessionPreferences: View {
    @ObservedObject private var timer = FocusTimerModel.shared
    @Default(.toolsAccent) private var toolsAccent
    @Default(.toolsRed) private var toolsRed
    @Default(.toolsGreen) private var toolsGreen
    @Default(.toolsBlue) private var toolsBlue

    var body: some View {
        Section("Focus defaults") {
            Stepper("Focus duration: \(timer.durationMinutes) min", value: $timer.durationMinutes, in: 1...120)
                .disabled(timer.isVisible && !timer.isFinished)
        }
        Section("Appearance") {
            Picker("Tools accent color", selection: $toolsAccent) {
                ForEach(ToolsAccent.allCases) { accent in
                    Text(accent.rawValue).tag(accent)
                }
            }
            if toolsAccent == .custom {
                ColorPicker("Custom accent", selection: Binding(
                    get: { Color(red: toolsRed, green: toolsGreen, blue: toolsBlue) },
                    set: { color in
                        guard let rgb = NSColor(color).usingColorSpace(.deviceRGB) else { return }
                        toolsRed = rgb.redComponent
                        toolsGreen = rgb.greenComponent
                        toolsBlue = rgb.blueComponent
                    }
                ), supportsOpacity: false)
            }
            Text("Choose a tint for time tools. System follows your Mac’s accent color.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Break and sound") {
            Stepper("Break duration: \(timer.breakMinutes) min", value: $timer.breakMinutes, in: 1...30)
                .disabled(timer.isVisible && !timer.isFinished)
            Toggle("Play sound after a focus session or break", isOn: $timer.soundEnabled)
            Button("Preview completion chime") { NSSound(named: NSSound.Name("Glass"))?.play() }
            Text("Breaks start when you choose Take a break. Sessions and clock state are saved locally; running clocks include time while your Mac sleeps.")
                .font(.caption).foregroundStyle(.secondary)
        }
        Section("Recent focus sessions") {
            if timer.history.isEmpty {
                Text("Complete a focus session to see your progress here.").foregroundStyle(.secondary)
            } else {
                ForEach(Array(timer.history.suffix(5).reversed())) { record in
                    HStack {
                        VStack(alignment: .leading) {
                            Text(record.goal.isEmpty ? "Focus session" : record.goal).lineLimit(1)
                            Text(record.endedAt, style: .date).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(record.minutes) min").monospacedDigit()
                    }
                }
            }
        }
    }
}

@MainActor
struct ContentView: View {
    @EnvironmentObject var vm: BoringViewModel
    @ObservedObject var webcamManager = WebcamManager.shared

    @ObservedObject var coordinator = BoringViewCoordinator.shared
    @ObservedObject var musicManager = MusicManager.shared
    @ObservedObject private var focusTimer = FocusTimerModel.shared
    @ObservedObject private var utilityClocks = UtilityClockModel.shared
    @ObservedObject private var focusTasks = FocusTaskStore.shared
    @ObservedObject private var shelfSelection = ShelfSelectionModel.shared
    @ObservedObject private var clipboardHistory = ClipboardHistoryStore.shared
    @ObservedObject private var everydayReminders = EverydayReminderStore.shared
    @ObservedObject private var wellnessSharingState = SharingStateManager.shared
    @State private var wellnessOwner = UUID()
    @State private var wellnessSessionUnlocked = true
    @ObservedObject var batteryModel = BatteryStatusViewModel.shared
    @ObservedObject private var deviceConnections = DeviceConnectionStore.shared
    @Default(.deviceConnectionPopups) private var deviceConnectionPopups
    @ObservedObject private var agenda = CalendarAgendaStore.shared
    @Default(.calendarAgendaPopups) private var calendarAgendaPopups
    @State private var agendaOwner = UUID()
    @ObservedObject private var calls = CallActivityStore.shared
    @ObservedObject private var codingTasks = MorisTaskStore.shared
    @State private var prompterPresented = PrompterModel.shared.isPresented
    @State private var prompterScreenID = PrompterModel.shared.presentationScreenID

    private var showsPrompterReading: Bool {
        prompterPresented && prompterScreenID == vm.screenUUID
    }
    @Default(.experimentalCallDetection) private var experimentalCallDetection
    @ObservedObject var brightnessManager = BrightnessManager.shared
    @ObservedObject var volumeManager = VolumeManager.shared
    @State private var hoverTask: Task<Void, Never>?
    @State private var isHovering: Bool = false
    @State private var anyDropDebounceTask: Task<Void, Never>?

    @State private var gestureProgress: CGFloat = .zero

    @State private var haptics: Bool = false
    @State private var compactNotchWidth: CGFloat = 0

    private var ambientNotchWidth: CGFloat {
        max(vm.closedNotchSize.width, compactNotchWidth)
    }

    private var floatingPanelWidth: CGFloat {
        max(360, min(windowSize.width, ambientNotchWidth + 64))
    }

    @Namespace var albumArtNamespace

    @Default(.useMusicVisualizer) var useMusicVisualizer

    @Default(.showNotHumanFace) var showNotHumanFace
    @Default(.enableLyrics) private var enableLyrics
    @Default(.persistentNotchLyrics) private var persistentNotchLyrics
    @Default(.persistentNotchLyricLines) private var persistentNotchLyricLines
    @Default(.lyricAlignment) private var lyricAlignment
    @Default(.animateLyricTransitions) private var animateLyricTransitions
    @Default(.floatingLyricStyle) private var floatingLyricStyle
    @Default(.floatingLyricsAmbient) private var floatingLyricsAmbient
    @Default(.adaptiveLyricContrast) private var adaptiveLyricContrast
    @StateObject private var lyricContrast = LyricContrastSampler()
    @Default(.lyricGradientIntensity) private var lyricGradientIntensity
    @Default(.lyricGradientDepth) private var lyricGradientDepth
    @Default(.compactActivity) private var compactActivity
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    private var usesFocusActivity: Bool {
        (focusTimer.hasCompactActivity || utilityClocks.hasCompactTimer || utilityClocks.stopwatchRunning || utilityClocks.stopwatchSeconds > 0)
            && compactActivity != .music
    }

    private var usesDualActivity: Bool {
        usesFocusActivity && compactActivity == .automatic && musicManager.isPlaying
            && coordinator.musicLiveActivityEnabled
    }

    private var floatingLyricsVisible: Bool {
        showsPersistentLyrics && !prompterPresented && vm.notchState == .closed && !coordinator.helloAnimationRunning
            && !coordinator.sneakPeek.show && !coordinator.expandingView.show && !showsWellnessBanner && !showsDevicePopup && !showsAgendaPopup && !showsCallPopup && !showsTaskPopup
    }

    private var showsTaskPopup: Bool {
        MorisTaskFeature.isEnabled && codingTasks.notice != nil && !codingTasks.isConfiguring && wellnessSessionUnlocked && !vm.hideOnClosed && vm.notchState == .closed
            && !coordinator.firstLaunch && !coordinator.helloAnimationRunning && !coordinator.expandingView.show
            && !coordinator.sneakPeek.show && !showsCallPopup && !showsAgendaPopup && !showsWellnessBanner && !showsDevicePopup
            && !vm.anyDropZoneTargeting && !shelfSelection.isDragging && !shelfSelection.isPreviewing
            && !ShelfStateViewModel.shared.isLoading && !wellnessSharingState.preventNotchClose
    }

    private var showsCallPopup: Bool {
        calls.activity != nil && wellnessSessionUnlocked && !vm.hideOnClosed
            && !coordinator.firstLaunch && !coordinator.helloAnimationRunning && !coordinator.expandingView.show
            && !vm.anyDropZoneTargeting && !shelfSelection.isDragging && !shelfSelection.isPreviewing
            && !focusTimer.isEditingGoal && !focusTasks.isEditing && !clipboardHistory.isEditing && !shelfSelection.isEditingSearch
            && !wellnessSharingState.preventNotchClose
    }

    private var showsDevicePopup: Bool {
        deviceConnections.notice != nil && wellnessSessionUnlocked && !vm.hideOnClosed && vm.notchState == .closed
            && !coordinator.firstLaunch && !coordinator.helloAnimationRunning && !coordinator.expandingView.show
            && !coordinator.sneakPeek.show && !showsWellnessBanner && !vm.anyDropZoneTargeting
            && !shelfSelection.isDragging && !ShelfStateViewModel.shared.isLoading && !showsAgendaPopup && !showsCallPopup
    }

    private var showsAgendaPopup: Bool {
        agenda.notice != nil && wellnessSessionUnlocked && !vm.hideOnClosed && !showsCallPopup
            && !coordinator.firstLaunch && !coordinator.helloAnimationRunning && !coordinator.expandingView.show
            && !coordinator.sneakPeek.show && !showsWellnessBanner && !vm.anyDropZoneTargeting
            && !shelfSelection.isDragging && !ShelfStateViewModel.shared.isLoading && !shelfSelection.isPreviewing
            && !focusTimer.isEditingGoal && !focusTasks.isEditing && !clipboardHistory.isEditing && !shelfSelection.isEditingSearch
            && !wellnessSharingState.preventNotchClose
    }

    private var showsWellnessBanner: Bool {
        everydayReminders.pending != nil && wellnessSessionUnlocked && !vm.hideOnClosed && !showsCallPopup
            && !coordinator.firstLaunch && !coordinator.helloAnimationRunning
            && !coordinator.sneakPeek.show && !coordinator.expandingView.show
            && !focusTimer.isEditingGoal && !focusTasks.isEditing && !clipboardHistory.isEditing
            && !shelfSelection.isEditingSearch && !shelfSelection.isDragging && !shelfSelection.isPreviewing
            && !wellnessSharingState.preventNotchClose && !vm.anyDropZoneTargeting
    }

    private var showsPersistentLyrics: Bool {
        enableLyrics && persistentNotchLyrics && musicManager.isPlaying
            && !musicManager.isFetchingLyrics && !musicManager.syncedLyrics.isEmpty
            && !vm.hideOnClosed
    }

    // Shared interactive spring for movement/resizing to avoid conflicting animations
    private let animationSpring = Animation.interactiveSpring(response: 0.38, dampingFraction: 0.8, blendDuration: 0)

    private let extendedHoverPadding: CGFloat = 30
    private let zeroHeightHoverPadding: CGFloat = 10

    private var topCornerRadius: CGFloat {
       ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                ? cornerRadiusInsets.opened.top
                : cornerRadiusInsets.closed.top
    }

    private var currentNotchShape: NotchShape {
        NotchShape(
            topCornerRadius: topCornerRadius,
            bottomCornerRadius: ((vm.notchState == .open) && Defaults[.cornerRadiusScaling])
                ? cornerRadiusInsets.opened.bottom
                : cornerRadiusInsets.closed.bottom
        )
    }

    private var computedChinWidth: CGFloat {
        var chinWidth: CGFloat = vm.closedNotchSize.width

        if usesDualActivity && vm.notchState == .closed && !coordinator.expandingView.show
            && !vm.hideOnClosed && everydayReminders.pending == nil {
            return chinWidth + 156
        }

        if coordinator.expandingView.type == .battery && coordinator.expandingView.show
            && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
            && !vm.hideOnClosed && wellnessSessionUnlocked
        {
            chinWidth = 488
        } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music)
            && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle)
            && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed
        {
            chinWidth += (2 * max(0, vm.effectiveClosedNotchHeight - 12) + 20)
        } else if !coordinator.expandingView.show && vm.notchState == .closed
            && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace]
            && !vm.hideOnClosed
        {
            chinWidth = restingCatCameraGap + (restingCatCameraGap > 0 ? 0 : 8)
                + 2 * (min(22, max(10, vm.effectiveClosedNotchHeight - 12)) + 12)
                + 2 * cornerRadiusInsets.closed.bottom
        }

        return chinWidth
    }

    var body: some View {
        // Calculate scale based on gesture progress only
        let gestureScale: CGFloat = {
            guard gestureProgress != 0 else { return 1.0 }
            let scaleFactor = 1.0 + gestureProgress * 0.01
            return max(0.6, scaleFactor)
        }()
        
        ZStack(alignment: .top) {
            VStack(spacing: 0) {
                let mainLayout = NotchLayout()
                    .frame(alignment: .top)
                    .padding(
                        .horizontal,
                        vm.notchState == .open
                        ? Defaults[.cornerRadiusScaling]
                        ? (cornerRadiusInsets.opened.top) : (cornerRadiusInsets.opened.bottom)
                        : cornerRadiusInsets.closed.bottom
                    )
                    .padding([.horizontal, .bottom], vm.notchState == .open ? 12 : 0)
                    .frame(width: vm.notchState == .open ? vm.notchSize.width : nil, height: vm.notchState == .open ? vm.notchSize.height : nil, alignment: .top)
                    .background {
                        if vm.notchState == .open && coordinator.currentView == .home && Defaults[.lightingEffect] && !showsPrompterReading {
                            MediaNotchGradient(tint: Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.3),
                                               active: !musicManager.isPlayerIdle)
                        }
                    }
                    .background(.black)
                    .clipShape(currentNotchShape)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(.black)
                            .frame(height: 1)
                            .padding(.horizontal, topCornerRadius)
                    }
                    .shadow(
                        color: ((vm.notchState == .open || isHovering) && Defaults[.enableShadow])
                            ? .black.opacity(0.7) : .clear, radius: Defaults[.cornerRadiusScaling] ? 6 : 4
                    )
                    .padding(
                        .bottom,
                        vm.effectiveClosedNotchHeight == 0 ? 10 : 0
                    )
                
                mainLayout
                    .background {
                        GeometryReader { geometry in
                            Color.clear.preference(key: CompactNotchWidthKey.self, value: geometry.size.width)
                        }
                    }
                    .onPreferenceChange(CompactNotchWidthKey.self) { width in
                        if vm.notchState == .closed && width > 0 && abs(compactNotchWidth - width) > 0.5 {
                            compactNotchWidth = width
                        }
                    }
                    .frame(height: vm.notchState == .open ? vm.notchSize.height : nil, alignment: .top)
                    .conditionalModifier(true) { view in
                        let openAnimation = Animation.spring(response: 0.42, dampingFraction: 0.8, blendDuration: 0)
                        let closeAnimation = Animation.spring(response: 0.45, dampingFraction: 1.0, blendDuration: 0)
                        
                        return view
                            .animation(vm.notchState == .open ? openAnimation : closeAnimation, value: vm.notchState)
                            .animation(.smooth, value: gestureProgress)
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering in
                        handleHover(hovering)
                    }
                    .onTapGesture {
                        doOpen()
                    }
                    .conditionalModifier(Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .down, capturesMouseDrag: vm.notchState == .closed) { translation, phase in
                                handleDownGesture(translation: translation, phase: phase)
                            }
                    }
                    .conditionalModifier(Defaults[.closeGestureEnabled] && Defaults[.enableGestures]) { view in
                        view
                            .panGesture(direction: .up, capturesMouseDrag: false) { translation, phase in
                                handleUpGesture(translation: translation, phase: phase)
                            }
                    }
                    .onReceive(NotificationCenter.default.publisher(for: .sharingDidFinish)) { _ in
                        if vm.notchState == .open && !isHovering && !vm.isBatteryPopoverActive {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if self.vm.notchState == .open && !self.isHovering && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .onChange(of: vm.notchState) { _, newState in
                        if newState == .closed && isHovering {
                            withAnimation {
                                isHovering = false
                            }
                        }
                    }
                    .onChange(of: vm.isBatteryPopoverActive) {
                        if !vm.isBatteryPopoverActive && !isHovering && vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                            hoverTask?.cancel()
                            hoverTask = Task {
                                try? await Task.sleep(for: .milliseconds(100))
                                guard !Task.isCancelled else { return }
                                await MainActor.run {
                                    if !self.vm.isBatteryPopoverActive && !self.isHovering && self.vm.notchState == .open && !SharingStateManager.shared.preventNotchClose {
                                        self.vm.close()
                                    }
                                }
                            }
                        }
                    }
                    .sensoryFeedback(.alignment, trigger: haptics)
                    .contextMenu {
                        Button("Settings") {
                            DispatchQueue.main.async {
                                SettingsWindowController.shared.showWindow()
                            }
                        }
                        .keyboardShortcut(KeyEquivalent(","), modifiers: .command)
                        //                    Button("Edit") { // Doesnt work....
                        //                        let dn = DynamicNotch(content: EditPanelView())
                        //                        dn.toggle()
                        //                    }
                        //                    .keyboardShortcut("E", modifiers: .command)
                    }
                if vm.chinHeight > 0 {
                    Rectangle()
                        .fill(Color.black.opacity(0.01))
                        .frame(width: computedChinWidth, height: vm.chinHeight)
                }
            }
            .opacity(showsTaskPopup || showsPrompterReading || showsWellnessBanner || showsDevicePopup || showsAgendaPopup || showsCallPopup ? 0 : 1)
            .allowsHitTesting(!showsTaskPopup && !showsPrompterReading && !showsWellnessBanner && !showsDevicePopup && !showsAgendaPopup && !showsCallPopup)
            if showsTaskPopup, let notice = codingTasks.notice {
                VStack(spacing: 0) {
                    Color.clear.frame(height: max(24, vm.effectiveClosedNotchHeight))
                    MorisTaskPopup(notice: notice).padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 22)
                }
                .frame(width: 480).background(.black)
                .clipShape(NotchShape(topCornerRadius: 19, bottomCornerRadius: 24))
                .transition(.opacity).zIndex(7)
            }
            if showsPrompterReading {
                VStack(spacing: 0) {
                    Color.clear.frame(height: max(24, vm.effectiveClosedNotchHeight))
                    PrompterReadingPanel()
                }
                .frame(width: PrompterPanelController.readingSize.width, height: PrompterPanelController.readingSize.height)
                .background(.black)
                .clipShape(NotchShape(topCornerRadius: 19, bottomCornerRadius: 24))
                .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
                .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.97, anchor: .top)))
                .zIndex(8)
            }
            if showsCallPopup, let call = calls.activity {
                VStack(spacing: 0) {
                    Color.clear.frame(height: max(24, vm.effectiveClosedNotchHeight))
                    CallActivityPopup(call: call)
                        .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 20)
                }
                .frame(width: 480).background(.black)
                .clipShape(NotchShape(topCornerRadius: 19, bottomCornerRadius: 24))
                .transition(.opacity).zIndex(12)
            }
            if showsAgendaPopup, let alert = agenda.notice {
                VStack(spacing: 0) {
                    Color.clear.frame(height: max(24, vm.effectiveClosedNotchHeight))
                    CalendarAgendaPopup(alert: alert)
                        .padding(.horizontal, 22).padding(.top, 8).padding(.bottom, 20)
                }
                .frame(width: 480)
                .background(.black)
                .clipShape(NotchShape(topCornerRadius: 19, bottomCornerRadius: 24))
                .transition(.opacity).zIndex(11)
                .onAppear { agenda.beginPresentation(owner: agendaOwner) }
                .onDisappear { agenda.endPresentation(owner: agendaOwner) }
            }
            if showsDevicePopup, let notice = deviceConnections.notice {
                VStack(spacing: 0) {
                    Color.clear.frame(height: max(24, vm.effectiveClosedNotchHeight))
                    DeviceConnectionPopup(notice: notice)
                        .padding(.horizontal, 28).padding(.top, 12).padding(.bottom, 24)
                }
                .frame(width: 460)
                .background(.black)
                .clipShape(NotchShape(topCornerRadius: 19, bottomCornerRadius: 24))
                .transition(.opacity)
                .zIndex(9)
            }
            if showsWellnessBanner, let reminder = everydayReminders.pending {
                VStack(spacing: 0) {
                    Color.clear.frame(height: max(24, vm.effectiveClosedNotchHeight))
                    WellnessReminderBanner(reminder: reminder)
                        .padding(.horizontal, 24).padding(.top, 12).padding(.bottom, 22)
                }
                .frame(width: openNotchSize.width)
                .background(.black)
                .clipShape(NotchShape(topCornerRadius: 19, bottomCornerRadius: 26))
                .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
                .transition(.opacity.combined(with: .scale(scale: reduceMotion ? 1 : 0.94, anchor: .top)))
                .onAppear { everydayReminders.beginPresentation(owner: wellnessOwner) }
                .onDisappear { everydayReminders.endPresentation(owner: wellnessOwner) }
                .zIndex(10)
            }
        }
        .animation(reduceMotion ? .easeOut(duration: 0.15) : .spring(response: 0.45, dampingFraction: 0.86), value: showsWellnessBanner)
        .animation(reduceMotion ? nil : .spring(response: 0.45, dampingFraction: 0.88), value: coordinator.expandingView.show)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: usesFocusActivity)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: showsDevicePopup)
        .task { deviceConnections.configure(enabled: deviceConnectionPopups) }
        .onChange(of: deviceConnectionPopups) { _, enabled in deviceConnections.configure(enabled: enabled) }
        .task { agenda.configure(enabled: calendarAgendaPopups) }
        .onChange(of: calendarAgendaPopups) { _, enabled in agenda.configure(enabled: enabled) }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showsAgendaPopup)
        .task { calls.configure(enabled: experimentalCallDetection); calls.suspend(!wellnessSessionUnlocked) }
        .onChange(of: experimentalCallDetection) { _, enabled in calls.configure(enabled: enabled) }
        .onChange(of: wellnessSessionUnlocked) { _, unlocked in calls.suspend(!unlocked) }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: showsCallPopup)
        .onChange(of: deviceConnections.notice?.id) { _, _ in
            if !wellnessSessionUnlocked { deviceConnections.dismiss() }
        }
        .onReceive(DistributedNotificationCenter.default().publisher(for: NSNotification.Name("com.apple.screenIsLocked"))) { _ in wellnessSessionUnlocked = false }
        .onReceive(DistributedNotificationCenter.default().publisher(for: NSNotification.Name("com.apple.screenIsUnlocked"))) { _ in wellnessSessionUnlocked = true }
        .padding(.bottom, 8)
        .frame(width: windowSize.width, height: windowSize.height, alignment: .top)
        .ignoresSafeArea(.container, edges: .top)
        .compositingGroup()
        .scaleEffect(
            x: gestureScale,
            y: gestureScale,
            anchor: .top
        )
        .animation(.smooth, value: gestureProgress)
        .background(dragDetector)
        .background(PrompterNotchAnchor(viewModel: vm))
        .background(TabSwipeMonitor(canNavigate: {
            Defaults[.enableGestures] && Defaults[.swipeToSwitchTabs] &&
            vm.notchState == .open && !showsPrompterReading &&
            !vm.interactionLocks.isLocked && !vm.anyDropZoneTargeting &&
            !shelfSelection.isDragging && !shelfSelection.isPreviewing &&
            !shelfSelection.isEditingSearch && !focusTimer.isEditingGoal &&
            !focusTasks.isEditing && !clipboardHistory.isEditing &&
            !PrompterModel.shared.isEditing && !codingTasks.isConfiguring
        }, navigate: { step in
            let available = tabs.filter { $0.view != .shelf || Defaults[.boringShelf] }
            guard let index = available.firstIndex(where: { $0.view == coordinator.currentView }),
                  available.indices.contains(index + step) else { return }
            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) {
                coordinator.currentView = available[index + step].view
            }
        }))
        .background {
            FloatingLyricsPanel(
                isVisible: floatingLyricsVisible && floatingLyricStyle == .transparent,
                topInset: max(0, vm.effectiveClosedNotchHeight - 8),
                width: floatingPanelWidth,
                content: persistentLyricsView
                    .preferredColorScheme(.dark)
                    .frame(width: floatingPanelWidth, height: 100, alignment: .top),
                contrastSampler: lyricContrast,
                adaptiveContrast: adaptiveLyricContrast && !reduceTransparency && wellnessSessionUnlocked
            )
        }
        .preferredColorScheme(.dark)
        .environmentObject(vm)
        .onReceive(PrompterModel.shared.$isPresented.removeDuplicates()) { prompterPresented = $0 }
        .onReceive(PrompterModel.shared.$presentationScreenID.removeDuplicates()) { prompterScreenID = $0 }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.22), value: showsPrompterReading)
        .onChange(of: vm.interactionLocks.isLocked) { _, locked in
            if locked {
                hoverTask?.cancel()
            } else if !isHovering && vm.notchState == .open {
                handleHover(false)
            }
        }
        .onChange(of: shelfSelection.isDragging) { _, dragging in
            if dragging { hoverTask?.cancel() }
            else if !isHovering && vm.notchState == .open { handleHover(false) }
        }
        .onChange(of: focusTimer.isEditingGoal) { _, editing in
            if !editing && !isHovering && vm.notchState == .open {
                vm.close()
            }
        }
        .onChange(of: focusTasks.isEditing) { _, editing in
            if !editing && !isHovering && vm.notchState == .open { vm.close() }
        }
        .onChange(of: clipboardHistory.isEditing) { _, editing in
            if !editing && !isHovering && vm.notchState == .open { vm.close() }
        }
        .onChange(of: shelfSelection.isEditingSearch) { _, editing in
            if !editing && !isHovering && vm.notchState == .open { vm.close() }
        }
        .onChange(of: shelfSelection.isPreviewing) { _, previewing in
            if !previewing && !isHovering && vm.notchState == .open { vm.close() }
        }
        .onChange(of: coordinator.currentView) { _, selectedView in
            if vm.notchState == .open {
                vm.notchSize = PrompterModel.shared.isPresented && PrompterModel.shared.presentationScreenID == vm.screenUUID
                    ? PrompterPanelController.readingSize : expandedPanelSize(for: selectedView)
            }
        }
        .onChange(of: vm.anyDropZoneTargeting) { _, isTargeted in
            anyDropDebounceTask?.cancel()

            if isTargeted {
                if Defaults[.boringShelf] && !shelfSelection.isDragging {
                    hoverTask?.cancel()
                    coordinator.currentView = .shelf
                    if vm.notchState == .closed { vm.open() }
                }
                return
            }

            anyDropDebounceTask = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(500))
                guard !Task.isCancelled else { return }

                if vm.dropEvent {
                    vm.dropEvent = false
                    return
                }

                vm.dropEvent = false
                if !SharingStateManager.shared.preventNotchClose {
                    vm.close()
                }
            }
        }
    }

    @ViewBuilder
    func NotchLayout() -> some View {
        VStack(alignment: vm.notchState == .open ? .leading : .center) {
            VStack(alignment: vm.notchState == .open ? .leading : .center) {
                if coordinator.helloAnimationRunning {
                    Spacer()
                    HelloAnimation(onFinish: {
                        vm.closeHello()
                    }).frame(
                        width: getClosedNotchSize().width,
                        height: 80
                    )
                    .padding(.top, 40)
                    Spacer()
                } else {
                    if coordinator.expandingView.type == .battery && coordinator.expandingView.show
                        && vm.notchState == .closed && Defaults[.showPowerStatusNotifications]
                        && !vm.hideOnClosed && wellnessSessionUnlocked
                    {
                        VStack(spacing: 0) {
                            // All text sits below the camera's physical cutout.
                            Color.clear.frame(height: max(24, vm.effectiveClosedNotchHeight))
                            ChargingConfirmationView()
                                .padding(.horizontal, 22)
                                .padding(.top, 8)
                                .padding(.bottom, 22)
                        }
                        .frame(width: 460)
                      } else if coordinator.sneakPeek.show && Defaults[.inlineHUD] && (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && vm.notchState == .closed {
                          InlineHUD(type: $coordinator.sneakPeek.type, value: $coordinator.sneakPeek.value, icon: $coordinator.sneakPeek.icon, hoverAnimation: $isHovering, gestureProgress: $gestureProgress)
                              .transition(.opacity)
                      } else if let reminder = everydayReminders.pending, vm.notchState == .closed && !vm.hideOnClosed {
                          HStack(spacing: 8) {
                              Image(systemName: reminder == .water ? "drop.fill" : "eye")
                                  .frame(width: 22)
                              Color.clear.frame(width: max(0, vm.closedNotchSize.width - 6))
                              Text(reminder == .water ? "Water" : "Break").font(.caption).frame(width: 48)
                          }
                          .foregroundStyle(.mint)
                          .frame(height: vm.effectiveClosedNotchHeight)
                      } else if usesDualActivity && vm.notchState == .closed && !vm.hideOnClosed && !coordinator.expandingView.show {
                          compactDualActivity
                      } else if usesFocusActivity && vm.notchState == .closed && !vm.hideOnClosed {
                          compactFocusActivity
                      } else if (!coordinator.expandingView.show || coordinator.expandingView.type == .music) && vm.notchState == .closed && (musicManager.isPlaying || !musicManager.isPlayerIdle) && coordinator.musicLiveActivityEnabled && !vm.hideOnClosed {
                          MusicLiveActivity()
                              .frame(alignment: .center)
                      } else if !coordinator.expandingView.show && vm.notchState == .closed && (!musicManager.isPlaying && musicManager.isPlayerIdle) && Defaults[.showNotHumanFace] && !vm.hideOnClosed  {
                          BoringFaceAnimation()
                       } else if vm.notchState == .open {
                           BoringHeader()
                               .frame(height: max(24, vm.effectiveClosedNotchHeight))
                               .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
                       } else {
                           Rectangle().fill(.clear).frame(width: vm.closedNotchSize.width - 20, height: vm.effectiveClosedNotchHeight)
                       }

                      if floatingLyricsVisible && floatingLyricStyle == .black {
                          persistentLyricsView
                      }

                      if coordinator.sneakPeek.show {
                          if (coordinator.sneakPeek.type != .music) && (coordinator.sneakPeek.type != .battery) && !Defaults[.inlineHUD] && vm.notchState == .closed {
                              SystemEventIndicatorModifier(
                                  eventType: $coordinator.sneakPeek.type,
                                  value: $coordinator.sneakPeek.value,
                                  icon: $coordinator.sneakPeek.icon,
                                  sendEventBack: { newVal in
                                      switch coordinator.sneakPeek.type {
                                      case .volume:
                                          VolumeManager.shared.setAbsolute(Float32(newVal))
                                      case .brightness:
                                          BrightnessManager.shared.setAbsolute(value: Float32(newVal))
                                      default:
                                          break
                                      }
                                  }
                              )
                              .padding(.bottom, 10)
                              .padding(.leading, 4)
                              .padding(.trailing, 8)
                          }
                          // Old sneak peek music
                          else if coordinator.sneakPeek.type == .music {
                              if vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard {
                                  HStack(alignment: .center) {
                                      Image(systemName: "music.note")
                                      GeometryReader { geo in
                                          MarqueeText(.constant(musicManager.songTitle + " - " + musicManager.artistName),  textColor: Defaults[.playerColorTinting] ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.6) : .gray, minDuration: 1, frameWidth: geo.size.width)
                                      }
                                  }
                                  .foregroundStyle(.gray)
                                  .padding(.bottom, 10)
                              }
                          }
                      }
                  }
              }
              .conditionalModifier((coordinator.sneakPeek.show && (coordinator.sneakPeek.type == .music) && vm.notchState == .closed && !vm.hideOnClosed && Defaults[.sneakPeekStyles] == .standard) || (coordinator.sneakPeek.show && (coordinator.sneakPeek.type != .music) && (vm.notchState == .closed))) { view in
                  view
                      .fixedSize()
              }
              .zIndex(2)
            if vm.notchState == .open {
                VStack {
                    switch coordinator.currentView {
                    case .home:
                        NotchHomeView(albumArtNamespace: albumArtNamespace)
                    case .shelf:
                        ShelfView()
                    case .focus:
                        FocusTimerControls()
                    case .everyday:
                        EverydayToolsView()
                    case .prompter:
                        PrompterEditorView()
                    case .tasks:
                        if MorisTaskFeature.isEnabled { MorisTasksView() }
                        else { NotchHomeView(albumArtNamespace: albumArtNamespace) }
                    }
                }
                .transition(
                    .scale(scale: 0.8, anchor: .top)
                    .combined(with: .opacity)
                    .animation(.smooth(duration: 0.35))
                )
                .zIndex(1)
                .allowsHitTesting(vm.notchState == .open)
                .opacity(gestureProgress != 0 ? 1.0 - min(abs(gestureProgress) * 0.1, 0.3) : 1.0)
            }
        }
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], delegate: GeneralDropTargetDelegate(isTargeted: $vm.generalDropTargeting) { providers in
            vm.dropEvent = true
            ShelfStateViewModel.shared.load(providers)
        })
    }

    private var compactClockStatus: (label: String, icon: String, completed: Bool) {
        let hasStopwatch = utilityClocks.stopwatchRunning || utilityClocks.stopwatchSeconds > 0
        let showFocus = focusTimer.hasCompactActivity && (!focusTimer.isFinished || (!utilityClocks.hasCompactTimer && !hasStopwatch))
        let showTimer = !showFocus && utilityClocks.hasCompactTimer && (!utilityClocks.timerDone || !hasStopwatch)
        let completed = showFocus ? focusTimer.isFinished : showTimer ? utilityClocks.timerDone : false
        let label = showFocus
            ? (focusTimer.isFinished ? "Done" : focusTimer.displayTime)
            : showTimer
                ? (utilityClocks.timerDone ? "Done" : UtilityClockModel.formatted(utilityClocks.remaining))
                : UtilityClockModel.formatted(utilityClocks.stopwatchSeconds)
        let paused = showFocus ? !focusTimer.isRunning : showTimer ? !utilityClocks.timerRunning : !utilityClocks.stopwatchRunning
        let icon = completed ? "checkmark.circle.fill" : paused ? "pause.circle" : showFocus || showTimer ? "timer" : "stopwatch"
        return (label, icon, completed)
    }

    private var compactDualActivity: some View {
        let status = compactClockStatus
        return HStack(spacing: 8) {
            Button {
                coordinator.currentView = .home
                vm.open()
            } label: {
                HStack(spacing: 7) {
                    Image(nsImage: musicManager.albumArt).resizable().scaledToFill()
                        .frame(width: 20, height: 20).clipShape(RoundedRectangle(cornerRadius: 5))
                    CompactMusicSpectrum(isPlaying: $musicManager.isPlaying, tint: compactSpectrumColor)
                }
                .foregroundStyle(Color(nsColor: musicManager.avgColor))
                .frame(width: 70, height: vm.effectiveClosedNotchHeight).contentShape(Rectangle())
            }.buttonStyle(.plain).help("Open music controls")
                .accessibilityLabel("Music: \(musicManager.songTitle). Open player")
            Color.clear.frame(width: max(0, vm.closedNotchSize.width - 6))
            Button {
                coordinator.currentView = .focus
                vm.open()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: status.icon).font(.system(size: 12))
                    Text(status.label).font(.system(size: 11, weight: .semibold))
                        .monospacedDigit().contentTransition(.numericText()).lineLimit(1)
                }
                .foregroundStyle(status.completed ? Color.green : Color.white)
                .frame(width: 70, height: vm.effectiveClosedNotchHeight).contentShape(Rectangle())
            }.buttonStyle(.plain).help("Open time tools")
                .accessibilityLabel("Clock: \(status.label). Open time tools")
        }
        .frame(height: vm.effectiveClosedNotchHeight)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: status.completed)
    }

    private var compactFocusActivity: some View {
        let status = compactClockStatus
        return HStack(spacing: 8) {
            Image(systemName: status.icon)
                .frame(width: 22)
            Color.clear.frame(width: max(0, vm.closedNotchSize.width - 6))
            Text(status.label)
                .monospacedDigit()
                .frame(width: 48)
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(status.completed ? .green : .white)
        .frame(height: vm.effectiveClosedNotchHeight)
        .accessibilityLabel("Clock activity \(status.label)")
    }

    private var persistentLyricsView: some View {
        TimelineView(.periodic(from: .now, by: 0.25)) { timeline in
            let darkText = floatingLyricStyle == .transparent && !reduceTransparency && adaptiveLyricContrast && lyricContrast.usesDarkText
            let textColor: Color = darkText ? .black : .white
            let outline: Color = floatingLyricStyle == .black ? .clear : (darkText ? .white : .black)
            let delta = max(0, timeline.date.timeIntervalSince(musicManager.timestampDate))
            let elapsed = min(musicManager.songDuration, musicManager.elapsedTime + delta * musicManager.playbackRate)
            let context = musicManager.lyricContext(at: elapsed)
            VStack(alignment: lyricAlignment == .leading ? .leading : .center, spacing: 1) {
                Text(context.current)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(textColor)
                    .contentTransition(.opacity)
                if persistentNotchLyricLines == 2 {
                    Text(context.next ?? " ")
                        .font(.system(size: 9.5))
                        .foregroundStyle(textColor.opacity(0.85))
                }
            }
            .lineLimit(1)
            .multilineTextAlignment(lyricAlignment.textAlignment)
            .shadow(color: outline.opacity(0.9), radius: 0.8, x: 1)
            .shadow(color: outline.opacity(0.9), radius: 0.8, x: -1)
            .shadow(color: outline.opacity(0.9), radius: 0.8, y: 1)
            .shadow(color: outline.opacity(0.9), radius: 0.8, y: -1)
            .frame(width: floatingLyricStyle == .black ? 320 : max(220, min(380, ambientNotchWidth - 32)), alignment: lyricAlignment.frameAlignment)
            .padding(.horizontal, 12)
            .padding(.top, floatingLyricStyle == .transparent ? 14 : 10)
            .padding(.bottom, 6)
            .background(alignment: .top) {
                if floatingLyricStyle == .black {
                    Color.black
                } else if reduceTransparency {
                    RoundedRectangle(cornerRadius: 10).fill(.black.opacity(0.9))
                } else {
                    ZStack(alignment: .top) {
                        if floatingLyricsAmbient {
                            LinearGradient(stops: [
                                // Transparent, not black: the panel's top edge
                                // cannot create a horizontal band across the notch.
                                .init(color: .clear, location: 0),
                                .init(color: Color(nsColor: musicManager.avgColor).opacity(lyricGradientIntensity * 0.38), location: 0.12),
                                .init(color: Color(nsColor: musicManager.avgColor).opacity(lyricGradientIntensity * 0.45), location: 0.2),
                                .init(color: Color(nsColor: musicManager.avgColor).opacity(0.18 * lyricGradientIntensity), location: 0.65),
                                .init(color: .clear, location: 1)
                            ], startPoint: .top, endPoint: .bottom)
                            .frame(width: floatingPanelWidth, height: lyricGradientDepth)
                            .mask {
                                TaperedLyricGlow(topWidth: ambientNotchWidth - 2 * cornerRadiusInsets.closed.top)
                                    .fill(.black)
                                    .blur(radius: 8)
                            }
                            .mask {
                                LinearGradient(stops: [
                                    .init(color: .clear, location: 0),
                                    .init(color: .black, location: 0.18),
                                    .init(color: .black, location: 0.82),
                                    .init(color: .clear, location: 1)
                                ], startPoint: .leading, endPoint: .trailing)
                            }
                        }
                    }
                }
            }
            .animation(animateLyricTransitions && !reduceMotion ? .easeInOut(duration: 0.2) : nil, value: context.current)
        }
        .accessibilityLabel("Synced lyrics")
    }

    @ViewBuilder
    func BoringFaceAnimation() -> some View {
        RestingCatEyes(
            cameraGap: restingCatCameraGap,
            height: vm.effectiveClosedNotchHeight,
            isActive: !showsTaskPopup && !showsWellnessBanner && !showsDevicePopup && !showsAgendaPopup && !showsCallPopup
        )
        .overlay(alignment: .bottomTrailing) {
            if MorisTaskFeature.isEnabled && codingTasks.runningCount > 0 {
                Circle().fill(.blue).frame(width: 5, height: 5)
                    .accessibilityLabel("\(codingTasks.runningCount) local tasks running")
            }
        }
    }

    private var restingCatCameraGap: CGFloat {
        let screen = vm.screenUUID.flatMap { NSScreen.screen(withUUID: $0) } ?? NSScreen.main
        guard let screen, screen.safeAreaInsets.top > 0 else { return 0 }
        // Derive the protected gap from hardware, even when the user customizes notch size.
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            return max(vm.closedNotchSize.width, screen.frame.width - left.width - right.width + 8)
        }
        return vm.closedNotchSize.width + 8
    }

    @ViewBuilder
    func MusicLiveActivity() -> some View {
        HStack {
            Image(nsImage: musicManager.albumArt)
                .resizable()
                .clipped()
                .clipShape(
                    RoundedRectangle(
                        cornerRadius: MusicPlayerImageSizes.cornerRadiusInset.closed)
                )
                .matchedGeometryEffect(id: "albumArt", in: albumArtNamespace)
                .frame(
                    width: max(0, vm.effectiveClosedNotchHeight - 12),
                    height: max(0, vm.effectiveClosedNotchHeight - 12)
                )
            Rectangle()
                .fill(.black)
                .overlay(
                    HStack(alignment: .top) {
                        if coordinator.expandingView.show
                            && coordinator.expandingView.type == .music
                        {
                            MarqueeText(
                                .constant(musicManager.songTitle),
                                textColor: Defaults[.coloredSpectrogram]
                                    ? Color(nsColor: musicManager.avgColor) : Color.gray,
                                minDuration: 0.4,
                                frameWidth: 100
                            )
                            .opacity(
                                (coordinator.expandingView.show
                                    && Defaults[.sneakPeekStyles] == .inline)
                                    ? 1 : 0
                            )
                            Spacer(minLength: vm.closedNotchSize.width)
                            // Song Artist
                            Text(musicManager.artistName)
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .foregroundStyle(
                                    Defaults[.coloredSpectrogram]
                                        ? Color(nsColor: musicManager.avgColor)
                                        : Color.gray
                                )
                                .opacity(
                                    (coordinator.expandingView.show
                                        && coordinator.expandingView.type == .music
                                        && Defaults[.sneakPeekStyles] == .inline)
                                        ? 1 : 0
                                )
                        }
                    }
                )
                .frame(
                    width: (coordinator.expandingView.show
                        && coordinator.expandingView.type == .music
                        && Defaults[.sneakPeekStyles] == .inline)
                        ? 380
                        : vm.closedNotchSize.width
                            + -cornerRadiusInsets.closed.top
                )

            HStack {
                if showsPersistentLyrics || useMusicVisualizer {
                    CompactMusicSpectrum(isPlaying: $musicManager.isPlaying, tint: compactSpectrumColor)
                        .matchedGeometryEffect(id: "spectrum", in: albumArtNamespace)
                } else {
                    LottieAnimationContainer()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(
                width: max(
                    0,
                    vm.effectiveClosedNotchHeight - 12
                        + gestureProgress / 2
                ),
                height: max(
                    0,
                    vm.effectiveClosedNotchHeight - 12
                ),
                alignment: .center
            )
        }
        .frame(
            height: vm.effectiveClosedNotchHeight,
            alignment: .center
        )
    }

    private var compactSpectrumColor: Color {
        Defaults[.coloredSpectrogram]
            ? Color(nsColor: musicManager.avgColor).ensureMinimumBrightness(factor: 0.65) : .white
    }

    @ViewBuilder
    var dragDetector: some View {
        if Defaults[.boringShelf] {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
        .onDrop(of: [.fileURL, .url, .utf8PlainText, .plainText, .data], isTargeted: $vm.dragDetectorTargeting) { providers in
            guard !shelfSelection.isDragging else { return false }
            vm.dropEvent = true
            ShelfStateViewModel.shared.load(providers)
            return true
        }
        } else {
            EmptyView()
        }
    }

    private func doOpen() {
        withAnimation(animationSpring) {
            if everydayReminders.pending != nil { coordinator.currentView = .everyday }
            vm.open()
        }
    }

    // MARK: - Hover Management

    private func handleHover(_ hovering: Bool) {
        if coordinator.firstLaunch { return }
        hoverTask?.cancel()
        
        if hovering {
            withAnimation(animationSpring) {
                isHovering = true
            }
            
            if vm.notchState == .closed && Defaults[.enableHaptics] {
                haptics.toggle()
            }
            
            guard vm.notchState == .closed,
                  !coordinator.sneakPeek.show,
                  Defaults[.openNotchOnHover] else { return }
            
            hoverTask = Task {
                try? await Task.sleep(for: .seconds(Defaults[.minimumHoverDuration]))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    guard self.vm.notchState == .closed,
                          self.isHovering,
                          !self.coordinator.sneakPeek.show else { return }
                    
                    self.doOpen()
                }
            }
        } else {
            isHovering = false
            if vm.interactionLocks.isLocked {
                return
            }
            hoverTask = Task {
                try? await Task.sleep(for: .milliseconds(100))
                guard !Task.isCancelled else { return }
                
                await MainActor.run {
                    guard !Task.isCancelled, !self.isHovering, !self.vm.interactionLocks.isLocked else { return }
                    if self.vm.notchState == .open && !self.vm.isBatteryPopoverActive && !SharingStateManager.shared.preventNotchClose {
                        self.vm.close()
                    }
                }
            }
        }
    }

    // MARK: - Gesture Handling

    private func handleDownGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .closed else { return }

        if phase == .ended {
            withAnimation(animationSpring) { gestureProgress = .zero }
            return
        }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * 20
        }

        if translation > Defaults[.gestureSensitivity] {
            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
            doOpen()
        }
    }

    private func handleUpGesture(translation: CGFloat, phase: NSEvent.Phase) {
        guard vm.notchState == .open && !vm.isHoveringCalendar else { return }

        withAnimation(animationSpring) {
            gestureProgress = (translation / Defaults[.gestureSensitivity]) * -20
        }

        if phase == .ended {
            withAnimation(animationSpring) {
                gestureProgress = .zero
            }
        }

        if translation > Defaults[.gestureSensitivity] {
            withAnimation(animationSpring) {
                isHovering = false
            }
            if !SharingStateManager.shared.preventNotchClose { 
                gestureProgress = .zero
                vm.close()
            }

            if Defaults[.enableHaptics] {
                haptics.toggle()
            }
        }
    }
}

struct FullScreenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onDrop: () -> Void

    func dropEntered(info _: DropInfo) {
        isTargeted = true
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info _: DropInfo) -> Bool {
        isTargeted = false
        onDrop()
        return true
    }

}

struct GeneralDropTargetDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    var onDrop: ([NSItemProvider]) -> Void
    private let types = [UTType.fileURL, .url, .utf8PlainText, .plainText, .data]

    func validateDrop(info: DropInfo) -> Bool {
        Defaults[.boringShelf] && !ShelfSelectionModel.shared.isDragging && info.hasItemsConforming(to: types)
    }

    func dropEntered(info: DropInfo) {
        isTargeted = validateDrop(info: info)
    }

    func dropExited(info: DropInfo) {
        isTargeted = false
    }

    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: validateDrop(info: info) ? .copy : .cancel)
    }

    func performDrop(info: DropInfo) -> Bool {
        guard validateDrop(info: info) else { return false }
        let providers = info.itemProviders(for: types)
        guard !providers.isEmpty else { return false }
        onDrop(providers)
        isTargeted = false
        return true
    }
}

#Preview {
    let vm = BoringViewModel()
    vm.open()
    return ContentView()
        .environmentObject(vm)
        .frame(width: vm.notchSize.width, height: vm.notchSize.height)
}
