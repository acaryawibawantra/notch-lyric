import Foundation

Task { @MainActor in
    let name = "moris.prompter.tests." + UUID().uuidString
    let storage = UserDefaults(suiteName: name)!
    defer { storage.removePersistentDomain(forName: name) }
    var date = Date(timeIntervalSince1970: 1000)
    let model = PrompterModel(storage: storage, now: { date }, schedulesTicks: false)
    model.play()
    precondition(!model.isRunning && !model.hasScript)
    model.script = "  \n  "
    model.setBounds(100)
    model.play()
    precondition(!model.isRunning)
    model.script = "A script for MORIS.\nAnother line."
    model.setBounds(0)
    model.play()
    precondition(!model.isRunning, "No auto-scrolling when the script fits")
    model.setBounds(300)
    model.play()
    date = date.addingTimeInterval(1)
    model.tick()
    precondition(model.offset == 30 && model.isRunning)
    model.pause()
    date = date.addingTimeInterval(10)
    model.tick()
    precondition(model.offset == 30)
    model.play()
    date = date.addingTimeInterval(1)
    model.tick()
    precondition(model.offset == 60)
    model.speed = 60
    date = date.addingTimeInterval(1)
    model.tick()
    precondition(model.offset == 120)
    date = date.addingTimeInterval(120)
    model.tick()
    precondition(!model.isRunning && model.offset == 120, "Sleep pauses rather than skipping the script")
    model.seek(290)
    model.play()
    date = date.addingTimeInterval(1)
    model.tick()
    precondition(model.offset == 300 && !model.isRunning && model.progress == 1)
    model.play()
    precondition(model.offset == 0 && model.isRunning, "Replay starts at the beginning")
    model.fontSize = 32
    precondition(!model.isRunning && model.offset == 0)
    model.seek(-100)
    precondition(model.offset == 0)
    model.seek(.infinity)
    precondition(model.offset == 0)
    model.seek(500)
    precondition(model.offset == 300)
    model.setBounds(100)
    precondition(model.offset == 100 && !model.isRunning)
    model.speed = .nan
    model.fontSize = .infinity
    precondition(model.speed == 30 && model.fontSize == 26)
    model.speed = 500
    model.fontSize = 1
    precondition(model.speed == 100 && model.fontSize == 18)
    model.script = String(repeating: "🐈", count: 50_010)
    precondition(model.script.count == 50_000)
    let restored = PrompterModel(storage: storage, now: { date }, schedulesTicks: false)
    precondition(restored.script == model.script && restored.speed == 100 && restored.fontSize == 18)
    precondition(!restored.isRunning && !restored.isPresented && restored.offset == 0)
    model.script = ""
    precondition(!model.hasScript && !model.isRunning && model.offset == 0)
    let cleared = PrompterModel(storage: storage, schedulesTicks: false)
    precondition(cleared.script.isEmpty)
    print("PASS: prompter play/pause/replay, speed, end bounds, sleep pause, manual seek, text reset, local draft restoration, Unicode cap and clearing")
    exit(0)
}
RunLoop.main.run()
