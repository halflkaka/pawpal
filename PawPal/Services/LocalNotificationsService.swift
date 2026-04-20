import Foundation
import UserNotifications

/// Local-notification scheduler for the one push category that's actually
/// device-schedulable: milestone day-of reminders for pet birthdays.
///
/// This is the APNs-free stopgap described in
/// `docs/sessions/2026-04-18-pm-local-notifications-stopgap.md`: a user
/// with `pets.birthday` set gets a `UNCalendarNotificationTrigger` that
/// fires at 09:00 local time on the matching month-day, repeating yearly.
/// No Supabase roundtrip, no APNs key, no dev-program enrollment.
///
/// Coexistence with APNs (when it lands): local notifications own
/// device-schedulable milestones; server-originating events (like,
/// comment, follow, chat) stay on APNs. The two paths share
/// `DeepLinkRouter` on tap — local notifications carry the same
/// `{type, target_id}` userInfo shape that
/// `AppDelegate.userNotificationCenter(_:didReceive:)` already parses.
///
/// Mirrors the `PushService` / `PetsService` shape:
///   * `@MainActor final class ... ObservableObject`
///   * `static let shared` singleton
///   * `print("[LocalNotif] ...")` logging style
@MainActor
final class LocalNotificationsService: ObservableObject {
    /// Shared singleton — matches the `PushService` / `ChatService` pattern.
    static let shared = LocalNotificationsService()

    /// Identifier prefix for every milestone reminder we schedule.
    /// `cancelAll()` filters on this so we never touch non-milestone
    /// pending requests (future categories can claim their own prefix).
    private let milestonePrefix = "pawpal.milestone.birthday."

    /// Identifier prefix for every playdate reminder.
    /// ID shape: `pawpal.playdate.reminder.<uuid>.<phase>` where phase
    /// is one of `t_minus_24h` / `t_minus_1h` / `t_plus_2h`.
    /// `cancelPlaydateReminders(for:)` filters on the `<uuid>.` prefix
    /// so we can remove all three phases for a specific playdate in
    /// one pass; `cancelAll()` filters on the `pawpal.playdate.`
    /// prefix to sweep every playdate reminder at sign-out.
    private let playdatePrefix = "pawpal.playdate.reminder."

    private init() {}

    /// Cancels every previously scheduled birthday reminder, then
    /// schedules one `UNCalendarNotificationTrigger` (repeats yearly)
    /// per pet that has a non-nil `birthday`. Early-exits silently when
    /// the OS authorization status is anything other than `.authorized`
    /// or `.provisional` — priming owns the permission prompt, not us.
    ///
    /// The cancel-then-reschedule loop is the dedupe strategy: a pet
    /// whose birthday was cleared, or a pet that was deleted from the
    /// local cache, simply doesn't get re-added on the next pass and
    /// drops out of the pending tray. Matches the "reschedule on every
    /// `petsService.pets` change" wiring in `MainTabView`.
    func scheduleBirthdayReminders(for pets: [RemotePet]) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
           || settings.authorizationStatus == .provisional else {
            print("[LocalNotif] 未授权,跳过生日提醒调度")
            return
        }

