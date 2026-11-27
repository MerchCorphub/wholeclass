-- Know Your Holes Series: seasons. Each season is sold separately (one year), Episode 1 of each season is free.
create table if not exists public.series_seasons (
  n int primary key check (n between 1 and 99),
  title text not null,
  blurb text,
  price numeric(8,2) not null default 14.99 check (price >= 1 and price <= 999),
  published boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.series_seasons enable row level security;
insert into public.series_seasons (n, title, blurb, price, published)
select 1, 'The Missing Fit', 'Real situations that show how holes shape the way we love, argue and choose.', coalesce((select amount from public.prices where kind = 'series'), 14.99), true
on conflict (n) do nothing;

alter table public.series_episodes add column if not exists season int not null default 1;
alter table public.series_episodes drop constraint if exists series_episodes_pkey;
alter table public.series_episodes add primary key (season, n);
alter table public.series_episodes drop constraint if exists series_episodes_season_fkey;
alter table public.series_episodes add constraint series_episodes_season_fkey foreign key (season) references public.series_seasons(n) on delete cascade;

alter table public.access_grants add column if not exists season int not null default 1;
alter table public.payments add column if not exists season int not null default 1;

-- Can this member play this file?
create or replace function public.can_hear_episode(p_name text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from members m where m.id = auth.uid() and m.is_admin)
      or exists (select 1 from series_episodes e join series_seasons s on s.n = e.season where e.audio_path = p_name and s.published and e.free)
      or exists (select 1 from series_episodes e join series_seasons s on s.n = e.season
                 join access_grants a on a.member_id = auth.uid() and a.product = 'series' and a.season = e.season
                   and a.starts_at <= now() and (a.expires_at is null or a.expires_at > now())
                 where e.audio_path = p_name and s.published)
$$;

-- Member view: published seasons with their episodes
create or replace function public.series_episode_list() returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object(
    'season', s.n, 'title', s.title, 'blurb', s.blurb, 'price', s.price,
    'unlocked', coalesce(g.found, false),
    'expires_at', g.expires_at,
    'episodes', (select coalesce(json_agg(json_build_object('n', e.n, 'title', e.title, 'free', e.free, 'ready', e.audio_path is not null,
        'duration_sec', e.duration_sec,
        'path', case when e.audio_path is not null and public.can_hear_episode(e.audio_path) then e.audio_path end) order by e.n), '[]'::json)
      from series_episodes e where e.season = s.n)) order by s.n), '[]'::json)
  from series_seasons s
  left join lateral (select true found, max(a.expires_at) expires_at from access_grants a
     where a.member_id = auth.uid() and a.product = 'series' and a.season = s.n and a.starts_at <= now() and (a.expires_at is null or a.expires_at > now())
     having count(*) > 0) g on true
  where s.published
$$;

-- Season 1 stays the "series_unlocked" flag the app home screen uses
create or replace function public.my_access() returns json
language plpgsql stable security definer set search_path = public, private as $$
declare uid uuid := auth.uid(); g access_grants; sg access_grants; price prices; sprice numeric; seats_used int;
begin
  if uid is null then return json_build_object('signed_in', false); end if;
  select * into g from access_grants a where a.member_id = uid and a.product = 'class' and a.starts_at <= now() and (a.expires_at is null or a.expires_at > now())
    order by a.expires_at desc nulls first limit 1;
  select * into sg from access_grants a where a.member_id = uid and a.product = 'series' and a.season = 1 and a.starts_at <= now() and (a.expires_at is null or a.expires_at > now())
    order by a.expires_at desc nulls first limit 1;
  select * into price from prices where kind = 'individual';
  select s.price into sprice from series_seasons s where s.n = 1;
  select count(*) into seats_used from seat_invites where giver_id = uid and created_at > now() - interval '1 year';
  return json_build_object('signed_in', true, 'unlocked', g.id is not null, 'kind', g.kind, 'expires_at', g.expires_at,
    'price', price.amount, 'seats_left', case when g.kind in ('paid', 'book_key', 'admin') then greatest(4 - seats_used, 0) else 0 end,
    'group', (select json_build_object('name', gr.name) from group_members gm join groups gr on gr.id = gm.group_id where gm.member_id = uid order by gm.joined_at desc limit 1),
    'series_unlocked', sg.id is not null, 'series_expires_at', sg.expires_at, 'series_price', sprice,
    'seasons', (select count(*) from series_seasons where published));
end $$;

