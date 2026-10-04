alter table public.profiles
  add column if not exists role text not null default 'user';

create index if not exists profiles_role_idx on public.profiles(role);
