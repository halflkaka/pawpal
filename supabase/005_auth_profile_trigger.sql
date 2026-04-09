create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, username, display_name)
  values (
    new.id,
    coalesce(nullif(split_part(new.email, '@', 1), ''), 'pet-user'),
    coalesce(nullif(split_part(new.email, '@', 1), ''), 'Pet User')
  )
  on conflict (id) do update
  set
    username = coalesce(public.profiles.username, excluded.username),
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
  coalesce(nullif(split_part(email, '@', 1), ''), 'pet-user'),
  coalesce(nullif(split_part(email, '@', 1), ''), 'Pet User')
from auth.users
where id not in (select id from public.profiles);
