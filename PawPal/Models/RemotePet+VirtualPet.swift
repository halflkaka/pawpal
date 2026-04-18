import SwiftUI

/// Display & seeding helpers for the interactive `VirtualPetView` stage.
///
/// These live on `RemotePet` (not on a single screen) because two screens
/// now render the virtual pet:
///
/// * `ProfileView` — the logged-in user's own pets
/// * `PetProfileView` — any pet opened from the feed / search / contacts
///
/// Keeping one copy avoids the drift that bit us earlier in the project
/// (cats ended up with a different stage than dogs simply because the
/// second call-site forgot to pass `species`). If you change any of these
/// rules, both screens pick up the change automatically.
extension RemotePet {

    /// Friendly Chinese breed label, falling back to species when the
    /// breed field isn't populated. Keeps the virtual pet header readable
    /// when the user skipped the breed field during pet creation.
    var chineseBreed: String {
        let raw = breed?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !raw.isEmpty { return raw }
        switch (species ?? "").lowercased() {
        case "dog":   return "狗狗"
        case "cat":   return "猫咪"
        default:      return species ?? "宠物"
        }
    }

    /// Formats the stored `age_text` as a short Chinese string. `pet.age`
    /// is free-form (users can type "3", "3 岁", "5 years", "6 months"),
    /// so we normalise English units into Chinese and append 岁 when
    /// nothing suggests a unit is already present. See `ProfileView` git
    /// history for the original motivation — we used to emit "5 years 岁".
    var formattedAge: String {
        let raw = age?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !raw.isEmpty else { return "—" }

        let lowered = raw.lowercased()
        let englishReplacements: [(String, String)] = [
            ("years",  "岁"),
            ("year",   "岁"),
            ("yrs",    "岁"),
            ("yr",     "岁"),
            ("months", "个月"),
            ("month",  "个月"),
            ("mos",    "个月"),
            ("weeks",  "周"),
            ("week",   "周"),
            ("days",   "天"),
            ("day",    "天"),
        ]
        if let (token, chinese) = englishReplacements.first(where: { lowered.contains($0.0) }) {
            let numeric = raw
                .replacingOccurrences(of: token, with: "", options: .caseInsensitive)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return numeric.isEmpty ? chinese : "\(numeric) \(chinese)"
        }

        let hasChineseUnit = raw.contains("岁") || raw.contains("月")
            || raw.contains("周") || raw.contains("年") || raw.contains("天")
        return hasChineseUnit ? raw : "\(raw) 岁"
    }

    /// Warm background for the virtual pet stage — varies by breed so
    /// huskies read cool-blue and corgis/shibas read peachy-warm.
    var virtualPetBackground: Color {
        switch DogAvatar.Variant.from(breed: breed) {
        case .husky:
            return Color(red: 0.898, green: 0.925, blue: 0.949)  // #E5ECF2
        case .corgi:
            return Color(red: 1.00, green: 0.878, blue: 0.800)   // #FFE0CC
        case .shiba, .beagle:
            return Color(red: 0.992, green: 0.863, blue: 0.725)  // #FDDCB9
        default:
            return Color(red: 1.00, green: 0.902, blue: 0.800)   // #FFE6CC
        }
    }

    /// Builds the full `VirtualPetState` for this pet given its derived
    /// `PetStats` (from the pet's own posts). Centralising this keeps the
    /// two call-sites identical.
    ///
    /// `accessory` seeds from the persisted `pets.accessory` column so a
    /// pet that was dressed up in a previous session still has its hat /
    /// glasses on when the profile is revisited. Rows from before
    /// migration 014, or rows where the column is NULL, fall back to
    /// `.none`.
    ///
    /// Mood / hunger / energy are now time-aware: rather than pure
    /// functions of post-count, they shift with real elapsed time since
    /// the pet's most recent post and with the current time of day. See
    /// `PetStats.derivedHunger / derivedEnergy / decayedMood` for the
    /// formulas. A pet that hasn't been posted about in 12+ hours will
    /// read a little hungrier and a little less cheerful on the next
    /// visit — the virtual pet feels like it lives between sessions.
    func virtualPetState(stats: PetStats, posts: [RemotePost] = [], now: Date = Date()) -> VirtualPetState {
        let savedAccessory = DogAvatar.Accessory(rawValue: accessory ?? "none") ?? DogAvatar.Accessory.none
        let lastPostAt = PetStats.lastPostAt(in: posts)
        return VirtualPetState(
            name: name,
            breed: chineseBreed,
            age: formattedAge,
            species: species,
            variant: DogAvatar.Variant.from(breed: breed),
            background: virtualPetBackground,
            mood: PetStats.decayedMood(base: stats.happiness, lastPostAt: lastPostAt, now: now),
            hunger: PetStats.derivedHunger(lastPostAt: lastPostAt, now: now),
            energy: PetStats.derivedEnergy(now: now),
            accessory: savedAccessory,
            thought: PetStats.initialThought(for: self, stats: stats)
        )
    }
}

