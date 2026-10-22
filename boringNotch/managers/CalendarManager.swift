//
//  CalendarManager.swift
//  boringNotch
//
//  Created by Harsh Vardhan  Goswami  on 08/09/24.
//

import Defaults
import EventKit
import SwiftUI

// MARK: - CalendarManager
struct NativeReminderItem: Identifiable {
    let id: String
    let title: String
    let list: String
    let due: Date?
}

@MainActor
class CalendarManager: ObservableObject {
    static let shared = CalendarManager()

    @Published var currentWeekStartDate: Date
    @Published var events: [EventModel] = []
    @Published var nativeReminders: [NativeReminderItem] = []
    @Published var syncError: String?
    @Published var allCalendars: [CalendarModel] = []
    @Published var eventCalendars: [CalendarModel] = []
    @Published var reminderLists: [CalendarModel] = []
    @Published var selectedCalendarIDs: Set<String> = []
    @Published var calendarAuthorizationStatus: EKAuthorizationStatus = .notDetermined
    @Published var reminderAuthorizationStatus: EKAuthorizationStatus = .notDetermined
    private var selectedCalendars: [CalendarModel] = []
    private let calendarService = CalendarService()

    private var eventStoreChangedObserver: NSObjectProtocol?

    private init() {
        self.currentWeekStartDate = CalendarManager.startOfDay(Date())
        setupEventStoreChangedObserver()
        Task {
            await reloadCalendarAndReminderLists()
        }
    }

    deinit {
        if let observer = eventStoreChangedObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    private func setupEventStoreChangedObserver() {
        eventStoreChangedObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task {
                await self?.reloadCalendarAndReminderLists()
            }
        }
    }

    @MainActor
    func reloadCalendarAndReminderLists() async {
        calendarAuthorizationStatus = EKEventStore.authorizationStatus(for: .event)
        reminderAuthorizationStatus = EKEventStore.authorizationStatus(for: .reminder)
        let all = await calendarService.calendars()
        self.eventCalendars = all.filter { !$0.isReminder }
        self.reminderLists = all.filter { $0.isReminder }
        self.allCalendars = all // for legacy compatibility, can be removed if not needed
        updateSelectedCalendars()
        await updateEvents()
    }

    func checkCalendarAuthorization() async {
        let status = EKEventStore.authorizationStatus(for: .event)
        DispatchQueue.main.async {
            print("📅 Current calendar authorization status: \(status)")
            self.calendarAuthorizationStatus = status
        }

        switch status {
        case .notDetermined:
            guard let granted = try? await calendarService.requestAccess(to: .event) else {
                self.calendarAuthorizationStatus = .notDetermined
                return
            }
            self.calendarAuthorizationStatus = granted ? .fullAccess : .denied
            if granted {
                await reloadCalendarAndReminderLists()
                events = await calendarService.events(
                    from: currentWeekStartDate,
                    to: Calendar.current.date(byAdding: .day, value: 1, to: currentWeekStartDate)!,
                    calendars: selectedCalendars.map { $0.id })
            }
        case .restricted, .denied:
            NSLog("Calendar access denied or restricted")
        case .fullAccess:
            NSLog("Full access")
            await reloadCalendarAndReminderLists()
            events = await calendarService.events(
                from: currentWeekStartDate,
                to: Calendar.current.date(byAdding: .day, value: 1, to: currentWeekStartDate)!,
                calendars: selectedCalendars.map { $0.id })
        case .writeOnly:
            NSLog("Write only")
        @unknown default:
            print("Unknown authorization status")
        }
    }
    
    func checkReminderAuthorization() async {
        let status = EKEventStore.authorizationStatus(for: .reminder)
        DispatchQueue.main.async {
            print("📅 Current reminder authorization status: \(status)")
            self.reminderAuthorizationStatus = status
        }

        switch status {
        case .notDetermined:
            guard let granted = try? await calendarService.requestAccess(to: .reminder) else {
                self.reminderAuthorizationStatus = .notDetermined
                return
            }
            self.reminderAuthorizationStatus = granted ? .fullAccess : .denied
            if granted {
                await reloadCalendarAndReminderLists()
            }
        case .restricted, .denied:
            NSLog("Reminder access denied or restricted")
        case .fullAccess:
            NSLog("Full access")
            await reloadCalendarAndReminderLists()
        case .writeOnly:
            NSLog("Write only")
        @unknown default:
            print("Unknown authorization status")
        }
    }
        

    func updateSelectedCalendars() {
        // Populate selectedCalendarIDs based on Defaults calendar selection state
        switch Defaults[.calendarSelectionState] {
        case .all:
            selectedCalendarIDs = Set(allCalendars.map { $0.id })
        case .selected(let identifiers):
            selectedCalendarIDs = identifiers
        }

        // Update the local calendar objects that correspond to the selected ids
        selectedCalendars = allCalendars.filter { selectedCalendarIDs.contains($0.id) }
        Task { await CalendarAgendaStore.shared.refresh() }
    }

