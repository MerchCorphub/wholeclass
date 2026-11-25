-- WholeClass™ — The Know Your Holes Discovery Class
-- 0001: members, saved progress, daily entries, access (paid / book key / guided group / gifted seat),
-- pricing and Stripe payments. Every table has row level security: a member only ever sees their own rows.
-- Access and payments are written only by security-definer functions, never directly by the browser.

create schema if not exists private;
revoke all on schema private from public, anon, authenticated;

-- ---------- members ----------
create table public.members (
  id uuid primary key references auth.users(id) on delete cascade,
  first_name text not null default '' check (length(first_name) <= 60),
  last_name text not null default '' check (length(last_name) <= 60),
  email text,
  faith text not null default 'biblical' check (faith in ('biblical', 'informed', 'secular')),
  adult_confirmed boolean not null default false,
  agreed_terms_at timestamptz,
  is_admin boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
alter table public.members enable row level security;
create policy members_select on public.members for select to authenticated using (id = (select auth.uid()));
create policy members_insert on public.members for insert to authenticated with check (id = (select auth.uid()) and is_admin = false);
create policy members_update on public.members for update to authenticated using (id = (select auth.uid())) with check (id = (select auth.uid()));

-- ---------- one progress record per member (the whole 14-day journey) ----------
create table public.progress (
  member_id uuid primary key references public.members(id) on delete cascade,
  day int not null default 1 check (day between 1 and 14),
  done jsonb not null default '{}'::jsonb,          -- {"1":true,"2":true,...}
  base jsonb not null default '{}'::jsonb,          -- Day 1 Quick Five scores {"Trust":4,...}
  mid jsonb not null default '{}'::jsonb,           -- Day 7 re-score
  fin jsonb not null default '{}'::jsonb,           -- Day 13 re-score (top ten)
  sev jsonb not null default '{}'::jsonb,           -- Daily Diagnosis Box severities
  sight jsonb not null default '{}'::jsonb,         -- Hunt sightings per hole
  final_top text[],                                 -- confirmed top five, in order
  origin jsonb not null default '{}'::jsonb,
  shape jsonb not null default '{}'::jsonb,
  keystone text,
  letter jsonb not null default '{}'::jsonb,        -- IWK Letter to Self, five parts
  light_used int not null default 0 check (light_used between 0 and 2),
  last_completed_on date,                           -- the member's local date when they last finished a day
  started_at timestamptz not null default now(),
  completed_at timestamptz,
  updated_at timestamptz not null default now()
);
alter table public.progress enable row level security;
create policy progress_all on public.progress for all to authenticated
  using (member_id = (select auth.uid())) with check (member_id = (select auth.uid()));

-- ---------- each finished day's private answers ----------
create table public.day_entries (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members(id) on delete cascade,
  day int not null check (day between 1 and 14),
  light boolean not null default false,
  answers jsonb not null default '{}'::jsonb,       -- IWK questions: Yes / Sometimes / No
  moment text check (length(moment) <= 4000),
  whys text[] check (array_length(whys, 1) is null or array_length(whys, 1) <= 5),
  points_to text,
  trigger text check (length(trigger) <= 500),
  who_affected text check (length(who_affected) <= 500),
  hidden_strength text check (length(hidden_strength) <= 500),
  action text check (length(action) <= 2000),
  grow text check (length(grow) <= 500),
  created_at timestamptz not null default now(),
  unique (member_id, day)
);
alter table public.day_entries enable row level security;
create policy entries_all on public.day_entries for all to authenticated
  using (member_id = (select auth.uid())) with check (member_id = (select auth.uid()));

-- ---------- prices (the browser can read them; only the database owner changes them) ----------
create table public.prices (
  kind text primary key check (kind in ('individual')),
  amount numeric(10,2) not null check (amount > 0),
  label text not null,
  days int not null default 365
);
insert into public.prices (kind, amount, label, days) values ('individual', 20.00, 'WholeClass · 14-Day Discovery Class · one year', 365);
alter table public.prices enable row level security;
create policy prices_read on public.prices for select to anon, authenticated using (true);

-- ---------- guided groups (church, ministry or counselor) ----------
create table public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  code text not null unique check (code ~ '^[A-Z0-9]{4,12}$'),
  facilitator_id uuid references public.members(id) on delete set null,
  seats int not null default 25 check (seats > 0),
  expires_at timestamptz not null default (now() + interval '1 year'),
  active boolean not null default true,
  created_at timestamptz not null default now()
);
alter table public.groups enable row level security;
create policy groups_facilitator on public.groups for select to authenticated using (facilitator_id = (select auth.uid()));

