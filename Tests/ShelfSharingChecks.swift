Task { @MainActor in
    let file = NSItemProvider(item: URL(fileURLWithPath: "/tmp/moris-fixture.pdf") as NSURL,
                              typeIdentifier: UTType.fileURL.identifier)
    let text = NSItemProvider(item: "A note, not a file path" as NSString, typeIdentifier: UTType.utf8PlainText.identifier)
    let web = NSItemProvider(item: "https://example.com/cat" as NSString, typeIdentifier: UTType.utf8PlainText.identifier)
    let payload = await ShareDropLoader.load([file, text, web], supportsRawText: true)
    precondition(payload.items.count == 3, "Mixed text must not replace file batches")
    precondition((payload.items[0] as? URL)?.isFileURL == true)
    precondition(payload.items[1] as? String == "A note, not a file path")
    precondition((payload.items[2] as? URL)?.absoluteString == "https://example.com/cat")
    precondition(payload.temporaryURLs.isEmpty)

    var begins = 0, finishes = 0, ends = 0, failures = 0
    let delegate = SharingLifecycleDelegate(id: UUID(), onEnd: { ends += 1 }, onBegin: { begins += 1 },
                                            onFinish: { finishes += 1 }, onFailure: { _ in failures += 1 })
    delegate.markServiceBegan()
    delegate.markServiceBegan()
    try? await Task.sleep(for: .seconds(2.3))
    precondition(begins == 1 && ends == 0 && finishes == 0, "Do not tear down a share after two seconds")
    // Construct a service only to invoke delegate callbacks. Never perform a share.
    guard let service = NSSharingService(named: .sendViaAirDrop) else { fatalError("AirDrop service unavailable") }
    delegate.sharingService(service, didShareItems: payload.items)
    delegate.sharingService(service, didShareItems: payload.items)
    precondition(ends == 1 && finishes == 1)
    let manager = SharingStateManager.shared
    manager.beginInteraction()
    let unpresented = manager.makeDelegate()
    unpresented.cancelBeforePresentation()
    precondition(manager.preventNotchClose, "Failed anchoring must not release another owner's hold")
    manager.endInteraction()
    precondition(!manager.preventNotchClose)
    let failed = SharingLifecycleDelegate(id: UUID(), onEnd: { ends += 1 }, onBegin: { begins += 1 },
                                          onFinish: { finishes += 1 }, onFailure: { _ in failures += 1 })
    failed.markPickerBegan()
    failed.sharingService(service, didFailToShareItems: [], error: CocoaError(.userCancelled))
    precondition(failures == 1 && begins == 2 && finishes == 2 && ends == 2)
    let cancelled = manager.makeDelegate()
    cancelled.markPickerBegan()
    cancelled.sharingServicePicker(NSSharingServicePicker(items: []), didChoose: nil)
    precondition(!manager.preventNotchClose)
    print("PASS: mixed share payloads, file-first extraction, link text classification, callback-based lifetime, cancellation/failure and balanced holds; no sharing performed")
    exit(0)
}
RunLoop.main.run()
