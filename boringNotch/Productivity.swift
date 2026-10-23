import AppKit
import Combine
import IOKit.pwr_mgt
import SwiftUI

/// Parked until pairing and integrations are ready for general users.
enum MorisTaskFeature {
    static let isEnabled = false
}

enum KeepAwakePower {
    static func create(seconds: TimeInterval?) -> UInt32? {
        var id: IOPMAssertionID = 0
        let result = IOPMAssertionCreateWithDescription(kIOPMAssertionTypePreventUserIdleSystemSleep as CFString,
            "MORIS Keep Awake" as CFString, "User-selected Keep Awake session" as CFString,
            "Keep background work running until the selected duration ends." as CFString,
            nil, seconds ?? 0, kIOPMAssertionTimeoutActionRelease as CFString, &id)
        return result == kIOReturnSuccess ? id : nil
    }
}

@MainActor
final class KeepAwakeModel: ObservableObject {
    static let shared = KeepAwakeModel()
    @Published private(set) var isActive = false
    @Published private(set) var remaining: Int?
    @Published private(set) var error: String?
    private var assertion: UInt32?
    private var deadline: Date?
    private var ticker: Task<Void, Never>?
    private let now: () -> Date
    private let create: (TimeInterval?) -> UInt32?
    private let release: (UInt32) -> Void
    private let schedulesTicks: Bool

    init(now: @escaping () -> Date = Date.init, schedulesTicks: Bool = true,
         create: @escaping (TimeInterval?) -> UInt32? = KeepAwakePower.create,
         release: @escaping (UInt32) -> Void = { _ = IOPMAssertionRelease($0) }) {
        self.now = now; self.schedulesTicks = schedulesTicks; self.create = create; self.release = release
    }

    func start(minutes: Int?) {
        stop()
        let seconds = minutes.map { Double(min(480, max(1, $0)) * 60) }
        guard let id = create(seconds) else { error = "macOS could not start Keep Awake."; return }
        assertion = id
        deadline = seconds.map { now().addingTimeInterval($0) }
        remaining = seconds.map { Int($0) }
        isActive = true
        error = nil
        guard schedulesTicks else { return }
        ticker = Task { @MainActor [weak self] in
            do {
                while !Task.isCancelled {
                    try await Task.sleep(for: .seconds(1))
                    guard let self, self.isActive else { return }
                    self.tick()
                }
            } catch {}
        }
    }

    func tick() {
        guard isActive, let deadline else { return }
        let seconds = max(0, Int(ceil(deadline.timeIntervalSince(now()))))
        remaining = seconds
        if seconds == 0 { stop() }
    }

    func stop() {
        ticker?.cancel(); ticker = nil
        if let assertion { release(assertion) }
        assertion = nil; deadline = nil; remaining = nil; isActive = false
    }
}

enum MorisTaskState: String, CaseIterable {
    case running, waiting, completed, failed
    var label: String {
        switch self { case .running: "Running"; case .waiting: "Needs attention"; case .completed: "Completed"; case .failed: "Failed" }
    }
    var symbol: String {
        switch self { case .running: "arrow.triangle.2.circlepath"; case .waiting: "hand.raised.fill"; case .completed: "checkmark.circle.fill"; case .failed: "exclamationmark.circle.fill" }
    }
    var color: Color {
        switch self { case .running: .blue; case .waiting: .orange; case .completed: .green; case .failed: .red }
    }
}

struct MorisTaskEvent {
    let id: String
    let title: String
    let source: String
    let state: MorisTaskState
    let sentAt: Date

    static func parse(_ url: URL, token: String, now: Date) -> Self? {
        guard url.absoluteString.utf8.count <= 4096,
              let parts = URLComponents(url: url, resolvingAgainstBaseURL: false),
              parts.scheme == "moris", parts.host == "task", parts.path.isEmpty,
              parts.user == nil, parts.password == nil, parts.port == nil, parts.fragment == nil,
              let query = parts.queryItems, Set(query.map(\.name)).count == query.count else { return nil }
        let values = Dictionary(uniqueKeysWithValues: query.map { ($0.name, $0.value ?? "") })
        guard Set(values.keys) == Set(["token", "id", "status", "source", "title", "sentAt"]),
              !token.isEmpty, values["token"] == token,
              let id = values["id"], (1...80).contains(id.count),
              id.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._:-").contains($0) }),
              let state = values["status"].flatMap(MorisTaskState.init(rawValue:)),
              let source = values["source"], ["command", "claude"].contains(source),
              let title = values["title"], !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              title.count <= 160, !title.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              let rawDate = values["sentAt"].flatMap(Double.init), rawDate.isFinite else { return nil }
        let sentAt = Date(timeIntervalSince1970: rawDate / 1000)
        guard abs(sentAt.timeIntervalSince(now)) <= 300 else { return nil }
        return Self(id: source + ":" + id, title: title, source: source, state: state, sentAt: sentAt)
    }
}

