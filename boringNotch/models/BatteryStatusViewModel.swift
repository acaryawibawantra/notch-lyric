import Cocoa
import Defaults
import Foundation
import IOKit.ps
import SwiftUI
import IOBluetooth

struct DeviceConnectionNotice: Identifiable, Equatable {
    let id = UUID()
    let name: String
    let detail: String
    let symbol: String

    static func bluetooth(name: String) -> Self {
        let lower = name.lowercased()
        let symbol = lower.contains("airpods") ? "airpodspro" : lower.contains("mouse") ? "computermouse.fill"
            : lower.contains("keyboard") ? "keyboard.fill" : lower.contains("headphone") || lower.contains("beats") ? "headphones"
            : "antenna.radiowaves.left.and.right"
        return Self(name: name.isEmpty ? "Bluetooth accessory" : name, detail: "Bluetooth connected", symbol: symbol)
    }
}

/// Opt-in connection events, not proximity scanning. No device battery estimates.
@MainActor
final class DeviceConnectionStore: NSObject, ObservableObject {
    static let shared = DeviceConnectionStore()
    @Published private(set) var notice: DeviceConnectionNotice?
    @Published private(set) var isMonitoring = false
    private var registration: IOBluetoothUserNotification?
    private var mountObserver: NSObjectProtocol?
    private var dismissTask: Task<Void, Never>?
    private var recent: [String: Date] = [:]

    func configure(enabled: Bool) {
        guard enabled != isMonitoring else { return }
        if !enabled {
            registration?.unregister()
            registration = nil
            if let mountObserver { NSWorkspace.shared.notificationCenter.removeObserver(mountObserver) }
            mountObserver = nil
            isMonitoring = false
            dismiss()
            recent = [:]
            return
        }
        isMonitoring = true
        registration = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(connected(_:device:)))
        mountObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didMountNotification,
                                                                         object: nil, queue: .main) { [weak self] event in
            guard let url = event.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            // Report mounted local external volumes; never read their files.
            guard let values = try? url.resourceValues(forKeys: [.volumeIsLocalKey, .volumeIsRemovableKey, .volumeIsInternalKey]),
                  values.volumeIsLocal == true, values.volumeIsRemovable == true || values.volumeIsInternal == false else { return }
            Task { @MainActor in
                guard let self, self.isMonitoring else { return }
                self.receive(.init(name: url.lastPathComponent, detail: "External volume mounted", symbol: "externaldrive.fill"), key: "volume:" + url.path)
            }
        }
    }

    @objc nonisolated private func connected(_ notification: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        let name = device.name ?? "Bluetooth accessory"
        let key = device.addressString ?? name
        Task { @MainActor [weak self] in
            guard let self, self.isMonitoring else { return }
            self.receive(.bluetooth(name: name), key: key)
        }
    }

    private func receive(_ event: DeviceConnectionNotice, key: String) {
        let now = Date()
        guard recent[key].map({ now.timeIntervalSince($0) < 5 }) != true else { return }
        recent = recent.filter { now.timeIntervalSince($0.value) < 5 }
        recent[key] = now
        present(event)
    }

    func preview() { present(.bluetooth(name: "AirPods · Preview")) }

    private func present(_ event: DeviceConnectionNotice) {
        dismissTask?.cancel()
        notice = event
        dismissTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(4)) } catch { return }
            self?.notice = nil
        }
    }

    func dismiss() { dismissTask?.cancel(); dismissTask = nil; notice = nil }
}

/// A view model that manages and monitors the battery status of the device
class BatteryStatusViewModel: ObservableObject {

    private var wasCharging: Bool = false
    private var powerSourceChangedCallback: IOPowerSourceCallbackType?
    private var runLoopSource: Unmanaged<CFRunLoopSource>?

    @ObservedObject var coordinator = BoringViewCoordinator.shared

    @Published private(set) var levelBattery: Float = 0.0
    @Published private(set) var maxCapacity: Float = 0.0
    @Published private(set) var isPluggedIn: Bool = false
    @Published private(set) var isCharging: Bool = false
    @Published private(set) var isInLowPowerMode: Bool = false
    @Published private(set) var isInitial: Bool = false
    @Published private(set) var timeToFullCharge: Int = 0
    @Published private(set) var statusText: String = ""
    @Published private(set) var isLowPowerNotification = false
    private var lastConnectionNotification = Date.distantPast

    private let managerBattery = BatteryActivityManager.shared
    private var managerBatteryId: Int?

    static let shared = BatteryStatusViewModel()

