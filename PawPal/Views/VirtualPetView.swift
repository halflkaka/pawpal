import SwiftUI

// MARK: - Virtual Pet State

/// Small mutable state container that backs `VirtualPetView`. Kept local to
/// the view — there's no backend mirror yet (see docs/scope.md "Virtual pet").
/// Seed values come from real post counts via `PetStats.make(from:)`.
struct VirtualPetState: Equatable {
    var name: String
    var breed: String
    var age: String
    /// Species string matching `RemotePet.species`. Going forward the
    /// pet editor only offers "Dog" and "Cat" (see #36), but legacy
    /// records may still carry "Rabbit", "Bird", "Hamster", or "Other"
    /// — the thought-pool and renderer fall back gracefully for those.
    /// Nil/empty defaults to Dog for backwards compatibility.
    var species: String? = nil
    var variant: DogAvatar.Variant
    /// Stage background colour (top of the gradient).
    var background: Color
    /// 0-100 mood bar.
    var mood: Int
    /// 0-100 hunger bar.
    var hunger: Int
    /// 0-100 energy bar.
    var energy: Int
    var accessory: DogAvatar.Accessory = .none
    var thought: String = ""

    /// True when the pet should render as a dog (so it uses the
    /// `LargeDog` canvas + accessory chips). All other species fall back
    /// to the curated `PetCharacterView` illustration inside the same
    /// interactive stage.
    var isDog: Bool {
        let trimmed = (species ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.isEmpty { return true }  // legacy callers pre-species
        return trimmed == "dog"
    }

    static let preview = VirtualPetState(
        name: "Biscuit",
        breed: "金毛",
        age: "3 岁",
        species: "Dog",
        variant: .golden,
        background: Color(red: 1.00, green: 0.902, blue: 0.800),
        mood: 86,
        hunger: 62,
        energy: 74,
        accessory: .none,
        thought: "这是零食吗？"
    )
}

// MARK: - VirtualPetView

/// Interactive "virtual pet" stage shown on the Profile screen.
///
/// Tap the pet to boop it (mood +3, heart pops up, spring jump).
/// Feed / Pet / Play update the stats and swap the thought bubble.
/// Bow / Hat / Glasses buttons toggle the avatar's accessory.
struct VirtualPetView: View {
    @State var state: VirtualPetState
    /// The pet this view represents. When non-nil the view plugs into
    /// the shared `VirtualPetStateStore` so the tap counter ("已经摸了
    /// kaka X 下") and feed/pet/play stat deltas stay in sync across
    /// every screen showing the same pet. Left nil for previews where
    /// there's no real pet id to key on — those fall back to view-local
    /// state and the store isn't touched.
    var petID: UUID? = nil
    /// External, parent-owned accessory value. When non-nil, this takes
    /// precedence over `state.accessory` for display and the view syncs
    /// its internal `state.accessory` to any changes via `.onChange`.
    /// This is what makes cross-view sync work: `ProfileView` and
    /// `PetProfileView` both bind this to `pet.accessory` (which in turn
    /// reflects the shared `PetsService` cache). When the owner dresses
    /// up the pet in one view, the cache updates → both views' bound
    /// `externalAccessory` changes → both `VirtualPetView` instances
    /// animate to the new accessory without being re-init'd, so
    /// thoughts / tapCount / breathing state all survive.
    ///
    /// Left nil for preview call sites that don't care about external
    /// sync — those render from `state.accessory` as before.
    var externalAccessory: DogAvatar.Accessory? = nil
    /// Parent-owned mood / hunger / energy values. Same pattern as
    /// `externalAccessory` — both profile screens compute the stats from
    /// the pet's posts + current time via `pet.virtualPetState(stats:posts:)`
    /// and pass the resulting ints in here. `.onChange(initial: true)`
    /// mirrors them into the internal `state` so the bars read the same
    /// number in both views regardless of which one appeared first.
    ///
    /// Without this, the internal `@State var state: VirtualPetState`
    /// latched mood/hunger/energy at first appear and never updated from
    /// subsequent init passes — the exact same latching bug that made
    /// accessory drift (see CHANGELOG #43). Applying the same
    /// controlled-input pattern keeps 心情/饱食/活力 consistent across
    /// `ProfileView` ↔ `PetProfileView` without needing a shared store.
    ///
    /// Left nil for previews (they seed from the hardcoded `.preview`
    /// state and don't care about cross-view sync).
    var externalMood: Int? = nil
    var externalHunger: Int? = nil
    var externalEnergy: Int? = nil
    /// Optional callback so the parent can persist the accessory choice.
    var onAccessoryChanged: ((DogAvatar.Accessory) -> Void)? = nil
    /// Fires once per tap-to-boop. `PetProfileView` uses this to debounce
    /// taps and batch-increment the pet's shared `boop_count` in the
    /// backend (CHANGELOG #38). Owner screens (`ProfileView`) can leave
    /// it nil — booping your own pet doesn't contribute to the public
    /// counter.
    var onBoop: (() -> Void)? = nil
    /// Fires when the owner taps 喂食 / 玩耍 / 摸摸. The parent routes
    /// these through `VirtualPetStateStore.applyAction` so the stat bumps
    /// are persisted and visible in the sibling profile screen too. Left
    /// nil for visitors (only the owner should be able to feed/play/pat).
    var onAction: ((VirtualPetStateStore.PetAction) -> Void)? = nil

