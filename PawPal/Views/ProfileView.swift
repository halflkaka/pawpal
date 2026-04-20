import SwiftUI
import PhotosUI
import MapKit

struct ProfileView: View {
    let user: AppUser
    @Bindable var authManager: AuthManager
    @AppStorage("activePetID") private var activePetID = ""
    // Shared with `PetProfileView` so that optimistic local updates on one
    // screen (e.g. tapping the 🎩 chip here) are immediately visible to
    // the other without a Supabase round-trip. See `PetsService.shared`
    // docstring for why we moved off of per-view `@StateObject` instances.
    @ObservedObject private var petsService = PetsService.shared
    /// Shared with `PetProfileView` for tap-count sync and persisted
    /// feed/pet/play stat bumps (migration 015). See
    /// `VirtualPetStateStore` for the full rationale.
    @ObservedObject private var petStateStore = VirtualPetStateStore.shared
    /// Used to derive the pending-invite badge next to "我的约玩". The
    /// same cache drives FeedView's pinned request cards, so the badge
    /// and the feed card stay in lock-step (accept one → both disappear).
    @ObservedObject private var playdateService = PlaydateService.shared
    @State private var showingAddPet = false
    @State private var editingPet: RemotePet?
    @State private var showingEditAccount = false
    @State private var isSavingPet = false
    @State private var isSavingProfile = false
    @State private var pendingDeletePet: RemotePet?
    @State private var profile: RemoteProfile?
    @State private var isLoadingProfile = false
    @State private var profileErrorMessage: String?
    @State private var statusMessage: String?
    @State private var followerCount = 0
    @State private var isLoadingAll = false
    @State private var petToView: RemotePet?
    /// Posts / Tagged tab strip selection (Tagged is a placeholder for now —
    /// no `taggedPosts` backend exists yet; switching tabs shows an empty
    /// state so the affordance is discoverable without faking data).
    @State private var selectedGridTab: GridTab = .posts
    /// Called when the user taps "创建首条帖子" — switches to the Create tab.
    var onCreatePost: (() -> Void)? = nil
    @StateObject private var followService = FollowService()
    @StateObject private var postsService = PostsService()

    enum GridTab: Hashable {
        case posts
        case tagged
    }

    /// Navigation payload for the 关注 / 粉丝 stat cells. Hashable so it
    /// can flow through `.navigationDestination(for:)` on the parent
    /// NavigationStack without needing a separate `@State` toggle.
    struct FollowListDestination: Hashable {
        let mode: FollowListView.Mode
    }

    /// Navigation marker for the "我的约玩" row. Hashable singleton so a
    /// plain `NavigationLink(value:)` can hop into `PlaydatesListView`
    /// through `.navigationDestination(for:)` on the parent stack.
    struct MyPlaydatesDestination: Hashable {}

    private let profileService = ProfileService()

