import SwiftUI

struct ProfileView: View {
    let user: AppUser
    @Bindable var authManager: AuthManager
    @AppStorage("activePetID") private var activePetID = ""
    @StateObject private var petsService = PetsService()
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
    @StateObject private var followService = FollowService()
    @StateObject private var postsService = PostsService()

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
                Divider()
                petsBand
                Divider()
                postsGrid
            }
        }
        .scrollIndicators(.hidden)
        .background(PawPalBackground())
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .top) { topBar }
        .navigationDestination(for: RemotePet.self) { pet in
            PetProfileView(pet: pet)
        }
        .task { await loadAll() }
        .refreshable { await loadAll() }
        .sheet(isPresented: $showingAddPet, onDismiss: { statusMessage = nil }) {
            ProfilePetEditorSheet(
                title: "添加宠物",
                pet: nil,
                isSaving: isSavingPet,
                errorMessage: petsService.errorMessage
            ) { name, species, breed, sex, age, weight, homeCity, bio in
                guard !isSavingPet else { return false }
                isSavingPet = true
                defer { isSavingPet = false }
                let saved = await petsService.addPet(
                    for: user.id, name: name, species: species,
                    breed: breed, sex: sex, age: age, weight: weight,
                    homeCity: homeCity, bio: bio
                )
                if saved != nil {
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
            ) { name, species, breed, sex, age, weight, homeCity, bio in
                guard !isSavingPet else { return false }
                isSavingPet = true
                defer { isSavingPet = false }
                var updated = pet
                updated.name = name; updated.species = species; updated.breed = breed
                updated.sex = sex; updated.age = age; updated.weight = weight
                updated.home_city = homeCity; updated.bio = bio
                await petsService.updatePet(updated, for: user.id)
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
            ) { username, displayName, bio in
                await saveProfile(username: username, displayName: displayName, bio: bio)
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

    private var profileHeader: some View {
        VStack(spacing: 18) {
            // Avatar
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [PawPalTheme.orange, PawPalTheme.orangeSoft],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 88, height: 88)
                    .shadow(color: PawPalTheme.orange.opacity(0.32), radius: 18, y: 8)
                Image(systemName: "person.fill")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(.white)
            }

            // Name + handle + bio
            VStack(spacing: 6) {
                Text(accountDisplayName)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(PawPalTheme.primaryText)

                Text(profileHandle.isEmpty ? (user.email ?? "") : profileHandle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.secondary)

                if let bio = trimmed(profile?.bio) {
                    Text(bio)
                        .font(.system(size: 14))
                        .foregroundStyle(PawPalTheme.secondaryText)
                        .multilineTextAlignment(.center)
                        .lineSpacing(2)
                        .padding(.horizontal, 24)
                        .padding(.top, 2)
                }
            }

            // Edit Profile button
            Button { showingEditAccount = true } label: {
                Text("编辑资料")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(PawPalTheme.primaryText)
                    .padding(.horizontal, 28)
                    .padding(.vertical, 10)
                    .background(.white, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .shadow(color: PawPalTheme.shadow, radius: 8, y: 4)
            }
            .buttonStyle(.plain)

            // Stats row
            HStack(spacing: 0) {
                statCell(value: "\(postsService.userPosts.count)", label: "帖子")
                statDivider()
                statCell(value: "\(petsService.pets.count)", label: "宠物")
                statDivider()
                statCell(value: "\(followerCount)", label: "粉丝")
                statDivider()
                statCell(value: "\(followService.followingIDs.count)", label: "关注")
            }
            .padding(.vertical, 12)
            .background(Color.white.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .padding(.horizontal, 20)
        .padding(.top, 20)
        .padding(.bottom, 28)
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
        return VStack(spacing: 8) {
            ZStack {
                if isActive {
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [PawPalTheme.orange, PawPalTheme.orangeSoft],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 68, height: 68)
                } else {
                    Circle()
                        .fill(PawPalTheme.cardSoft)
                        .frame(width: 68, height: 68)
                        .overlay(
                            Circle().stroke(PawPalTheme.orangeGlow, lineWidth: 1.5)
                        )
                }

                Image(systemName: iconName(for: pet.species ?? ""))
                    .font(.system(size: 28, weight: .medium))
                    .foregroundStyle(isActive ? .white : PawPalTheme.orange)
            }
            .shadow(
                color: isActive ? PawPalTheme.orange.opacity(0.35) : PawPalTheme.softShadow,
                radius: 10, y: 4
            )
            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: isActive)

            Text(pet.name)
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)
                .lineLimit(1)
        }
        .frame(width: 72)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation { activePetID = pet.id.uuidString }
        }
        .contextMenu {
            NavigationLink(value: pet) {
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

    // MARK: - Posts grid

    private var postsGrid: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "square.grid.3x3.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(PawPalTheme.orange)
                Text("帖子")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(PawPalTheme.primaryText)
                Spacer()
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)

            Divider()

            if postsService.userPosts.isEmpty {
                emptyPostsState
            } else {
                realPostsGrid
            }
        }
    }

    // MARK: - Empty posts state

    private var emptyPostsState: some View {
        VStack(spacing: 16) {
            Text("暂无帖子")
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .foregroundStyle(PawPalTheme.primaryText)
                .padding(.top, 24)
            Text("分享你的宠物日常，开启社交新世界")
                .font(.system(size: 14))
                .foregroundStyle(PawPalTheme.secondaryText)
                .multilineTextAlignment(.center)
            VStack(spacing: 12) {
                actionCard(
                    icon: "square.and.pencil",
                    title: "创建首条帖子",
                    subtitle: "去发布页分享宠物的精彩时刻",
                    color: PawPalTheme.orange
                )
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

    private var realPostsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
            ForEach(postsService.userPosts) { post in
                profilePostCard(post)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private func profilePostCard(_ post: RemotePost) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let imageURL = post.imageURLs.first {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(height: 150)
                            .frame(maxWidth: .infinity)
                            .clipped()
                    case .failure:
                        profilePostPlaceholder(height: 150, icon: "photo")
                    default:
                        profilePostPlaceholder(height: 150, icon: nil)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                profilePostPlaceholder(height: 150, icon: "text.alignleft")
            }

            Text(post.caption)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(PawPalTheme.primaryText)
                .lineLimit(2)

            HStack(spacing: 10) {
                Label("\(post.likeCount)", systemImage: "heart")
                Label("\(postsService.commentCount(for: post.id))", systemImage: "message")
            }
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(PawPalTheme.secondaryText)
        }
        .padding(10)
        .background(Color.white.opacity(0.85), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: PawPalTheme.shadow, radius: 8, y: 4)
    }

    private func profilePostPlaceholder(height: CGFloat, icon: String?) -> some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(PawPalTheme.cardSoft)
            .frame(maxWidth: .infinity)
            .frame(height: height)
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

    // MARK: - Helpers

    private func loadAll() async {
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

    private func saveProfile(username: String, displayName: String, bio: String) async -> Bool {
        guard !isSavingProfile else { return false }
        isSavingProfile = true
        profileErrorMessage = nil
        defer { isSavingProfile = false }
        do {
            profile = try await profileService.saveProfile(
                for: user.id, username: username, displayName: displayName, bio: bio
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

    private let ageUnits    = ["岁", "个月"]
    private let weightUnits = ["公斤", "斤"]
    private let speciesOptions: [(emoji: String, label: String)] = [
        ("🐶", "Dog"), ("🐱", "Cat"), ("🐰", "Rabbit"),
        ("🦜", "Bird"), ("🐹", "Hamster"), ("🐾", "Other")
    ]

    let title: String
    let isSaving: Bool
    let errorMessage: String?
    let onSave: (String, String, String, String, String, String, String, String) async -> Bool

    init(
        title: String, pet: RemotePet?, isSaving: Bool,
        errorMessage: String?,
        onSave: @escaping (String, String, String, String, String, String, String, String) async -> Bool
    ) {
        self.title        = title
        self.isSaving     = isSaving
        self.errorMessage = errorMessage
        self.onSave       = onSave
        _name     = State(initialValue: pet?.name ?? "")
        _species  = State(initialValue: pet?.species?.isEmpty == false ? pet!.species! : "Dog")
        _breed    = State(initialValue: pet?.breed ?? "")
        _sex      = State(initialValue: pet?.sex ?? "")
        _homeCity = State(initialValue: pet?.home_city ?? "")
        _bio      = State(initialValue: pet?.bio ?? "")
        let parsedAge    = Self.splitMeasurement(pet?.age,    fallbackUnit: "岁")
        _ageValue    = State(initialValue: parsedAge.value)
        _ageUnit     = State(initialValue: parsedAge.unit)
        let parsedWeight = Self.splitMeasurement(pet?.weight, fallbackUnit: "公斤")
        _weightValue = State(initialValue: parsedWeight.value)
        _weightUnit  = State(initialValue: parsedWeight.unit)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color(.systemGroupedBackground).ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {

                        // MARK: Header
                        VStack(spacing: 10) {
                            Text(speciesEmoji(for: species))
                                .font(.system(size: 64))
                                .animation(.spring(response: 0.3, dampingFraction: 0.6), value: species)

                            Text(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                                 ? title
                                 : name.trimmingCharacters(in: .whitespacesAndNewlines))
                                .font(.system(size: 22, weight: .bold, design: .rounded))
                                .foregroundStyle(PawPalTheme.primaryText)
                                .animation(.easeInOut(duration: 0.15), value: name)
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
                                        Picker("", selection: $ageUnit) {
                                            ForEach(ageUnits, id: \.self) { Text($0).tag($0) }
                                        }
                                        .pickerStyle(.menu)
                                        .labelsHidden()
                                    }
                                }

                                Divider().padding(.leading, 16)

                                fieldRow(label: "体重") {
                                    HStack(spacing: 8) {
                                        TextField("例如：25", text: $weightValue)
                                            .keyboardType(.decimalPad)
                                            .multilineTextAlignment(.trailing)
                                            .frame(width: 60)
                                        Picker("", selection: $weightUnit) {
                                            ForEach(weightUnits, id: \.self) { Text($0).tag($0) }
                                        }
                                        .pickerStyle(.menu)
                                        .labelsHidden()
                                    }
                                }

                                Divider().padding(.leading, 16)

                                fieldRow(label: "家乡") {
                                    TextField("例如：西雅图", text: $homeCity)
                                        .multilineTextAlignment(.trailing)
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
                                    composedAge, composedWeight, homeCity, bio
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

    private var sexSelector: some View {
        HStack(spacing: 6) {
            ForEach([("未设置", ""), ("公", "Male"), ("母", "Female")], id: \.1) { label, value in
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
            Spacer()
            content()
                .font(.system(size: 15))
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
}

// MARK: - Account Editor Sheet

private struct ProfileAccountEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var username: String
    @State private var displayName: String
    @State private var bio: String

    let isSaving: Bool
    let errorMessage: String?
    let onSave: (String, String, String) async -> Bool

    init(profile: RemoteProfile, fallbackDisplayName: String, isSaving: Bool, errorMessage: String?, onSave: @escaping (String, String, String) async -> Bool) {
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
                        // Header
                        VStack(spacing: 12) {
                            ZStack {
                                Circle()
                                    .fill(PawPalTheme.cardSoft)
                                    .frame(width: 72, height: 72)
                                Image(systemName: "person.crop.circle.fill")
                                    .font(.system(size: 30))
                                    .foregroundStyle(PawPalTheme.orange)
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
                                let ok = await onSave(username, displayName, bio)
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