    /// Observing the shared store means any change to `tapCounts` or
    /// `petStates` triggers a re-render here — critical so `ProfileView`
    /// and `PetProfileView` both refresh when the other one feeds the
    /// pet. When `petID` is nil (previews) the view reads local state
    /// instead; see `effectiveTapCount` below.
    @ObservedObject private var store = VirtualPetStateStore.shared

    @State private var isJumping = false
    @State private var reactEmoji: String? = nil
    @State private var reactID: Int = 0
    /// Fallback tap counter for previews / call sites that don't pass a
    /// `petID`. Real screens read from `store.tapCount(for:)`.
    @State private var localTapCount = 0
    @State private var thoughtTimerID = UUID()

    /// Unified view into the tap counter: shared store when we have a
    /// pet id, local state otherwise. Both views observing the same pet
    /// id hit the same dict entry, so the "已经摸了 X 下" label counts
    /// up together regardless of which screen is on top.
    private var effectiveTapCount: Int {
        if let petID {
            return store.tapCount(for: petID)
        }
        return localTapCount
    }

    private let thoughtRotationInterval: TimeInterval = 4.5

    var body: some View {
        // Slightly larger outer spacing groups the card into three visual
        // chunks (header / stage+stats / actions) instead of reading as one
        // dense stack. User feedback: "拥挤" (crowded) on the default 14pt
        // spacing at 18pt padding.
        VStack(spacing: 20) {
            headerRow

            // Stage and stats read as a single block (the bars explain the
            // character above them), so they use a tighter internal spacing.
            VStack(spacing: 14) {
                stage
                statsRow
            }

            actionsRow

            if effectiveTapCount > 0 {
                Text(tapCountText)
                    .font(PawPalFont.ui(size: 11))
                    .foregroundStyle(PawPalTheme.tertiaryText)
                    .transition(.opacity)
                    .padding(.top, 2)
            }
        }
        .padding(20)
        .background(PawPalTheme.card, in: RoundedRectangle(cornerRadius: PawPalRadius.xxl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: PawPalRadius.xxl, style: .continuous)
                .stroke(PawPalTheme.hairline, lineWidth: 0.5)
        )
        .shadow(color: PawPalTheme.softShadow, radius: 14, y: 2)
        .task(id: thoughtTimerID) {
            // Rotate the thought every 4.5s
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: UInt64(thoughtRotationInterval * 1_000_000_000))
                if Task.isCancelled { break }
                let pool = Self.thoughts(for: state.variant, species: state.species)
                if let next = pool.randomElement(), next != state.thought {
                    withAnimation(.easeOut(duration: 0.3)) {
                        state.thought = next
                    }
                }
            }
        }
        // Sync internal `state.accessory` to the parent-owned value so
        // cross-view changes (e.g. the owner dressed up the pet in
        // another screen) animate in without re-initialising the view.
        // Without this, `@State var state` latches the accessory at first
        // appear and never updates from subsequent init passes — which
        // was the root of "the virtual pet in pet profile and the normal
        // profile is not in sync".
        //
        // `initial: true` mirrors the incoming value into state the first
        // time the view appears too, so the initial render reads the
        // cache-current accessory even when VirtualPetState was seeded
        // stale (e.g. captured before the optimistic cache write landed).
        .onChange(of: externalAccessory, initial: true) { _, new in
            guard let new, state.accessory != new else { return }
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                state.accessory = new
            }
        }
        // Stats sync: mirror parent-computed mood / hunger / energy into
        // internal state so both profile screens display the same bars
        // for the same pet. See the `externalMood/Hunger/Energy` docs
        // above for rationale. `initial: true` seeds on first appear
        // too — important because the parent may pass newer values than
        // the `state:` init captured.
        .onChange(of: externalMood, initial: true) { _, new in
            guard let new, state.mood != new else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                state.mood = new
            }
        }
        .onChange(of: externalHunger, initial: true) { _, new in
            guard let new, state.hunger != new else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                state.hunger = new
            }
        }
        .onChange(of: externalEnergy, initial: true) { _, new in
            guard let new, state.energy != new else { return }
            withAnimation(.easeOut(duration: 0.3)) {
                state.energy = new
            }
        }
    }

    // MARK: Sections

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("虚拟\(state.name)".uppercased())
                    .font(PawPalFont.ui(size: 11, weight: .semibold))
                    .tracking(0.6)
                    .foregroundStyle(PawPalTheme.secondaryText)
                Text("\(state.breed) · \(state.age)")
                    .font(PawPalFont.ui(size: 13))
                    .foregroundStyle(PawPalTheme.secondaryText)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 12)
            // Breathing room between accessory chips (6 → 8) so the row of
            // three glyphs doesn't read as a single block pushed against the
            // title. 12pt between title and chips keeps the header legible
            // even on narrower screens.
            //
            // Accessory chips are dog-only — the bow/hat/glasses renderers
            // live inside `LargeDog`. For cats/rabbits/birds/etc the stage
            // uses `PetCharacterView`, which has no accessory layer, so
            // hide the chips entirely for non-dog species.
            if state.isDog {
                HStack(spacing: 8) {
                    accessoryButton(label: "🎀", for: .bow)
                    accessoryButton(label: "🎩", for: .hat)
                    accessoryButton(label: "👓", for: .glasses)
                }
            }
        }
    }

    private var stage: some View {
        ZStack(alignment: .top) {
            // Gradient floor
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [state.background, state.background.lightened(by: 0.15)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            // Floor line
            VStack {
                Spacer()
                Rectangle()
                    .fill(Color.white.opacity(0.3))
                    .frame(height: 36)
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(PawPalTheme.hairline)
                            .frame(height: 1)
                    }
            }
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))

            // Pet + reaction emoji — bottom-aligned via Spacer so the
            // extra 30pt of stage height (190 → 220) becomes headroom for
            // the thought bubble, not extra floor.
            //
            // Character is species-aware: dogs render through the custom
            // `LargeDog` canvas (which supports accessories + breed
            // variants); cats/rabbits/birds/hamsters/other fall back to
            // the curated `PetCharacterView` illustration. Both branches
            // use the same tap+bounce mechanics so feed/pet/play and
            // boop-to-tap feel identical regardless of species.
            VStack {
                Spacer()
                ZStack {
                    petCharacter

                    if let emoji = reactEmoji {
                        Text(emoji)
                            .font(.system(size: 36))
                            .offset(y: -90)
                            .modifier(ReactionRiseModifier())
                            .id(reactID)
                    }
                }
            }
            .frame(height: 220)

            // Thought bubble — top-trailing (above-right of the pet).
            // The bubble's tail is at its bottom-LEFT (see `thoughtBubble`
            // below: offset(x:22, y:5) from bottomLeading), so anchoring
            // the bubble to the trailing edge makes the tail point
            // down-and-inward toward the pet's head — the natural cartoon
            // thought-bubble silhouette.
            //
            // Vertical clearance: stage is now 220pt tall. Dog frame
            // (170pt) is bottom-aligned, so dog top sits at y≈50. Hat
            // accessory top is at stage-y≈53. Bubble with padding.top 10
            // + bubble height ~36 reaches down to y≈46 — leaving ~7pt of
            // air between bubble bottom and the tallest accessory.
            if !state.thought.isEmpty {
                thoughtBubble
                    .padding(.top, 10)
                    .padding(.trailing, 24)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .id("thought-\(state.thought)")
            }
        }
        .frame(height: 220)
    }

    /// Character body shown on the stage. Dogs use the purpose-built
    /// `LargeDog` canvas (with accessory + breed variant support); all
    /// other species reuse `PetCharacterView` so cats, rabbits, birds,
    /// hamsters, and generic "other" each get a species-appropriate
    /// illustration without needing a bespoke SwiftUI drawing.
    @ViewBuilder
    private var petCharacter: some View {
        if state.isDog {
            LargeDog(
                variant: state.variant,
                accessory: state.accessory,
                expression: state.energy < 30 ? .sleepy : .happy
            )
            .scaleEffect(
                x: isJumping ? 1.0 : 1.0,
                y: isJumping ? 1.05 : 1.0,
                anchor: .bottom
            )
            .offset(y: isJumping ? -22 : 0)
            .modifier(BreathingModifier(active: !isJumping))
            .onTapGesture(perform: tapPet)
        } else {
            // PetCharacterView has its own internal tap bounce +
            // excited-flash animation, so we route the state update
            // through its `onTap` callback rather than stacking our own
            // onTapGesture on top (which would double up the animation).
            // `size: 170` matches the 180×170 visual footprint of
            // LargeDog so the stage geometry (thought-bubble clearance,
            // floor line) stays calibrated.
            PetCharacterView(
                species: state.species,
                mood: petCharacterMood,
                size: 170,
                onTap: { tapPet() }
            )
            .scaleEffect(
                x: isJumping ? 1.0 : 1.0,
                y: isJumping ? 1.05 : 1.0,
                anchor: .bottom
            )
            .offset(y: isJumping ? -22 : 0)
            .modifier(BreathingModifier(active: !isJumping))
        }
    }

    /// Map the virtual pet's numeric state into a `PetCharacterMood` for
    /// the non-dog renderer. Energy wins when low (character looks sleepy),
    /// otherwise high mood reads as excited, mid-range reads as happy.
    private var petCharacterMood: PetCharacterMood {
        if state.energy < 30 { return .sleeping }
        if state.mood >= 85 { return .excited }
        if state.energy >= 75 { return .energetic }
        if state.mood < 40 { return .chill }
        return .happy
    }

    private var statsRow: some View {
        // Bars were 12pt apart; 16pt reads as three distinct gauges rather
        // than a packed strip. Keeps the 6pt bar height unchanged.
        HStack(alignment: .top, spacing: 16) {
            PawPalStatBar(label: "心情", value: state.mood, color: PawPalTheme.accent)
            PawPalStatBar(label: "饱食", value: state.hunger, color: PawPalTheme.amber)
            PawPalStatBar(label: "活力", value: state.energy, color: PawPalTheme.mint)
        }
    }

    private var actionsRow: some View {
        // Buttons: gap 8 → 10 and tile padding 11 → 14 so each pill looks
        // like a proper tap target instead of a crowded grid cell.
        HStack(spacing: 10) {
            actionButton(icon: "fork.knife", label: "喂食", action: feed)
            actionButton(icon: "pawprint.fill", label: "摸摸", action: pat)
            actionButton(icon: "tennis.racket", label: "玩耍", action: play)
        }
    }

    // MARK: Sub-components

    private var thoughtBubble: some View {
        ZStack(alignment: .bottomLeading) {
            Text(state.thought)
                .font(PawPalFont.ui(size: 13))
                .foregroundStyle(PawPalTheme.primaryText)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.white)
                )
                .shadow(color: Color.black.opacity(0.08), radius: 6, y: 2)

            // Tail
            Rectangle()
                .fill(Color.white)
                .frame(width: 10, height: 10)
                .rotationEffect(.degrees(45))
                .offset(x: 22, y: 5)
                .shadow(color: Color.black.opacity(0.04), radius: 2, y: 1)
        }
        .frame(maxWidth: 160, alignment: .leading)
    }

    private func accessoryButton(label: String, for accessory: DogAvatar.Accessory) -> some View {
        let isActive = state.accessory == accessory
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.6)) {
                state.accessory = isActive ? .none : accessory
            }
            onAccessoryChanged?(state.accessory)
        } label: {
            Text(label)
                .font(.system(size: 16))
                .frame(width: 34, height: 34)
                .background(
                    Circle().fill(isActive ? PawPalTheme.primaryText : PawPalTheme.cardSoft)
                )
                .overlay(
                    Circle().stroke(PawPalTheme.hairline, lineWidth: 0.5)
                )
                .saturation(isActive ? 1.0 : 0.8)
        }
        .buttonStyle(.plain)
    }

    private func actionButton(icon: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(PawPalTheme.primaryText)
                Text(label)
                    .font(PawPalFont.ui(size: 12, weight: .medium))
                    .foregroundStyle(PawPalTheme.primaryText)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: PawPalRadius.md, style: .continuous)
                    .fill(PawPalTheme.subtleSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: PawPalRadius.md, style: .continuous)
                    .stroke(PawPalTheme.hairline, lineWidth: 0.5)
            )
        }
        .buttonStyle(PawPalPressStyle())
    }

    // MARK: Actions

    private func tapPet() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        // Tap counter lives in the shared store so the "已经摸了 X 下"
        // label stays in sync between ProfileView and PetProfileView.
        // Previews (petID nil) keep a local counter so the preview
        // sheet doesn't leak into the real session's store.
        if let petID {
            store.incrementTapCount(petID: petID)
        } else {
            localTapCount += 1
        }
        reactID += 1
        reactEmoji = "❤️"
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
            isJumping = true
        }
        // Stat bars are now parent-driven (see `externalMood/Hunger/Energy`)
        // so local bumps here would immediately drift from the sibling
        // screen's copy. Interaction feedback lives in the heart emoji,
        // jump, and tap-count label — not the mood bar.

        // Notify the parent so it can batch-increment the shared
        // boop_count. We intentionally fire per-tap (not debounced
        // here) — the parent owns the debounce policy so it can flush
        // on view-disappear even for short visits with only 1-2 taps.
        onBoop?()

        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    isJumping = false
                }
            }
            try? await Task.sleep(nanoseconds: 700_000_000)
            await MainActor.run {
                reactEmoji = nil
            }
        }
    }

    // Feed / pet / play now route through `onAction` so the parent can
    // apply the persisted delta via `VirtualPetStateStore` — the store
    // updates both views' bound `externalMood/Hunger/Energy` on the same
    // frame via its `@Published petStates`, so the tapped bar visibly
    // bumps AND the sibling profile screen shows the same value. Local
    // thought-bubble / jump / reaction-emoji updates are cosmetic and
    // stay in the view because they're intentionally per-tap.
    //
    // Calls are no-ops when `onAction` is nil (visitor screens) — the
    // reaction emoji still fires so the button feels responsive, but the
    // stat bars don't move because only the owner can mutate `pet_state`.
    private func feed() {
        showReaction("🍖")
        withAnimation(.easeOut(duration: 0.3)) {
            state.thought = "真香~"
        }
        onAction?(.feed)
    }

    private func pat() {
        showReaction("✨")
        withAnimation(.easeOut(duration: 0.3)) {
            state.thought = "是个乖宝宝"
        }
        onAction?(.pat)
    }

    private func play() {
        showReaction("🎾")
        withAnimation(.spring(response: 0.35, dampingFraction: 0.55)) {
            isJumping = true
        }
        withAnimation(.easeOut(duration: 0.3)) {
            state.thought = "一起玩!"
        }
        onAction?(.play)
        Task {
            try? await Task.sleep(nanoseconds: 500_000_000)
            await MainActor.run {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) {
                    isJumping = false
                }
            }
        }
    }

    private func showReaction(_ emoji: String) {
        reactID += 1
        reactEmoji = emoji
        Task {
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            await MainActor.run {
                reactEmoji = nil
            }
        }
    }

    private var tapCountText: String {
        "已经摸了 \(state.name) \(effectiveTapCount) 下 🐾"
    }

    // MARK: Thought pools

    /// Chinese-localised thought pools, keyed by breed variant. Picked up by
    /// the task loop every few seconds.
    /// Species-aware thought pool. When the pet is a dog we branch on
    /// breed variant for flavour; everything else uses a species-level
    /// pool so cats / rabbits / birds / hamsters / "other" feel
    /// distinct from each other without needing per-breed data.
    static func thoughts(for variant: DogAvatar.Variant, species: String? = nil) -> [String] {
        let normalized = (species ?? "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        switch normalized {
        case "cat":
            return ["想要零食...", "呼噜呼噜", "窗外有鸟!", "抓我抓我", "喵?", "今天也很优雅"]
        case "rabbit":
            return ["跳一跳!", "萝卜呢?", "耳朵动了动", "想出笼子", "窝里最舒服"]
        case "bird":
            return ["啾啾啾!", "今天阳光不错", "想出去飞飞", "梳理羽毛中", "*晨间歌唱*"]
        case "hamster":
            return ["嗑瓜子...", "藏点粮食", "跑轮时间", "腮帮子满了", "偷偷摸摸"]
        case "other":
            return ["今天心情不错", "陪我玩吧", "咦?", "发呆ing", "*小脑袋转转*"]
        case "dog", "":
            // Legacy dog path — branch on breed variant.
            switch variant {
            case .golden:  return ["这是零食吗？", "好喜欢你", "出去玩吗?", "*摇尾巴ing*", "嗨嗨嗨嗨"]
            case .corgi:   return ["溜达溜达溜达", "小短腿能量", "汪!", "我能跳!!", "蝴蝶结激活"]
            case .shiba:   return ["一脸嫌弃", "哼。", "好吧,摸我。", "shibe.", "需要零食"]
            case .husky:   return ["那是松鼠吗", "嗷呜——", "下雪了??", "戏剧性叹气", "跟我跑"]
            case .poodle:  return ["优雅.", "拍照?", "新造型", "高贵地汪", "SPA哪天"]
            case .beagle:  return ["嗅嗅嗅", "吃的?", "那是吃的?", "调查中...", "汪汪汪"]
            case .pug:     return ["zzz...", "呼——噜", "睡觉时间", "*打呼*", "困困的"]
            }
        default:
            // Unknown species string — generic friendly pool.
            return ["今天也很开心", "陪我聊聊~", "想要抱抱", "*发呆ing*", "嗨嗨嗨嗨"]
        }
    }
}