    private var activePet: RemotePet? {
        petsService.pets.first(where: { $0.id.uuidString == activePetID })
            ?? petsService.pets.first
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                profileHeader
                softDivider
                petsBand
                highlightsStrip
                myPlaydatesRow
                if activePet != nil {
                    softDivider
                    featuredPetSection
                }
                softDivider
                postsGrid
            }
        }
        .scrollIndicators(.hidden)
        // HTML ProfileScreen uses `background: '#fff'` (pure white) — distinct
        // from Feed's warm cream. Keeps the profile reading as a clean gallery.
        .background(Color.white)
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) { topBar }
        .task(id: activePetID) {
            // Reload pet-filtered posts whenever the user picks a different pet.
            if let id = activePet?.id { await postsService.loadPetPosts(for: id) }
        }
        .navigationDestination(for: RemotePet.self) { pet in
            PetProfileView(
                pet: pet,
                currentUserID: user.id,
                currentUserDisplayName: accountDisplayName,
                currentUsername: profile?.username,
                authManager: authManager
            )
        }
        .navigationDestination(isPresented: Binding(
            get: { petToView != nil },
            set: { if !$0 { petToView = nil } }
        )) {
            if let pet = petToView {
                PetProfileView(
                    pet: pet,
                    currentUserID: user.id,
                    currentUserDisplayName: accountDisplayName,
                    currentUsername: profile?.username,
                    authManager: authManager
                )
            }
        }
        .navigationDestination(for: RemotePost.self) { post in
            PostDetailView(
                post: post,
                currentUserID: user.id,
                isOwnPost: post.owner_user_id == user.id,
                currentUserDisplayName: accountDisplayName,
                currentUsername: profile?.username,
                postsService: postsService,
                authManager: authManager
            )
        }
        // Follow-list push. Routed through a dedicated value so the
        // stat-cell `NavigationLink` (below) can be a plain tap target
        // without exposing internal construction of `FollowListView`.
        .navigationDestination(for: FollowListDestination.self) { dest in
            FollowListView(
                targetUserID: user.id,
                viewerUserID: user.id,
                authManager: authManager,
                initialMode: dest.mode
            )
        }
        // "我的约玩" push — separate value type so the list can be
        // surfaced from any tap-through on the profile without fighting
        // the pet / post destinations above.
        .navigationDestination(for: MyPlaydatesDestination.self) { _ in
            PlaydatesListView(currentUserID: user.id, authManager: authManager)
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
        .sheet(isPresented: $showingAddPet, onDismiss: { statusMessage = nil }) {
            ProfilePetEditorSheet(
                title: "添加宠物",
                pet: nil,
                isSaving: isSavingPet,
                errorMessage: petsService.errorMessage
            ) { name, species, breed, sex, age, weight, homeCity, bio, birthday, openToPlaydates, avatarData in
                guard !isSavingPet else { return false }
                isSavingPet = true
                defer { isSavingPet = false }
                let saved = await petsService.addPet(
                    for: user.id, name: name, species: species,
                    breed: breed, sex: sex, age: age, weight: weight,
                    homeCity: homeCity, bio: bio,
                    birthday: birthday, avatarData: avatarData
                )
                if let saved {
                    // Persist the user's playdate toggle choice through
                    // the same code path the edit sheet uses. As of
                    // 2026-04-19 the DB default is `true`, so we only
                    // need to round-trip when the user explicitly
                    // toggled OFF during creation; the ON case is a
                    // no-op because the INSERT already wrote `true` via
                    // the column default.
                    if !openToPlaydates {
                        var patched = saved
                        patched.open_to_playdates = false
                        await petsService.updatePet(patched, for: user.id, avatarData: nil)
                    }
                    if activePetID.isEmpty {
                        activePetID = petsService.pets.first?.id.uuidString ?? ""
                    }
                    statusMessage = "已添加宠物"
                    return true
                }
                return false
            }
        }
        .sheet(item: $editingPet, onDismiss: { statusMessage = nil }) { pet in
            ProfilePetEditorSheet(
                title: "编辑宠物",
                pet: pet,
                isSaving: isSavingPet,
                errorMessage: petsService.errorMessage
            ) { name, species, breed, sex, age, weight, homeCity, bio, birthday, openToPlaydates, avatarData in
                guard !isSavingPet else { return false }
                isSavingPet = true
                defer { isSavingPet = false }
                var updated = pet
                updated.name = name; updated.species = species; updated.breed = breed
                updated.sex = sex; updated.age = age; updated.weight = weight
                updated.home_city = homeCity; updated.bio = bio
                updated.birthday = birthday
                updated.open_to_playdates = openToPlaydates
                await petsService.updatePet(updated, for: user.id, avatarData: avatarData)
                if petsService.errorMessage == nil {
                    statusMessage = "已更新宠物"
                    return true
                }
                return false
            }
        }
        .sheet(isPresented: $showingEditAccount, onDismiss: { statusMessage = nil }) {
            ProfileAccountEditorSheet(
                profile: editableProfile,
                fallbackDisplayName: fallbackName,
                isSaving: isSavingProfile,
                errorMessage: profileErrorMessage
            ) { username, displayName, bio, avatarData in
                await saveProfile(username: username, displayName: displayName, bio: bio, avatarData: avatarData)
            }
        }
        .alert("删除宠物？", isPresented: deleteAlertBinding, presenting: pendingDeletePet) { pet in
            Button("删除", role: .destructive) {
                Task {
                    let wasActive = pet.id.uuidString == activePetID
                    await petsService.deletePet(pet.id, for: user.id)
                    if petsService.errorMessage == nil {
                        if wasActive { activePetID = petsService.pets.first?.id.uuidString ?? "" }
                        statusMessage = "已删除宠物"
                    }
                }
            }
            Button("取消", role: .cancel) { pendingDeletePet = nil }
        } message: { pet in
            Text("要删除 \(pet.name) 吗？此操作无法撤销。")
        }
    }

    // MARK: - Top bar

    private var topBar: some View {
        HStack {
            Text("个人主页")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)

            Spacer()

            if let statusMessage {
                Text(statusMessage)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(PawPalTheme.orange)
                    .transition(.opacity)
                    .onAppear {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                            withAnimation { self.statusMessage = nil }
                        }
                    }
            }

            Spacer()

            Menu {
                Button { showingEditAccount = true } label: {
                    Label("编辑账号", systemImage: "person.crop.circle")
                }
                Divider()
                Button(role: .destructive) {
                    authManager.signOut()
                } label: {
                    Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                }
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(PawPalTheme.secondaryText)
                    .frame(width: 36, height: 36)
                    .background(Color.white.opacity(0.72), in: Circle())
                    .shadow(color: PawPalTheme.shadow, radius: 8, y: 3)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial)
    }

    // MARK: - Profile header

    /// The featured pet for the hero block. Prefers the first pet in the
    /// user's list (ordered by created_at desc per `loadPets`, so "first"
    /// is the most recently added). There's no `featured_pet_id` on
    /// `profiles` yet — if/when that lands this helper is the single
    /// place to resolve it. Nil when the user has no pets yet, which
    /// routes the header into the add-your-first-pet CTA.
    private var featuredHeroPet: RemotePet? {
        petsService.pets.first
    }

    private var profileHeader: some View {
        VStack(spacing: 14) {
            // Pet-first hero block. When the user has at least one pet,
            // the top of the profile leads with the featured pet (large
            // avatar + pet name + species/breed pills), with the human
            // identity rendered as a secondary @handle line below. When
            // the user has no pets yet, the whole card becomes an
            // "添加第一只宠物" CTA that opens the same editor as the `+`
            // button on the pets rail — so new accounts have an obvious,
            // single next step from their own profile.
            if let pet = featuredHeroPet {
                petHeroRow(pet)
            } else {
                addFirstPetHeroCard
            }

            // Bio / "about me" line. Surfaces the user's bio if set; otherwise
            // shows a gentle nudge to add one. Tapping either state opens the
            // account editor sheet. Prevents the header from feeling naked
            // when the bio field is empty.
            bioLine

            // Stats row — redacted while the first loadAll() is in flight.
            // Kept in the pet-first layout so social proof stays visible.
            //
            // 粉丝 / 关注 cells are wrapped in a `NavigationLink` so tapping
            // them opens the follow-list view (new in #46). 帖子 / 宠物
            // stay plain because there's no dedicated list screen for
            // those (the posts grid and pets rail are already on this
            // screen). `.buttonStyle(.plain)` keeps the typography flat
            // so the row doesn't suddenly look like two pills + two
            // labels.
            HStack(spacing: 0) {
                statCell(value: "\(postsService.userPosts.count)", label: "帖子")
                statDivider()
                statCell(value: "\(petsService.pets.count)", label: "宠物")
                statDivider()
                NavigationLink(value: FollowListDestination(mode: .followers)) {
                    statCell(value: "\(followerCount)", label: "粉丝")
                }
                .buttonStyle(.plain)
                statDivider()
                NavigationLink(value: FollowListDestination(mode: .following)) {
                    statCell(value: "\(followService.followingIDs.count)", label: "关注")
                }
                .buttonStyle(.plain)
            }
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .redacted(reason: isLoadingAll ? .placeholder : [])

            // Action row. Primary call-to-action is "编辑资料"; secondary chips
            // surface common profile actions. Gives the header something
            // touchable below the stats so it doesn't abruptly terminate.
            headerActionRow
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
        .padding(.bottom, 18)
    }

    // MARK: - Pet-first hero row

    /// Hero block that leads the Me profile when the user has at least
    /// one pet. Pet avatar (72pt) on the left, pet name + species/breed
    /// pill row + owner @handle stacked on the right. The human identity
    /// is intentionally demoted to a small caption line at the bottom
    /// so the pet reads as the protagonist of the screen (see
    /// product.md §Core principles).
    private func petHeroRow(_ pet: RemotePet) -> some View {
        HStack(alignment: .center, spacing: 14) {
            petHeroAvatar(pet)

            VStack(alignment: .leading, spacing: 6) {
                Text(pet.name)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(PawPalTheme.primaryText)
                    .lineLimit(1)

                // Species + breed + (optional) city as a single wrapping
                // pill row. Keeps the hero compact regardless of how much
                // metadata the pet has filled in — if there's only a
                // species the row renders a single pill, no awkward gaps.
                petHeroMetaPills(pet)

                // Owner's @handle (or display name / email fallback) as
                // the demoted secondary line. Small, muted, anchored to
                // the bottom so the hierarchy reads pet-first-human-second
                // at a glance.
                Text(ownerSecondaryLine)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PawPalTheme.tertiaryText)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, 4)
    }

    /// 72pt avatar ring for the hero pet. Uses the pet's photo when set,
    /// otherwise falls back to the same breed-aware DogAvatar / species
    /// glyph used by the pets rail so the hero never renders as a blank
    /// circle.
    @ViewBuilder
    private func petHeroAvatar(_ pet: RemotePet) -> some View {
        let size: CGFloat = 72
        let isDog = (pet.species ?? "").lowercased() == "dog"
        ZStack {
            Circle()
                .stroke(PawPalTheme.accent.opacity(0.25), lineWidth: 2)
                .frame(width: size, height: size)
            if let urlStr = pet.avatar_url, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                            .frame(width: size - 6, height: size - 6)
                            .clipShape(Circle())
                    } else if isDog {
                        DogAvatar(
                            variant: DogAvatar.Variant.from(breed: pet.breed),
                            size: size - 6,
                            background: Color(red: 1.00, green: 0.953, blue: 0.902)
                        )
                    } else {
                        Image(systemName: iconName(for: pet.species ?? ""))
                            .font(.system(size: 30, weight: .medium))
                            .foregroundStyle(PawPalTheme.accent)
                            .frame(width: size - 6, height: size - 6)
                            .background(PawPalTheme.cardSoft, in: Circle())
                    }
                }
            } else if isDog {
                DogAvatar(
                    variant: DogAvatar.Variant.from(breed: pet.breed),
                    size: size - 6,
                    background: Color(red: 1.00, green: 0.953, blue: 0.902)
                )
            } else {
                Image(systemName: iconName(for: pet.species ?? ""))
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(PawPalTheme.accent)
                    .frame(width: size - 6, height: size - 6)
                    .background(PawPalTheme.cardSoft, in: Circle())
            }
        }
        .frame(width: size, height: size)
        .shadow(color: PawPalTheme.softShadow, radius: 10, y: 4)
    }

    /// Species + breed + city as a wrapping pill row. Empty fields are
    /// skipped so a sparsely-filled pet still renders cleanly.
    @ViewBuilder
    private func petHeroMetaPills(_ pet: RemotePet) -> some View {
        HStack(spacing: 6) {
            if let species = pet.species, !species.isEmpty {
                PawPalPill(
                    text: heroSpeciesDisplayName(species),
                    systemImage: "pawprint.fill",
                    tint: PawPalTheme.orange
                )
            }
            if let breed = pet.breed?.trimmingCharacters(in: .whitespacesAndNewlines), !breed.isEmpty {
                PawPalPill(text: breed, systemImage: nil, tint: PawPalTheme.secondaryText)
            }
            if let city = pet.home_city?.trimmingCharacters(in: .whitespacesAndNewlines), !city.isEmpty {
                PawPalPill(text: city, systemImage: "location.fill", tint: PawPalTheme.accent)
            }
        }
    }

    /// Owner's secondary line shown beneath the pet identity. Falls back
    /// through @handle → display name → email so the line is never empty.
    private var ownerSecondaryLine: String {
        if !profileHandle.isEmpty { return profileHandle }
        if !accountDisplayName.isEmpty { return accountDisplayName }
        return user.email ?? "—"
    }

    /// Lowercase-tolerant species → Chinese display-name mapping for the
    /// hero pill. Mirrors the copy used by FeedView / PostDetailView so
    /// the same pet reads the same everywhere.
    private func heroSpeciesDisplayName(_ english: String) -> String {
        switch english.lowercased() {
        case "dog":             return "狗狗"
        case "cat":             return "猫咪"
        case "rabbit", "bunny": return "兔兔"
        case "bird":            return "鸟类"
        case "fish":            return "鱼类"
        case "hamster":         return "仓鼠"
        default:                return english
        }
    }

    /// Full-width CTA rendered in place of the pet hero when the user
    /// has no pets yet. Tapping the card opens the same add-pet editor
    /// as the "+" on the pets rail — giving a brand-new account an
    /// obvious, single next step from their own profile without making
    /// them hunt for the rail's tiny ghost bubble.
    private var addFirstPetHeroCard: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            showingAddPet = true
        } label: {
            HStack(spacing: 14) {
                ZStack {
                    Circle()
                        .fill(PawPalTheme.accentTint)
                        .frame(width: 72, height: 72)
                    Text("🐾")
                        .font(.system(size: 30))
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("添加第一只宠物")
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundStyle(PawPalTheme.primaryText)
                    Text("创建毛孩子的主页，才能发布 TA 的动态")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PawPalTheme.secondaryText)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
                Spacer(minLength: 6)
                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(PawPalTheme.accent)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(PawPalTheme.accentTint)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(PawPalTheme.accent.opacity(0.28), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("add-first-pet-hero-card")
    }

    /// Bio line — either displays the user's bio (wrapped to 2 lines) with an
    /// inline "编辑" affordance, or prompts the user to add one. Prompt state
    /// uses accent tint + sparkles to read as an opportunity, not an error.
    private var bioLine: some View {
        let bio = (profile?.bio ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return Button {
            showingEditAccount = true
        } label: {
            HStack(alignment: .top, spacing: 10) {
                if bio.isEmpty {
                    Image(systemName: "sparkles")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PawPalTheme.accent)
                        .padding(.top, 2)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("给主页加一段介绍吧")
                            .font(.system(size: 13, weight: .semibold, design: .rounded))
                            .foregroundStyle(PawPalTheme.primaryText)
                        Text("一句话告诉大家你和你的毛孩子")
                            .font(.system(size: 11))
                            .foregroundStyle(PawPalTheme.secondaryText)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PawPalTheme.tertiaryText)
                } else {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(PawPalTheme.accent.opacity(0.55))
                        .padding(.top, 4)
                    Text(bio)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(PawPalTheme.primaryText)
                        .lineSpacing(3)
                        .lineLimit(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Image(systemName: "pencil")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(PawPalTheme.tertiaryText)
                        .padding(.top, 3)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(bio.isEmpty ? PawPalTheme.accentTint : PawPalTheme.subtleSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(bio.isEmpty ? PawPalTheme.accent.opacity(0.25) : PawPalTheme.hairline, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile-bio-row")
    }

    /// Primary "编辑资料" pill plus two secondary chips. Uses the share sheet
    /// for "分享主页" (shares a pawpal:// link with the user's handle — harmless
    /// placeholder URL that survives until we stand up real deep-linking).
    private var headerActionRow: some View {
        HStack(spacing: 10) {
            Button { showingEditAccount = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "pencil")
                        .font(.system(size: 12, weight: .bold))
                    Text("编辑资料")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        colors: [PawPalTheme.accent, PawPalTheme.accentSoft],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    in: Capsule()
                )
                .shadow(color: PawPalTheme.accent.opacity(0.28), radius: 10, y: 4)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("edit-profile-button")

            ShareLink(item: shareURLForSelf, message: Text(shareMessage)) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(PawPalTheme.primaryText)
                    .frame(width: 40, height: 40)
                    .background(Color.white.opacity(0.9), in: Circle())
                    .overlay(Circle().stroke(PawPalTheme.hairline, lineWidth: 1))
            }
            .buttonStyle(.plain)
            // Instrumentation: share-tap viral-loop signal for the
            // Me profile surface. Mirrors the post / pet surfaces
            // above; `surface = "profile"` is the dimension.
            .simultaneousGesture(TapGesture().onEnded {
                AnalyticsService.shared.log(.shareTap, properties: ["surface": "profile"])
            })
        }
    }

    /// Deep link for the share sheet. Delegates to `ShareLinkBuilder` so
    /// the URL shape (`pawpal://u/<handle-or-uuid>`) stays in one place.
    /// Works even without real universal-link handling: iOS passes the
    /// URL through as text in Messages / WeChat / 小红书 / etc., and the
    /// `pawpal://` scheme round-trips on devices with the app installed.
    private var shareURLForSelf: URL {
        ShareLinkBuilder.profileURL(handle: profile?.username, userID: user.id)
    }

    private var shareMessage: String {
        ShareLinkBuilder.profileShareMessage(displayName: accountDisplayName)
    }

    /// Reusable user-avatar bubble — used in the compact header.
    /// Falls back to a person glyph when there is no avatar URL or the
    /// image fails to load.
    private func userAvatar(size: CGFloat) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [PawPalTheme.orange, PawPalTheme.orangeSoft],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: size, height: size)
                .shadow(color: PawPalTheme.orange.opacity(0.28), radius: 10, y: 4)
            if let urlStr = profile?.avatar_url, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                            .frame(width: size, height: size)
                            .clipShape(Circle())
                    } else {
                        Image(systemName: "person.fill")
                            .font(.system(size: size * 0.42, weight: .medium))
                            .foregroundStyle(.white)
                    }
                }
            } else {
                Image(systemName: "person.fill")
                    .font(.system(size: size * 0.42, weight: .medium))
                    .foregroundStyle(.white)
            }
        }
    }

    private func statCell(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(size: 19, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func statDivider() -> some View {
        Rectangle()
            .fill(Color(.separator).opacity(0.5))
            .frame(width: 1, height: 28)
    }

    // MARK: - Pets band

    private var petsBand: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("我的宠物")
                    .font(.system(size: 16, weight: .bold, design: .rounded))
                    .foregroundStyle(PawPalTheme.primaryText)

                Spacer()

                Button { showingAddPet = true } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus")
                            .font(.system(size: 12, weight: .bold))
                        Text("添加")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                    }
                    .foregroundStyle(PawPalTheme.orange)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 7)
                    .background(PawPalTheme.orange.opacity(0.1), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("add-pet-button")
            }
            .padding(.horizontal, 20)

            if petsService.isLoading && petsService.pets.isEmpty {
                HStack { ProgressView().padding(.horizontal, 20) }
            } else if petsService.pets.isEmpty {
                Text("还没有宠物，先添加第一只吧！🐾")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 20)
            } else {
                ScrollView(.horizontal) {
                    HStack(spacing: 18) {
                        ForEach(petsService.pets) { pet in
                            petBubble(pet)
                        }
                        // Ghost "+" bubble sits as a peer at the end of the
                        // row so the band never feels half-filled when the
                        // user has only one or two pets. Tapping it opens
                        // the same editor as the "添加" button in the header.
                        addPetGhostBubble
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 6)
                }
                .scrollIndicators(.hidden)
            }

            if let err = petsService.errorMessage {
                Text(err)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 20)
            }
        }
        .padding(.vertical, 20)
    }

    private func petBubble(_ pet: RemotePet) -> some View {
        let isActive = pet.id.uuidString == activePetID
        let isDog = (pet.species ?? "").lowercased() == "dog"
        return VStack(spacing: 8) {
            ZStack {
                // Active accent ring + cream gap (matches the design's
                // selected-pet treatment in the profile picker).
                if isActive {
                    Circle()
                        .stroke(PawPalTheme.accent, lineWidth: 2)
                        .frame(width: 72, height: 72)
                }

                if let urlStr = pet.avatar_url, let url = URL(string: urlStr) {
                    AsyncImage(url: url) { phase in
                        if case .success(let img) = phase {
                            img.resizable().scaledToFill()
                                .frame(width: 64, height: 64)
                                .clipShape(Circle())
                        } else if isDog {
                            DogAvatar(
                                variant: DogAvatar.Variant.from(breed: pet.breed),
                                size: 64,
                                background: Color(red: 1.00, green: 0.953, blue: 0.902)
                            )
                        } else {
                            Image(systemName: iconName(for: pet.species ?? ""))
                                .font(.system(size: 28, weight: .medium))
                                .foregroundStyle(PawPalTheme.accent)
                                .frame(width: 64, height: 64)
                                .background(PawPalTheme.cardSoft, in: Circle())
                        }
                    }
                } else if isDog {
                    DogAvatar(
                        variant: DogAvatar.Variant.from(breed: pet.breed),
                        size: 64,
                        background: Color(red: 1.00, green: 0.953, blue: 0.902)
                    )
                } else {
                    Image(systemName: iconName(for: pet.species ?? ""))
                        .font(.system(size: 28, weight: .medium))
                        .foregroundStyle(PawPalTheme.accent)
                        .frame(width: 64, height: 64)
                        .background(PawPalTheme.cardSoft, in: Circle())
                }
            }
            .frame(width: 72, height: 72)
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)

            Text(pet.name)
                .font(.system(size: 12, weight: isActive ? .bold : .medium, design: .default))
                .foregroundStyle(isActive ? PawPalTheme.primaryText : PawPalTheme.tertiaryText)
                .lineLimit(1)
        }
        .frame(width: 72)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation { activePetID = pet.id.uuidString }
        }
        .contextMenu {
            Button {
                petToView = pet
            } label: {
                Label("查看主页", systemImage: "pawprint.fill")
            }
            Button {
                withAnimation { activePetID = pet.id.uuidString }
            } label: {
                Label("设为当前宠物", systemImage: "star.fill")
            }
            Button { editingPet = pet } label: {
                Label("编辑宠物", systemImage: "pencil")
            }
            Divider()
            Button("删除", role: .destructive) {
                pendingDeletePet = pet
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                pendingDeletePet = pet
            } label: {
                Label("删除", systemImage: "trash")
            }
        }
    }

    /// Dashed-ring ghost bubble rendered at the end of the pets scroll row.
    /// Peer-sized to the real pet bubbles (72pt outer) so single-pet users
    /// see a balanced row rather than a lonely avatar with empty trailing
    /// space. Tapping opens the same add-pet sheet as the header "+ 添加".
    private var addPetGhostBubble: some View {
        Button { showingAddPet = true } label: {
            VStack(spacing: 8) {
                ZStack {
                    Circle()
                        .strokeBorder(
                            PawPalTheme.accent.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1.5, dash: [5, 4])
                        )
                        .frame(width: 72, height: 72)
                    Image(systemName: "plus")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(PawPalTheme.accent)
                }
                Text("添加宠物")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PawPalTheme.secondaryText)
                    .lineLimit(1)
            }
            .frame(width: 72)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("add-pet-ghost-bubble")
    }

    // MARK: - Highlights strip

    /// Three compact cards that give the top of the profile some visual
    /// density without introducing a new backend. Everything here is derived
    /// from data we already load.
    ///
    /// 1. 累计点赞 — sum of `likeCount` across the user's posts.
    /// 2. 最新动态 — relative time of the most recent post ("2小时前" /
    ///    "昨天" / "3天前"); falls back to "尚未发布" when the user has
    ///    no posts yet.
    /// 3. 陪伴天数 — days since the earliest pet's `created_at`. Gives a
    ///    sense of how long the account has been "chronicling" pets.
    private var highlightsStrip: some View {
        HStack(spacing: 10) {
            highlightCard(
                emoji: "💛",
                value: "\(totalLikesAcrossPosts)",
                label: "累计点赞",
                tint: PawPalTheme.red.opacity(0.12)
            )
            highlightCard(
                emoji: "📝",
                value: latestPostRelative,
                label: "最新动态",
                tint: PawPalTheme.accentTint
            )
            highlightCard(
                emoji: "🐾",
                value: companionshipDurationText,
                label: "陪伴天数",
                tint: PawPalTheme.subtleSurface
            )
        }
        .padding(.horizontal, 20)
        .padding(.top, 4)
        .padding(.bottom, 18)
        .redacted(reason: isLoadingAll ? .placeholder : [])
    }

    private func highlightCard(emoji: String, value: String, label: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(emoji)
                .font(.system(size: 18))
            Text(value)
                .font(.system(size: 17, weight: .heavy, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(PawPalTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(tint)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(PawPalTheme.hairline, lineWidth: 1)
        )
    }

    private var totalLikesAcrossPosts: Int {
        postsService.userPosts.reduce(0) { $0 + $1.likeCount }
    }

    private var latestPostRelative: String {
        guard let latest = postsService.userPosts
            .max(by: { $0.created_at < $1.created_at })?.created_at else {
            return "尚未发布"
        }
        let interval = Date().timeIntervalSince(latest)
        let minutes = Int(interval / 60)
        let hours   = Int(interval / 3600)
        let days    = Int(interval / 86400)
        if minutes < 1    { return "刚刚" }
        if minutes < 60   { return "\(minutes)分钟前" }
        if hours   < 24   { return "\(hours)小时前" }
        if days    < 2    { return "昨天" }
        if days    < 30   { return "\(days)天前" }
        let months = days / 30
        if months < 12    { return "\(months)个月前" }
        return "\(months / 12)年前"
    }

    /// Days since the earliest pet was created. 0–1 day reads as "今天";
    /// single digits read as "N天"; larger values render as "N天" up to a
    /// year, then fall back to "一年以上".
    private var companionshipDurationText: String {
        guard let earliest = petsService.pets
            .min(by: { $0.created_at < $1.created_at })?.created_at else {
            return "—"
        }
        let days = max(0, Int(Date().timeIntervalSince(earliest) / 86400))
        if days < 1        { return "今天" }
        if days < 365      { return "\(days)天" }
        return "一年以上"
    }

    /// Softer section separator — the default `Divider()` reads harsh against
    /// the warm PawPal background. Uses the hairline token and a hair of
    /// vertical padding so sections breathe.
    private var softDivider: some View {
        Rectangle()
            .fill(PawPalTheme.hairline)
            .frame(height: 0.5)
            .padding(.horizontal, 20)
    }

    // MARK: - My Playdates row

    /// Pinned "我的约玩" entry point — lives just below the highlights
    /// strip so the flagship pet-to-pet surface is one tap away from
    /// anywhere on the profile. A small warm-yellow badge shows the
    /// count of pending invites where the viewer is the invitee
    /// (mirrors the pinned request-card count on FeedView, so the two
    /// surfaces agree on "how many things need my attention").
    private var myPlaydatesRow: some View {
        NavigationLink(value: MyPlaydatesDestination()) {
            HStack(spacing: 12) {
                // Icon tile — warm peach wash + calendar glyph. Same
                // size + shape as the highlight cards above so the row
                // visually continues the strip's rhythm.
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(PawPalTheme.accentTint)
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(PawPalTheme.accent)
                }
                .frame(width: 36, height: 36)

                VStack(alignment: .leading, spacing: 2) {
                    Text("我的约玩")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundStyle(PawPalTheme.primaryText)
                    Text("查看发出的和收到的约玩邀请")
                        .font(.system(size: 11))
                        .foregroundStyle(PawPalTheme.secondaryText)
                        .lineLimit(1)
                }

                Spacer(minLength: 8)

                if pendingInviteCount > 0 {
                    Text("\(pendingInviteCount)")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .foregroundStyle(PawPalTheme.primaryText)
                        .frame(minWidth: 18, minHeight: 18)
                        .padding(.horizontal, 5)
                        .background(PawPalTheme.amber, in: Capsule())
                }

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(PawPalTheme.tertiaryText)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(PawPalTheme.subtleSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(PawPalTheme.hairline, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(TapGesture().onEnded {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        })
        .padding(.horizontal, 20)
        .padding(.top, 2)
        .padding(.bottom, 14)
    }

    /// Count of `proposed` playdate rows where the current user is the
    /// invitee. Drives the badge on the "我的约玩" row. Re-derives on
    /// every `PlaydateService` publication, so accept/decline taps
    /// anywhere in the app clear the badge without a reload.
    private var pendingInviteCount: Int {
        playdateService.playdates.values.reduce(0) { acc, row in
            acc + (row.status == .proposed && row.invitee_user_id == user.id ? 1 : 0)
        }
    }

    // MARK: - Featured pet section

    /// Derived stats for the currently-selected pet. Recomputed whenever
    /// `postsService.petPosts` changes because `PetStats.make` is cheap.
    private var activePetStats: PetStats {
        PetStats.make(from: postsService.petPosts)
    }

    /// The centerpiece of the redesigned profile. For dogs we show the new
    /// `VirtualPetView` stage with mood/hunger/energy bars. The stage is
    /// species-agnostic: dogs render through the `LargeDog` canvas (with
    /// accessory chips), other species route the same interactive chrome
    /// (feed/pet/play, stats, thought bubble, tap-to-boop) around a
    /// `PetCharacterView` illustration. This means a newly-created cat
    /// gets the same playable experience as a dog — just with a cat
    /// visual and cat-flavoured thought copy.
    @ViewBuilder
    private var featuredPetSection: some View {
        if let pet = activePet {
            // Seed values derived from the real PetStats so a newly-
            // created pet still reads plausibly, and a pet with many
            // posts lands near the design's reference numbers. The
            // full seeding logic lives on `RemotePet` (see
            // `RemotePet+VirtualPet.swift`) and is shared with
            // `PetProfileView` so both screens stay in lock-step.
            // Owner-only call site: persist the dress-up choice back to
            // `pets.accessory` (migration 014) so the bow / hat / glasses
            // is still there on relaunch. No `onBoop` — booping your own
            // pet shouldn't inflate the public boop counter.
            //
            // Compute the seed state once and reuse it for both the
            // `state:` init param AND the external stat bindings so
            // the two are guaranteed to agree on the same snapshot of
            // (posts + time).
            let vpState = pet.virtualPetState(
                stats: activePetStats,
                posts: postsService.petPosts
            )
            // Prefer the persisted `pet_state` snapshot over the time-
            // derived baseline so the owner's feed / pet / play taps
            // actually move the bars AND stay moved across restart. When
            // no row exists yet (new pet, pre-migration) the snapshot is
            // nil and we fall back to the baseline values computed above.
            let persisted = petStateStore.state(for: pet.id)
            let displayMood   = persisted?.mood   ?? vpState.mood
            let displayHunger = persisted?.hunger ?? vpState.hunger
            let displayEnergy = persisted?.energy ?? vpState.energy
            VirtualPetView(
                state: vpState,
                // Keying the shared store on the pet id lets both views
                // display the same tap counter and stat bars. See
                // `VirtualPetStateStore` for the full rationale.
                petID: pet.id,
                // Parent-owned accessory so a change in `PetProfileView`
                // (which shares `PetsService.shared`) flows back here
                // automatically via the bound `pet.accessory`. Without
                // this, `VirtualPetView`'s `@State` would latch the
                // accessory at first appear and the two screens would
                // drift apart.
                externalAccessory: DogAvatar.Accessory(rawValue: pet.accessory ?? "none") ?? DogAvatar.Accessory.none,
                // Stat bars: feed these from the persisted snapshot when
                // we have one, otherwise from the time-derived baseline.
                // `VirtualPetStateStore` updates `petStates` optimistically
                // on feed/pet/play so the bar animates on the same tick
                // the owner taps the button.
                externalMood: displayMood,
                externalHunger: displayHunger,
                externalEnergy: displayEnergy,
                onAccessoryChanged: { accessory in
                    Task {
                        await petsService.updatePetAccessory(
                            petID: pet.id,
                            ownerID: user.id,
                            accessory: accessory.rawValue
                        )
                    }
                },
                onAction: { action in
                    Task {
                        await petStateStore.applyAction(
                            action,
                            petID: pet.id,
                            baseline: (vpState.mood, vpState.hunger, vpState.energy)
                        )
                    }
                }
            )
                .id(pet.id)  // reset state only when user switches pets
                .padding(.horizontal, 20)
                .padding(.vertical, 20)
                .task(id: pet.id) {
                    // Lazy-load the persisted snapshot the first time we
                    // render this pet. Keyed on pet.id so switching the
                    // active pet refetches instead of showing stale data.
                    await petStateStore.loadIfNeeded(petID: pet.id)
                }
        }
    }

    /// Mood chip shown above the character. Uses the mood's own tint so
    /// "energetic" reads yellow, "sleeping" reads muted, etc.
    private func moodChip(for mood: PetCharacterMood) -> some View {
        HStack(spacing: 6) {
            Image(systemName: mood.systemImage)
                .font(.system(size: 11, weight: .bold))
            Text(mood.chineseLabel)
                .font(.system(size: 13, weight: .bold, design: .rounded))
        }
        .foregroundStyle(PawPalTheme.primaryText)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(mood.tint.opacity(0.35), in: Capsule())
        .overlay(Capsule().stroke(mood.tint.opacity(0.5), lineWidth: 1))
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: mood)
    }

    /// Stat pill with a leading SF Symbol. Used for happiness (heart) and
    /// personality (bolt/leaf/etc).
    private func statPillSymbol(symbol: String, label: String, symbolTint: Color) -> some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(symbolTint)
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.92), in: Capsule())
        .overlay(Capsule().stroke(PawPalTheme.shadow, lineWidth: 1))
        .shadow(color: PawPalTheme.softShadow, radius: 4, y: 2)
    }

    /// Stat pill with a leading emoji. The mockup uses a bone emoji for the
    /// Level pill, which SF Symbols cannot match cleanly.
    private func statPillEmoji(emoji: String, label: String) -> some View {
        HStack(spacing: 5) {
            Text(emoji)
                .font(.system(size: 12))
            Text(label)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.white.opacity(0.92), in: Capsule())
        .overlay(Capsule().stroke(PawPalTheme.shadow, lineWidth: 1))
        .shadow(color: PawPalTheme.softShadow, radius: 4, y: 2)
    }

    // MARK: - Posts grid

    private var postsGrid: some View {
        VStack(spacing: 0) {
            // Thin section band that separates the pet stage from the grid.
            // Mirrors the prototype's `#FAF7F4` hairline divider strip.
            Rectangle()
                .fill(PawPalTheme.subtleSurface)
                .frame(height: 8)
                .overlay(alignment: .top) {
                    Rectangle().fill(PawPalTheme.hairline).frame(height: 0.5)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(PawPalTheme.hairline).frame(height: 0.5)
                }

            // Posts / Tagged tab strip. The active tab has an accent
            // underline; inactive tab is muted.
            HStack(spacing: 0) {
                gridTab(
                    title: "Posts",
                    icon: "square.grid.3x3",
                    tab: .posts
                )
                gridTab(
                    title: "Tagged",
                    icon: "tag",
                    tab: .tagged
                )
            }
            .overlay(alignment: .bottom) {
                Rectangle().fill(PawPalTheme.hairline).frame(height: 0.5)
            }

            // Caption row: "Showing N posts of {petName}". Only surfaced
            // for the Posts tab — Tagged has its own empty state.
            if selectedGridTab == .posts, let pet = activePet {
                HStack(spacing: 4) {
                    Text("共 ")
                        .foregroundStyle(PawPalTheme.secondaryText)
                    Text("\(postsService.petPosts.count)")
                        .fontWeight(.bold)
                        .foregroundStyle(PawPalTheme.primaryText)
                    Text(" 条 ")
                        .foregroundStyle(PawPalTheme.secondaryText)
                    Text(pet.name)
                        .fontWeight(.bold)
                        .foregroundStyle(PawPalTheme.primaryText)
                    Text(" 的帖子")
                        .foregroundStyle(PawPalTheme.secondaryText)
                    Spacer()
                }
                .font(.system(size: 11))
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 6)
            }

            // Content for the active tab.
            Group {
                switch selectedGridTab {
                case .posts:
                    postsTabContent
                case .tagged:
                    taggedTabContent
                }
            }
        }
    }

    /// A single tab pill in the Posts/Tagged strip. Selected state has an
    /// accent underline and primary-ink text; inactive state is muted.
    private func gridTab(title: String, icon: String, tab: GridTab) -> some View {
        let selected = selectedGridTab == tab
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selectedGridTab = tab }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } label: {
            VStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: selected ? .semibold : .regular))
                    Text(title)
                        .font(.system(size: 13, weight: selected ? .semibold : .regular))
                }
                .foregroundStyle(selected ? PawPalTheme.primaryText : PawPalTheme.secondaryText)

                Rectangle()
                    .fill(selected ? PawPalTheme.accent : Color.clear)
                    .frame(height: 2)
            }
            .padding(.top, 12)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Real Posts tab content — delegates to the existing
    /// loading / empty / grid branches.
    @ViewBuilder
    private var postsTabContent: some View {
        let activePetPosts = postsService.petPosts
        let isLoadingPetPosts = postsService.isLoadingPetPosts

        if activePet == nil {
            noPetSelectedState
        } else if isLoadingPetPosts && activePetPosts.isEmpty {
            postsLoadingSkeleton
        } else if activePetPosts.isEmpty {
            emptyPostsState
        } else {
            realPostsGrid
        }
    }

    /// Tagged tab content — placeholder while we wait for a tagged-posts
    /// backend. Matches the design's "No posts of X yet" empty state.
    private var taggedTabContent: some View {
        VStack(spacing: 10) {
            Image(systemName: "tag")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(PawPalTheme.tertiaryText)
            Text("还没有被标记的帖子")
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)
            Text("当朋友在帖子中 @ 你的宠物时，会出现在这里")
                .font(.system(size: 12))
                .foregroundStyle(PawPalTheme.secondaryText)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
        .padding(.horizontal, 32)
    }

    /// Shown when the user has no pets yet — nudges them toward adding one.
    private var noPetSelectedState: some View {
        VStack(spacing: 10) {
            Text("还没有选中的宠物")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)
            Text("添加一只宠物，开启 TA 的主页")
                .font(.system(size: 13))
                .foregroundStyle(PawPalTheme.secondaryText)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    // MARK: - Posts loading skeleton

    /// Instagram-style 3-column skeleton. Square tiles with a hair gap to
    /// match the design's `gap: 3` grid.
    private var postsLoadingSkeleton: some View {
        LazyVGrid(columns: gridColumns, spacing: 3) {
            ForEach(0..<9, id: \.self) { _ in
                Rectangle()
                    .fill(PawPalTheme.cardSoft)
                    .aspectRatio(1, contentMode: .fill)
            }
        }
        .padding(.horizontal, 0)
        .padding(.vertical, 8)
        .redacted(reason: .placeholder)
    }

    /// Shared columns for the 3-column tile grid.
    private var gridColumns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 3),
            GridItem(.flexible(), spacing: 3),
            GridItem(.flexible(), spacing: 3)
        ]
    }

    // MARK: - Empty posts state

    private var emptyPostsState: some View {
        let petName = activePet?.name ?? "宠物"
        return VStack(spacing: 16) {
            Text("\(petName) 还没有帖子")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)
                .padding(.top, 24)
            Text("分享 TA 的日常，留下一段美好回忆吧")
                .font(.system(size: 14))
                .foregroundStyle(PawPalTheme.secondaryText)
                .multilineTextAlignment(.center)
            VStack(spacing: 12) {
                Button {
                    onCreatePost?()
                } label: {
                    actionCard(
                        icon: "square.and.pencil",
                        title: "为 \(petName) 发第一条",
                        subtitle: "去发布页分享 TA 的精彩时刻",
                        color: PawPalTheme.orange
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
        }
    }

    private func actionCard(icon: String, title: String, subtitle: String, color: Color) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 44, height: 44)
                .background(color, in: Circle())
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(PawPalTheme.primaryText)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(PawPalTheme.secondaryText)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.system(size: 14))
                .foregroundStyle(PawPalTheme.tertiaryText)
        }
        .padding(12)
        .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .shadow(color: PawPalTheme.shadow, radius: 8, y: 4)
    }

    /// Instagram-style 3-up grid of square tiles. No card chrome — the
    /// photo is the tile, with a like badge in the bottom-left corner.
    private var realPostsGrid: some View {
        LazyVGrid(columns: gridColumns, spacing: 3) {
            ForEach(postsService.petPosts) { post in
                NavigationLink(value: post) {
                    profilePostTile(post)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 0)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }

    /// Square tile for the 3-column profile grid. Shows the first photo
    /// (or a placeholder) with a like-count overlay.
    private func profilePostTile(_ post: RemotePost) -> some View {
        let hasImage = post.imageURLs.first != nil
        // Use the `Color.clear.aspectRatio(..., .fit).overlay { … }` idiom
        // to guarantee the tile is exactly 1:1 and never proposes a larger
        // size to its content. The previous `.aspectRatio(1, contentMode:
        // .fill)` on the outer ZStack let the photo render taller/wider
        // than the cell (you could see pink flowers leaking into the
        // adjacent "Image test" tile). Overlay + .clipped here prevents
        // that.
        //
        // Two separate overlays (content, then badge) instead of a ZStack
        // inside a single overlay. The ZStack approach relied on
        // `.bottomLeading` alignment to pin the badge, but `scaledToFill`
        // on the image could grow the ZStack's effective bounds past the
        // tile frame, which pushed the badge into negative x on photo
        // tiles and left only the right edge visible (exactly the "`2`
        // with missing heart + pill" artefact reported in #45 follow-up).
        // Anchoring the badge to the outer `Color.clear` via
        // `.overlay(alignment: .bottomLeading)` binds it to the tile's
        // frame, not the content layer's.
        return Color.clear
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                Group {
                    if let imageURL = post.imageURLs.first {
                        AsyncImage(url: imageURL) { phase in
                            switch phase {
                            case .success(let image):
                                image
                                    .resizable()
                                    .scaledToFill()
                            case .failure:
                                profileTilePlaceholder(icon: "photo")
                            default:
                                profileTilePlaceholder(icon: nil)
                            }
                        }
                    } else {
                        // Text-only tile: no placeholder icon (previously a
                        // big `text.alignleft` glyph sat behind the caption
                        // and read as broken/loading UI). Clean cardSoft
                        // fill with a small accent quote glyph + the caption
                        // itself, clipped to the square so long captions
                        // truncate gracefully.
                        textOnlyProfileTile(caption: post.caption)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()
            }
            .overlay(alignment: .bottomLeading) {
                // Like-count badge — translucent dark pill so it stays
                // legible over both photo tiles (previously white-on-
                // photo) and the new text-only tiles (previously
                // invisible white-on-cream).
                //
                // Only rendered when the post has at least one like: a
                // zero-state "♥ 0" overlay was both visually noisy and
                // drew the eye to the absence of engagement.
                if post.likeCount > 0 {
                    HStack(spacing: 3) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text(formatCount(post.likeCount))
                            .font(.system(size: 10, weight: .bold))
                            .fixedSize(horizontal: true, vertical: false)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 5)
                    .background(
                        Capsule(style: .continuous)
                            .fill(Color.black.opacity(hasImage ? 0.5 : 0.55))
                    )
                    .padding(.leading, 6)
                    .padding(.bottom, 6)
                }
            }
            .clipped()
            .contentShape(Rectangle())
    }

    /// Text-only post tile body — soft gradient fill with a tinted quote
    /// glyph and the caption rendered as the hero of the tile. Caption is
    /// clipped to 5 lines and horizontally constrained so the last line
    /// never runs under the like-count badge.
    private func textOnlyProfileTile(caption: String) -> some View {
        // Solid `cardSoft` fill. Previously used a LinearGradient that
        // faded to `cardSoft.opacity(0.7)` at the bottom-right for depth,
        // but the translucency revealed whatever was behind the grid and
        // made tiles read as slightly dirty. A flat fill is cleaner on
        // any parent background.
        Rectangle()
            .fill(PawPalTheme.cardSoft)
            .overlay(alignment: .topLeading) {
                VStack(alignment: .leading, spacing: 6) {
                    Image(systemName: "quote.opening")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(PawPalTheme.accent)
                    // 11.5pt is a hair smaller than 12 — on the square
                    // tile this fits ~9 CJK glyphs per line instead of 8,
                    // so captions like "如果我发一条纯文字，特别长的动态怎么办呢"
                    // wrap in 3 lines instead of 4. 6-line clamp gives a
                    // little more breathing room before truncation.
                    Text(caption)
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(PawPalTheme.primaryText)
                        .multilineTextAlignment(.leading)
                        .lineLimit(6)
                        .truncationMode(.tail)
                        // Reserve space on the bottom so the badge never
                        // sits under the caption's last line.
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 11)
                .padding(.top, 11)
                .padding(.bottom, 28)
            }
    }

    private func profileTilePlaceholder(icon: String?) -> some View {
        Rectangle()
            .fill(PawPalTheme.cardSoft)
            .overlay {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(PawPalTheme.tertiaryText)
                } else {
                    ProgressView()
                }
            }
    }

    /// Compact like-count formatter for tile badges (e.g. 1240 → "1.2k").
    private func formatCount(_ value: Int) -> String {
        if value >= 1000 {
            let k = Double(value) / 1000.0
            return String(format: "%.1fk", k)
        }
        return "\(value)"
    }

    // MARK: - Helpers

    private func loadAll() async {
        isLoadingAll = true
        defer { isLoadingAll = false }
        async let profileTask: () = loadProfile()
        async let petsTask: () = petsService.loadPets(for: user.id)
        async let followsTask: () = followService.loadFollowing(for: user.id)
        async let postsTask: () = postsService.loadUserPosts(for: user.id)
        async let followerTask: Int = followService.followerCount(for: user.id)
        let (_, _, _, _, loadedFollowerCount) = await (profileTask, petsTask, followsTask, postsTask, followerTask)
        followerCount = loadedFollowerCount
        if activePetID.isEmpty, let first = petsService.pets.first {
            activePetID = first.id.uuidString
        }
        // Load per-pet posts for the resolved active pet. This ensures the
        // grid populates on first mount even when `activePetID` was already
        // persisted in AppStorage (in which case the `.task(id:)` observer
        // would not refire on launch since the id didn't change).
        if let id = activePet?.id {
            await postsService.loadPetPosts(for: id)
        }
    }

    private func loadProfile() async {
        isLoadingProfile = true
        profileErrorMessage = nil
        defer { isLoadingProfile = false }
        do {
            profile = try await profileService.loadProfile(for: user.id)
        } catch {
            profileErrorMessage = error.localizedDescription
        }
    }

    private func saveProfile(username: String, displayName: String, bio: String, avatarData: Data? = nil) async -> Bool {
        guard !isSavingProfile else { return false }
        isSavingProfile = true
        profileErrorMessage = nil
        defer { isSavingProfile = false }
        do {
            profile = try await profileService.saveProfile(
                for: user.id, username: username, displayName: displayName, bio: bio,
                currentAvatarURL: profile?.avatar_url, avatarData: avatarData
            )
            await authManager.refreshCurrentProfile()
            statusMessage = "账号已更新"
            return true
        } catch {
            profileErrorMessage = error.localizedDescription
            return false
        }
    }

    private var accountDisplayName: String {
        let dn = profile?.display_name?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dn, !dn.isEmpty { return dn }
        return user.displayName ?? fallbackName
    }

    private var profileHandle: String {
        if let username = trimmed(profile?.username) { return "@\(username)" }
        return ""
    }

    private var editableProfile: RemoteProfile {
        profile ?? RemoteProfile(id: user.id, username: nil, display_name: user.displayName, bio: nil, avatar_url: nil)
    }

    private var deleteAlertBinding: Binding<Bool> {
        Binding(get: { pendingDeletePet != nil }, set: { if !$0 { pendingDeletePet = nil } })
    }

    private var fallbackName: String {
        user.email?.components(separatedBy: "@").first ?? "用户"
    }

    private func iconName(for species: String) -> String {
        switch species.lowercased() {
        case "cat":   return "cat.fill"
        case "other": return "pawprint.circle.fill"
        default:      return "dog.fill"
        }
    }

    private func trimmed(_ value: String?) -> String? {
        guard let value else { return nil }
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return cleaned.isEmpty ? nil : cleaned
    }
}

