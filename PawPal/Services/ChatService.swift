import Foundation
import Supabase

/// Direct-message service backed by the `conversations` + `messages` tables
/// introduced in migration 016. MVP scope (per docs/scope.md):
///
///   * 1:1 conversations between two profiles (no group chat).
///   * Text messages only (no stickers, reactions, or read receipts).
///   * Reads on pull-to-refresh / view-reopen — realtime subscriptions
///     land in a follow-up PR.
///
/// Up until now the chat tab was rendered from `ChatSampleData`; every
/// "conversation" was an in-memory struct that reset on cold start and
/// the "auto-reply" was a hardcoded timer in `ChatDetailView`. This
/// service replaces that with real, persisted messages scoped to the
/// authenticated user.
@MainActor
final class ChatService: ObservableObject {
    /// Shared singleton so the chat list + detail views don't each hold
    /// their own cache. Matches the pattern used by `PetsService.shared`
    /// for the same cross-view consistency reason.
    static let shared = ChatService()

    /// Inbox summaries — one row per conversation the authenticated user
    /// participates in, ordered by recency. `@Published` so the list view
    /// refreshes when a message is sent or a new conversation is started.
    @Published var threads: [ChatThread] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?

    /// Cached message lists keyed by conversation id. Populated lazily as
    /// the user opens a conversation. The detail view reads from this
    /// dict so re-entering the same conversation is instant.
    @Published var messagesByConversation: [UUID: [RemoteMessage]] = [:]

    private let client: SupabaseClient

    init() {
        client = SupabaseConfig.client
    }

    // MARK: - Inbox

    /// Fetches all conversations the user participates in, plus the
    /// partner profile for each so the list row can render an avatar +
    /// handle without a second round-trip per row.
    ///
    /// Strategy: one SELECT on `conversations` filtered by
    /// `participant_a.eq.user OR participant_b.eq.user`, then a single
    /// SELECT on `profiles` for every *other* participant id we saw.
    /// This keeps the inbox at two queries total regardless of thread
    /// count, which matters because the realtime path that'll replace
    /// this in a follow-up still needs the partner cache.
    func loadThreads(for userID: UUID) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            // Supabase PostgREST `or` filter: fetch rows where either
            // participant column equals the user's id.
            let raw: [RemoteConversation] = try await client
                .from("conversations")
                .select()
                .or("participant_a.eq.\(userID.uuidString),participant_b.eq.\(userID.uuidString)")
                .order("last_message_at", ascending: false, nullsFirst: false)
                .execute()
                .value

            // Collect the set of partner ids so we can fetch every
            // needed profile in one call.
            let partnerIDs: [UUID] = raw.map { $0.partner(for: userID) }
            let partners = try await fetchProfiles(ids: Array(Set(partnerIDs)))
            let partnerByID = Dictionary(uniqueKeysWithValues: partners.map { ($0.id, $0) })

