-- Membership authority stays server-side. Prices are intentionally unset until
-- the merchant account, tax approach, and final commercial offer are approved.
alter table public.subscriptions
  add column if not exists billing_provider text not null default 'manual',
  add column if not exists provider_subscription_id text,
  add column if not exists provider_price_id text,
  add column if not exists billing_interval text,
  add column if not exists current_period_start timestamptz,
  add column if not exists usage_period_start date,
  add column if not exists cancel_at_period_end boolean not null default false,
  add column if not exists updated_at timestamptz not null default now();

create unique index if not exists subscriptions_provider_subscription_uidx
  on public.subscriptions (billing_provider, provider_subscription_id)
  where provider_subscription_id is not null;

create table if not exists public.membership_plans (
  code text primary key,
  name text not null,
  description text not null default '',
  minutes_limit integer not null check (minutes_limit >= 0),
  features jsonb not null default '{}'::jsonb,
  monthly_price_minor integer,
  annual_price_minor integer,
  currency text not null default 'MXN',
  enabled boolean not null default true,
  display_order integer not null default 0,
  updated_at timestamptz not null default now(),
  check (monthly_price_minor is null or monthly_price_minor >= 0),
  check (annual_price_minor is null or annual_price_minor >= 0)
);

insert into public.membership_plans
  (code, name, description, minutes_limit, features, display_order)
values
  ('free', 'Gratis', 'Para empezar a organizar tus clases.', 60,
   '{"topics":true,"notes":true,"transcription":true,"ai_chat":false,"study_material":false}'::jsonb, 0),
  ('plus', 'Plus', 'Para estudiar con más capacidad y asistencia de IA.', 600,
   '{"topics":true,"notes":true,"transcription":true,"ai_chat":true,"study_material":true}'::jsonb, 1),
  ('pro', 'Pro', 'Para uso intensivo, sesiones largas y estudio avanzado.', 2400,
   '{"topics":true,"notes":true,"transcription":true,"ai_chat":true,"study_material":true,"priority_processing":true}'::jsonb, 2)
on conflict (code) do update set
  name = excluded.name,
  description = excluded.description,
  minutes_limit = excluded.minutes_limit,
  features = excluded.features,
  display_order = excluded.display_order,
  updated_at = now();

alter table public.membership_plans enable row level security;
drop policy if exists "membership plans readable" on public.membership_plans;
create policy "membership plans readable" on public.membership_plans
  for select using (enabled);

-- Clients may inspect (and remove as part of account-data deletion) their own
-- row, but cannot self-assign paid plans, change status, or inflate quotas.
drop policy if exists "subscription own row" on public.subscriptions;
drop policy if exists "subscriptions own select" on public.subscriptions;
drop policy if exists "subscriptions own delete" on public.subscriptions;
create policy "subscriptions own select" on public.subscriptions
  for select using (auth.uid() = user_id);
create policy "subscriptions own delete" on public.subscriptions
  for delete using (auth.uid() = user_id);

create table if not exists public.billing_webhook_events (
  provider text not null,
  event_id text not null,
  event_type text not null,
  received_at timestamptz not null default now(),
  processed_at timestamptz,
  processing_error text,
  primary key (provider, event_id)
);
alter table public.billing_webhook_events enable row level security;

