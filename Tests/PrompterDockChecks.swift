// Test adapters for notch state, not a second implementation of the controller.
@MainActor final class BoringViewModel {
    var screenUUID: String?
    var notchSize = CGSize(width: 100, height: 30)
    var opens = 0
    var closes = 0
    init(_ id: String) { screenUUID = id }
    func open() { opens += 1 }
    func close() { closes += 1 }
}
@MainActor final class BoringViewCoordinator {
    enum View { case home, prompter }
    static let shared = BoringViewCoordinator()
    var currentView = View.home
}

Task { @MainActor in
    let name = "moris.prompter.dock.tests." + UUID().uuidString
    let storage = UserDefaults(suiteName: name)!
    defer { storage.removePersistentDomain(forName: name) }
    _ = NSApplication.shared
    let model = PrompterModel(storage: storage, schedulesTicks: false)
    var activations = 0
    // Never activate/show the fixture windows; real user windows are untouched.
    let controller = PrompterPanelController(model: model, activateWindow: { _ in activations += 1 })
    let first = BoringViewModel("fixture-display-a")
    let second = BoringViewModel("fixture-display-b")
    @MainActor func fixtureWindow() -> NSPanel {
        let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 720, height: 330),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = true
        return window
    }
    let firstWindow = fixtureWindow()
    let secondWindow = fixtureWindow()
    controller.bind(firstWindow, to: first)
    controller.bind(secondWindow, to: second)
    controller.present(source: first)
    precondition(!model.isPresented && activations == 0, "Empty script must not open reading mode")
    model.script = "Fixture text only."
    controller.present(source: first)
    precondition(model.isPresented && model.presentationScreenID == "fixture-display-a")
    precondition(first.notchSize == PrompterPanelController.readingSize && first.opens == 1)
    precondition(activations == 1 && !firstWindow.isVisible && !secondWindow.isVisible)
    precondition(!firstWindow.hidesOnDeactivate, "Reading must stay visible when another app is activated")
    model.setBounds(100)
    model.play()
    precondition(model.isRunning)
    controller.present(source: second)
    precondition(!model.isRunning && model.isPresented && model.presentationScreenID == "fixture-display-b")
    precondition(first.closes == 1 && second.opens == 1)
    precondition(firstWindow.hidesOnDeactivate && !secondWindow.hidesOnDeactivate)
    controller.editScript()
    precondition(!model.isPresented && model.presentationScreenID == nil && !model.isRunning)
    precondition(BoringViewCoordinator.shared.currentView == .prompter && second.opens == 2 && second.closes == 1)
    precondition(model.script == "Fixture text only.")
    controller.present(source: first)
    controller.dismiss()
    precondition(!model.isPresented && !model.isRunning && first.closes == 2)
    precondition(firstWindow.hidesOnDeactivate && secondWindow.hidesOnDeactivate,
                 "Closing must restore the original notch window behavior")
    controller.dismiss()
    precondition(first.closes == 2, "Repeated close must not close other notches")
    firstWindow.close()
    secondWindow.close()
    print("PASS: reading uses registered notch window, target-display routing, read/edit/close, pause on switch, retained script, idempotent dismissal")
    exit(0)
}
RunLoop.main.run()
