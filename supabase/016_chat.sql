-- 016_chat.sql
--
-- MVP direct-message schema.  Up until this migration the chat tab
-- was a design shell backed by `ChatSampleData` — conversations,
-- messages, reactions and the auto-reply were all in-memory and
-- cleared on every cold start.  This migration adds the minimum
-- schema the client needs to send and read real messages.
--
-- Scope (per the in-app scope decision):
--   * 1:1 conversations between two profiles (no group chat yet).
--   * Text messages only (no images, no reactions).
--   * Read on pull-to-refresh / view-reopen — realtime subs land
--     in a follow-up migration.
--
-- Design:
--
-- `conversations` normalises the participant pair with `participant_a`
-- and `participant_b` (sorted by uuid on insert, enforced by trigger)
-- so we never end up with two rows for the same pair.  A uniqueness
-- constraint on (participant_a, participant_b) closes the race where
-- both users start a DM from each other at the same time.
--
-- `messages` is an append-only log scoped to a conversation.  Plain
-- (`text`, `sender_id`, `created_at`) — no edit / delete for the MVP.
--
-- RLS: a user can read / write a conversation row if they are one of
-- its participants.  Messages follow the same rule via the conversation
-- FK.  This means a DM between A and B is invisible to C in both
-- tables, even via direct queries.

create table if not exists conversations (
  id uuid primary key default gen_random_uuid(),
  participant_a uuid not null references profiles(id) on delete cascade,
  participant_b uuid not null references profiles(id) on delete cascade,
  last_message_at timestamptz,
  last_message_preview text,
  created_at timestamptz not null default now(),
  -- Enforce canonical ordering of the pair (a < b) so (A,B) and (B,A)
  -- become the same row.  Clients should sort uuids before inserting;
  -- the CHECK catches mistakes.
  constraint conversations_participants_ordered check (participant_a < participant_b),
  constraint conversations_no_self check (participant_a <> participant_b),
  constraint conversations_pair_unique unique (participant_a, participant_b)
);

create index if not exists conversations_participant_a_idx on conversations(participant_a);
create index if not exists conversations_participant_b_idx on conversations(participant_b);
create index if not exists conversations_last_message_idx on conversations(last_message_at desc);

create table if not exists messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references conversations(id) on delete cascade,
  sender_id uuid not null references profiles(id) on delete cascade,
  text text not null check (char_length(text) between 1 and 4000),
  created_at timestamptz not null default now()
);

create index if not exists messages_conversation_idx on messages(conversation_id, created_at);

-- Keep conversation preview + last_message_at in sync with inserts
-- so the inbox list can order by recency without a JOIN-per-row.
create or replace function update_conversation_last_message()
returns trigger
language plpgsql
as $$
begin
  update conversations
    set last_message_at = new.created_at,
        last_message_preview = left(new.text, 120)
    where id = new.conversation_id;
  return new;
end;
$$;

drop trigger if exists messages_touch_conversation on messages;
create trigger messages_touch_conversation
  after insert on messages
  for each row execute function update_conversation_last_message();

-- RLS
alter table conversations enable row level security;
alter table messages enable row level security;

-- Conversations: readable + writable by either participant.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'conversations'
      and policyname = 'conversations_select_participant'
  ) then
    create policy "conversations_select_participant" on conversations
      for select
      using (auth.uid() = participant_a or auth.uid() = participant_b);
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'conversations'
      and policyname = 'conversations_insert_participant'
  ) then
    create policy "conversations_insert_participant" on conversations
      for insert
      with check (auth.uid() = participant_a or auth.uid() = participant_b);
  end if;

  -- UPDATE is allowed because the trigger above runs with definer
  -- privileges effectively (it's a normal trigger but runs in the
  -- context of the INSERT on messages).  We still restrict manual
  -- updates to participants — this matters if a future PR lets users
  -- edit conversation metadata (e.g. a per-user nickname).
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'conversations'
      and policyname = 'conversations_update_participant'
  ) then
    create policy "conversations_update_participant" on conversations
      for update
      using (auth.uid() = participant_a or auth.uid() = participant_b)
      with check (auth.uid() = participant_a or auth.uid() = participant_b);
  end if;
end $$;

-- Messages: readable by either participant of the parent conversation.
-- Insertable by the sender if they are a participant.
do $$
begin
  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'messages'
      and policyname = 'messages_select_participant'
  ) then
    create policy "messages_select_participant" on messages
      for select
      using (
        exists (
          select 1 from conversations c
          where c.id = conversation_id
            and (auth.uid() = c.participant_a or auth.uid() = c.participant_b)
        )
      );
  end if;

  if not exists (
    select 1 from pg_policies
    where schemaname = 'public'
      and tablename = 'messages'
      and policyname = 'messages_insert_sender'
  ) then
    create policy "messages_insert_sender" on messages
      for insert
      with check (
        sender_id = auth.uid()
        and exists (
          select 1 from conversations c
          where c.id = conversation_id
            and (auth.uid() = c.participant_a or auth.uid() = c.participant_b)
        )
      );
  end if;
end $$;
