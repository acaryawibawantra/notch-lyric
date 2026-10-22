import AppKit
import Combine
import Defaults
import ScreenCaptureKit
import SwiftUI

enum LyricContrastRules {
    /// Linear relative luminance; hysteresis avoids flicker near the crossover.
    static func prefersDark(_ luminance: Double, previouslyDark: Bool) -> Bool {
        guard luminance.isFinite else { return false }
        if luminance > 0.22 { return true }
        if luminance < 0.14 { return false }
        return previouslyDark
    }

    static func localRect(_ area: CGRect, screen: CGRect) -> CGRect {
        let clipped = area.intersection(screen)
        guard !clipped.isNull, clipped.width > 0, clipped.height > 0 else { return .zero }
        return CGRect(x: clipped.minX - screen.minX, y: screen.maxY - clipped.maxY,
                      width: clipped.width, height: clipped.height)
    }
}

/// Per-display sampler. Only runs for visible transparent lyrics after opt-in and
/// OS permission. Cropped pixels stay in memory and are discarded after averaging.
@MainActor
final class LyricContrastSampler: ObservableObject {
    @Published private(set) var usesDarkText = false
    private var worker: Task<Void, Never>?
    private var screen: NSScreen?
    private var area = CGRect.zero
    private var revision = 0

    func configure(enabled: Bool, screen: NSScreen?, area: CGRect) {
        guard enabled, let screen, CGPreflightScreenCaptureAccess() else { stop(); return }
        if self.screen !== screen || self.area != area { revision += 1 }
        self.screen = screen
        self.area = area
        guard worker == nil else { return }
        worker = Task { @MainActor [weak self] in
            do {
                while !Task.isCancelled {
                    await self?.sample()
                    guard self != nil else { return }
                    try await Task.sleep(for: .seconds(2))
                }
            } catch { /* Hiding, pausing, changing mode or locking cancels work. */ }
        }
    }

    func stop() {
        guard worker != nil || screen != nil || usesDarkText else { return }
        revision += 1
        worker?.cancel()
        worker = nil
        screen = nil
        if usesDarkText {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.worker == nil else { return }
                self.usesDarkText = false
            }
        }
    }

    deinit { worker?.cancel() }

    private func sample() async {
        guard !Task.isCancelled, CGPreflightScreenCaptureAccess(), let screen,
              let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { stop(); return }
        let generation = revision
        let crop = LyricContrastRules.localRect(area, screen: screen.frame)
        guard crop.width > 1, crop.height > 1 else { return }
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            guard !Task.isCancelled, generation == revision,
                  let display = content.displays.first(where: { $0.displayID == displayID.uint32Value }) else { return }
            let ownApps = content.applications.filter { $0.processID == ProcessInfo.processInfo.processIdentifier }
            guard !ownApps.isEmpty else { return }
            let filter = SCContentFilter(display: display, excludingApplications: ownApps, exceptingWindows: [])
            let config = SCStreamConfiguration()
            config.sourceRect = crop
            config.width = 64
            config.height = 16
            config.showsCursor = false
            let image = try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: config)
            guard !Task.isCancelled, generation == revision else { return }
            if let brightness = Self.luminance(image) {
                let dark = LyricContrastRules.prefersDark(brightness, previouslyDark: usesDarkText)
                if dark != usesDarkText { usesDarkText = dark }
            }
        } catch {
            // Permission revocation/capture failures fail back to outlined white.
            if generation == revision && usesDarkText { usesDarkText = false }
        }
    }

    static func luminance(_ image: CGImage) -> Double? {
        let width = 64, height = 16
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        return pixels.withUnsafeMutableBytes { bytes in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                    bitsPerComponent: 8, bytesPerRow: width * 4, space: space,
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            let buffer = bytes.bindMemory(to: UInt8.self)
            func linear(_ value: UInt8) -> Double {
                let v = Double(value) / 255
                return v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4)
            }
            var total: Double = 0
            for index in stride(from: 0, to: buffer.count, by: 4) {
                total += 0.2126 * linear(buffer[index]) + 0.7152 * linear(buffer[index + 1]) + 0.0722 * linear(buffer[index + 2])
            }
            return total / Double(width * height)
        }
    }
}