create table public.group_members (
  group_id uuid not null references public.groups(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, member_id)
);
alter table public.group_members enable row level security;
create policy gm_self on public.group_members for select to authenticated using (member_id = (select auth.uid()));

-- ---------- printed-book keys ----------
create table public.book_keys (
  code text primary key check (code ~ '^[A-Z0-9-]{6,20}$'),
  batch text,
  claimed_by uuid references public.members(id) on delete set null,
  claimed_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.book_keys enable row level security;   -- no policies: only functions touch keys

-- ---------- gifted seats ("challenge someone") ----------
create table public.seat_invites (
  code text primary key,
  giver_id uuid not null references public.members(id) on delete cascade,
  to_label text check (length(to_label) <= 80),
  claimed_by uuid references public.members(id) on delete set null,
  claimed_at timestamptz,
  created_at timestamptz not null default now()
);
alter table public.seat_invites enable row level security;
create policy invites_giver on public.seat_invites for select to authenticated using (giver_id = (select auth.uid()));

-- ---------- access grants ----------
create table public.access_grants (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members(id) on delete cascade,
  kind text not null check (kind in ('paid', 'book_key', 'group', 'seat', 'admin')),
  ref text,
  starts_at timestamptz not null default now(),
  expires_at timestamptz,
  created_at timestamptz not null default now()
);
create index on public.access_grants (member_id);
alter table public.access_grants enable row level security;
create policy access_self on public.access_grants for select to authenticated using (member_id = (select auth.uid()));

-- ---------- payments (written only by the stripe-pay server function) ----------
create table public.payments (
  id uuid primary key default gen_random_uuid(),
  member_id uuid references public.members(id) on delete set null,
  email text,
  description text not null,
  amount numeric(10,2) not null check (amount > 0),
  currency text not null default 'usd',
  status text not null default 'open' check (status in ('open', 'paid', 'expired')),
  stripe_session_id text unique,
  stripe_payment_intent text,
  created_at timestamptz not null default now(),
  paid_at timestamptz
);
create index on public.payments (member_id);
alter table public.payments enable row level security;
create policy payments_self on public.payments for select to authenticated using (member_id = (select auth.uid()));

-- ---------- interest list for upcoming courses ----------
create table public.course_interest (
  member_id uuid not null references public.members(id) on delete cascade,
  course text not null check (course in ('kyh_series')),
  created_at timestamptz not null default now(),
  primary key (member_id, course)
);
alter table public.course_interest enable row level security;
create policy interest_self on public.course_interest for all to authenticated
  using (member_id = (select auth.uid())) with check (member_id = (select auth.uid()));

-- ================= helpers =================
create or replace function private.has_access(uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from access_grants a where a.member_id = uid and a.starts_at <= now() and (a.expires_at is null or a.expires_at > now())) $$;

create or replace function private.new_code(n int) returns text
language sql volatile set search_path = public as $$
  select string_agg(substr('ABCDEFGHJKLMNPQRSTUVWXYZ23456789', 1 + floor(random() * 32)::int, 1), '') from generate_series(1, n) $$;

-- ================= member-facing functions =================

-- Create my member row and progress row on first sign-in (safe to call every time)
create or replace function public.ensure_member(p_first text, p_last text, p_faith text, p_adult boolean, p_agreed boolean)
returns public.members language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m members;
begin
  if uid is null then raise exception 'Please sign in.'; end if;
  select * into m from members where id = uid;
  if m.id is null then
    insert into members (id, first_name, last_name, email, faith, adult_confirmed, agreed_terms_at)
    values (uid, left(coalesce(nullif(trim(p_first), ''), split_part((select email from auth.users where id = uid), '@', 1)), 60), left(coalesce(trim(p_last), ''), 60),
            (select email from auth.users where id = uid),
            case when p_faith in ('biblical', 'informed', 'secular') then p_faith else 'biblical' end,
            coalesce(p_adult, false), case when p_agreed then now() end)
    returning * into m;
  end if;
  insert into progress (member_id) values (uid) on conflict do nothing;
  return m;
end $$;

-- What I can open right now
create or replace function public.my_access()
returns json language plpgsql stable security definer set search_path = public, private as $$
declare uid uuid := auth.uid(); g access_grants; price prices; seats_used int;
begin
  if uid is null then return json_build_object('signed_in', false); end if;
  select * into g from access_grants a where a.member_id = uid and a.starts_at <= now() and (a.expires_at is null or a.expires_at > now())
    order by a.expires_at desc nulls first limit 1;
  select * into price from prices where kind = 'individual';
  select count(*) into seats_used from seat_invites where giver_id = uid and created_at > now() - interval '1 year';
  return json_build_object('signed_in', true, 'unlocked', g.id is not null, 'kind', g.kind, 'expires_at', g.expires_at,
    'price', price.amount, 'seats_left', case when g.kind in ('paid', 'book_key', 'admin') then greatest(4 - seats_used, 0) else 0 end,
    'group', (select json_build_object('name', gr.name) from group_members gm join groups gr on gr.id = gm.group_id where gm.member_id = uid order by gm.joined_at desc limit 1));
end $$;

-- Printed book key
create or replace function public.redeem_book_key(p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); k book_keys; c text := upper(regexp_replace(coalesce(p_code, ''), '\s', '', 'g'));
begin
  if uid is null then raise exception 'Please sign in.'; end if;
  select * into k from book_keys where code = c for update;
  if k.code is null then raise exception 'That book key was not found. Check the code inside the back cover.'; end if;
  if k.claimed_by is not null and k.claimed_by <> uid then raise exception 'That book key has already been used.'; end if;
  if k.claimed_by is null then
    update book_keys set claimed_by = uid, claimed_at = now() where code = c;
    insert into access_grants (member_id, kind, ref, expires_at) values (uid, 'book_key', c, now() + interval '1 year');
  end if;
  return public.my_access();
end $$;

-- Guided group code
create or replace function public.join_group(p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); g groups; used int; c text := upper(regexp_replace(coalesce(p_code, ''), '\s', '', 'g'));
begin
  if uid is null then raise exception 'Please sign in.'; end if;
  select * into g from groups where code = c and active for update;
  if g.id is null then raise exception 'That group code was not found. Ask your facilitator to check it.'; end if;
  if g.expires_at <= now() then raise exception 'That group''s seats have ended. Ask your facilitator.'; end if;
  if not exists (select 1 from group_members where group_id = g.id and member_id = uid) then
    select count(*) into used from group_members where group_id = g.id;
    if used >= g.seats then raise exception 'This group is full. Ask your facilitator to add seats.'; end if;
    insert into group_members (group_id, member_id) values (g.id, uid);
    insert into access_grants (member_id, kind, ref, expires_at) values (uid, 'group', g.id::text, g.expires_at);
  end if;
  return public.my_access();
end $$;

-- Give a seat to someone (up to 4 a year, for members who bought or redeemed a book key)
create or replace function public.give_seat(p_to text)
returns json language plpgsql security definer set search_path = public, private as $$
declare uid uuid := auth.uid(); used int; c text; v_kind text;
begin
  if uid is null then raise exception 'Please sign in.'; end if;
  select a.kind into v_kind from access_grants a where a.member_id = uid and (a.expires_at is null or a.expires_at > now()) and a.kind in ('paid', 'book_key', 'admin') limit 1;
  if v_kind is null then raise exception 'Seats to give come with your own purchase or book key.'; end if;
  select count(*) into used from seat_invites where giver_id = uid and created_at > now() - interval '1 year';
  if used >= 4 then raise exception 'You have given all 4 seats for this year.'; end if;
  loop
    c := private.new_code(8);
    exit when not exists (select 1 from seat_invites where code = c);
  end loop;
  insert into seat_invites (code, giver_id, to_label) values (c, uid, left(nullif(trim(p_to), ''), 80));
  return json_build_object('code', c, 'seats_left', 3 - used);
end $$;

-- Accept a gifted seat: the full class for 30 days
create or replace function public.accept_seat(p_code text)
returns json language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); s seat_invites; c text := upper(regexp_replace(coalesce(p_code, ''), '\s', '', 'g'));
begin
  if uid is null then raise exception 'Please sign in.'; end if;
  select * into s from seat_invites where code = c for update;
  if s.code is null then raise exception 'That invitation was not found.'; end if;
  if s.giver_id = uid then raise exception 'This is a seat you gave. Send the link to the person you are challenging.'; end if;
  if s.claimed_by is not null and s.claimed_by <> uid then raise exception 'Someone has already accepted this seat.'; end if;
  if s.claimed_by is null then
    update seat_invites set claimed_by = uid, claimed_at = now() where code = c;
    insert into access_grants (member_id, kind, ref, expires_at) values (uid, 'seat', c, now() + interval '30 days');
  end if;
  return public.my_access();