// MARK: - LargeDog

/// Full-body version of `DogAvatar` — head + body + legs + tail + cheek blush.
/// Used on the Virtual Pet stage so the character feels more alive.
struct LargeDog: View {
    var variant: DogAvatar.Variant = .golden
    var accessory: DogAvatar.Accessory = .none
    var expression: DogAvatar.Expression = .happy

    private struct Palette {
        let body: Color
        let ear: Color
        let muzzle: Color
        let belly: Color
        let spot: Color?
    }

    var body: some View {
        let p = palette(for: variant)
        let ink = Color(red: 0.165, green: 0.141, blue: 0.125)
        let blush = Color(red: 1.00, green: 0.702, blue: 0.627)  // #FFB3A0

        return ZStack {
            Canvas { ctx, size in
                let w = size.width
                let h = size.height
                let sx: (CGFloat) -> CGFloat = { $0 / 180.0 * w }
                let sy: (CGFloat) -> CGFloat = { $0 / 170.0 * h }

                // Back legs
                let back1 = Path(roundedRect: CGRect(x: sx(42), y: sy(125), width: sx(22), height: sy(32)), cornerRadius: sx(10))
                ctx.fill(back1, with: .color(p.body))
                let back2 = Path(roundedRect: CGRect(x: sx(116), y: sy(125), width: sx(22), height: sy(32)), cornerRadius: sx(10))
                ctx.fill(back2, with: .color(p.body))

                // Body
                let body = Path(ellipseIn: CGRect(x: sx(38), y: sy(86), width: sx(104), height: sy(68)))
                ctx.fill(body, with: .color(p.body))

                // Belly
                ctx.opacity = 0.7
                let belly = Path(ellipseIn: CGRect(x: sx(54), y: sy(114), width: sx(72), height: sy(36)))
                ctx.fill(belly, with: .color(p.belly))
                ctx.opacity = 1.0

                // Front legs
                let front1 = Path(roundedRect: CGRect(x: sx(66), y: sy(132), width: sx(18), height: sy(28)), cornerRadius: sx(8))
                ctx.fill(front1, with: .color(p.body))
                let front2 = Path(roundedRect: CGRect(x: sx(96), y: sy(132), width: sx(18), height: sy(28)), cornerRadius: sx(8))
                ctx.fill(front2, with: .color(p.body))

                // Paws
                ctx.opacity = 0.8
                let paw1 = Path(ellipseIn: CGRect(x: sx(64), y: sy(155), width: sx(22), height: sy(10)))
                ctx.fill(paw1, with: .color(p.muzzle))
                let paw2 = Path(ellipseIn: CGRect(x: sx(94), y: sy(155), width: sx(22), height: sy(10)))
                ctx.fill(paw2, with: .color(p.muzzle))
                ctx.opacity = 1.0

                // Head
                let head = Path(ellipseIn: CGRect(x: sx(46), y: sy(26), width: sx(88), height: sy(88)))
                ctx.fill(head, with: .color(p.body))

                // Ears
                drawRotatedEllipse(
                    ctx: &ctx,
                    center: CGPoint(x: sx(54), y: sy(52)),
                    rx: sx(15), ry: sy(24),
                    rotation: -20,
                    fill: p.ear
                )
                drawRotatedEllipse(
                    ctx: &ctx,
                    center: CGPoint(x: sx(126), y: sy(52)),
                    rx: sx(15), ry: sy(24),
                    rotation: 20,
                    fill: p.ear
                )
                ctx.opacity = 0.3
                drawRotatedEllipse(
                    ctx: &ctx,
                    center: CGPoint(x: sx(54), y: sy(56)),
                    rx: sx(8), ry: sy(14),
                    rotation: -20,
                    fill: p.body
                )
                drawRotatedEllipse(
                    ctx: &ctx,
                    center: CGPoint(x: sx(126), y: sy(56)),
                    rx: sx(8), ry: sy(14),
                    rotation: 20,
                    fill: p.body
                )
                ctx.opacity = 1.0

                // Spot on head
                if let spot = p.spot {
                    ctx.opacity = 0.9
                    let sp = Path(ellipseIn: CGRect(x: sx(58), y: sy(50), width: sx(24), height: sy(20)))
                    ctx.fill(sp, with: .color(spot))
                    ctx.opacity = 1.0
                }

                // Muzzle
                let muzzle = Path(ellipseIn: CGRect(x: sx(68), y: sy(70), width: sx(44), height: sy(32)))
                ctx.fill(muzzle, with: .color(p.muzzle))

                // Nose
                let nose = Path(ellipseIn: CGRect(x: sx(85), y: sy(76.5), width: sx(10), height: sy(7)))
                ctx.fill(nose, with: .color(ink))

                // Mouth
                var mouthPath = Path()
                mouthPath.move(to: CGPoint(x: sx(90), y: sy(84)))
                mouthPath.addQuadCurve(
                    to: CGPoint(x: sx(84), y: sy(91)),
                    control: CGPoint(x: sx(90), y: sy(90))
                )
                mouthPath.move(to: CGPoint(x: sx(90), y: sy(84)))
                mouthPath.addQuadCurve(
                    to: CGPoint(x: sx(96), y: sy(91)),
                    control: CGPoint(x: sx(90), y: sy(90))
                )
                ctx.stroke(mouthPath, with: .color(ink), style: StrokeStyle(lineWidth: sx(1.8), lineCap: .round))

                if expression == .happy {
                    let tongue = Path(ellipseIn: CGRect(x: sx(86), y: sy(91), width: sx(8), height: sy(6)))
                    ctx.fill(tongue, with: .color(Color(red: 0.933, green: 0.533, blue: 0.533)))
                }

                // Eyes
                if expression == .sleepy {
                    var e1 = Path()
                    e1.move(to: CGPoint(x: sx(72), y: sy(72)))
                    e1.addQuadCurve(to: CGPoint(x: sx(88), y: sy(72)), control: CGPoint(x: sx(80), y: sy(69)))
                    var e2 = Path()
                    e2.move(to: CGPoint(x: sx(92), y: sy(72)))
                    e2.addQuadCurve(to: CGPoint(x: sx(108), y: sy(72)), control: CGPoint(x: sx(100), y: sy(69)))
                    ctx.stroke(e1, with: .color(ink), style: StrokeStyle(lineWidth: sx(3), lineCap: .round))
                    ctx.stroke(e2, with: .color(ink), style: StrokeStyle(lineWidth: sx(3), lineCap: .round))
                } else {
                    let eye1 = Path(ellipseIn: CGRect(x: sx(72.5), y: sy(65.8), width: sx(7), height: sy(8.4)))
                    ctx.fill(eye1, with: .color(ink))
                    let eye2 = Path(ellipseIn: CGRect(x: sx(100.5), y: sy(65.8), width: sx(7), height: sy(8.4)))
                    ctx.fill(eye2, with: .color(ink))
                    let gleam1 = Path(ellipseIn: CGRect(x: sx(76.8), y: sy(66.8), width: sx(2.4), height: sy(2.4)))
                    ctx.fill(gleam1, with: .color(.white))
                    let gleam2 = Path(ellipseIn: CGRect(x: sx(104.8), y: sy(66.8), width: sx(2.4), height: sy(2.4)))
                    ctx.fill(gleam2, with: .color(.white))
                }

                // Cheek blush
                ctx.opacity = 0.4
                let blush1 = Path(ellipseIn: CGRect(x: sx(58), y: sy(79), width: sx(12), height: sy(6)))
                ctx.fill(blush1, with: .color(blush))
                let blush2 = Path(ellipseIn: CGRect(x: sx(110), y: sy(79), width: sx(12), height: sy(6)))
                ctx.fill(blush2, with: .color(blush))
                ctx.opacity = 1.0
            }
            .frame(width: 180, height: 170)

            // Tail — overlaid so we can animate it independently
            Tail(bodyColor: p.body)
                .stroke(p.body, style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .frame(width: 180, height: 170)
                .modifier(TailWagModifier())

            // Accessories
            accessoryView
                .frame(width: 180, height: 170, alignment: .topLeading)
        }
        .frame(width: 180, height: 170)
    }

    @ViewBuilder
    private var accessoryView: some View {
        switch accessory {
        case .none:
            EmptyView()
        case .bow:
            // Right ear is a rotated ellipse centered at (126, 52),
            // rx:15 ry:24 rotated +20° — the outer tip lands near
            // (134, 30). Earlier position (135, 25) sat just above and
            // slightly outside the tip, so the knot looked detached from
            // the ear. (130, 32) nestles the bow onto the ear itself.
            Text("🎀")
                .font(.system(size: 32))
                .position(x: 130, y: 32)
        case .hat:
            // Hat was rendering at 58pt / y:0 which put it floating well
            // above the head (mostly off the top of the 180×170 dog frame)
            // and overlapping the thought bubble. Calibrated to the same
            // scale as the bow: 38pt centered over the head crown. The
            // head ellipse is drawn in sy(26)...sy(114), so y ≈ 22 places
            // the brim right on the forehead.
            Text("🎩")
                .font(.system(size: 38))
                .position(x: 90, y: 22)
        case .glasses:
            HStack(spacing: 2) {
                Circle()
                    .strokeBorder(Color(red: 0.165, green: 0.141, blue: 0.125), lineWidth: 2.5)
                    .background(Circle().fill(Color.white.opacity(0.18)))
                    .frame(width: 26, height: 22)
                Circle()
                    .strokeBorder(Color(red: 0.165, green: 0.141, blue: 0.125), lineWidth: 2.5)
                    .background(Circle().fill(Color.white.opacity(0.18)))
                    .frame(width: 26, height: 22)
            }
            .overlay(
                Rectangle()
                    .fill(Color(red: 0.165, green: 0.141, blue: 0.125))
                    .frame(width: 6, height: 2.5)
            )
            .position(x: 90, y: 70)
        }
    }

    private func palette(for variant: DogAvatar.Variant) -> Palette {
        switch variant {
        case .golden:
            return Palette(
                body:   Color(red: 0.910, green: 0.718, blue: 0.478),
                ear:    Color(red: 0.784, green: 0.604, blue: 0.361),
                muzzle: Color(red: 0.961, green: 0.875, blue: 0.710),
                belly:  Color(red: 0.961, green: 0.875, blue: 0.710),
                spot:   nil
            )
        case .corgi:
            return Palette(
                body:   Color(red: 0.910, green: 0.655, blue: 0.400),
                ear:    .white,
                muzzle: .white,
                belly:  .white,
                spot:   Color(red: 0.910, green: 0.655, blue: 0.400)
            )
        case .husky:
            return Palette(
                body:   Color(red: 0.847, green: 0.847, blue: 0.863),
                ear:    Color(red: 0.227, green: 0.227, blue: 0.227),
                muzzle: .white,
                belly:  .white,
                spot:   Color(red: 0.227, green: 0.227, blue: 0.227)
            )
        case .shiba:
            return Palette(
                body:   Color(red: 0.851, green: 0.565, blue: 0.353),
                ear:    Color(red: 0.722, green: 0.451, blue: 0.251),
                muzzle: Color(red: 0.969, green: 0.894, blue: 0.812),
                belly:  Color(red: 0.969, green: 0.894, blue: 0.812),
                spot:   nil
            )
        case .beagle:
            return Palette(
                body:   Color(red: 0.941, green: 0.882, blue: 0.784),
                ear:    Color(red: 0.482, green: 0.290, blue: 0.165),
                muzzle: .white,
                belly:  .white,
                spot:   Color(red: 0.482, green: 0.290, blue: 0.165)
            )
        case .poodle:
            return Palette(
                body:   Color(red: 0.180, green: 0.165, blue: 0.165),
                ear:    Color(red: 0.180, green: 0.165, blue: 0.165),
                muzzle: Color(red: 0.290, green: 0.271, blue: 0.271),
                belly:  Color(red: 0.290, green: 0.271, blue: 0.271),
                spot:   nil
            )
        case .pug:
            return Palette(
                body:   Color(red: 0.878, green: 0.769, blue: 0.561),
                ear:    Color(red: 0.227, green: 0.180, blue: 0.157),
                muzzle: Color(red: 0.227, green: 0.180, blue: 0.157),
                belly:  Color(red: 0.961, green: 0.875, blue: 0.710),
                spot:   nil
            )
        }
    }

    // MARK: - Canvas helper

    private func drawRotatedEllipse(
        ctx: inout GraphicsContext,
        center: CGPoint,
        rx: CGFloat,
        ry: CGFloat,
        rotation: Double,
        fill: Color
    ) {
        ctx.drawLayer { inner in
            inner.translateBy(x: center.x, y: center.y)
            inner.rotate(by: .degrees(rotation))
            let path = Path(ellipseIn: CGRect(x: -rx, y: -ry, width: rx * 2, height: ry * 2))
            inner.fill(path, with: .color(fill))
        }
    }
}

// MARK: - Tail shape + animations

private struct Tail: Shape {
    let bodyColor: Color
    func path(in rect: CGRect) -> Path {
        var path = Path()
        // Match the design: M 140 120 Q 165 105 160 85 in a 180x170 viewBox
        let sx = rect.width / 180.0
        let sy = rect.height / 170.0
        path.move(to: CGPoint(x: 140 * sx, y: 120 * sy))
        path.addQuadCurve(
            to: CGPoint(x: 160 * sx, y: 85 * sy),
            control: CGPoint(x: 165 * sx, y: 105 * sy)
        )
        return path
    }
}

/// Gentle rotation animation on the tail group.
private struct TailWagModifier: ViewModifier {
    @State private var wagging = false
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(wagging ? 12 : -12), anchor: UnitPoint(x: 142.0 / 180.0, y: 120.0 / 170.0))
            .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: wagging)
            .onAppear { wagging = true }
    }
}

