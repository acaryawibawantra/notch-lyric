Task { @MainActor in
    precondition(QuickShareProvider(id: "AirDrop", imageData: nil, supportsRawText: false).displayImage != nil,
                 "AirDrop must have a fallback icon when the system symbol is unavailable")
    let target = ShareDropView(frame: NSRect(x: 0, y: 0, width: 82, height: 126))
    let board = NSPasteboard.withUniqueName()
    defer { board.releaseGlobally() }
    let file = NSPasteboardItem()
    file.setString("file:///tmp/Cat%20notes.pdf", forType: .fileURL)
    file.setString("/tmp/Cat notes.pdf", forType: .string)
    let link = NSPasteboardItem()
    link.setString("https://example.com", forType: .URL)
    board.writeObjects([file, link])
    var providers: [NSItemProvider] = []
    target.onDrop = { items, view in
        precondition(view === target)
        providers = items
        return true
    }
    precondition(target.acceptPasteboard(board))
    precondition(providers.count == 2)
    board.clearContents() // Source drag ends; the snapshotted providers must survive.
    let fileURL = await providers[0].extractFileURL()
    let webURL = await providers[1].extractURL()
    precondition(fileURL?.path == "/tmp/Cat notes.pdf")
    precondition(webURL?.absoluteString == "https://example.com")
    precondition(!target.acceptPasteboard(board))
    target.enabled = false
    precondition(!target.acceptPasteboard(board))
    var clicks = 0
    target.onClick = { _ in clicks += 1 }
    let event = NSEvent.mouseEvent(with: .leftMouseDown, location: .zero, modifierFlags: [], timestamp: 0,
                                  windowNumber: 0, context: nil, eventNumber: 1, clickCount: 1, pressure: 1)!
    target.mouseDown(with: event)
    precondition(clicks == 0)
    target.enabled = true
    target.mouseDown(with: event)
    precondition(clicks == 1 && target.acceptsFirstMouse(for: nil))
    print("PASS: native AirDrop receiver snapshots file/link payload before drag ends, rejects empty/disabled drops and handles one-click activation; no picker or share opened")
    exit(0)
}
RunLoop.main.run()
