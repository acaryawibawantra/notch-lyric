// Run with: sh Tests/run-clock-checks.sh
import Foundation
import Combine
import AppKit

@MainActor
func runClockChecks() {
    let suite = "notchLyric.clockChecks.\(UUID().uuidString)"
    let storage = UserDefaults(suiteName: suite)!
    defer { storage.removePersistentDomain(forName: suite) }
    var current = Date(timeIntervalSince1970: 1_800_000_000)
    var focusSounds = 0
    let focus = FocusTimerModel(storage: storage, now: { current }, completionSound: { focusSounds += 1 })
    focus.durationMinutes = 1
    focus.breakMinutes = 1
    focus.goal = "Verify session recovery"
    focus.start()
    current = current.addingTimeInterval(10)
    focus.pause()
    precondition(focus.remainingSeconds == 50 && !focus.isRunning)
    current = current.addingTimeInterval(90)
    let restored = FocusTimerModel(storage: storage, now: { current }, completionSound: { focusSounds += 1 })
    precondition(restored.remainingSeconds == 50 && restored.goal == focus.goal && !restored.isRunning)
    restored.start()
    current = current.addingTimeInterval(60)
    restored.updateRemainingTime()
    restored.updateRemainingTime()
    precondition(restored.isFinished && restored.history.count == 1 && focusSounds == 1)
    restored.startBreak()
    current = current.addingTimeInterval(61)
    restored.updateRemainingTime()
    precondition(restored.phase == .rest && restored.isFinished && restored.history.count == 1)
    precondition(focusSounds == 2)
    precondition(restored.hasCompactActivity && restored.showsCompletion)
    current = current.addingTimeInterval(6)
    restored.updateRemainingTime()
    precondition(!restored.hasCompactActivity && restored.isFinished && restored.history.count == 1)
    let hiddenCompletion = FocusTimerModel(storage: storage, now: { current }, completionSound: {})
    precondition(hiddenCompletion.isFinished && !hiddenCompletion.hasCompactActivity)
    hiddenCompletion.reset()
    restored.reset()
    restored.start()
    current = current.addingTimeInterval(61)
    let recoveredExpired = FocusTimerModel(storage: storage, now: { current }, completionSound: {})
    precondition(recoveredExpired.history.count == 2 && recoveredExpired.isFinished)
    let recoveredAgain = FocusTimerModel(storage: storage, now: { current }, completionSound: {})
    precondition(recoveredAgain.history.count == 2)
    restored.reset()
    recoveredExpired.reset()
    recoveredAgain.reset()
    focus.reset()

    var completedTaskIDs: [UUID] = []
    let linked = FocusTimerModel(storage: storage, now: { current }, completionSound: {}, completeTask: { completedTaskIDs.append($0) })
    let taskID = UUID()
    linked.selectTask(id: taskID, title: "Linked task")
    linked.start()
    current = current.addingTimeInterval(61)
    linked.updateRemainingTime()
    linked.updateRemainingTime()
    precondition(completedTaskIDs == [taskID] && linked.selectedTaskID == nil)
    linked.reset()
    linked.selectTask(id: UUID(), title: "Original")
    linked.goal = "Manually changed"
    precondition(linked.selectedTaskID == nil)

    var timerSounds = 0
    let clocks = UtilityClockModel(storage: storage, now: { current }, completionSound: { timerSounds += 1 })
    clocks.minutes = 1
    clocks.toggleTimer()
    clocks.toggleStopwatch()
    current = current.addingTimeInterval(15)
    clocks.tick()
    precondition(clocks.remaining == 45 && clocks.stopwatchSeconds == 15)
    clocks.toggleStopwatch()
    current = current.addingTimeInterval(46)
    clocks.tick()
    clocks.tick()
    precondition(clocks.timerDone && timerSounds == 1 && clocks.stopwatchSeconds == 15)
    let recoveredClocks = UtilityClockModel(storage: storage, now: { current }, completionSound: {})
    precondition(recoveredClocks.timerDone && recoveredClocks.stopwatchSeconds == 15 && !recoveredClocks.stopwatchRunning)
    precondition(recoveredClocks.showsTimerCompletion)
    current = current.addingTimeInterval(6)
    recoveredClocks.tick()
    precondition(!recoveredClocks.hasCompactTimer && recoveredClocks.timerDone)
    let hiddenTimer = UtilityClockModel(storage: storage, now: { current }, completionSound: {})
    precondition(hiddenTimer.timerDone && !hiddenTimer.hasCompactTimer)
    hiddenTimer.resetTimer()
    recoveredClocks.toggleStopwatch()
    current = current.addingTimeInterval(5)
    recoveredClocks.tick()
    precondition(recoveredClocks.stopwatchSeconds == 20)
    clocks.resetTimer()
    clocks.resetStopwatch()
    let beforeStop = timerSounds
    clocks.toggleStopwatch()
    current = current.addingTimeInterval(2)
    clocks.toggleStopwatch()
    precondition(timerSounds == beforeStop) // Pause is silent.
    clocks.stopStopwatch()
    precondition(timerSounds == beforeStop + 1 && clocks.stopwatchSeconds == 0)
    clocks.stopStopwatch()
    clocks.resetStopwatch()
    precondition(timerSounds == beforeStop + 1) // No duplicate done sound.
    recoveredClocks.resetStopwatch()
    recoveredClocks.resetTimer()
    recoveredClocks.startTimer(seconds: 30)
    precondition(recoveredClocks.selectedSeconds == 30 && recoveredClocks.remaining == 30)
    current = current.addingTimeInterval(10)
    recoveredClocks.tick()
    precondition(recoveredClocks.remaining == 20)
    let recoveredPreset = UtilityClockModel(storage: storage, now: { current }, completionSound: {})
    precondition(recoveredPreset.selectedSeconds == 30 && recoveredPreset.remaining == 20 && recoveredPreset.timerRunning)
    recoveredClocks.resetTimer()
    recoveredPreset.resetTimer()
    print("PASS: focus pause/resume, recovery, expired recovery, single completion, breaks, timer, independent stopwatch, persistence")
}