struct MorisTaskRecord: Identifiable {
    let id: String
    var title: String
    var source: String
    var state: MorisTaskState
    var started: Date
    var updated: Date
    var unread: Bool
}

struct MorisTaskNotice: Identifiable {
    let id = UUID()
    let title: String
    let state: MorisTaskState
    let isPreview: Bool
}

@MainActor
final class MorisTaskStore: ObservableObject {
    static let shared = MorisTaskStore()
    @Published var bridgeEnabled: Bool {
        didSet {
            storage.set(bridgeEnabled, forKey: "moris.tasks.enabled")
            if !bridgeEnabled { records = []; dismissNotice(); recent = [] }
        }
    }
    @Published private(set) var records: [MorisTaskRecord] = []
    @Published private(set) var notice: MorisTaskNotice?
    @Published var isConfiguring = false
    private(set) var token: String
    private let storage: UserDefaults
    private let now: () -> Date
    private let isAvailable: Bool
    private var recent: [Date] = []
    private var dismissTask: Task<Void, Never>?

    init(storage: UserDefaults = .standard, now: @escaping () -> Date = Date.init, isAvailable: Bool = MorisTaskFeature.isEnabled) {
        self.isAvailable = isAvailable
        self.storage = storage; self.now = now
        bridgeEnabled = isAvailable && storage.bool(forKey: "moris.tasks.enabled")
        if !isAvailable { storage.set(false, forKey: "moris.tasks.enabled") }
        token = storage.string(forKey: "moris.tasks.token") ?? UUID().uuidString
        storage.set(token, forKey: "moris.tasks.token")
    }

    var runningCount: Int { records.filter { $0.state == .running }.count }

    @discardableResult func receive(_ url: URL) -> Bool {
        guard isAvailable, bridgeEnabled, let event = MorisTaskEvent.parse(url, token: token, now: now()) else { return false }
        if let index = records.firstIndex(where: { $0.id == event.id }), event.sentAt > records[index].updated,
           records[index].state == event.state, records[index].title == event.title {
            records[index].updated = event.sentAt
            return true
        }
        recent = recent.filter { now().timeIntervalSince($0) < 60 }
        guard recent.count < 60 else { return false }
        if let index = records.firstIndex(where: { $0.id == event.id }) {
            guard event.sentAt > records[index].updated else { return false }
            let changed = records[index].state != event.state
            if event.state == .running && [.completed, .failed].contains(records[index].state) { records[index].started = event.sentAt }
            records[index].title = event.title
            records[index].state = event.state
            records[index].updated = event.sentAt
            if changed { records[index].unread = event.state != .running }
            if changed && event.state != .running { present(title: event.title, state: event.state) }
        } else {
            records.append(.init(id: event.id, title: event.title, source: event.source, state: event.state,
                                 started: event.sentAt, updated: event.sentAt, unread: event.state != .running))
            if event.state != .running { present(title: event.title, state: event.state) }
        }
        recent.append(now())
        records.sort { ($0.state == .running || $0.state == .waiting ? 0 : 1, -$0.updated.timeIntervalSince1970)
            < ($1.state == .running || $1.state == .waiting ? 0 : 1, -$1.updated.timeIntervalSince1970) }
        records = Array(records.prefix(50))
        return true
    }

    func markRead(_ id: String) { if let index = records.firstIndex(where: { $0.id == id }) { records[index].unread = false } }
    func clearFinished() { records.removeAll { $0.state == .completed || $0.state == .failed } }
    func rotateToken() {
        token = UUID().uuidString
        storage.set(token, forKey: "moris.tasks.token")
        records = []; recent = []; dismissNotice()
    }
    func preview() {
        guard isAvailable else { return }
        present(title: "MORIS task preview", state: .completed, preview: true)
    }
    func dismissNotice() { dismissTask?.cancel(); dismissTask = nil; notice = nil }
    private func present(title: String, state: MorisTaskState, preview: Bool = false) {
        dismissNotice()
        let value = MorisTaskNotice(title: title, state: state, isPreview: preview)
        notice = value
        dismissTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(5)) } catch { return }
            guard self?.notice?.id == value.id else { return }
            self?.notice = nil
        }
    }
}

