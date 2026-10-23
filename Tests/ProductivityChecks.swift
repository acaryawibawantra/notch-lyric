Task { @MainActor in
    var date = Date(timeIntervalSince1970: 1000)
    var created: [TimeInterval?] = []
    var released: [UInt32] = []
    let awake = KeepAwakeModel(now: { date }, schedulesTicks: false, create: { duration in
        created.append(duration); return UInt32(created.count)
    }, release: { released.append($0) })
    precondition(!awake.isActive)
    awake.start(minutes: 30)
    precondition(awake.isActive && awake.remaining == 1800 && created[0] == 1800)
    date = date.addingTimeInterval(100)
    awake.tick()
    precondition(awake.remaining == 1700)
    awake.start(minutes: 60)
    precondition(released == [1] && created.count == 2)
    date = date.addingTimeInterval(3601)
    awake.tick()
    precondition(!awake.isActive && released == [1, 2])
    awake.start(minutes: nil)
    precondition(awake.isActive && awake.remaining == nil && created.last! == nil)
    awake.stop(); awake.stop()
    precondition(released == [1, 2, 3])
    awake.start(minutes: 9999)
    precondition(awake.remaining == 480 * 60)
    awake.stop()
    let failed = KeepAwakeModel(schedulesTicks: false, create: { _ in nil }, release: { _ in preconditionFailure() })
    failed.start(minutes: 30)
    precondition(!failed.isActive && failed.error != nil)

    let suite = "moris.tasks.tests." + UUID().uuidString
    let storage = UserDefaults(suiteName: suite)!
    defer { storage.removePersistentDomain(forName: suite) }
    let tasks = MorisTaskStore(storage: storage, now: { date }, isAvailable: true)
    @MainActor func url(_ id: String = "build", _ state: String = "running", token: String? = nil,
             title: String = "Fixture build", source: String = "command", timestamp: Date? = nil) -> URL {
        var parts = URLComponents(string: "moris://task")!
        parts.queryItems = ["id": id, "status": state, "title": title, "source": source,
                            "token": token ?? tasks.token,
                            "sentAt": String((timestamp ?? date).timeIntervalSince1970 * 1000)]
            .map { URLQueryItem(name: $0.key, value: $0.value) }
        return parts.url!
    }
    precondition(!tasks.receive(url()), "Bridge must be opt-in")
    tasks.bridgeEnabled = true
    precondition(!tasks.receive(url(token: "wrong")))
    precondition(!tasks.receive(url("../unsafe")))
    precondition(!tasks.receive(url("build", "unknown")))
    precondition(!tasks.receive(url(title: "Unsafe\nTitle")))
    precondition(!tasks.receive(url(source: "verified-codex-account")))
    precondition(!tasks.receive(url(timestamp: date.addingTimeInterval(-301))))
    precondition(tasks.receive(url()) && tasks.runningCount == 1 && tasks.notice == nil)
    precondition(!tasks.receive(url()), "Same timestamp must not replay")
    date = date.addingTimeInterval(1)
    precondition(tasks.receive(url("build", "waiting")))
    precondition(tasks.records[0].unread && tasks.notice?.state == .waiting)
    tasks.dismissNotice()
    date = date.addingTimeInterval(1)
    precondition(tasks.receive(url("build", "waiting")) && tasks.notice == nil, "Repeated state must not spam popups")
    precondition(!tasks.receive(url("build", "completed", timestamp: date.addingTimeInterval(-2))), "Ignore out-of-order event")
    date = date.addingTimeInterval(1)
    precondition(tasks.receive(url("build", "completed")) && tasks.notice?.state == .completed)
    tasks.markRead("command:build")
    precondition(!tasks.records[0].unread)
    tasks.clearFinished()
    precondition(tasks.records.isEmpty)
    tasks.preview()
    precondition(tasks.notice?.isPreview == true && tasks.records.isEmpty)
    let old = tasks.token
    tasks.rotateToken()
    precondition(old != tasks.token && tasks.notice == nil)
    precondition(!tasks.receive(url(token: old)))
    for index in 0..<50 {
        date = date.addingTimeInterval(0.01)
        _ = tasks.receive(url("fixture-\(index)"))
    }
    precondition(tasks.records.count <= 50)
    var rejected = 0
    for index in 50..<80 {
        date = date.addingTimeInterval(0.01)
        if !tasks.receive(url("fixture-\(index)")) { rejected += 1 }
    }
    precondition(rejected > 0 && tasks.records.count == 50, "Floods must be rate-limited and bounded")
    tasks.bridgeEnabled = false
    precondition(tasks.records.isEmpty && tasks.notice == nil)
    let restored = MorisTaskStore(storage: storage)
    precondition(!restored.bridgeEnabled && restored.records.isEmpty && restored.token == tasks.token)
    storage.set(true, forKey: "moris.tasks.enabled")
    let held = MorisTaskStore(storage: storage, now: { date })
    precondition(!held.bridgeEnabled && !storage.bool(forKey: "moris.tasks.enabled"))
    held.bridgeEnabled = true // Even a stale caller cannot bypass the release gate.
    precondition(!held.receive(url(token: held.token)) && held.records.isEmpty)
    held.preview()
    precondition(held.notice == nil)
    print("PASS: fake power assertions, timed/indefinite sessions, replacement, failure, timeout; opt-in paired task events, validation, replay/order guards, state notices, clearing and token reset")
    exit(0)
}
RunLoop.main.run()
