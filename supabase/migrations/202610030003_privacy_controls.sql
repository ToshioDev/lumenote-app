alter table public.profiles
  add column if not exists ai_processing_enabled boolean not null default true;