            self.threads = raw.map { conv in
                ChatThread(
                    conversationID: conv.id,
                    partnerID: conv.partner(for: userID),
                    partnerProfile: partnerByID[conv.partner(for: userID)],
                    lastMessagePreview: conv.last_message_preview,
                    lastMessageAt: conv.last_message_at,
                    createdAt: conv.created_at
                )
            }
        } catch {
            print("[ChatService] loadThreads 失败: \(error)")
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Messages

    /// Loads the full message log for a conversation. Cached in
    /// `messagesByConversation` so re-entering the same thread doesn't
    /// refetch. Callers should still call this on appear — the cache
    /// check is internal.
    func loadMessages(conversationID: UUID, force: Bool = false) async {
        if !force, messagesByConversation[conversationID] != nil { return }

        do {
            let rows: [RemoteMessage] = try await client
                .from("messages")
                .select()
                .eq("conversation_id", value: conversationID.uuidString)
                .order("created_at", ascending: true)
                .execute()
                .value
            messagesByConversation[conversationID] = rows
        } catch {
            print("[ChatService] loadMessages 失败 for \(conversationID): \(error)")
        }
    }

    /// Sends a message, appends it to the local cache optimistically, and
    /// returns the final server row. On failure the optimistic message
    /// is removed so the UI doesn't show a ghost "sent" bubble.
    ///
    /// Also updates the matching `ChatThread` in `threads` so the inbox
    /// row's preview + timestamp move to the top without a full refetch.
    @discardableResult
    func sendMessage(conversationID: UUID, senderID: UUID, text: String) async -> RemoteMessage? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // Optimistic local insert so the bubble renders immediately —
        // the server round-trip replaces the placeholder with the real
        // row (same id, correct timestamp) on success.
        let tempID = UUID()
        let optimistic = RemoteMessage(
            id: tempID,
            conversation_id: conversationID,
            sender_id: senderID,
            text: trimmed,
            created_at: Date()
        )
        var current = messagesByConversation[conversationID] ?? []
        current.append(optimistic)
        messagesByConversation[conversationID] = current

        struct MessageInsert: Encodable {
            let conversation_id: UUID
            let sender_id: UUID
            let text: String
        }
        let payload = MessageInsert(
            conversation_id: conversationID,
            sender_id: senderID,
            text: trimmed
        )

        do {
            let inserted: RemoteMessage = try await client
                .from("messages")
                .insert(payload)
                .select()
                .single()
                .execute()
                .value

            // Swap the optimistic placeholder for the real row.
            if var list = messagesByConversation[conversationID],
               let idx = list.firstIndex(where: { $0.id == tempID }) {
                list[idx] = inserted
                messagesByConversation[conversationID] = list
            }

            // Update the inbox summary so the row jumps to the top.
            if let idx = threads.firstIndex(where: { $0.conversationID == conversationID }) {
                var thread = threads[idx]
                thread.lastMessagePreview = String(trimmed.prefix(120))
                thread.lastMessageAt = inserted.created_at
                threads.remove(at: idx)
                threads.insert(thread, at: 0)
            }
            return inserted
        } catch {
            print("[ChatService] sendMessage 失败: \(error)")
            // Roll back the optimistic insert — message rendering as
            // sent when it wasn't is worse than it vanishing.
            if var list = messagesByConversation[conversationID] {
                list.removeAll(where: { $0.id == tempID })
                messagesByConversation[conversationID] = list
            }
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Starting conversations

    /// Returns the id of the conversation between `userA` and `userB`,
    /// creating one if it doesn't exist yet. Participant ids are sorted
    /// before insert so `(A,B)` and `(B,A)` map to the same row — this
    /// matches the canonical-ordering CHECK constraint from migration
    /// 016. The DB's unique (participant_a, participant_b) index closes
    /// the race where both users open a DM to each other at the same
    /// time.
    ///
    /// No-ops (returns nil) when the caller tries to start a
    /// conversation with themselves.
    func startConversation(userA: UUID, userB: UUID) async -> UUID? {
        guard userA != userB else { return nil }
        let (a, b) = canonical(userA, userB)

        // Try to find an existing row first to avoid an insert-then-
        // fail roundtrip in the common "re-open DM" case.
        do {
            let existing: [RemoteConversation] = try await client
                .from("conversations")
                .select()
                .eq("participant_a", value: a.uuidString)
                .eq("participant_b", value: b.uuidString)
                .limit(1)
                .execute()
                .value
            if let row = existing.first {
                return row.id
            }
        } catch {
            // Non-fatal — fall through to the insert path.
            print("[ChatService] startConversation lookup 失败: \(error)")
        }

        struct ConversationInsert: Encodable {
            let participant_a: UUID
            let participant_b: UUID
        }
        do {
            let inserted: RemoteConversation = try await client
                .from("conversations")
                .insert(ConversationInsert(participant_a: a, participant_b: b))
                .select()
                .single()
                .execute()
                .value
            return inserted.id
        } catch {
            print("[ChatService] startConversation insert 失败: \(error)")
            errorMessage = error.localizedDescription
            return nil
        }
    }

    // MARK: - Helpers

    /// Canonical ordering — the smaller uuid lands in `participant_a`.
    /// Uses the string form to match PostgreSQL's `<` comparison on
    /// uuid columns, which is how the `conversations_participants_ordered`
    /// CHECK constraint sorts rows.
    private func canonical(_ x: UUID, _ y: UUID) -> (UUID, UUID) {
        x.uuidString < y.uuidString ? (x, y) : (y, x)
    }

    /// Fetches a batch of profiles by id. Returns an empty array when
    /// the input list is empty so the caller can treat "no partners"
    /// the same as "no matches".
    private func fetchProfiles(ids: [UUID]) async throws -> [RemoteProfile] {
        guard !ids.isEmpty else { return [] }
        let list = ids.map { $0.uuidString }.joined(separator: ",")
        let rows: [RemoteProfile] = try await client
            .from("profiles")
            .select()
            .filter("id", operator: "in", value: "(\(list))")
            .execute()
            .value
        return rows
    }
}

// MARK: - Row shapes

/// Raw row from the `conversations` table. Mirrors migration 016.
struct RemoteConversation: Codable, Equatable {
    let id: UUID
    let participant_a: UUID
    let participant_b: UUID
    var last_message_at: Date?
    var last_message_preview: String?
    let created_at: Date

    /// The "other" participant relative to `viewerID`. Callers pass the
    /// authenticated user's id to get the partner they're talking to —
    /// no branching in the view layer.
    func partner(for viewerID: UUID) -> UUID {
        participant_a == viewerID ? participant_b : participant_a
    }
}

/// Raw row from the `messages` table. Mirrors migration 016.
struct RemoteMessage: Codable, Equatable, Identifiable, Hashable {
    let id: UUID
    let conversation_id: UUID
    let sender_id: UUID
    let text: String
    let created_at: Date
}

/// Inbox summary combining a conversation with its partner profile and
/// preview metadata. This is what the list view renders — kept separate
/// from `RemoteConversation` so the display type can evolve (adding
/// unread counts, online flags, etc.) without reshaping the DB row.
struct ChatThread: Identifiable, Equatable, Hashable {
    var id: UUID { conversationID }
    let conversationID: UUID
    let partnerID: UUID
    var partnerProfile: RemoteProfile?
    var lastMessagePreview: String?
    var lastMessageAt: Date?
    let createdAt: Date

    /// Hash on the conversation id alone. `RemoteProfile` is only
    /// `Equatable`, so auto-synthesis of `Hashable` fails — and hashing
    /// on the full payload would needlessly thrash NavigationStack's
    /// destination diffing when the partner profile refreshes. The
    /// conversation id is unique per row and stable for the life of
    /// the thread, which is what we actually want for navigation.
    func hash(into hasher: inout Hasher) {
        hasher.combine(conversationID)
    }

    /// Display handle for the inbox row. Falls back to a truncated
    /// partner id when the profile is missing or has no username set
    /// (shouldn't happen in practice since `profiles.username` is NOT
    /// NULL on insert, but defensive for rows loaded pre-schema).
    var displayHandle: String {
        if let username = partnerProfile?.username?.trimmingCharacters(in: .whitespacesAndNewlines),
           !username.isEmpty {
            return "@\(username)"
        }
        if let display = partnerProfile?.display_name?.trimmingCharacters(in: .whitespacesAndNewlines),
           !display.isEmpty {
            return display
        }
        return "@\(String(partnerID.uuidString.prefix(8)))"
    }

    /// Short display name used above the composer in the detail header.
    var displayName: String {
        partnerProfile?.display_name?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? partnerProfile?.username?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
            ?? "用户"
    }
}

private extension String {
    /// Convenience used by `ChatThread.displayName` — returns nil when
    /// the string is empty so chained `??` short-circuits the next
    /// candidate.
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