-- Checkout for one season
drop function if exists public.stripe_prepare(uuid, text);
create or replace function public.stripe_prepare(p_user uuid, p_product text, p_season int default 1) returns json
language plpgsql security definer set search_path = public, private as $$
declare m members; pr prices; s series_seasons; pay uuid; prod text := coalesce(p_product, 'class'); amt numeric; label text; sn int := coalesce(p_season, 1);
begin
  if prod not in ('class', 'series') then raise exception 'Unknown product.'; end if;
  select * into m from members where id = p_user;
  if m.id is null then raise exception 'Create your account first.'; end if;
  if prod = 'class' then
    if exists (select 1 from access_grants where member_id = p_user and product = 'class' and kind in ('paid', 'book_key', 'admin') and (expires_at is null or expires_at > now())) then
      raise exception 'Your class is already open.';
    end if;
    select * into pr from prices where kind = 'individual';
    amt := pr.amount; label := pr.label; sn := 1;
  else
    select * into s from series_seasons where n = sn and published;
    if s.n is null then raise exception 'That season is not available yet.'; end if;
    if exists (select 1 from access_grants where member_id = p_user and product = 'series' and season = sn and (expires_at is null or expires_at > now())) then
      raise exception 'Season % is already open for you.', sn;
    end if;
    amt := s.price; label := 'Know Your Holes Series, Season ' || sn || ': ' || s.title || ' (one year)';
  end if;
  insert into payments (member_id, email, description, amount, product, season) values (p_user, m.email, label, amt, prod, sn) returning id into pay;
  return json_build_object('payment_id', pay, 'amount_cents', round(amt * 100)::int, 'description', label, 'email', m.email, 'product', prod, 'season', sn);
end $$;
revoke all on function public.stripe_prepare(uuid, text, int) from public, anon, authenticated;

create or replace function public.stripe_activate(p_session text, p_intent text, p_amount_cents integer) returns text
language plpgsql security definer set search_path = public as $$
declare p payments; d int;
begin
  select * into p from payments where stripe_session_id = p_session for update;
  if p.id is null then raise exception 'Payment not found.'; end if;
  if p.status = 'paid' then return 'already'; end if;
  if p_amount_cents < round(p.amount * 100)::int then raise exception 'The amount paid does not match.'; end if;
  select days into d from prices where kind = case p.product when 'series' then 'series' else 'individual' end;
  update payments set status = 'paid', paid_at = now(), stripe_payment_intent = p_intent where id = p.id;
  insert into access_grants (member_id, kind, ref, expires_at, product, season) values (p.member_id, 'paid', p.id::text, now() + make_interval(days => coalesce(d, 365)), p.product, p.season);
  return 'paid';
end $$;
revoke all on function public.stripe_activate(text, text, integer) from public, anon, authenticated;

-- Admin: seasons and episodes
create or replace function public.admin_episodes() returns json
language plpgsql stable security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  return (select coalesce(json_agg(json_build_object('season', s.n, 'title', s.title, 'blurb', s.blurb, 'price', s.price, 'published', s.published,
    'buyers', (select count(distinct a.member_id) from access_grants a where a.product = 'series' and a.season = s.n and (a.expires_at is null or a.expires_at > now())),
    'episodes', (select coalesce(json_agg(json_build_object('n', e.n, 'title', e.title, 'audio_path', e.audio_path, 'duration_sec', e.duration_sec, 'free', e.free, 'published_at', e.published_at) order by e.n), '[]'::json)
       from series_episodes e where e.season = s.n)) order by s.n), '[]'::json) from series_seasons s);
end $$;

drop function if exists public.admin_save_episode(int, text, text, int, boolean);
create or replace function public.admin_save_episode(p_season int, p_n int, p_title text, p_audio_path text, p_duration_sec int, p_free boolean) returns json
language plpgsql security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  if not exists (select 1 from series_seasons where n = p_season) then raise exception 'Season not found.'; end if;
  if p_n is null or p_n < 1 or p_n > 99 then raise exception 'Episode number must be 1 to 99.'; end if;
  insert into series_episodes (season, n, title, audio_path, duration_sec, free, published_at, updated_at)
  values (p_season, p_n, nullif(trim(p_title), ''), nullif(p_audio_path, ''), p_duration_sec, coalesce(p_free, p_n = 1), case when nullif(p_audio_path, '') is not null then now() end, now())
  on conflict (season, n) do update set title = nullif(trim(p_title), ''), audio_path = nullif(p_audio_path, ''), duration_sec = p_duration_sec,
    free = coalesce(p_free, series_episodes.free), published_at = case when nullif(p_audio_path, '') is null then null else coalesce(series_episodes.published_at, now()) end, updated_at = now();
  return public.admin_episodes();
end $$;

create or replace function public.admin_delete_episode(p_season int, p_n int) returns json
language plpgsql security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  if exists (select 1 from series_episodes where season = p_season and n = p_n and audio_path is not null) then raise exception 'Delete the audio first.'; end if;
  delete from series_episodes where season = p_season and n = p_n;
  return public.admin_episodes();
end $$;