    func getCalendarSelected(_ calendar: CalendarModel) -> Bool {
        return selectedCalendarIDs.contains(calendar.id)
    }

    func setCalendarSelected(_ calendar: CalendarModel, isSelected: Bool) async {
        var selectionState = Defaults[.calendarSelectionState]

        switch selectionState {
        case .all:
            if !isSelected {
                let identifiers = Set(allCalendars.map { $0.id }).subtracting([calendar.id])
                selectionState = .selected(identifiers)
            }

        case .selected(var identifiers):
            if isSelected {
                identifiers.insert(calendar.id)
            } else {
                identifiers.remove(calendar.id)
            }

            selectionState =
                identifiers.isEmpty
                ? .all : identifiers.count == allCalendars.count ? .all : .selected(identifiers)  // if empty, select all
        }

        Defaults[.calendarSelectionState] = selectionState
        updateSelectedCalendars()
        await updateEvents()
    }

    static func startOfDay(_ date: Date) -> Date {
        return Calendar.current.startOfDay(for: date)
    }

    func updateCurrentDate(_ date: Date) async {
        currentWeekStartDate = Calendar.current.startOfDay(for: date)
        await updateEvents()
    }

    private func updateEvents() async {
        let calendarIDs = selectedCalendars.map { $0.id }
        let eventsResult = await calendarService.events(
            from: currentWeekStartDate,
            to: Calendar.current.date(byAdding: .day, value: 1, to: currentWeekStartDate)!,
            calendars: calendarIDs
        )
        self.events = eventsResult
        self.nativeReminders = await calendarService.incompleteReminders(calendars: calendarIDs)
    }
    
    func setReminderCompleted(reminderID: String, completed: Bool) async {
        await calendarService.setReminderCompleted(reminderID: reminderID, completed: completed)
        // Refresh events after updating
        events = await calendarService.events(
            from: currentWeekStartDate,
            to: Calendar.current.date(byAdding: .day, value: 1, to: currentWeekStartDate)!,
            calendars: selectedCalendars.map { $0.id })
    }

    @discardableResult
    func completeNativeReminder(_ id: String) async -> Bool {
        do {
            try await calendarService.completeNativeReminder(id)
            syncError = nil
            await updateEvents()
            return true
        } catch { syncError = error.localizedDescription; return false }
    }

    func loadAgendaAlerts(at now: Date) async -> [CalendarAgendaAlert] {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else { return [] }
        let calendars = await calendarService.calendars().filter { !$0.isReminder }
        let ids: [String]
        switch Defaults[.calendarSelectionState] {
        case .all: ids = calendars.map(\.id)
        case .selected(let selected): ids = calendars.filter { selected.contains($0.id) }.map(\.id)
        }
        let start = Calendar.current.date(byAdding: .day, value: -1, to: now) ?? now
        let end = Calendar.current.date(byAdding: .day, value: 32, to: now) ?? now
        return await calendarService.agendaAlerts(from: start, to: end, calendars: ids)
    }
}

struct CalendarAgendaAlert: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let fire: Date
    let calendar: String
    let allDay: Bool
    static func alarmDate(start: Date, absolute: Date?, offset: TimeInterval) -> Date {
        absolute ?? start.addingTimeInterval(offset)
    }
}

/// Calendar dates are absolute instants; IDs include occurrence + alarm time.
struct CalendarAlarmLedger {
    var delivered: [String: Double] = [:]
    mutating func due(_ alerts: [CalendarAgendaAlert], at now: Date) -> [CalendarAgendaAlert] {
        delivered = delivered.filter { now.timeIntervalSince1970 - $0.value < 7 * 86400 }
        var result: [CalendarAgendaAlert] = []
        for alert in alerts.sorted(by: { $0.fire < $1.fire }) {
            guard delivered[alert.id] == nil, alert.fire <= now,
                  now.timeIntervalSince(alert.fire) <= 120 else { continue }
            delivered[alert.id] = now.timeIntervalSince1970
            result.append(alert)
        }
        return result
    }
}

@MainActor
final class CalendarAgendaStore: ObservableObject {
    static let shared = CalendarAgendaStore()
    @Published private(set) var notice: CalendarAgendaAlert?
    @Published private(set) var status = "Calendar popups are off."
    private var enabled = false
    private var ledger = CalendarAlarmLedger(delivered: UserDefaults.standard.dictionary(forKey: "moris.calendarAlerts.delivered") as? [String: Double] ?? [:])
    private var alerts: [CalendarAgendaAlert] = []
    private var queue: [CalendarAgendaAlert] = []
    private var runner: Task<Void, Never>?
    private var dismissTask: Task<Void, Never>?
    private var observer: NSObjectProtocol?
    private var revision = 0
    private var lastRefresh = Date.distantPast
    private var presentationOwners: Set<UUID> = []

