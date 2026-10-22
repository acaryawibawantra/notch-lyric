import Foundation
import AppKit
import ApplicationServices

/// Conservative heuristics, not a telephony API. Never inspect chat text or text values.
enum CallDetectionRules {
    static let appIDs: Set<String> = ["com.apple.FaceTime", "com.apple.mobilephone", "net.whatsapp.WhatsApp",
        "us.zoom.xos", "com.microsoft.teams2", "com.microsoft.teams", "com.hnc.Discord",
        "org.telegram.desktop", "com.tinyspeck.slackmacgap", "com.apple.FaceTime.FaceTimeNotificationCenterService"]

    static func isCallWindow(bundle: String, title: String) -> Bool {
        let native = bundle == "com.apple.FaceTime" || bundle == "com.apple.mobilephone" || bundle.hasPrefix("com.apple.FaceTime.")
        return native || ["call", "panggilan", "facetime", "meeting", "rapat", "huddle"].contains { title.lowercased().contains($0) }
    }

    static func phase(bundle: String, windowTitle: String, buttons: [String]) -> String? {
        guard appIDs.contains(bundle), isCallWindow(bundle: bundle, title: windowTitle) else { return nil }
        func normalized(_ value: String) -> String {
            value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
                .replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: "-", with: " ")
        }
        let title = normalized(windowTitle)
        let labels = buttons.map(normalized)
        func has(_ phrases: [String]) -> Bool { labels.contains { label in phrases.contains { label.contains($0) } } }
        let callWindow = ["call", "panggilan", "facetime", "meeting", "rapat"].contains { title.contains($0) }
        let native = bundle == "com.apple.FaceTime" || bundle == "com.apple.mobilephone" || bundle.hasPrefix("com.apple.FaceTime.")
        if (callWindow || native), has(["answer", "accept", "terima", "jawab"]), has(["decline", "reject", "tolak"]) {
            return "incoming"
        }
        if has(["end call", "leave call", "leave meeting", "hang up", "akhiri panggilan", "akhiri rapat", "keluar rapat"]),
           has(["mute", "microphone", "mikrofon", "camera", "kamera"]) {
            return "active"
        }
        return nil
    }
}

enum CallAccessibilityScanner {
    private static let queue = DispatchQueue(label: "moris.call-accessibility", qos: .utility)
    static func snapshot(reply: @escaping (String?) -> Void) {
        // Capture AppKit application metadata on main; perform bounded AX messaging off main.
        DispatchQueue.main.async {
            let apps = NSWorkspace.shared.runningApplications.compactMap { app -> (Int32, String, String)? in
                guard let id = app.bundleIdentifier, CallDetectionRules.appIDs.contains(id) else { return nil }
                return (app.processIdentifier, id, id.hasPrefix("com.apple.FaceTime.") ? "FaceTime" : app.localizedName ?? id)
            }
            queue.async {
                guard AXIsProcessTrusted() else { reply(encode(status: "needsAccessibility", calls: [])); return }
                let deadline = Date().addingTimeInterval(0.8)
                var calls: [[String: Any]] = []
                for (pid, bundle, name) in apps {
                    guard Date() < deadline else { break }
                    let app = AXUIElementCreateApplication(pid)
                    AXUIElementSetMessagingTimeout(app, 0.05)
                    guard let windows = attribute(app, kAXWindowsAttribute) as? [AXUIElement] else { continue }
                    for window in windows.prefix(4) {
                        guard Date() < deadline else { break }
                        if attribute(window, kAXMinimizedAttribute) as? Bool == true || attribute(window, kAXHiddenAttribute) as? Bool == true { continue }
                        let title = attribute(window, kAXTitleAttribute) as? String ?? ""
                        guard CallDetectionRules.isCallWindow(bundle: bundle, title: title) else { continue }
                        let labels = buttonLabels(window, deadline: deadline)
                        if let phase = CallDetectionRules.phase(bundle: bundle, windowTitle: title, buttons: labels) {
                            // Window title is used only in memory for classification, never returned or logged.
                            calls.append(["bundle": bundle, "app": name, "pid": pid, "phase": phase])
                        }
                    }
                }
                calls.sort { ($0["phase"] as? String == "incoming" ? 0 : 1) < ($1["phase"] as? String == "incoming" ? 0 : 1) }
                reply(encode(status: "experimental", calls: Array(calls.prefix(3))))
            }
        }
    }
    private static func encode(status: String, calls: [[String: Any]]) -> String? {
        guard let data = try? JSONSerialization.data(withJSONObject: ["status": status, "calls": calls]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        AXUIElementSetMessagingTimeout(element, 0.05)
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }
    private static func buttonLabels(_ root: AXUIElement, deadline: Date) -> [String] {
        var pending: [(AXUIElement, Int)] = [(root, 0)]
        var index = 0
        var labels: [String] = []
        while index < pending.count && index < 120 && Date() < deadline {
            let (node, depth) = pending[index]
            index += 1
            if attribute(node, kAXHiddenAttribute) as? Bool == true { continue }
            if attribute(node, kAXRoleAttribute) as? String == kAXButtonRole {
                for key in [kAXTitleAttribute, kAXDescriptionAttribute] {
                    if let value = attribute(node, key) as? String { labels.append(String(value.prefix(120))) }
                }
            }
            // No AXValue reads: message content, typed text, and contact lists are not collected.
            if depth < 6, pending.count < 120, let children = attribute(node, kAXChildrenAttribute) as? [AXUIElement] {
                pending.append(contentsOf: children.prefix(120 - pending.count).map { ($0, depth + 1) })
            }
        }
        return labels
    }
}
