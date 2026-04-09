create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  base_username text;
  candidate_username text;
begin
  base_username := coalesce(nullif(split_part(new.email, '@', 1), ''), 'pet-user');
  candidate_username := left(base_username, 24) || '-' || substr(new.id::text, 1, 8);

  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    candidate_username,
    base_username
  )
  on conflict (id) do update
  set
    username = public.profiles.username,
    display_name = coalesce(public.profiles.display_name, excluded.display_name);

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

insert into public.profiles (id, username, display_name)
select
  id,
  left(coalesce(nullif(split_part(email, '@', 1), ''), 'pet-user'), 24) || '-' || substr(id::text, 1, 8),
  coalesce(nullif(split_part(email, '@', 1), ''), 'Pet User')
from auth.users
where id not in (select id from public.profiles)
on conflict (id) do nothing;