    func configure(enabled: Bool) {
        guard enabled != self.enabled else { return }
        self.enabled = enabled
        revision += 1
        runner?.cancel()
        if !enabled {
            if let observer { NotificationCenter.default.removeObserver(observer) }
            observer = nil
            dismissTask?.cancel()
            notice = nil; queue = []; alerts = []
            status = "Calendar popups are off."
            return
        }
        observer = NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in await self?.refresh() }
        }
        runner = Task { @MainActor [weak self] in
            await self?.refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(5)) } catch { return }
                guard let self else { return }
                if Date().timeIntervalSince(self.lastRefresh) >= 60 { await self.refresh() }
                self.checkDue()
            }
        }
    }

    func refresh() async {
        guard enabled else { return }
        revision += 1
        let request = revision
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            alerts = []; queue = []; notice = nil
            status = "Allow Calendar access to follow event alerts."
            lastRefresh = Date()
            return
        }
        let result = await CalendarManager.shared.loadAgendaAlerts(at: Date())
        guard enabled, request == revision else { return }
        alerts = result
        // Drop stale queued alerts if an event was edited or deleted.
        let valid = Set(result.map(\.id))
        queue.removeAll { !valid.contains($0.id) }
        if let notice, !notice.id.hasPrefix("preview:"), !valid.contains(notice.id) { dismiss() }
        lastRefresh = Date()
        status = "Following time-based alerts in your selected calendars."
        checkDue()
    }

    private func checkDue() {
        guard enabled else { return }
        if presentationOwners.isEmpty, let notice, Date().timeIntervalSince(notice.fire) > 120 {
            dismiss()
        }
        let due = ledger.due(alerts, at: Date())
        guard !due.isEmpty else { return }
        UserDefaults.standard.set(ledger.delivered, forKey: "moris.calendarAlerts.delivered")
        queue.append(contentsOf: due)
        if notice == nil { showNext() }
    }

    private func showNext() {
        dismissTask?.cancel()
        dismissTask = nil
        queue.removeAll { Date().timeIntervalSince($0.fire) > 120 }
        notice = queue.isEmpty ? nil : queue.removeFirst()
        if !presentationOwners.isEmpty { startDismissal() }
    }
    private func startDismissal() {
        guard notice != nil else { return }
        dismissTask = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .seconds(12)) } catch { return }
            self?.dismiss()
        }
    }
    func beginPresentation(owner: UUID) {
        presentationOwners.insert(owner)
        if dismissTask == nil { startDismissal() }
    }
    func endPresentation(owner: UUID) {
        presentationOwners.remove(owner)
        if presentationOwners.isEmpty { dismissTask?.cancel(); dismissTask = nil }
    }
    func dismiss() { showNext() }
    func preview() {
        queue.insert(.init(id: "preview:\(UUID())", title: "MORIS · Calendar preview", start: Date().addingTimeInterval(1800),
                           fire: Date(), calendar: "Preview only", allDay: false), at: 0)
        if notice == nil { showNext() }
    }
}

struct CalendarAgendaPreferences: View {
    @Default(.calendarAgendaPopups) private var enabled
    @ObservedObject private var store = CalendarAgendaStore.shared
    @ObservedObject private var manager = CalendarManager.shared
    var body: some View {
        Toggle("Show Calendar alerts in MORIS", isOn: $enabled)
            .onChange(of: enabled) { _, value in
                store.configure(enabled: value)
                if value { Task { await manager.checkCalendarAuthorization(); await store.refresh() } }
            }
        Text(store.status).font(.caption).foregroundStyle(.secondary)
        Button("Preview Calendar popup") { store.preview() }
        Text("Follows saved time-based alerts in selected calendars, including multiple alerts. MORIS must be running; popups may appear within a few seconds. Events without alerts are not given a default reminder. Apple Calendar notifications remain enabled independently.")
            .font(.caption).foregroundStyle(.secondary)
    }
}

struct CalendarAgendaPopup: View {
    let alert: CalendarAgendaAlert
    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(.orange.gradient)
                .frame(width: 54, height: 54)
                .background(.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 15))
            VStack(alignment: .leading, spacing: 5) {
                Text(alert.title.isEmpty ? "Calendar event" : alert.title)
                    .font(.system(size: 17, weight: .semibold)).lineLimit(2)
                HStack(spacing: 5) {
                    if alert.allDay { Text("All day") }
                    else { Text(alert.start, style: .time) }
                    Text("· \(alert.calendar)").lineLimit(1)
                }.font(.system(size: 11)).foregroundStyle(.secondary)
                Button("Open Calendar") {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") { NSWorkspace.shared.open(url) }
                    CalendarAgendaStore.shared.dismiss()
                }.buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(.orange)
            }
            Spacer(minLength: 0)
            Button { CalendarAgendaStore.shared.dismiss() } label: {
                Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).padding(8)
            }.buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Dismiss Calendar alert")
        }
        .foregroundStyle(.white)
    }
}