        // Cancel any existing birthday requests first so a deleted /
        // edited pet doesn't leave orphan reminders in the tray.
        let pending = await center.pendingNotificationRequests()
        let stale = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(milestonePrefix) }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }

        for pet in pets {
            guard let birthday = pet.birthday else { continue }
            let cal = Calendar(identifier: .gregorian)
            let bComps = cal.dateComponents([.month, .day], from: birthday)
            guard let month = bComps.month, let day = bComps.day else { continue }

            // Compute the next-occurrence age for the body copy. The
            // trigger repeats yearly so this string is refreshed on
            // every app-open reschedule — acceptable one-year drift at
            // worst if the user never opens the app between birthdays.
            let now = Date()
            let nowComps = cal.dateComponents([.year, .month, .day], from: now)
            let candidateYear: Int = {
                guard let nm = nowComps.month,
                      let nd = nowComps.day,
                      let ny = nowComps.year else {
                    return cal.component(.year, from: now)
                }
                // If (month, day) is on or after today, the next occurrence
                // is still this year; otherwise roll to next year.
                if (month, day) >= (nm, nd) { return ny }
                return ny + 1
            }()
            let nextBirthday = cal.date(from: DateComponents(
                year: candidateYear, month: month, day: day
            )) ?? now
            let age = cal.dateComponents([.year], from: birthday, to: nextBirthday).year ?? 0

            let content = UNMutableNotificationContent()
            content.title = "🎂 \(pet.name) 今天生日！"
            content.body  = "今天是 \(pet.name) 的 \(age) 岁生日，点这里发个祝福帖吧 ❤️"
            content.sound = .default
            // Mirror the APNs payload shape so AppDelegate's
            // `userNotificationCenter(_:didReceive:)` can reuse the same
            // `type` / `target_id` parsing path — DeepLinkRouter routes
            // `birthday_today` to `.pet(UUID)`.
            content.userInfo = [
                "type": "birthday_today",
                "target_id": pet.id.uuidString
            ]

            var fireComps = DateComponents()
            fireComps.hour = 9
            fireComps.minute = 0
            fireComps.month = month
            fireComps.day = day
            let trigger = UNCalendarNotificationTrigger(
                dateMatching: fireComps,
                repeats: true
            )

            let request = UNNotificationRequest(
                identifier: "\(milestonePrefix)\(pet.id.uuidString)",
                content: content,
                trigger: trigger
            )

            do {
                try await center.add(request)
                print("[LocalNotif] 已排程 \(pet.name) 的生日提醒 (\(month)/\(day) 09:00)")
            } catch {
                print("[LocalNotif] 排程失败: \(error.localizedDescription)")
            }
        }
    }

    /// Cancels the birthday reminder for a single pet. Covers the
    /// pet-delete path without requiring a full reschedule-all roundtrip;
    /// the reschedule-all flow in `scheduleBirthdayReminders` is the
    /// safer default and also handles this case implicitly.
    func cancelBirthday(for petID: UUID) {
        let center = UNUserNotificationCenter.current()
        let id = "\(milestonePrefix)\(petID.uuidString)"
        center.removePendingNotificationRequests(withIdentifiers: [id])
    }

    // MARK: - Playdate reminders
    //
    // Device-scheduled reminders for accepted playdates. Three phases
    // per playdate:
    //   * T-24h → "明天和 {other_pet_name} 遛弯 🐾"
    //   * T-1h  → "还有一小时就要出发啦"
    //   * T+2h  → "今天遛得怎么样？" (→ post-playdate prompt)
    //
    // The APNs path's `playdate_t_*` types are intentionally not wired
    // on the server (see `docs/decisions.md` → "Local notifications
    // own device-schedulable events; APNs owns server events"), so
    // these reminders work today without paid-developer-program
    // enrollment. The `dispatch-notification` edge function returns
    // `unsupported_type` for those strings on purpose.
    //
    // `MainTabView` observes `.playdateDidChange` and calls
    // `schedulePlaydateReminders` with the current accepted-future set;
    // `PlaydateService.cancel` / `.decline` also call
    // `cancelPlaydateReminders` directly as belt-and-suspenders (the
    // reschedule-all path would catch it on the next `.playdateDidChange`
    // anyway, but doing it inline keeps the pending tray accurate even
    // if the observer is briefly unwired — e.g. during a tab switch).

    /// Schedules up to three `UNCalendarNotificationTrigger`s per
    /// accepted, future-scheduled playdate. Cancels every existing
    /// `pawpal.playdate.reminder.*` pending request first (the
    /// cancel-then-reschedule loop is the dedupe strategy — a
    /// declined / cancelled playdate simply isn't re-added on the
    /// next pass).
    ///
    /// Each `playdate` passed in must already be paired with the
    /// "other" pet name (relative to the viewer) via the
    /// `otherPetNameByID` map — the caller resolves the viewer side
    /// and looks up `PetsService.shared`'s cached pets, so this
    /// service stays storage-agnostic. Playdates whose
    /// `otherPetNameByID` entry is missing fall back to `毛孩子`.
    ///
    /// Phases whose fire date is already in the past are skipped per
    /// phase (e.g. a user who accepts 30 min before the playdate
    /// only gets the T+2h reminder). Repeats = false for every
    /// trigger — a playdate is a one-off event.
    func schedulePlaydateReminders(
        for playdates: [RemotePlaydate],
        otherPetNameByID: [UUID: String] = [:]
    ) async {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized
           || settings.authorizationStatus == .provisional else {
            print("[LocalNotif] 未授权,跳过遛弯提醒调度")
            return
        }

        // Cancel every existing playdate reminder first — the
        // reschedule-all flow treats the passed-in list as canonical.
        let pending = await center.pendingNotificationRequests()
        let stale = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(playdatePrefix) }
        if !stale.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: stale)
        }

        let now = Date()
        let cal = Calendar(identifier: .gregorian)

        for playdate in playdates {
            guard playdate.status == .accepted else { continue }
            let otherPetName = otherPetNameByID[playdate.id] ?? "毛孩子"
            let location = playdate.location_name

            let phases: [(suffix: String, offset: TimeInterval, type: String, title: String, body: String)] = [
                (
                    "t_minus_24h",
                    -24 * 60 * 60,
                    "playdate_t_minus_24h",
                    "明天和 \(otherPetName) 遛弯 🐾",
                    "在 \(location)，别忘了带水和小食"
                ),
                (
                    "t_minus_1h",
                    -60 * 60,
                    "playdate_t_minus_1h",
                    "还有一小时就要出发啦",
                    "去 \(location) 和 \(otherPetName) 遛弯，记得戴牵引绳"
                ),
                (
                    "t_plus_2h",
                    2 * 60 * 60,
                    "playdate_t_plus_2h",
                    "今天遛得怎么样？",
                    "和 \(otherPetName) 的遛弯刚结束，发一条日记记录一下吧"
                )
            ]

            for phase in phases {
                let fireDate = playdate.scheduled_at.addingTimeInterval(phase.offset)
                guard fireDate > now else { continue }

                let content = UNMutableNotificationContent()
                content.title = phase.title
                content.body = phase.body
                content.sound = .default
                // Mirror the APNs payload shape so AppDelegate's
                // `userNotificationCenter(_:didReceive:)` reuses the
                // same `type` / `target_id` parsing path — DeepLinkRouter
                // routes all three to `.playdate(UUID)`.
                content.userInfo = [
                    "type": phase.type,
                    "target_id": playdate.id.uuidString
                ]

                let fireComps = cal.dateComponents(
                    [.year, .month, .day, .hour, .minute],
                    from: fireDate
                )
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: fireComps,
                    repeats: false
                )

                let request = UNNotificationRequest(
                    identifier: "\(playdatePrefix)\(playdate.id.uuidString).\(phase.suffix)",
                    content: content,
                    trigger: trigger
                )

                do {
                    try await center.add(request)
                    print("[LocalNotif] 已排程遛弯提醒 \(phase.suffix) for \(playdate.id)")
                } catch {
                    print("[LocalNotif] 遛弯提醒排程失败 (\(phase.suffix)): \(error.localizedDescription)")
                }
            }
        }
    }

    /// Cancels all three phase reminders for a single playdate. Called
    /// inline from `PlaydateService.cancel` / `.decline` so the
    /// pending tray clears immediately, even before the next
    /// `.playdateDidChange` observer tick. A full
    /// `schedulePlaydateReminders` pass would also catch this, but the
    /// inline cancel is cheap and keeps the tray honest.
    func cancelPlaydateReminders(for playdateID: UUID) {
        let center = UNUserNotificationCenter.current()
        let base = "\(playdatePrefix)\(playdateID.uuidString)."
        let ids = [
            "\(base)t_minus_24h",
            "\(base)t_minus_1h",
            "\(base)t_plus_2h"
        ]
        center.removePendingNotificationRequests(withIdentifiers: ids)
    }

    /// Cancels every locally-scheduled reminder this service manages.
    /// Called from `AuthManager.signOut` so a device that's been
    /// signed out doesn't keep firing reminders for the previous
    /// user's pets or playdates.
    ///
    /// Filtered to the union of `pawpal.milestone.` and
    /// `pawpal.playdate.` prefixes so we don't nuke any unrelated
    /// categories scheduled by other parts of the app in the future.
    func cancelAll() async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests()
        let prefixes = ["pawpal.milestone.", "pawpal.playdate."]
        let ids = pending
            .map(\.identifier)
            .filter { id in
                prefixes.contains(where: id.hasPrefix)
            }
        if !ids.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: ids)
            print("[LocalNotif] 已清除 \(ids.count) 个本地提醒")
        }
    }
}