struct LyricContrastPreferences: View {
    var onPermissionPresentation: (Bool) -> Void = { _ in }
    @Default(.adaptiveLyricContrast) private var enabled
    @State private var confirmPermission = false
    @State private var needsPermission = false
    @State private var requestingPermission = false
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle("Auto contrast for transparent lyrics", isOn: $enabled)
                .onChange(of: enabled) { _, value in
                    if value && !CGPreflightScreenCaptureAccess() {
                        enabled = false
                        onPermissionPresentation(true)
                        confirmPermission = true
                    }
                }
            Text("Optional Screen Recording access samples only the area behind live lyrics every 2 seconds. No images are saved or uploaded.")
                .font(.caption2).foregroundStyle(.secondary)
            if needsPermission {
                Text("Enable Screen Recording for MORIS, relaunch if macOS asks, then turn Auto contrast on again. Without access, lyrics use a contrast outline.")
                    .font(.caption2).foregroundStyle(.secondary)
                Button("Open Screen Recording settings") {
                    NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
                }.font(.caption)
            }
        }
        .alert("Allow background sampling?", isPresented: $confirmPermission) {
            Button("Allow") {
                requestingPermission = true
                onPermissionPresentation(true)
                defer { requestingPermission = false; onPermissionPresentation(false) }
                _ = CGRequestScreenCaptureAccess()
                enabled = CGPreflightScreenCaptureAccess()
                needsPermission = !enabled
            }
            Button("Cancel", role: .cancel) { onPermissionPresentation(false) }
        } message: {
            Text("macOS requires Screen Recording permission to read colors behind the lyrics. MORIS only averages a small crop locally; it does not save a recording or capture audio.")
        }
        .onChange(of: confirmPermission) { _, showing in
            onPermissionPresentation(showing || requestingPermission)
        }
        .onDisappear { if !requestingPermission { onPermissionPresentation(false) } }
    }
}

struct LiveLyricsShortcut: View {
    @EnvironmentObject private var vm: BoringViewModel
    @Default(.enableLyrics) private var lyricsEnabled
    @Default(.persistentNotchLyrics) private var liveEnabled
    @Default(.floatingLyricStyle) private var style
    @State private var showingOptions = false
    @State private var popoverOwner = UUID()
    @State private var permissionOwner = UUID()

    private var optionsPresented: Binding<Bool> {
        Binding(get: { showingOptions }, set: { showing in
            vm.setInteraction(popoverOwner, active: showing)
            showingOptions = showing
        })
    }
    var body: some View {
        Button { optionsPresented.wrappedValue.toggle() } label: {
            Label("Live lyrics", systemImage: style == .transparent ? "rectangle.dashed" : "rectangle.fill")
                .font(.system(size: 11, weight: .medium))
                .padding(.horizontal, 8).frame(height: 25)
                .background(.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain).help("Live lyrics background and contrast")
        .popover(isPresented: optionsPresented) {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Show live lyrics", isOn: $liveEnabled)
                    .onChange(of: liveEnabled) { _, value in if value { lyricsEnabled = true } }
                Picker("Background", selection: $style) {
                    Text("Transparent").tag(FloatingLyricStyle.transparent)
                    Text("Black").tag(FloatingLyricStyle.black)
                }.pickerStyle(.segmented)
                .onChange(of: style) { _, _ in lyricsEnabled = true; liveEnabled = true }
                LyricContrastPreferences(onPermissionPresentation: { vm.setInteraction(permissionOwner, active: $0) })
                    .disabled(style == .black)
            }
            .padding(16).frame(width: 320)
        }
        .onDisappear {
            vm.setInteraction(popoverOwner, active: false)
            vm.setInteraction(permissionOwner, active: false)
        }
    }
}
