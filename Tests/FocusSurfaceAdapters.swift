import AppKit
import SwiftUI
import Combine

// Rendering fixtures only. Runtime behavior is covered by FocusClockChecks.
enum FocusPhase { case focus, rest }
final class BoringNotchSkyLightWindow: NSWindow {}
@MainActor final class FocusTimerModel: ObservableObject {
    static let shared = FocusTimerModel()
    @Published var durationMinutes = 25
    @Published var goal = ""
    @Published var isEditingGoal = false
    @Published var isVisible = false
    @Published var isRunning = false
    @Published var isFinished = false
    @Published var phase = FocusPhase.focus
    var remainingSeconds = 1500
    var sessionMinutes = 25
    var completedSessions = 2
    var focusedMinutesToday = 50
    func reset() {}
    func pause() {}
    func start() {}
    func startBreak() {}
}

@MainActor final class UtilityClockModel: ObservableObject {
    static let shared = UtilityClockModel()
    var stopwatchRunning = false
    var stopwatchSeconds = 0
    func resetStopwatch() {}
    func toggleStopwatch() {}
    static func formatted(_ seconds: Int) -> String {
        String(format: "%02d:%02d", seconds / 60, seconds % 60)
    }
}
