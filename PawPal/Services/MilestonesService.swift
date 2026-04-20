import Foundation

/// Derived-not-stored milestone surfaces: birthdays (from `pets.birthday`)
/// and memory loops (from `posts.created_at`).
///
/// Stateless by design — every method is a pure function over in-memory
/// inputs. No cache, no `@Published`, no Supabase client. See
/// `docs/decisions.md` entry "Milestones are derived, not stored" for why.
@MainActor
final class MilestonesService {

    // MARK: - Public data shapes

    enum MilestoneKind: Hashable {
        case birthday(years: Int)
    }

    struct Milestone: Identifiable, Hashable {
        let id: String                  // "<petID>-birthday-<yyyy-MM-dd>"
        let pet: RemotePet
        let kind: MilestoneKind
        let date: Date
        let title: String
        let prefillCaption: String
    }

    struct MemoryPost: Identifiable, Hashable {
        let id: UUID
        let post: RemotePost
        let yearsAgo: Int
        let eyebrow: String
        let prefillCaption: String
    }

    // MARK: - Public API

    func milestonesToday(forPets pets: [RemotePet], now: Date = Date()) -> [Milestone] {
        pets.compactMap { birthdayToday(for: $0, now: now) }
    }

    /// Returns the next upcoming milestones for `pet`, de-duplicated by
    /// kind so the same anniversary isn't shown three years in a row.
    ///
    /// The MVP only ships one kind (birthday), so this collapses to
    /// "the next birthday, or nothing if the pet has no birthday set
    /// and no birthday has happened yet this year". When additional
    /// kinds land (gotcha day, account anniversary, first-playdate)
    /// each kind contributes at most one future milestone here.
    ///
    /// If today is the pet's birthday, it's intentionally excluded —
    /// "today" lives on `milestonesToday(forPets:)` / the FeedView
    /// card, not on the "即将到来" rail, so they don't compete.
    func upcomingMilestones(forPet pet: RemotePet, limit: Int = 3, now: Date = Date()) -> [Milestone] {
        guard let birthday = pet.birthday else { return [] }
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        let currentYear = cal.component(.year, from: now)

        // Walk forward until we find a birthday that's strictly after
        // today. Cap at +10y so a malformed date can't spin forever.
        var nextBirthday: Milestone?
        for offset in 0...10 {
            let year = currentYear + offset
            guard let m = birthdayOn(year: year, for: pet, birthday: birthday, now: now) else { continue }
            if m.date > startOfToday {
                nextBirthday = m
                break
            }
        }

        // Single entry today — additional milestone kinds will each
        // contribute their own future instance in future MVP passes.
        return Array([nextBirthday].compactMap { $0 }.prefix(limit))
    }

    func memoriesToday(forUser userID: UUID?, from posts: [RemotePost], now: Date = Date()) -> [MemoryPost] {
        guard let userID else { return [] }
        let (todayMonth, todayDay, todayYear) = monthDayYear(of: now)
        return posts.compactMap { post -> MemoryPost? in
            guard post.owner_user_id == userID else { return nil }
            let (m, d, y) = monthDayYear(of: post.created_at)
            guard m == todayMonth, d == todayDay, y < todayYear else { return nil }
            let yearsAgo = todayYear - y
            let petName = post.pet?.name ?? "TA"
            return MemoryPost(
                id: post.id,
                post: post,
                yearsAgo: yearsAgo,
                eyebrow: "\(yearsAgo)年前的今天",
                prefillCaption: "和 \(petName) 一起，\(yearsAgo)年了 ❤️"
            )
        }
        .sorted { $0.yearsAgo < $1.yearsAgo }
    }

    // MARK: - Internal date math

    private func birthdayToday(for pet: RemotePet, now: Date) -> Milestone? {
        guard let birthday = pet.birthday else { return nil }
        guard let m = birthdayOn(
            year: Calendar.current.component(.year, from: now),
            for: pet, birthday: birthday, now: now
        ) else { return nil }
        return Calendar.current.isDate(m.date, inSameDayAs: now) ? m : nil
    }

    private func birthdayOn(year: Int, for pet: RemotePet, birthday: Date, now: Date) -> Milestone? {
        let cal = Calendar.current
        let birthComps = cal.dateComponents([.year, .month, .day], from: birthday)
        guard let birthMonth = birthComps.month,
              let birthDay = birthComps.day,
              let birthYear = birthComps.year else { return nil }

        var comps = DateComponents()
        comps.year = year
        comps.month = birthMonth
        comps.day = birthDay
        var date = cal.date(from: comps)
        if date == nil, birthMonth == 2, birthDay == 29 {
            comps.day = 28
            date = cal.date(from: comps)
        }
        guard let resolvedDate = date else { return nil }

        let age = max(0, year - birthYear)
        let isToday = cal.isDate(resolvedDate, inSameDayAs: now)
        let title = isToday
            ? "\(pet.name) 今天 \(age) 岁啦"
            : "\(pet.name) 即将 \(age) 岁"
        let prefill = "\(pet.name) 今天 \(age) 岁啦 🎂"

        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        let idKey = f.string(from: resolvedDate)

        return Milestone(
            id: "\(pet.id.uuidString)-birthday-\(idKey)",
            pet: pet,
            kind: .birthday(years: age),
            date: resolvedDate,
            title: title,
            prefillCaption: prefill
        )
    }

    private func monthDayYear(of date: Date) -> (Int, Int, Int) {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return (c.month ?? 0, c.day ?? 0, c.year ?? 0)
    }
}