-- Create or edit a season. A new season starts hidden with 12 empty episodes (Episode 1 free).
create or replace function public.admin_save_season(p_n int, p_title text, p_blurb text, p_price numeric, p_published boolean, p_episodes int default 12) returns json
language plpgsql security definer set search_path = public, private as $$
declare is_new boolean;
begin
  perform private.require_admin();
  if p_n is null or p_n < 1 or p_n > 99 then raise exception 'Season number must be 1 to 99.'; end if;
  if nullif(trim(p_title), '') is null then raise exception 'Give the season a title.'; end if;
  if p_price is null or p_price < 1 or p_price > 999 then raise exception 'Price must be between $1 and $999.'; end if;
  is_new := not exists (select 1 from series_seasons where n = p_n);
  insert into series_seasons (n, title, blurb, price, published) values (p_n, trim(p_title), nullif(trim(p_blurb), ''), round(p_price, 2), coalesce(p_published, false))
  on conflict (n) do update set title = excluded.title, blurb = excluded.blurb, price = excluded.price, published = excluded.published, updated_at = now();
  if is_new then
    insert into series_episodes (season, n, free) select p_n, g, g = 1 from generate_series(1, least(greatest(coalesce(p_episodes, 12), 1), 99)) g on conflict do nothing;
  end if;
  if p_n = 1 then update prices set amount = round(p_price, 2) where kind = 'series'; end if;
  return public.admin_episodes();
end $$;

create or replace function public.admin_delete_season(p_n int) returns json
language plpgsql security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  if p_n = 1 then raise exception 'Season 1 cannot be deleted.'; end if;
  if exists (select 1 from series_episodes where season = p_n and audio_path is not null) then raise exception 'Delete this season''s audio first.'; end if;
  if exists (select 1 from access_grants where product = 'series' and season = p_n) or exists (select 1 from payments where product = 'series' and season = p_n and status = 'paid') then
    raise exception 'Members have bought this season. Hide it instead of deleting it.';
  end if;
  delete from series_seasons where n = p_n;
  return public.admin_episodes();
end $$;

-- Settings "Series price" keeps Season 1 in step
create or replace function public.admin_set_price(p_amount numeric, p_kind text) returns json
language plpgsql security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  if coalesce(p_kind, 'individual') not in ('individual', 'series') then raise exception 'Unknown price.'; end if;
  if p_amount is null or p_amount < 1 or p_amount > 999 then raise exception 'Price must be between $1 and $999.'; end if;
  update prices set amount = round(p_amount, 2) where kind = coalesce(p_kind, 'individual');
  if p_kind = 'series' then update series_seasons set price = round(p_amount, 2), updated_at = now() where n = 1; end if;
  return public.admin_overview();
end $$;

drop function if exists public.admin_grant(uuid, int, text, text);
create or replace function public.admin_grant(p_member uuid, p_days int, p_note text, p_product text, p_season int default 1) returns json
language plpgsql security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  if coalesce(p_product, 'class') not in ('class', 'series') then raise exception 'Unknown product.'; end if;
  if p_days is null or p_days < 1 or p_days > 3650 then raise exception 'Choose between 1 and 3650 days.'; end if;
  if not exists (select 1 from members where id = p_member) then raise exception 'Member not found.'; end if;
  if p_product = 'series' and not exists (select 1 from series_seasons where n = coalesce(p_season, 1)) then raise exception 'Season not found.'; end if;
  insert into access_grants (member_id, kind, ref, expires_at, product, season)
  values (p_member, 'admin', left(coalesce(nullif(trim(p_note), ''), 'Granted by admin'), 120), now() + make_interval(days => p_days), coalesce(p_product, 'class'), coalesce(p_season, 1));
  return public.admin_member_grants(p_member);
end $$;

revoke all on function public.admin_save_episode(int, int, text, text, int, boolean), public.admin_delete_episode(int, int), public.admin_save_season(int, text, text, numeric, boolean, int),
  public.admin_delete_season(int), public.admin_grant(uuid, int, text, text, int) from public, anon;
grant execute on function public.admin_save_episode(int, int, text, text, int, boolean), public.admin_delete_episode(int, int), public.admin_save_season(int, text, text, numeric, boolean, int),
  public.admin_delete_season(int), public.admin_grant(uuid, int, text, text, int) to authenticated;

grant execute on function public.stripe_prepare(uuid, text, int) to service_role;
grant execute on function public.stripe_activate(text, text, integer) to service_role;

create or replace function public.admin_member_grants(p_member uuid) returns json
language plpgsql stable security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  return (select coalesce(json_agg(json_build_object('id', id, 'kind', kind, 'product', product, 'season', season, 'ref', ref, 'starts_at', starts_at, 'expires_at', expires_at,
    'active', starts_at <= now() and (expires_at is null or expires_at > now())) order by created_at desc), '[]'::json)
    from access_grants where member_id = p_member);
end $$;
