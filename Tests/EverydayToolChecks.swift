import Foundation
import Combine

@MainActor
func runEverydayChecks() {
    let copies = [ClipboardEntry(text: "Newest draft"), ClipboardEntry(text: "Pinned reference", pinned: true), ClipboardEntry(text: "Older draft")]
    let selection = ClipboardPanelSelection()
    precondition(selection.items(from: copies).map(\.id) == [copies[1].id, copies[0].id, copies[2].id])
    selection.reconcile(copies)
    precondition(selection.selectedID == copies[1].id)
    selection.move(1, in: copies)
    precondition(selection.selectedID == copies[0].id)
    selection.move(99, in: copies)
    precondition(selection.selectedID == copies[2].id)
    selection.move(-99, in: copies)
    precondition(selection.selectedID == copies[1].id)
    selection.search = "DRAFT"
    selection.reconcile(copies)
    precondition(selection.selectedID == copies[0].id && selection.items(from: copies).count == 2)
    selection.search = "no match"
    selection.reconcile(copies)
    selection.move(1, in: copies)
    precondition(selection.selectedID == nil)
    print("PASS: clipboard search, stable pinned ordering, arrow selection, bounds, filtering, empty results")
    let suite = "notchLyric.everydayChecks.\(UUID().uuidString)"
    let storage = UserDefaults(suiteName: suite)!
    defer { storage.removePersistentDomain(forName: suite) }
    let tasks = FocusTaskStore(storage: storage)
    tasks.add("   ")
    precondition(tasks.tasks.isEmpty)
    tasks.add("  Finish draft  ")
    precondition(tasks.tasks.first?.title == "Finish draft")
    let id = tasks.tasks[0].id
    tasks.toggle(id)
    let recovered = FocusTaskStore(storage: storage)
    precondition(recovered.tasks[0].completed && recovered.tasks[0].id == id)
    recovered.remove(id)
    precondition(FocusTaskStore(storage: storage).tasks.isEmpty)

    var current = Date(timeIntervalSince1970: 1_800_000_000)
    let reminders = EverydayReminderStore(storage: storage, now: { current })
    reminders.waterMinutes = 5
    reminders.waterEnabled = true
    current = current.addingTimeInterval(299)
    reminders.check()
    precondition(reminders.pending == nil)
    current = current.addingTimeInterval(1)
    reminders.check()
    precondition(reminders.pending == .water)
    reminders.acknowledge(snooze: true)
    precondition(reminders.pending == nil)
    current = current.addingTimeInterval(300)
    reminders.check()
    precondition(reminders.pending == .water)
    reminders.waterEnabled = false
    precondition(reminders.pending == nil)
    reminders.eyesMinutes = 5
    reminders.eyesEnabled = true
    current = current.addingTimeInterval(300)
    reminders.check()
    precondition(reminders.pending == .eyes)
    reminders.eyesEnabled = false
    let banner = EverydayReminderStore(storage: storage, now: { current })
    banner.waterMinutes = 5
    banner.waterEnabled = true
    current = current.addingTimeInterval(300)
    banner.check()
    current = current.addingTimeInterval(100)
    banner.check()
    precondition(banner.pending == .water && banner.remainingSeconds == 5) // Deferred, not yet visible.
    let screen1 = UUID(), screen2 = UUID()
    banner.beginPresentation(owner: screen1)
    current = current.addingTimeInterval(2)
    banner.check()
    precondition(banner.remainingSeconds == 3)
    banner.beginPresentation(owner: screen2)
    banner.endPresentation(owner: screen1)
    current = current.addingTimeInterval(1)
    banner.check()
    precondition(banner.remainingSeconds == 2)
    banner.endPresentation(owner: screen2)
    current = current.addingTimeInterval(100)
    banner.check()
    precondition(banner.pending == .water && banner.remainingSeconds == 2) // Hidden on every display: paused.
    banner.beginPresentation(owner: screen1)
    current = current.addingTimeInterval(2)
    banner.check()
    precondition(banner.pending == nil && banner.remainingSeconds == 0)
    current = current.addingTimeInterval(295)
    banner.preview(.eyes)
    banner.beginPresentation(owner: screen1)
    current = current.addingTimeInterval(5)
    banner.check()
    precondition(banner.pending == nil && !banner.eyesEnabled)
    banner.check()
    precondition(banner.pending == .water) // Preview did not postpone the real schedule.
    banner.acknowledge(snooze: true)
    current = current.addingTimeInterval(299)
    banner.check()
    precondition(banner.pending == nil)
    current = current.addingTimeInterval(1)
    banner.check()
    precondition(banner.pending == .water)
    banner.waterEnabled = false
    precondition(banner.pending == nil)
    print("PASS: reminder visibility countdown, multi-display ownership, pause/resume, auto-dismiss, preview isolation, snooze")
    print("PASS: task validation, completion, persistence, deletion, reminder deadlines, snooze, disabling, eye breaks")
}
MainActor.assumeIsolated { runEverydayChecks() }