MainActor.assumeIsolated { runClockChecks() }

@MainActor
func runReminderFocusChecks() async {
    let suite = "notchLyric.reminderFocusChecks.\(UUID().uuidString)"
    let storage = UserDefaults(suiteName: suite)!
    defer { storage.removePersistentDomain(forName: suite) }
    var current = Date(timeIntervalSince1970: 1_800_000_000)
    var attempts: [String] = []
    var canSave = false
    let model = FocusTimerModel(storage: storage, now: { current }, completionSound: {}, completeReminder: {
        attempts.append($0)
        return canSave
    })
    model.durationMinutes = 1
    model.selectReminder(id: "apple-reminder-1", title: "Write proposal")
    model.start()
    current = current.addingTimeInterval(61)
    model.updateRemainingTime()
    await Task.yield()
    await model.syncCompletedReminder()
    precondition(model.pendingReminderID == "apple-reminder-1" && model.selectedReminderID == nil)
    let recovered = FocusTimerModel(storage: storage, now: { current }, completionSound: {}, completeReminder: {
        attempts.append($0)
        return canSave
    })
    precondition(recovered.pendingReminderID == "apple-reminder-1")
    canSave = true
    await recovered.syncCompletedReminder()
    let count = attempts.count
    await recovered.syncCompletedReminder()
    precondition(recovered.pendingReminderID == nil && attempts.count == count)
    recovered.reset()
    recovered.selectReminder(id: "apple-reminder-2", title: "Review")
    recovered.goal = "Different goal"
    precondition(recovered.selectedReminderID == nil)
    recovered.selectReminder(id: "apple-reminder-2", title: "Review")
    recovered.startBreak()
    current = current.addingTimeInterval(301)
    recovered.updateRemainingTime()
    await Task.yield()
    precondition(attempts.count == count)
    print("PASS: Apple Reminder focus link, failed-sync recovery, retry, single completion, manual unlink, no completion on break")
}

await runReminderFocusChecks()
