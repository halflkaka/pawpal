import Foundation

/// Derived, client-side stats for a pet profile. Computed purely from the
/// `RemotePost` data we already load — no schema changes, no new tables.
///
/// The formulas are calibrated so that the mockup's reference values line
/// up naturally with real data:
///
/// * 24 posts → Level 12 (posts / 2)
/// * 24 posts with a small amount of engagement → 98% happy
/// * 20+ posts → "活力" personality
struct PetStats: Equatable {
    /// Pet experience level. Grows as the owner shares more moments.
    let level: Int

    /// 0–100 "happiness" score. Mixes post activity and engagement so a
    /// well-loved pet reads close to 100%.
    let happiness: Int

    /// Derived personality — displayed in the third stat pill.
    let personality: Personality

    /// Inferred mood from the most recent few posts — drives the
    /// character's expression and the coloured mood chip above the character.
    let mood: PetCharacterMood

    // MARK: - Derived personalities (real, not random)

    enum Personality: Equatable {
        case shy        // 0 posts — the pet is still getting used to the camera
        case gentle     // 1–4 posts
        case playful    // 5–14 posts
        case energetic  // 15+ posts

        /// Chinese label shown on the profile stat pill.
        var chineseLabel: String {
            switch self {
            case .shy:        return "害羞"
            case .gentle:     return "温顺"
            case .playful:    return "活泼"
            case .energetic:  return "活力"
            }
        }

        /// SF Symbol shown alongside the label.
        var systemImage: String {
            switch self {
            case .shy:        return "moon.fill"
            case .gentle:     return "leaf.fill"
            case .playful:    return "sparkles"
            case .energetic:  return "bolt.fill"
            }
        }
    }

    // MARK: - Derivation

    /// Build derived stats from the filtered posts belonging to a single pet.
    static func make(from posts: [RemotePost]) -> PetStats {
        let postCount  = posts.count
        let totalLikes = posts.reduce(0) { $0 + $1.likeCount }

        return PetStats(
            level: derivedLevel(posts: postCount),
            happiness: derivedHappiness(posts: postCount, totalLikes: totalLikes),
            personality: derivedPersonality(posts: postCount),
            mood: derivedMood(from: posts)
        )
    }

    /// The most-recent post timestamp, used as the "last interaction"
    /// anchor for the time-based mood / hunger bars below. Nil when the
    /// pet has no posts yet — the helpers treat nil as "never fed" and
    /// clamp to a neutral mid value instead of free-falling to zero.
    static func lastPostAt(in posts: [RemotePost]) -> Date? {
        posts.map(\.created_at).max()
    }

    // MARK: - Formulas (exposed as static functions so tests can pin them)

    /// Level grows 1-per-2-posts, with a floor of 1 so new pets still feel
    /// like they've "started". 24 posts → Level 12, matching the mockup.
    static func derivedLevel(posts: Int) -> Int {
        max(1, posts / 2)
    }

    /// Happiness starts at a warm 50 baseline (every pet deserves affection),
    /// rises +2 per post, and +1 per like received, clamped to 100. With 24
    /// posts and zero likes the score lands at 98 — exactly the mockup value.
    static func derivedHappiness(posts: Int, totalLikes: Int) -> Int {
        let raw = 50 + posts * 2 + totalLikes
        return min(100, max(0, raw))
    }

    /// Personality thresholds are chosen so a brand-new pet reads "害羞"
    /// (shy) and a pet with a healthy posting cadence reads "活力" (energetic).
    static func derivedPersonality(posts: Int) -> Personality {
        switch posts {
        case 0:           return .shy
        case 1..<5:       return .gentle
        case 5..<15:      return .playful
        default:          return .energetic
        }
    }

    /// Mood is inferred from the most recent five posts. We count which
    /// PawPal mood emoji appears most often and map it to the character
    /// expression. Ties are broken by recency (latest wins).
    static func derivedMood(from posts: [RemotePost]) -> PetCharacterMood {
        guard !posts.isEmpty else { return .happy }

        let recent = posts
            .sorted { $0.created_at > $1.created_at }
            .prefix(5)

        var counts: [String: Int] = [:]
        var lastSeen: [String: Date] = [:]
        for post in recent {
            guard let raw = post.mood?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !raw.isEmpty else { continue }
            counts[raw, default: 0] += 1
            if lastSeen[raw] == nil { lastSeen[raw] = post.created_at }
        }

        guard let topEmoji = counts
            .sorted(by: { (a, b) in
                if a.value != b.value { return a.value > b.value }
                return (lastSeen[a.key] ?? .distantPast) > (lastSeen[b.key] ?? .distantPast)
            })
            .first?.key
        else {
            return .happy
        }

        return mapMoodEmoji(topEmoji)
    }

    /// Maps the emoji set from `CreatePostView` to a character mood.
    /// The emoji set there is: 😊 😍 🤔 😴 🤩 😻 🥰 🎉.
    static func mapMoodEmoji(_ emoji: String) -> PetCharacterMood {
        switch emoji {
        case "😴":         return .sleeping
        case "🤩", "🎉":  return .excited
        case "🤔":         return .chill
        case "😊", "😍", "😻", "🥰":
            return .happy
        default:
            return .happy
        }
    }
}