end $$;

-- Facilitators see completion only: names and days finished, never answers
create or replace function public.group_completion(p_group uuid)
returns table (first_name text, last_name text, days_done int, current_day int, completed boolean, joined_at timestamptz)
language sql stable security definer set search_path = public as $$
  select m.first_name, m.last_name,
         (select count(*)::int from jsonb_object_keys(coalesce(p.done, '{}'::jsonb))), coalesce(p.day, 1), p.completed_at is not null, gm.joined_at
  from groups g join group_members gm on gm.group_id = g.id join members m on m.id = gm.member_id left join progress p on p.member_id = m.id
  where g.id = p_group and (g.facilitator_id = auth.uid() or exists (select 1 from members a where a.id = auth.uid() and a.is_admin))
  order by m.last_name, m.first_name $$;

-- Everything I have saved, as one file
create or replace function public.export_my_data()
returns json language sql stable security definer set search_path = public as $$
  select json_build_object(
    'member', (select row_to_json(m) from members m where m.id = auth.uid()),
    'progress', (select row_to_json(p) from progress p where p.member_id = auth.uid()),
    'days', (select coalesce(json_agg(row_to_json(d) order by d.day), '[]'::json) from day_entries d where d.member_id = auth.uid()),
    'access', (select coalesce(json_agg(row_to_json(a)), '[]'::json) from access_grants a where a.member_id = auth.uid()),
    'exported_at', now()) $$;