// MARK: - Pet Editor Sheet

private struct ProfilePetEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var species: String
    @State private var breed: String
    @State private var sex: String
    @State private var ageValue: String
    @State private var ageUnit: String
    @State private var weightValue: String
    @State private var weightUnit: String
    @State private var homeCity: String
    @State private var bio: String
    @State private var birthday: Date?
    @State private var showingBirthdayPicker = false
    @State private var pickedAvatarItem: PhotosPickerItem?
    @State private var showingLocationPicker = false
    @State private var pickedAvatarData: Data?
    @State private var pickedAvatarImage: Image?
    /// Playdate opt-in — defaults to whatever the pet row carries
    /// (false for newly added pets / legacy rows without the column).
    /// Wired into the onSave closure below so `PetsService.updatePet`
    /// persists the toggle alongside the rest of the profile fields.
    @State private var openToPlaydates: Bool

    private let ageUnits    = ["岁", "个月"]
    private let weightUnits = ["公斤", "斤"]
    // Only Dog and Cat are offered when creating or editing a pet. The
    // virtual-pet stage has dedicated illustrations + interactions for
    // both species (`LargeDog` + `PetCharacterView.Cat`), whereas
    // rabbit/bird/hamster/other were previously selectable but had no
    // matching interactive experience. Narrowing the picker matches what
    // the app actually supports end-to-end. Legacy pets with other
    // species strings still render correctly via the defensive
    // fallbacks in FeedView / PetCharacterView / PostDetailView — we
    // just don't offer those choices at creation time anymore.
    private let speciesOptions: [(emoji: String, label: String)] = [
        ("🐶", "Dog"), ("🐱", "Cat")
    ]

    let title: String
    let existingAvatarURL: String?
    let isSaving: Bool
    let errorMessage: String?
    /// onSave arg order matches the textual form layout: basic fields,
    /// then birthday, then the playdate opt-in, then the optional
    /// avatar bytes. The `Bool` slot was inserted between `birthday` and
    /// `pickedAvatarData` when the playdates MVP landed — mirroring the
    /// pattern that added `birthday` itself earlier.
    let onSave: (String, String, String, String, String, String, String, String, Date?, Bool, Data?) async -> Bool

    init(
        title: String, pet: RemotePet?, isSaving: Bool,
        errorMessage: String?,
        onSave: @escaping (String, String, String, String, String, String, String, String, Date?, Bool, Data?) async -> Bool
    ) {
        self.title            = title
        self.existingAvatarURL = pet?.avatar_url
        self.isSaving         = isSaving
        self.errorMessage     = errorMessage
        self.onSave           = onSave
        _name     = State(initialValue: pet?.name ?? "")
        _species  = State(initialValue: pet?.species?.isEmpty == false ? pet!.species! : "Dog")
        _breed    = State(initialValue: pet?.breed ?? "")
        _sex      = State(initialValue: pet?.sex ?? "")
        _homeCity = State(initialValue: pet?.home_city ?? "")
        _bio      = State(initialValue: pet?.bio ?? "")
        _birthday = State(initialValue: pet?.birthday)
        // Default `true` on 2026-04-19 — matches the DB default flipped
        // in migration 023. Legacy rows (nil column) show as on too;
        // they'll be persisted as `true` on the next save. See
        // docs/decisions.md → "Playdates are opt-out (default on)".
        _openToPlaydates = State(initialValue: pet?.open_to_playdates ?? true)
        let ageUnits_    = ["岁", "个月"]
        let weightUnits_ = ["公斤", "斤"]
        let parsedAge    = Self.splitMeasurement(pet?.age,    fallbackUnit: "岁")
        _ageValue    = State(initialValue: parsedAge.value)
        _ageUnit     = State(initialValue: ageUnits_.contains(parsedAge.unit)    ? parsedAge.unit    : "岁")
        let parsedWeight = Self.splitMeasurement(pet?.weight, fallbackUnit: "公斤")
        _weightValue = State(initialValue: parsedWeight.value)
        _weightUnit  = State(initialValue: weightUnits_.contains(parsedWeight.unit) ? parsedWeight.unit : "公斤")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {

                        // MARK: Header with avatar picker
                        VStack(spacing: 10) {
                            PhotosPicker(
                                selection: $pickedAvatarItem,
                                matching: .images,
                                photoLibrary: .shared()
                            ) {
                                ZStack(alignment: .bottomTrailing) {
                                    avatarPreview
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 26, height: 26)
                                        .background(PawPalTheme.orange, in: Circle())
                                        .offset(x: 4, y: 4)
                                }
                            }
                            .buttonStyle(.plain)
                            .onChange(of: pickedAvatarItem) { _, item in
                                Task {
                                    guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                                    pickedAvatarData = data
                                    if let uiImage = UIImage(data: data) {
                                        pickedAvatarImage = Image(uiImage: uiImage)
                                    }
                                }
                            }

                            Text(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                 ? title
                                 : name.trimmingCharacters(in: .whitespacesAndNewlines))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(PawPalTheme.primaryText)
                                .animation(.easeInOut(duration: 0.15), value: name)

                            Text("点击头像更换照片")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(PawPalTheme.tertiaryText)
                        }
                        .padding(.top, 24)

                        // MARK: Species chips
                        VStack(alignment: .leading, spacing: 10) {
                            sectionLabel("宠物类别")
                            ScrollView(.horizontal) {
                                HStack(spacing: 10) {
                                    ForEach(speciesOptions, id: \.label) { option in
                                        speciesChip(option)
                                    }
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 4)
                            }
                            .scrollIndicators(.hidden)
                        }

                        // MARK: Basics — name + breed
                        VStack(alignment: .leading, spacing: 10) {
                            sectionLabel("基础信息")
                            VStack(spacing: 0) {
                                fieldRow(label: "名字", required: true) {
                                    TextField("宠物名字", text: $name)
                                        .accessibilityIdentifier("add-pet-name-field")
                                }
                                Divider().padding(.leading, 16)
                                fieldRow(label: "品种") {
                                    TextField("例如：金毛", text: $breed)
                                        .multilineTextAlignment(.trailing)
                                }
                            }
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        // MARK: Details — sex, age, weight, hometown
                        VStack(alignment: .leading, spacing: 10) {
                            sectionLabel("详细信息")
                            VStack(spacing: 0) {
                                // Sex pills
                                HStack {
                                    Text("性别")
                                        .font(.system(size: 15))
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    sexSelector
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 14)

                                Divider().padding(.leading, 16)

                                fieldRow(label: "年龄") {
                                    HStack(spacing: 8) {
                                        TextField("例如：3", text: $ageValue)
                                            .keyboardType(.decimalPad)
                                            .multilineTextAlignment(.trailing)
                                            .frame(width: 60)
                                        unitMenu(options: ageUnits, selection: $ageUnit)
                                    }
                                }

                                Divider().padding(.leading, 16)

                                fieldRow(label: "体重") {
                                    HStack(spacing: 8) {
                                        TextField("例如：25", text: $weightValue)
                                            .keyboardType(.decimalPad)
                                            .multilineTextAlignment(.trailing)
                                            .frame(width: 60)
                                        unitMenu(options: weightUnits, selection: $weightUnit)
                                    }
                                }

                                Divider().padding(.leading, 16)

                                fieldRow(label: "家乡") {
                                    Button { showingLocationPicker = true } label: {
                                        HStack(spacing: 6) {
                                            Text(homeCity.isEmpty ? "选择城市" : homeCity)
                                                .foregroundStyle(homeCity.isEmpty ? Color(.placeholderText) : PawPalTheme.primaryText)
                                                .lineLimit(1)
                                                .truncationMode(.tail)
                                            Image(systemName: "location.fill")
                                                .font(.system(size: 11))
                                                .foregroundStyle(PawPalTheme.orange)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .sheet(isPresented: $showingLocationPicker) {
                                        LocationPickerSheet(selection: $homeCity)
                                    }
                                }

                                Divider().padding(.leading, 16)

                                fieldRow(label: "生日") {
                                    Button { showingBirthdayPicker = true } label: {
                                        HStack(spacing: 6) {
                                            Text(birthday.map(Self.formatBirthday) ?? "选择日期")
                                                .foregroundStyle(birthday == nil
                                                    ? Color(.placeholderText)
                                                    : PawPalTheme.primaryText)
                                            Image(systemName: "calendar")
                                                .font(.system(size: 11))
                                                .foregroundStyle(PawPalTheme.orange)
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    .sheet(isPresented: $showingBirthdayPicker) {
                                        birthdayPickerSheet
                                    }
                                }
                            }
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        // MARK: Bio
                        VStack(alignment: .leading, spacing: 10) {
                            sectionLabel("简介")
                            TextField("简单介绍一下你的宠物…", text: $bio, axis: .vertical)
                                .lineLimit(3...6)
                                .font(.system(size: 16))
                                .padding(16)
                                .background(Color(.systemBackground))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        // MARK: Playdate opt-in
                        //
                        // Default-off gate for receiving 约遛弯 invites.
                        // Hidden from onboarding per §8 of the playdates
                        // spec (one-job principle: onboarding is first-pet
                        // creation, not feature tour).
                        VStack(alignment: .leading, spacing: 10) {
                            sectionLabel("遛弯")
                            VStack(alignment: .leading, spacing: 6) {
                                Toggle("开放遛弯邀请", isOn: $openToPlaydates)
                                    .tint(PawPalTheme.accent)
                                Text("其他毛孩子的主人可以直接发送邀请")
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }

                        // MARK: Error
                        if let errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .foregroundStyle(.red)
                                Text(errorMessage)
                                    .font(.system(size: 13))
                                    .foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        // MARK: Save
                        Button {
                            Task {
                                let ok = await onSave(
                                    name, species, breed, sex,
                                    composedAge, composedWeight, homeCity, bio,
                                    birthday,
                                    openToPlaydates,
                                    pickedAvatarData
                                )
                                if ok { dismiss() }
                            }
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(canSave
                                          ? LinearGradient(colors: [PawPalTheme.orange, PawPalTheme.orangeSoft], startPoint: .leading, endPoint: .trailing)
                                          : LinearGradient(colors: [Color(.tertiarySystemFill), Color(.tertiarySystemFill)], startPoint: .leading, endPoint: .trailing))
                                    .frame(height: 52)
                                    .shadow(color: canSave ? PawPalTheme.orange.opacity(0.35) : .clear, radius: 12, y: 6)
                                if isSaving {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("保存")
                                        .font(.system(size: 17, weight: .bold, design: .rounded))
                                        .foregroundStyle(canSave ? .white : .secondary)
                                }
                            }
                        }
                        .disabled(!canSave || isSaving)
                        .accessibilityIdentifier("save-pet-button")
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    // MARK: - Subviews

    private var avatarPreview: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [PawPalTheme.orange.opacity(0.2), PawPalTheme.cardSoft],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 88, height: 88)

            if let pickedImage = pickedAvatarImage {
                pickedImage
                    .resizable().scaledToFill()
                    .frame(width: 88, height: 88)
                    .clipShape(Circle())
            } else if let urlStr = existingAvatarURL, let url = URL(string: urlStr) {
                AsyncImage(url: url) { phase in
                    if case .success(let img) = phase {
                        img.resizable().scaledToFill()
                            .frame(width: 88, height: 88)
                            .clipShape(Circle())
                    } else {
                        Text(speciesEmoji(for: species))
                            .font(.system(size: 44))
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: species)
                    }
                }
            } else {
                Text(speciesEmoji(for: species))
                    .font(.system(size: 44))
                    .animation(.spring(response: 0.3, dampingFraction: 0.6), value: species)
            }
        }
        .overlay(Circle().stroke(PawPalTheme.orange.opacity(0.35), lineWidth: 3))
        .shadow(color: PawPalTheme.orange.opacity(0.18), radius: 14, y: 6)
    }

    private func speciesChip(_ option: (emoji: String, label: String)) -> some View {
        let selected = species == option.label
        return Button {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.65)) {
                species = option.label
            }
        } label: {
            VStack(spacing: 6) {
                Text(option.emoji)
                    .font(.system(size: 26))
                Text(speciesDisplayName(option.label))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(selected ? .white : PawPalTheme.secondaryText)
            }
            .frame(width: 68, height: 72)
            .background(
                selected
                    ? AnyShapeStyle(LinearGradient(colors: [PawPalTheme.orange, PawPalTheme.orangeSoft], startPoint: .topLeading, endPoint: .bottomTrailing))
                    : AnyShapeStyle(Color(.systemBackground)),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .shadow(
                color: selected ? PawPalTheme.orange.opacity(0.3) : PawPalTheme.softShadow,
                radius: selected ? 10 : 4, y: selected ? 5 : 2
            )
            .scaleEffect(selected ? 1.05 : 1.0)
        }
        .buttonStyle(.plain)
        .animation(.spring(response: 0.3, dampingFraction: 0.65), value: selected)
    }

    private func unitMenu(options: [String], selection: Binding<String>) -> some View {
        Menu {
            ForEach(options, id: \.self) { option in
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection.wrappedValue = option
                    }
                } label: {
                    if selection.wrappedValue == option {
                        Label(option, systemImage: "checkmark")
                    } else {
                        Text(option)
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Text(selection.wrappedValue)
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
            }
            .foregroundStyle(PawPalTheme.orange)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(PawPalTheme.orange.opacity(0.12), in: Capsule())
        }
    }

    private var sexSelector: some View {
        HStack(spacing: 6) {
            ForEach([("公", "Male"), ("母", "Female")], id: \.1) { label, value in
                let selected = sex == value
                Button {
                    sex = value
                } label: {
                    Text(label)
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(selected ? .white : PawPalTheme.secondaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(
                            selected ? AnyShapeStyle(PawPalTheme.orange) : AnyShapeStyle(PawPalTheme.cardSoft),
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
                .animation(.easeInOut(duration: 0.15), value: selected)
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 4)
    }

    private func fieldRow<C: View>(label: String, required: Bool = false, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 12) {
            HStack(spacing: 4) {
                Text(label)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                if required {
                    Text("*")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(PawPalTheme.orange)
                }
            }
            .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: 8)

            content()
                .font(.system(size: 15))
                .multilineTextAlignment(.trailing)  // propagates into any TextField in content
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }

    // MARK: - Helpers

    private var canSave: Bool { !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var composedAge:    String { Self.composeMeasurement(value: ageValue,    unit: ageUnit) }
    private var composedWeight: String { Self.composeMeasurement(value: weightValue, unit: weightUnit) }

    private func speciesEmoji(for species: String) -> String {
        switch species {
        case "Dog":     return "🐶"
        case "Cat":     return "🐱"
        case "Rabbit":  return "🐰"
        case "Bird":    return "🦜"
        case "Hamster": return "🐹"
        default:        return "🐾"
        }
    }

    private static func splitMeasurement(_ raw: String?, fallbackUnit: String) -> (value: String, unit: String) {
        guard let raw = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !raw.isEmpty else { return ("", fallbackUnit) }
        let parts = raw.split(separator: " ", maxSplits: 1).map(String.init)
        return parts.count == 2 ? (parts[0], parts[1]) : (raw, fallbackUnit)
    }

    private static func composeMeasurement(value: String, unit: String) -> String {
        let v = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? "" : "\(v) \(unit)"
    }

    private func speciesDisplayName(_ english: String) -> String {
        switch english {
        case "Dog": return "狗狗"
        case "Cat": return "猫咪"
        case "Rabbit": return "兔兔"
        case "Bird": return "鸟类"
        case "Hamster": return "仓鼠"
        default: return "其他"
        }
    }

    // MARK: - Birthday picker

    private var birthdayPickerSheet: some View {
        NavigationStack {
            VStack(spacing: 16) {
                DatePicker(
                    "生日",
                    selection: Binding(
                        get: { birthday ?? Date() },
                        set: { birthday = $0 }
                    ),
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(PawPalTheme.accent)
                .padding(.horizontal, 20)

                if birthday != nil {
                    Button {
                        birthday = nil
                        showingBirthdayPicker = false
                    } label: {
                        Text("清除生日")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(PawPalTheme.accent)
                    }
                }
                Spacer()
            }
            .navigationTitle("选择生日")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") { showingBirthdayPicker = false }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private static func formatBirthday(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "zh_Hans_CN")
        f.dateFormat = "yyyy年M月d日"
        return f.string(from: date)
    }
}

// MARK: - Account Editor Sheet

private struct ProfileAccountEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var username: String
    @State private var displayName: String
    @State private var bio: String
    @State private var pickedAvatarItem: PhotosPickerItem?
    @State private var pickedAvatarData: Data?
    @State private var pickedAvatarImage: Image?

    let existingAvatarURL: String?
    let isSaving: Bool
    let errorMessage: String?
    let onSave: (String, String, String, Data?) async -> Bool

    init(profile: RemoteProfile, fallbackDisplayName: String, isSaving: Bool, errorMessage: String?, onSave: @escaping (String, String, String, Data?) async -> Bool) {
        self.existingAvatarURL = profile.avatar_url
        self.isSaving     = isSaving
        self.errorMessage = errorMessage
        self.onSave       = onSave
        _username    = State(initialValue: profile.username    ?? "")
        _displayName = State(initialValue: profile.display_name ?? fallbackDisplayName)
        _bio         = State(initialValue: profile.bio          ?? "")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 20) {
                        // Header with avatar picker
                        VStack(spacing: 12) {
                            PhotosPicker(
                                selection: $pickedAvatarItem,
                                matching: .images,
                                photoLibrary: .shared()
                            ) {
                                ZStack(alignment: .bottomTrailing) {
                                    ZStack {
                                        Circle()
                                            .fill(LinearGradient(
                                                colors: [PawPalTheme.orange, PawPalTheme.orangeSoft],
                                                startPoint: .topLeading, endPoint: .bottomTrailing))
                                            .frame(width: 80, height: 80)
                                        if let pickedAvatarImage {
                                            pickedAvatarImage
                                                .resizable().scaledToFill()
                                                .frame(width: 80, height: 80)
                                                .clipShape(Circle())
                                        } else if let urlStr = existingAvatarURL, let url = URL(string: urlStr) {
                                            AsyncImage(url: url) { phase in
                                                if case .success(let img) = phase {
                                                    img.resizable().scaledToFill()
                                                        .frame(width: 80, height: 80)
                                                        .clipShape(Circle())
                                                } else {
                                                    Image(systemName: "person.fill")
                                                        .font(.system(size: 32, weight: .medium))
                                                        .foregroundStyle(.white)
                                                }
                                            }
                                        } else {
                                            Image(systemName: "person.fill")
                                                .font(.system(size: 32, weight: .medium))
                                                .foregroundStyle(.white)
                                        }
                                    }
                                    Image(systemName: "camera.fill")
                                        .font(.system(size: 12, weight: .bold))
                                        .foregroundStyle(.white)
                                        .frame(width: 26, height: 26)
                                        .background(PawPalTheme.orange, in: Circle())
                                        .offset(x: 4, y: 4)
                                }
                            }
                            .buttonStyle(.plain)
                            .onChange(of: pickedAvatarItem) { _, item in
                                Task {
                                    guard let data = try? await item?.loadTransferable(type: Data.self) else { return }
                                    pickedAvatarData = data
                                    if let uiImage = UIImage(data: data) {
                                        pickedAvatarImage = Image(uiImage: uiImage)
                                    }
                                }
                            }
                            Text("编辑账号")
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(PawPalTheme.primaryText)
                        }
                        .padding(.top, 20)

                        // Fields
                        VStack(spacing: 0) {
                            accountRow("用户名") {
                                TextField("必填", text: $username)
                                    .textInputAutocapitalization(.never)
                                    .autocorrectionDisabled()
                            }
                            Divider().padding(.leading, 16)
                            accountRow("显示名") {
                                TextField("选填", text: $displayName)
                            }
                        }
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        // Bio
                        VStack(alignment: .leading, spacing: 10) {
                            Text("简介")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                            TextField("简单介绍一下你自己…", text: $bio, axis: .vertical)
                                .lineLimit(4...8)
                                .font(.system(size: 16))
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

                        // Error
                        if let errorMessage {
                            HStack(spacing: 8) {
                                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(.red)
                                Text(errorMessage).font(.system(size: 13)).foregroundStyle(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(14)
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }

                        // Save button
                        Button {
                            Task {
                                let ok = await onSave(username, displayName, bio, pickedAvatarData)
                                if ok { dismiss() }
                            }
                        } label: {
                            ZStack {
                                RoundedRectangle(cornerRadius: 16, style: .continuous)
                                    .fill(canSave
                                          ? LinearGradient(colors: [PawPalTheme.orange, PawPalTheme.orangeSoft], startPoint: .leading, endPoint: .trailing)
                                          : LinearGradient(colors: [Color(.tertiarySystemFill), Color(.tertiarySystemFill)], startPoint: .leading, endPoint: .trailing)
                                    )
                                    .frame(height: 52)
                                    .shadow(color: canSave ? PawPalTheme.orange.opacity(0.35) : .clear, radius: 12, y: 6)
                                if isSaving {
                                    ProgressView().tint(.white)
                                } else {
                                    Text("保存")
                                        .font(.system(size: 17, weight: .bold, design: .rounded))
                                        .foregroundStyle(canSave ? .white : .secondary)
                                }
                            }
                        }
                        .disabled(!canSave || isSaving)
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("编辑账号")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
            }
        }
    }

    private var canSave: Bool { !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private func accountRow<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        HStack(spacing: 16) {
            Text(title)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .frame(width: 80, alignment: .leading)
            content()
                .font(.system(size: 16))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
    }
}

// MARK: - Location Picker

// `LocationCompleter` was lifted to file scope at
// `PawPal/Views/Components/LocationCompleter.swift` so the playdate
// composer can share the MKLocalSearchCompleter wrapper without
// duplicating the delegate plumbing. The `LocationPickerSheet` below
// continues to use it — the rename from `private` to the file-scope
// class is transparent to callers.

private struct LocationPickerSheet: View {
    @Binding var selection: String
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @StateObject private var completer = LocationCompleter()

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section {
                        Label("搜索城市或地区", systemImage: "magnifyingglass")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 14))
                    }
                } else if completer.results.isEmpty {
                    Section {
                        Label("没有找到匹配结果", systemImage: "mappin.slash")
                            .foregroundStyle(.secondary)
                            .font(.system(size: 14))
                    }
                } else {
                    Section {
                        ForEach(completer.results, id: \.title) { result in
                            Button {
                                let city = result.subtitle.isEmpty
                                    ? result.title
                                    : "\(result.title), \(result.subtitle)"
                                selection = city
                                dismiss()
                            } label: {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(result.title)
                                        .font(.system(size: 15, weight: .semibold))
                                        .foregroundStyle(PawPalTheme.primaryText)
                                    if !result.subtitle.isEmpty {
                                        Text(result.subtitle)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("选择家乡")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "搜索城市、地区…")
            .onChange(of: query) { _, q in completer.search(q) }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                if !selection.isEmpty {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("清除") {
                            selection = ""
                            dismiss()
                        }
                        .foregroundStyle(.red)
                    }
                }
            }
        }
    }
}