struct KeepAwakeControls: View {
    @ObservedObject private var awake = KeepAwakeModel.shared
    @State private var minutes = 30
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Keep Awake", systemImage: "cup.and.saucer.fill").font(.headline)
            Label(awake.isActive ? "Mac stays awake" : "Normal sleep settings", systemImage: awake.isActive ? "moon.zzz.fill" : "moon")
                .font(.caption).foregroundStyle(awake.isActive ? .mint : .secondary)
            if awake.isActive {
                Text(awake.remaining.map { UtilityClockModel.formatted($0) } ?? "Until stopped")
                    .font(.system(size: 28, weight: .medium, design: .rounded)).monospacedDigit()
                Button("Stop Keep Awake", systemImage: "stop.fill") { awake.stop() }.toolButton(prominent: true)
            } else {
                Picker("Duration", selection: $minutes) {
                    Text("30 minutes").tag(30); Text("1 hour").tag(60); Text("2 hours").tag(120); Text("Until stopped").tag(0)
                }.labelsHidden()
                Button("Start Keep Awake") { awake.start(minutes: minutes == 0 ? nil : minutes) }.toolButton(prominent: true)
            }
            if let error = awake.error { Text(error).font(.caption).foregroundStyle(.orange) }
            Text("Prevents idle system sleep. Display may dim; closing the lid or choosing Sleep can still suspend work. Stops when MORIS quits.")
                .font(.caption2).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct KeepAwakeMenuButton: View {
    @ObservedObject private var awake = KeepAwakeModel.shared
    var body: some View {
        Button(awake.isActive ? "Stop Keep Awake" : "Keep Awake · 30 minutes") {
            if awake.isActive { awake.stop() } else { awake.start(minutes: 30) }
        }
    }
}

struct MorisTasksView: View {
    @EnvironmentObject private var vm: BoringViewModel
    @ObservedObject private var tasks = MorisTaskStore.shared
    @State private var showSetup = false
    @State private var copied = false
    var body: some View {
        HStack(alignment: .top, spacing: 20) {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("MORIS Tasks", systemImage: "terminal").font(.headline)
                    Spacer()
                    Text("\(tasks.runningCount) running").font(.caption).foregroundStyle(.secondary)
                    Button { showSetup = true } label: { Image(systemName: "gearshape") }
                        .buttonStyle(.plain).accessibilityLabel("Task bridge setup")
                }
                if tasks.records.isEmpty {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Follow local commands and connected Claude Code sessions.").font(.callout)
                        Text("No tasks yet. Configure the opt-in local bridge to send real status events. MORIS does not scan your chats or accounts.")
                            .font(.caption).foregroundStyle(.secondary)
                        Button("Set up task bridge") { showSetup = true }.toolButton()
                        Button("Preview task notification") { tasks.preview(); vm.close() }.toolButton(compact: true)
                    }.padding(.vertical, 20)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(tasks.records) { task in
                                Button { tasks.markRead(task.id) } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: task.state.symbol).foregroundStyle(task.state.color)
                                        VStack(alignment: .leading, spacing: 3) {
                                            Text(task.title).font(.caption.weight(.medium)).lineLimit(2)
                                            Text("\(task.source == "claude" ? "Claude Code hook" : "Local command") · \(task.state.label)")
                                                .font(.caption2).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        if task.unread { Circle().fill(.blue).frame(width: 5, height: 5).accessibilityLabel("Unread") }
                                    }.padding(10).background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                    Button("Clear finished") { tasks.clearFinished() }.buttonStyle(.plain).font(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Text("Local bridge events · sender labels are not account verification.").font(.caption2).foregroundStyle(.secondary)
            }
            VStack { KeepAwakeControls(); Spacer(minLength: 0) }.frame(width: 230).toolCard(emphasized: true)
        }
        .popover(isPresented: $showSetup) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Local task bridge").font(.headline)
                Toggle("Accept paired local task events", isOn: $tasks.bridgeEnabled)
                Text("Use the companion scripts in scripts/moris-task.sh. Pair using this Mac's token. Titles/statuses stay in memory; events cannot run commands or approve requests.")
                    .font(.caption).foregroundStyle(.secondary)
                Button(copied ? "Token copied" : "Copy pairing token") {
                    NSPasteboard.general.clearContents(); NSPasteboard.general.setString(tasks.token, forType: .string)
                    copied = true
                }.disabled(!tasks.bridgeEnabled)
                Button("Reset pairing token") { tasks.rotateToken(); copied = false }
                Text("Treat the token as private. Any local sender with it can submit status labels. Disabling clears task records. Integrations require manual setup; no Codex account or usage connection is included yet.")
                    .font(.caption2).foregroundStyle(.secondary)
            }.padding(18).frame(width: 340)
        }
        .onChange(of: showSetup) { _, showing in tasks.isConfiguring = showing }
        .onDisappear { tasks.isConfiguring = false }
    }
}

struct MorisTaskPopup: View {
    let notice: MorisTaskNotice
    var body: some View {
        HStack(spacing: 16) {
            RestingCatEyes(cameraGap: 0, height: 34).frame(width: 80)
                .overlay(alignment: .bottomTrailing) { Image(systemName: notice.state.symbol).foregroundStyle(notice.state.color) }
            VStack(alignment: .leading, spacing: 5) {
                Text(notice.isPreview ? "Task notification · Preview" : notice.state.label).font(.headline)
                Text(notice.title).font(.caption).lineLimit(2)
                Text("MORIS local task bridge").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            Button { MorisTaskStore.shared.dismissNotice() } label: { Image(systemName: "xmark").frame(width: 28, height: 28) }
                .buttonStyle(.plain).accessibilityLabel("Dismiss task notification")
        }.frame(minHeight: 70)
    }
}
