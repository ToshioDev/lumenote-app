alter table public.profiles add column if not exists nickname text;
create index if not exists profiles_nickname_idx on public.profiles(nickname);

create or replace function public.handle_new_user() returns trigger
language plpgsql security definer as $$
begin
  insert into public.profiles (id, display_name, nickname)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'display_name', new.raw_user_meta_data->>'full_name', new.email),
    nullif(new.raw_user_meta_data->>'nickname', '')
  ) on conflict (id) do update set
    display_name = excluded.display_name,
    nickname = excluded.nickname;
  insert into public.subscriptions (user_id) values (new.id) on conflict (user_id) do nothing;
  return new;
end;
$$;