-- Erase my answers and progress (account and payment records stay for the purchase history)
create or replace function public.erase_my_answers()
returns void language plpgsql security definer set search_path = public as $$
begin
  if auth.uid() is null then raise exception 'Please sign in.'; end if;
  delete from day_entries where member_id = auth.uid();
  delete from progress where member_id = auth.uid();
  insert into progress (member_id) values (auth.uid());
end $$;

-- ================= called only by the stripe-pay server function =================
create or replace function public.stripe_prepare(p_user uuid)
returns json language plpgsql security definer set search_path = public, private as $$
declare m members; pr prices; pay uuid;
begin
  select * into m from members where id = p_user;
  if m.id is null then raise exception 'Create your account first.'; end if;
  if private.has_access(p_user) and exists (select 1 from access_grants where member_id = p_user and kind in ('paid', 'book_key', 'admin') and (expires_at is null or expires_at > now())) then
    raise exception 'Your class is already open.';
  end if;
  select * into pr from prices where kind = 'individual';
  insert into payments (member_id, email, description, amount) values (p_user, m.email, pr.label, pr.amount) returning id into pay;
  return json_build_object('payment_id', pay, 'amount_cents', (pr.amount * 100)::int, 'description', pr.label, 'email', m.email);
end $$;

create or replace function public.stripe_attach_session(p_payment uuid, p_session text)
returns void language sql security definer set search_path = public as $$
  update payments set stripe_session_id = p_session where id = p_payment and status = 'open' $$;

create or replace function public.stripe_activate(p_session text, p_intent text, p_amount_cents int)
returns text language plpgsql security definer set search_path = public as $$
declare p payments; d int;
begin
  select * into p from payments where stripe_session_id = p_session for update;
  if p.id is null then raise exception 'Payment not found.'; end if;
  if p.status = 'paid' then return 'already'; end if;
  if p_amount_cents < (p.amount * 100)::int then raise exception 'The amount paid does not match.'; end if;
  select days into d from prices where kind = 'individual';
  update payments set status = 'paid', paid_at = now(), stripe_payment_intent = p_intent where id = p.id;
  insert into access_grants (member_id, kind, ref, expires_at) values (p.member_id, 'paid', p.id::text, now() + make_interval(days => coalesce(d, 365)));
  return 'paid';
end $$;

create or replace function public.stripe_expire(p_session text)
returns void language sql security definer set search_path = public as $$
  update payments set status = 'expired' where stripe_session_id = p_session and status = 'open' $$;

-- ================= permissions =================
revoke execute on all functions in schema public from public, anon;
revoke execute on all functions in schema private from public, anon, authenticated;
grant usage on schema private to service_role;
grant execute on function public.ensure_member(text, text, text, boolean, boolean), public.my_access(), public.redeem_book_key(text),
  public.join_group(text), public.give_seat(text), public.accept_seat(text), public.group_completion(uuid),
  public.export_my_data(), public.erase_my_answers() to authenticated;
revoke execute on function public.stripe_prepare(uuid), public.stripe_attach_session(uuid, text), public.stripe_activate(text, text, int), public.stripe_expire(text) from authenticated;
grant execute on function public.stripe_prepare(uuid), public.stripe_attach_session(uuid, text), public.stripe_activate(text, text, int), public.stripe_expire(text) to service_role;

-- keep updated_at honest
create or replace function private.touch() returns trigger language plpgsql as $$ begin new.updated_at := now(); return new; end $$;
-- is_admin can never be changed from the browser
create or replace function private.members_guard() returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  if current_user in ('authenticated', 'anon') then new.is_admin := old.is_admin; new.id := old.id; end if;
  return new;
end $$;
create trigger members_touch before update on public.members for each row execute function private.members_guard();
create trigger progress_touch before update on public.progress for each row execute function private.touch();