    /// Initializes the view model with a given BoringViewModel instance
    /// - Parameter vm: The BoringViewModel instance
    private init() {
        setupPowerStatus()
        setupMonitor()
    }

    /// Sets up the initial power status by fetching battery information
    private func setupPowerStatus() {
        let batteryInfo = managerBattery.initializeBatteryInfo()
        updateBatteryInfo(batteryInfo)
    }

    /// Sets up the monitor to observe battery events
    private func setupMonitor() {
        managerBatteryId = managerBattery.addObserver { [weak self] event in
            guard let self = self else { return }
            self.handleBatteryEvent(event)
        }
    }

    /// Handles battery events and updates the corresponding properties
    /// - Parameter event: The battery event to handle
    private func handleBatteryEvent(_ event: BatteryActivityManager.BatteryEvent) {
        switch event {
        case .powerSourceChanged(let isPluggedIn):
            print("🔌 Power source: \(isPluggedIn ? "Connected" : "Disconnected")")
            withAnimation {
                self.isPluggedIn = isPluggedIn
                self.isLowPowerNotification = false
                self.statusText = isPluggedIn ? "Plugged In" : "Unplugged"
                self.lastConnectionNotification = Date()
                self.notifyImportanChangeStatus()
            }

        case .batteryLevelChanged(let level):
            print("🔋 Battery level: \(Int(level))%")
            withAnimation {
                self.levelBattery = level
            }

        case .lowPowerModeChanged(let isEnabled):
            print("⚡ Low power mode: \(isEnabled ? "Enabled" : "Disabled")")
            withAnimation {
                self.isInLowPowerMode = isEnabled
                self.isLowPowerNotification = true
                self.statusText = "Low Power: \(self.isInLowPowerMode ? "On" : "Off")"
                self.notifyImportanChangeStatus()
            }

        case .isChargingChanged(let isCharging):
            print("🔌 Charging: \(isCharging ? "Yes" : "No")")
            print("maxCapacity: \(self.maxCapacity)")
            print("levelBattery: \(self.levelBattery)")
            withAnimation {
                self.isCharging = isCharging
                self.statusText =
                    isCharging
                    ? "Charging battery"
                    : (self.levelBattery < self.maxCapacity ? "Not charging" : "Full charge")
                // Connecting generates both source and charging events. Update the
                // visible confirmation without presenting the same alert twice.
                if Date().timeIntervalSince(self.lastConnectionNotification) > 3 {
                    self.isLowPowerNotification = false
                    self.notifyImportanChangeStatus()
                }
            }

        case .timeToFullChargeChanged(let time):
            print("🕒 Time to full charge: \(time) minutes")
            withAnimation {
                self.timeToFullCharge = time
            }

        case .maxCapacityChanged(let capacity):
            print("🔋 Max capacity: \(capacity)")
            withAnimation {
                self.maxCapacity = capacity
            }

        case .error(let description):
            print("⚠️ Error: \(description)")
        }
    }

    /// Updates the battery information with the given BatteryInfo instance
    /// - Parameter batteryInfo: The BatteryInfo instance containing the battery data
    private func updateBatteryInfo(_ batteryInfo: BatteryInfo) {
        withAnimation {
            self.levelBattery = batteryInfo.currentCapacity
            self.isPluggedIn = batteryInfo.isPluggedIn
            self.isCharging = batteryInfo.isCharging
            self.isInLowPowerMode = batteryInfo.isInLowPowerMode
            self.timeToFullCharge = batteryInfo.timeToFullCharge
            self.maxCapacity = batteryInfo.maxCapacity
            self.statusText = batteryInfo.isPluggedIn ? "Plugged In" : "Unplugged"
        }
    }

    /// Notifies important changes in the battery status with an optional delay
    /// - Parameter delay: The delay before notifying the change, default is 0.0
    private func notifyImportanChangeStatus(delay: Double = 0.0) {
        guard Defaults[.showPowerStatusNotifications] else { return }
        Task {
            try? await Task.sleep(for: .seconds(delay))
            self.coordinator.toggleExpandingView(status: true, type: .battery)
        }
    }

    /// Uses real battery state without simulating a connection or changing settings.
    func previewPowerNotification() {
        isLowPowerNotification = false
        notifyImportanChangeStatus()
    }

    deinit {
        print("🔌 Cleaning up battery monitoring...")
        if let managerBatteryId: Int = managerBatteryId {
            managerBattery.removeObserver(byId: managerBatteryId)
        }
    }

}
