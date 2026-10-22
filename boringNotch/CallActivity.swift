import SwiftUI
import Defaults
import AppKit

struct DetectedCallActivity: Decodable, Equatable, Identifiable {
    let bundle: String
    let app: String
    let pid: Int32
    let phase: String
    var id: String { "\(bundle):\(pid)" }
}
private struct CallActivitySnapshot: Decodable {
    let status: String
    let calls: [DetectedCallActivity]
}

@MainActor
final class CallActivityStore: ObservableObject {
    static let shared = CallActivityStore()
    @Published private(set) var activity: DetectedCallActivity?
    @Published private(set) var status = "Call detection is off."
    private var enabled = false
    private var suspended = false
    private var runner: Task<Void, Never>?
    private var revision = 0
    private var missing = 0
    private var dismissedID: String?

    func configure(enabled: Bool) {
        guard enabled != self.enabled else { return }
        self.enabled = enabled
        revision += 1
        runner?.cancel()
        activity = nil; dismissedID = nil; missing = 0
        guard enabled else { status = "Call detection is off."; return }
        status = "Checking Accessibility access…"
        let generation = revision
        runner = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, self.enabled, self.revision == generation else { return }
                if !self.suspended {
                    let json = await XPCHelperClient.shared.callActivitySnapshot()
                    guard !Task.isCancelled, self.enabled, self.revision == generation else { return }
                    if self.suspended { self.activity = nil }
                    else { self.apply(json) }
                }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
    private func apply(_ json: String?) {
        guard let json, let data = json.data(using: .utf8), let snapshot = try? JSONDecoder().decode(CallActivitySnapshot.self, from: data) else {
            activity = nil
            status = "Call helper unavailable. Rebuild and relaunch MORIS."
            return
        }
        guard snapshot.status != "needsAccessibility" else {
            activity = nil
            status = "Accessibility permission is needed for the MORIS helper."
            return
        }
        status = "Experimental: detecting exposed call controls, not every app or call."
        if let candidate = snapshot.calls.first {
            missing = 0
            activity = candidate.id == dismissedID ? nil : candidate
        } else {
            missing += 1
            if missing >= 2 { activity = nil; dismissedID = nil }
        }
    }
    func suspend(_ value: Bool) {
        suspended = value
        if value { activity = nil; dismissedID = nil }
    }
    func dismiss() { dismissedID = activity?.id; activity = nil }
}

struct CallActivityPreferences: View {
    @Default(.experimentalCallDetection) private var enabled
    @ObservedObject private var store = CallActivityStore.shared
    var body: some View {
        Toggle("Experimental call detection", isOn: $enabled)
        Text(store.status).font(.caption).foregroundStyle(.secondary)
        Button("Allow helper Accessibility access") {
            Task { _ = await XPCHelperClient.shared.ensureAccessibilityAuthorization(promptIfNeeded: true) }
        }
        Button("Open Accessibility settings") {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") { NSWorkspace.shared.open(url) }
        }
        Text("Checks window titles and button labels locally in candidate call apps: FaceTime/Phone, WhatsApp, Zoom, Teams, Discord, Telegram and Slack. Availability depends on language, version and exposed call windows; browser calls are not supported. No answer/decline automation, microphone recording, saved history or server uploads.")
            .font(.caption).foregroundStyle(.secondary)
    }
}

struct CallActivityPopup: View {
    let call: DetectedCallActivity
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: call.phase == "incoming" ? "phone.arrow.down.left.fill" : "phone.fill")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(.green.gradient)
                .frame(width: 56, height: 56)
                .background(.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
            VStack(alignment: .leading, spacing: 5) {
                Text(call.phase == "incoming" ? "Incoming call detected" : "Call controls detected")
                    .font(.system(size: 17, weight: .semibold))
                Text(call.app).font(.system(size: 12)).foregroundStyle(.secondary)
                Button("Open app") {
                    let bundle = call.bundle.hasPrefix("com.apple.FaceTime.") ? "com.apple.FaceTime" : call.bundle
                    if bundle == call.bundle,
                       NSRunningApplication(processIdentifier: call.pid)?.activate(options: [.activateAllWindows]) == true { return }
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundle) { NSWorkspace.shared.open(url) }
                }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(.green)
            }
            Spacer(minLength: 0)
            Button { CallActivityStore.shared.dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).padding(8)
            }.buttonStyle(.plain).accessibilityLabel("Hide call activity")
        }.foregroundStyle(.white)
    }
}
