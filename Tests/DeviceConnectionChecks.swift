// No configure(enabled: true): tests never request Bluetooth access or monitor hardware.
Task { @MainActor in
    precondition(DeviceConnectionNotice.bluetooth(name: "AirPods Pro").symbol == "airpodspro")
    precondition(DeviceConnectionNotice.bluetooth(name: "Magic Mouse").symbol == "computermouse.fill")
    precondition(DeviceConnectionNotice.bluetooth(name: "Keyboard").symbol == "keyboard.fill")
    precondition(DeviceConnectionNotice.bluetooth(name: "").name == "Bluetooth accessory")
    let store = DeviceConnectionStore.shared
    precondition(!store.isMonitoring && store.notice == nil)
    store.preview()
    precondition(store.notice?.name.contains("Preview") == true && !store.isMonitoring)
    let first = store.notice?.id
    store.preview()
    precondition(store.notice?.id != first)
    try? await Task.sleep(for: .seconds(4.2))
    precondition(store.notice == nil)
    store.preview()
    store.dismiss()
    precondition(store.notice == nil && !store.isMonitoring)
    print("PASS: accessory symbols, labeled preview without monitoring, replacement, timeout, dismissal")
    exit(0)
}
RunLoop.main.run()
