// In-memory Defaults adapter: never reads or writes the user's preferences.
enum Defaults {
    protocol Serializable {}
    struct Key<Value> {
        let name: String
        let fallback: Value
    }
    static var values: [String: Any] = [:]
    static subscript<Value>(key: Key<Value>) -> Value {
        get { values[key.name] as? Value ?? key.fallback }
        set { values[key.name] = newValue }
    }
}
extension Defaults.Key where Value == MediaCompanion {
    static var mediaCompanion: Self { .init(name: "companion", fallback: .legacy) }
}
extension Defaults.Key where Value == Bool {
    static var expandedMediaLyrics: Self { .init(name: "lyrics", fallback: false) }
    static var enableLyrics: Self { .init(name: "enabled", fallback: false) }
    static var showCalendar: Self { .init(name: "calendar", fallback: false) }
}

assert(MediaCompanion.current == .none)
Defaults[.showCalendar] = true
assert(MediaCompanion.current == .calendar)
Defaults[.expandedMediaLyrics] = true
Defaults[.enableLyrics] = true
assert(MediaCompanion.current == .lyrics)
for panel in [MediaCompanion.calendar, .reminders, .timer, .focus, .lyrics, .none] {
    Defaults[.mediaCompanion] = panel
    assert(MediaCompanion.current == (panel == .focus ? .timer : panel), "Explicit selection must override legacy preferences; legacy Focus shares the time panel")
}
assert(Defaults[.showCalendar], "Closing split must not erase the Calendar preference")
assert(Defaults[.expandedMediaLyrics], "Resolving a panel must not mutate other preferences")
Defaults[.mediaCompanion] = .legacy
Defaults[.enableLyrics] = false
assert(MediaCompanion.current == .calendar, "Disabled legacy lyrics must not create a lyrics split")
assert(Set(MediaCompanion.allCases.map(\.rawValue)).count == MediaCompanion.allCases.count)
print("PASS: media companion selection, legacy migration, explicit close, independent preferences")
assert(TimeToolMode.resolve("Clocks") == .focus)
assert(TimeToolMode.resolve("Timer") == .focus)
assert(TimeToolMode.resolve("Focus") == .focus)
assert(TimeToolMode.resolve("Stopwatch") == .stopwatch)
assert(TimeToolMode.resolve("unknown") == .focus)
assert(TimeToolMode.allCases == [.focus, .stopwatch], "Only Focus and Stopwatch are exposed")
assert(MediaCompanion.shortcuts.filter { $0 == .timer }.count == 1)
assert(!MediaCompanion.shortcuts.contains(.focus))
print("PASS: two time modes, legacy Timer opens Focus, restored preferences, single Media time shortcut")