create table if not exists public.membership_minute_reservations (
  reservation_id uuid primary key,
  user_id uuid not null references auth.users(id) on delete cascade,
  note_id text,
  usage_period_start date not null,
  minutes integer not null check (minutes > 0),
  status text not null check (status in ('reserved', 'charged', 'released')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists membership_minute_reservations_pending_idx
  on public.membership_minute_reservations (user_id, usage_period_start)
  where status = 'reserved';
alter table public.membership_minute_reservations enable row level security;

create or replace function public.reserve_transcription_minutes(
  p_user_id uuid, p_reservation_id uuid, p_note_id text, p_minutes integer
) returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_sub public.subscriptions%rowtype;
  v_cycle date := date_trunc('month', now() at time zone 'UTC')::date;
  v_pending integer;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;
  if p_minutes < 1 or p_minutes > 10080 then
    raise exception 'invalid duration' using errcode = '22023';
  end if;
  select * into v_sub from public.subscriptions where user_id = p_user_id for update;
  if not found then
    return jsonb_build_object('allowed', false, 'reason', 'membership_missing');
  end if;
  if not (
    (v_sub.status in ('active', 'trialing') and
      (v_sub.current_period_end is null or v_sub.current_period_end > now()))
    or coalesce(v_sub.cancel_at_period_end and v_sub.current_period_end > now(), false)
  ) then
    return jsonb_build_object('allowed', false, 'reason', 'membership_inactive');
  end if;
  if v_sub.usage_period_start is distinct from v_cycle then
    update public.subscriptions
      set minutes_used = 0, usage_period_start = v_cycle, updated_at = now()
      where user_id = p_user_id returning * into v_sub;
  end if;
  update public.membership_minute_reservations
    set status = 'released', updated_at = now()
    where user_id = p_user_id and status = 'reserved'
      and created_at < now() - interval '24 hours';
  select coalesce(sum(minutes), 0)::integer into v_pending
    from public.membership_minute_reservations
    where user_id = p_user_id and usage_period_start = v_cycle and status = 'reserved';
  if v_sub.minutes_used + v_pending + p_minutes > v_sub.minutes_limit then
    return jsonb_build_object('allowed', false, 'reason', 'quota_exceeded',
      'used', v_sub.minutes_used + v_pending, 'limit', v_sub.minutes_limit);
  end if;
  insert into public.membership_minute_reservations
    (reservation_id, user_id, note_id, usage_period_start, minutes, status)
  values (p_reservation_id, p_user_id, p_note_id, v_cycle, p_minutes, 'reserved');
  return jsonb_build_object('allowed', true, 'used', v_sub.minutes_used + v_pending,
    'reserved', p_minutes, 'limit', v_sub.minutes_limit, 'period_start', v_cycle);
end;
$$;

create or replace function public.complete_transcription_minutes(p_reservation_id uuid)
returns jsonb language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_res public.membership_minute_reservations%rowtype;
  v_sub public.subscriptions%rowtype;
  v_cycle date := date_trunc('month', now() at time zone 'UTC')::date;
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;
  select * into v_res from public.membership_minute_reservations
    where reservation_id = p_reservation_id for update;
  if not found then return jsonb_build_object('completed', false, 'reason', 'reservation_missing'); end if;
  if v_res.status = 'charged' then return jsonb_build_object('completed', true, 'duplicate', true); end if;
  if v_res.status <> 'reserved' then return jsonb_build_object('completed', false, 'reason', 'reservation_not_active'); end if;
  select * into v_sub from public.subscriptions where user_id = v_res.user_id for update;
  if v_sub.usage_period_start is distinct from v_cycle then
    update public.subscriptions set minutes_used = 0, usage_period_start = v_cycle
      where user_id = v_res.user_id returning * into v_sub;
  end if;
  update public.subscriptions set minutes_used = minutes_used + v_res.minutes, updated_at = now()
    where user_id = v_res.user_id returning * into v_sub;
  update public.membership_minute_reservations set status = 'charged', updated_at = now()
    where reservation_id = p_reservation_id;
  return jsonb_build_object('completed', true, 'used', v_sub.minutes_used, 'limit', v_sub.minutes_limit);
end;
$$;

create or replace function public.release_transcription_minutes(p_reservation_id uuid)
returns boolean language plpgsql security definer set search_path = public, pg_temp as $$
begin
  if coalesce(auth.role(), '') <> 'service_role' then
    raise exception 'service role required' using errcode = '42501';
  end if;
  update public.membership_minute_reservations set status = 'released', updated_at = now()
    where reservation_id = p_reservation_id and status = 'reserved';
  return found;
end;
$$;

revoke all on function public.reserve_transcription_minutes(uuid, uuid, text, integer) from public, anon, authenticated;
revoke all on function public.complete_transcription_minutes(uuid) from public, anon, authenticated;
revoke all on function public.release_transcription_minutes(uuid) from public, anon, authenticated;
grant execute on function public.reserve_transcription_minutes(uuid, uuid, text, integer) to service_role;
grant execute on function public.complete_transcription_minutes(uuid) to service_role;
grant execute on function public.release_transcription_minutes(uuid) to service_role;
