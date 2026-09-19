import Foundation
import SwiftUI
import UserNotifications
import AppKit

/// Thin wrapper around macOS notifications.
final class Notifications: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifications()

    /// True when running inside a real .app bundle. Notifications need one;
    /// a bare `swift run` binary has no bundle identifier and would crash.
    private var isBundled: Bool { Bundle.main.bundleIdentifier != nil }

    func setup() {
        guard isBundled else { return }
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        center.requestAuthorization(options: [.alert, .sound, .badge]) { _, _ in }
    }

    // Show banners even while the app is in front.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification,
                                withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }

    func scheduleReminder(for note: Note, at date: Date) {
        guard isBundled else { return }
        let content = UNMutableNotificationContent()
        content.title = note.title.isEmpty ? "Reminder" : note.title
        content.body = note.body.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Open Orbit Notes"
        content.sound = .default
        let comps = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: date)
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
        let request = UNNotificationRequest(identifier: "reminder-\(note.id.uuidString)", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func cancelReminder(for id: UUID) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["reminder-\(id.uuidString)"])
    }

    /// Fires when a focus or break period ends, even if the app is in the background.
    func scheduleTimerEnd(in seconds: TimeInterval, isBreak: Bool) {
        guard isBundled, seconds > 1 else { return }
        let content = UNMutableNotificationContent()
        content.title = isBreak ? "Break's over" : "Focus session complete"
        content.body = isBreak ? "Ready to get back to it?" : "Nice work. Time for a short break."
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        let request = UNNotificationRequest(identifier: "timer-end", content: content, trigger: trigger)
        UNUserNotificationCenter.current().add(request)
    }

    func cancelTimerEnd() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: ["timer-end"])
    }
}

/// Pomodoro-style timer: focus periods with short breaks in between.
@MainActor
final class FocusTimer: ObservableObject {
    enum Phase: String { case focus, breakTime }

    @AppStorage("focusMinutes") var focusMinutes = 25 { didSet { if !isRunning { reset() } } }
    @AppStorage("breakMinutes") var breakMinutes = 5 { didSet { if !isRunning { reset() } } }

    @Published private(set) var phase: Phase = .focus
    @Published private(set) var remaining: TimeInterval = 25 * 60
    @Published private(set) var isRunning = false
    @Published var completedToday = 0

    private var endDate: Date?
    private var ticker: Timer?
    /// Called when a phase finishes so the store can log it.
    var onPhaseComplete: ((_ minutes: Int, _ isBreak: Bool) -> Void)?

    init() { reset() }

    var phaseLength: TimeInterval { TimeInterval((phase == .focus ? focusMinutes : breakMinutes) * 60) }
    var progress: Double { phaseLength > 0 ? 1 - remaining / phaseLength : 0 }

    var timeString: String {
        let s = max(0, Int(remaining.rounded()))
        return String(format: "%02d:%02d", s / 60, s % 60)
    }

    func start() {
        guard !isRunning else { return }
        isRunning = true
        endDate = Date().addingTimeInterval(remaining)
        Notifications.shared.scheduleTimerEnd(in: remaining, isBreak: phase == .breakTime)
        ticker = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.tick() }
        }
    }

    func pause() {
        guard isRunning else { return }
        isRunning = false
        ticker?.invalidate()
        ticker = nil
        if let end = endDate { remaining = max(0, end.timeIntervalSinceNow) }
        endDate = nil
        Notifications.shared.cancelTimerEnd()
    }

    func toggle() { isRunning ? pause() : start() }

    func reset() {
        pause()
        remaining = phaseLength
    }

    func skip() {
        pause()
        switchPhase()
    }

    private func tick() {
        guard isRunning, let end = endDate else { return }
        remaining = max(0, end.timeIntervalSinceNow)
        if remaining <= 0 { finishPhase() }
    }

    private func finishPhase() {
        pause()
        let minutes = Int(phaseLength / 60)
        let wasBreak = phase == .breakTime
        if !wasBreak { completedToday += 1 }
        onPhaseComplete?(minutes, wasBreak)
        NSSound(named: "Glass")?.play()
        switchPhase()
    }

    private func switchPhase() {
        phase = phase == .focus ? .breakTime : .focus
        remaining = phaseLength
    }
}
