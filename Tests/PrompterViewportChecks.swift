// Offscreen fixture window only. Never shown; no user windows or text are read.
Task { @MainActor in
    let name = "moris.prompter.viewport.tests." + UUID().uuidString
    let storage = UserDefaults(suiteName: name)!
    defer { storage.removePersistentDomain(forName: name) }
    _ = NSApplication.shared
    let model = PrompterModel(storage: storage, schedulesTicks: false)
    model.script = (1...30).map { "Fixture line \($0): read your script near the camera." }.joined(separator: "\n")
    let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 480, height: 150),
                          styleMask: [.borderless], backing: .buffered, defer: false)
    window.isReleasedWhenClosed = false
    let host = NSHostingView(rootView: PrompterTextViewport(model: model))
    window.contentView = host
    @MainActor func settle() async {
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            try? await Task.sleep(for: .milliseconds(40))
        }
    }
    @MainActor func scrollView(in view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        return view.subviews.lazy.compactMap { scrollView(in: $0) }.first
    }
    await settle()
    precondition(model.maximumOffset > 500, "Long text must measure a scrollable document")
    let scroll = scrollView(in: host)!
    precondition(scroll.documentView!.frame.height > scroll.contentSize.height)
    model.seek(model.maximumOffset / 2)
    await settle()
    precondition(abs(scroll.contentView.bounds.origin.y - model.offset) < 2, "Manual seek must update the native viewport")
    model.seek(model.maximumOffset)
    await settle()
    precondition(abs(scroll.contentView.bounds.maxY - scroll.documentView!.frame.height) < 2,
                 "The end of the document must be reachable")
    model.script = "Short script."
    await settle()
    precondition(model.maximumOffset == 0 && model.offset == 0 && !model.canPlay)
    window.close()
    print("PASS: native offscreen text layout, document measurement, seek, last-line reachability, short-script reset")
    exit(0)
}
RunLoop.main.run()