/// Subtle "breathing" scale applied to the pet when idle.
private struct BreathingModifier: ViewModifier {
    let active: Bool
    @State private var breathing = false
    func body(content: Content) -> some View {
        content
            .scaleEffect(
                x: (active && breathing) ? 0.98 : 1.0,
                y: (active && breathing) ? 1.03 : 1.0,
                anchor: .bottom
            )
            .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: breathing)
            .onAppear { breathing = true }
    }
}

/// Rises + fades the reaction emoji.
private struct ReactionRiseModifier: ViewModifier {
    @State private var appeared = false
    func body(content: Content) -> some View {
        content
            .opacity(appeared ? 0.0 : 1.0)
            .offset(y: appeared ? -40 : 0)
            .animation(.easeOut(duration: 1.1), value: appeared)
            .onAppear {
                // Small delay so initial render is at start-state, then animate to end.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) {
                    appeared = true
                }
            }
    }
}

// MARK: - Button style

struct PawPalPressStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.96 : 1.0)
            .animation(.spring(response: 0.25, dampingFraction: 0.7), value: configuration.isPressed)
    }
}

// MARK: - Color helpers

private extension Color {
    /// Returns a paler version of the color by mixing with white.
    func lightened(by amount: Double) -> Color {
        #if canImport(UIKit)
        let ui = UIColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if ui.getRed(&r, green: &g, blue: &b, alpha: &a) {
            let mix = CGFloat(min(max(amount, 0), 1))
            return Color(
                red: r + (1.0 - r) * mix,
                green: g + (1.0 - g) * mix,
                blue: b + (1.0 - b) * mix,
                opacity: a
            )
        }
        #endif
        return self.opacity(1.0 - amount * 0.4)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            VirtualPetView(state: .preview)
            VirtualPetView(state: {
                var s = VirtualPetState.preview
                s.name = "Scout"
                s.breed = "哈士奇"
                s.variant = .husky
                s.energy = 22
                s.background = Color(red: 0.898, green: 0.925, blue: 0.949)
                s.accessory = .glasses
                s.thought = "那是松鼠吗"
                return s
            }())
            // Non-dog species — verifies the shared stage/stats/actions
            // chrome wraps PetCharacterView cleanly, accessory chips are
            // hidden, and the thought pool picks up cat-flavoured copy.
            VirtualPetView(state: {
                var s = VirtualPetState.preview
                s.name = "Mochi"
                s.breed = "橘猫"
                s.species = "Cat"
                s.background = Color(red: 0.965, green: 0.925, blue: 0.875)
                s.accessory = .none
                s.mood = 78
                s.hunger = 55
                s.energy = 68
                s.thought = "呼噜呼噜"
                return s
            }())
        }
        .padding()
    }
    .background(PawPalTheme.background)
}