// MARK: - Shared stat-bar and thought helpers

extension PetStats {
    /// Time-based hunger: treat each post as a "meal event" — the pet
    /// was fed & photographed. Hunger starts at 100 right after a post
    /// and decays ~3 points per hour (1 point ≈ 20 min), floored at 20
    /// so a pet with no posts in a week reads "very hungry" without
    /// dropping to zero (which would make the bar look broken).
    ///
    /// A pet with no posts yet sits at a neutral 60 — we don't know
    /// when it was last fed, so free-falling is misleading.
    static func derivedHunger(lastPostAt: Date?, now: Date = Date()) -> Int {
        guard let lastPostAt else { return 60 }
        let hours = now.timeIntervalSince(lastPostAt) / 3600.0
        let raw = 100.0 - (hours * 3.0)
        return max(20, min(100, Int(raw)))
    }

    /// Time-of-day energy: sleepy overnight, peaks mid-afternoon, dips
    /// in the evening. Using a shifted sine so the curve peaks around
    /// 14:00 and bottoms out around 02:00, giving visitors a small
    /// delight — "查看宠物 at midnight → pet is sleeping" reads real.
    ///
    /// Formula: 60 + 30 * sin((hour - 8) * pi/12)
    ///   hour=2  → 60 + 30*sin(-pi/2)     = 30
    ///   hour=8  → 60 + 30*sin(0)         = 60
    ///   hour=14 → 60 + 30*sin(pi/2)      = 90
    ///   hour=20 → 60 + 30*sin(pi)        = 60
    ///
    /// Minutes contribute so the bar ticks smoothly across the hour.
    static func derivedEnergy(now: Date = Date()) -> Int {
        let cal = Calendar(identifier: .gregorian)
        let h = Double(cal.component(.hour, from: now))
        let m = Double(cal.component(.minute, from: now))
        let hour = h + m / 60.0
        let phase = (hour - 8.0) * .pi / 12.0
        let raw = 60.0 + 30.0 * sin(phase)
        return max(20, min(100, Int(raw)))
    }

    /// Mood decays slowly from the base happiness value (derived from
    /// post count + likes) as time since the last post grows. The idea:
    /// a pet that's been posted about recently feels cheerful, a pet
    /// that's been neglected drifts toward neutral.
    ///
    /// Decay rate: -1 point per 6 hours without a post, floor at 30 so
    /// the bar never looks abandoned. No posts yet → return the base
    /// unchanged (happiness baseline already handles that case).
    static func decayedMood(base: Int, lastPostAt: Date?, now: Date = Date()) -> Int {
        guard let lastPostAt else { return base }
        let hours = now.timeIntervalSince(lastPostAt) / 3600.0
        let decay = Int(hours / 6.0)
        return max(30, min(100, base - decay))
    }

    /// Seeds the thought bubble copy. Uses `VirtualPetView.thoughts(for:species:)`
    /// so cats get cat-flavoured copy and other species get their species pool.
    static func initialThought(for pet: RemotePet, stats: PetStats) -> String {
        let pool = VirtualPetView.thoughts(
            for: DogAvatar.Variant.from(breed: pet.breed),
            species: pet.species
        )
        return pool.randomElement() ?? "你好呀~"
    }
}
