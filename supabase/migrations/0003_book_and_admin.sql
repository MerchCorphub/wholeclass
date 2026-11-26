-- WholeClass 0003: Know Your Holes inside the app (chapters readable only with class access; the note and
-- Chapter 1 are free) and the admin console / facilitator functions. Every admin function checks is_admin.

-- ---------- book ----------
create table public.book_chapters (
  n int primary key check (n between 0 and 99),
  title text not null,
  html text not null,
  free boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.book_chapters enable row level security;
create policy chapters_read on public.book_chapters for select to authenticated using (
  free
  or exists (select 1 from public.access_grants a where a.member_id = (select auth.uid()) and a.starts_at <= now() and (a.expires_at is null or a.expires_at > now()))
  or exists (select 1 from public.members m where m.id = (select auth.uid()) and m.is_admin)
);

-- ---------- helpers ----------
create or replace function private.is_admin() returns boolean
language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from members where id = auth.uid()), false) $$;

create or replace function private.require_admin() returns void
language plpgsql stable security definer set search_path = public as $$
begin
  if not private.is_admin() then raise exception 'Admins only.'; end if;
end $$;

-- ---------- who am I (for the console) ----------
create or replace function public.console_me()
returns json language sql stable security definer set search_path = public, private as $$
  select json_build_object('admin', private.is_admin(),
    'facilitator', exists (select 1 from groups where facilitator_id = auth.uid()),
    'name', (select first_name from members where id = auth.uid())) $$;

-- ---------- overview ----------
create or replace function public.admin_overview()
returns json language plpgsql stable security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  return json_build_object(
    'members', (select count(*) from members),
    'new_7d', (select count(*) from members where created_at > now() - interval '7 days'),
    'quick_five_done', (select count(*) from progress where (done ? '1')),
    'open_access', (select count(distinct member_id) from access_grants where starts_at <= now() and (expires_at is null or expires_at > now())),
    'by_kind', (select coalesce(json_object_agg(kind, n), '{}'::json) from (select kind, count(distinct member_id) n from access_grants where expires_at is null or expires_at > now() group by kind) k),
    'completed', (select count(*) from progress where completed_at is not null),
    'paid_count', (select count(*) from payments where status = 'paid'),
    'revenue', (select coalesce(sum(amount), 0) from payments where status = 'paid'),
    'revenue_30d', (select coalesce(sum(amount), 0) from payments where status = 'paid' and paid_at > now() - interval '30 days'),
    'groups', (select count(*) from groups where active),
    'keys_total', (select count(*) from book_keys),
    'keys_claimed', (select count(*) from book_keys where claimed_by is not null),
    'seats_given', (select count(*) from seat_invites),
    'seats_accepted', (select count(*) from seat_invites where claimed_by is not null),
    'series_interest', (select count(*) from course_interest where course = 'kyh_series'),
    'price', (select amount from prices where kind = 'individual'),
    'by_day', (select coalesce(json_agg(json_build_object('day', d, 'n', n) order by d), '[]'::json) from (select day d, count(*) n from progress group by day) x));
end $$;

-- ---------- members ----------
create or replace function public.admin_members(p_search text default '')
returns json language plpgsql stable security definer set search_path = public, private as $$
declare q text := '%' || lower(coalesce(trim(p_search), '')) || '%';
begin
  perform private.require_admin();
  return (select coalesce(json_agg(r order by r.created_at desc), '[]'::json) from (
    select m.id, m.first_name, m.last_name, m.email, m.created_at, m.is_admin,
           coalesce(p.day, 1) as day, (select count(*) from jsonb_object_keys(coalesce(p.done, '{}'::jsonb))) as days_done, p.completed_at,
           (select json_build_object('kind', a.kind, 'expires_at', a.expires_at) from access_grants a where a.member_id = m.id and a.starts_at <= now() and (a.expires_at is null or a.expires_at > now()) order by a.expires_at desc nulls first limit 1) as access,
           (select g.name from group_members gm join groups g on g.id = gm.group_id where gm.member_id = m.id order by gm.joined_at desc limit 1) as group_name
    from members m left join progress p on p.member_id = m.id
    where lower(m.first_name || ' ' || m.last_name || ' ' || coalesce(m.email, '')) like q
    order by m.created_at desc limit 300) r);
end $$;

create or replace function public.admin_member_grants(p_member uuid)
returns json language plpgsql stable security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  return (select coalesce(json_agg(json_build_object('id', id, 'kind', kind, 'ref', ref, 'starts_at', starts_at, 'expires_at', expires_at,
    'active', starts_at <= now() and (expires_at is null or expires_at > now())) order by created_at desc), '[]'::json)
    from access_grants where member_id = p_member);
end $$;

create or replace function public.admin_grant(p_member uuid, p_days int, p_note text)
returns json language plpgsql security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  if p_days is null or p_days < 1 or p_days > 3650 then raise exception 'Choose between 1 and 3650 days.'; end if;
  if not exists (select 1 from members where id = p_member) then raise exception 'Member not found.'; end if;
  insert into access_grants (member_id, kind, ref, expires_at) values (p_member, 'admin', left(coalesce(nullif(trim(p_note), ''), 'Granted by admin'), 120), now() + make_interval(days => p_days));
  return public.admin_member_grants(p_member);
end $$;

create or replace function public.admin_revoke(p_grant uuid)
returns json language plpgsql security definer set search_path = public, private as $$
declare m uuid;
begin
  perform private.require_admin();
  update access_grants set expires_at = now() where id = p_grant and (expires_at is null or expires_at > now()) returning member_id into m;
  if m is null then raise exception 'That access is already ended.'; end if;
  return public.admin_member_grants(m);
end $$;

create or replace function public.admin_set_admin(p_email text, p_on boolean)
returns void language plpgsql security definer set search_path = public, private as $$
declare n int;
begin
  perform private.require_admin();
  if not p_on and lower(trim(p_email)) = lower((select email from members where id = auth.uid())) then raise exception 'You cannot remove your own admin access.'; end if;
  update members set is_admin = p_on where lower(email) = lower(trim(p_email));
  get diagnostics n = row_count;
  if n = 0 then raise exception 'No member with that email. They need to create an account first.'; end if;
end $$;

-- ---------- guided groups ----------
create or replace function public.admin_groups()
returns json language plpgsql stable security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  return (select coalesce(json_agg(r order by r.created_at desc), '[]'::json) from (
    select g.id, g.name, g.code, g.seats, g.expires_at, g.active, g.created_at,
           (select email from members where id = g.facilitator_id) as facilitator_email,
           (select count(*) from group_members where group_id = g.id) as used,
           (select count(*) from group_members gm join progress p on p.member_id = gm.member_id where gm.group_id = g.id and p.completed_at is not null) as completed
    from groups g) r);
end $$;

create or replace function public.admin_save_group(p_id uuid, p_name text, p_code text, p_seats int, p_expires date, p_active boolean, p_facilitator_email text)
returns json language plpgsql security definer set search_path = public, private as $$
declare f uuid; c text := upper(regexp_replace(coalesce(p_code, ''), '[^A-Za-z0-9]', '', 'g')); gid uuid;
begin
  perform private.require_admin();
  if coalesce(trim(p_name), '') = '' then raise exception 'Give the group a name.'; end if;
  if c = '' then loop c := private.new_code(6); exit when not exists (select 1 from groups where code = c); end loop; end if;
  if length(c) < 4 or length(c) > 12 then raise exception 'Codes are 4 to 12 letters or numbers.'; end if;
  if coalesce(trim(p_facilitator_email), '') <> '' then
    select id into f from members where lower(email) = lower(trim(p_facilitator_email));
    if f is null then raise exception 'No member with that facilitator email. They need to create an account first.'; end if;
  end if;
  if p_id is null then
    insert into groups (name, code, seats, expires_at, active, facilitator_id)
    values (trim(p_name), c, greatest(coalesce(p_seats, 25), 1), coalesce(p_expires::timestamptz + interval '1 day', now() + interval '1 year'), coalesce(p_active, true), f)
    returning id into gid;
  else
    update groups set name = trim(p_name), code = c, seats = greatest(coalesce(p_seats, seats), 1),
      expires_at = coalesce(p_expires::timestamptz + interval '1 day', expires_at), active = coalesce(p_active, active), facilitator_id = f
    where id = p_id returning id into gid;
    if gid is null then raise exception 'Group not found.'; end if;
    -- keep members' access in step with the group's end date
    update access_grants set expires_at = (select expires_at from groups where id = gid) where kind = 'group' and ref = gid::text and (expires_at is null or expires_at > now());
    if not coalesce(p_active, true) then update access_grants set expires_at = now() where kind = 'group' and ref = gid::text and (expires_at is null or expires_at > now()); end if;
  end if;
  return public.admin_groups();
exception when unique_violation then raise exception 'That code is already used by another group.';
end $$;

-- facilitators: the groups I lead (admins see all)
create or replace function public.my_groups()
returns json language sql stable security definer set search_path = public, private as $$
  select coalesce(json_agg(json_build_object('id', g.id, 'name', g.name, 'code', g.code, 'seats', g.seats, 'expires_at', g.expires_at,
    'used', (select count(*) from group_members where group_id = g.id)) order by g.name), '[]'::json)
  from groups g where g.facilitator_id = auth.uid() $$;

-- ---------- book keys ----------
create or replace function public.admin_make_keys(p_count int, p_batch text)
returns json language plpgsql security definer set search_path = public, private as $$
declare out text[] := '{}'; c text; i int := 0;
begin
  perform private.require_admin();
  if p_count is null or p_count < 1 or p_count > 2000 then raise exception 'Make between 1 and 2000 keys at a time.'; end if;
  while i < p_count loop
    c := private.new_code(4) || '-' || private.new_code(4);
    if not exists (select 1 from book_keys where code = c) then
      insert into book_keys (code, batch) values (c, left(coalesce(nullif(trim(p_batch), ''), to_char(now(), 'YYYY-MM-DD')), 60));
      out := out || c; i := i + 1;
    end if;
  end loop;
  return to_json(out);
end $$;

create or replace function public.admin_keys(p_batch text default null)
returns json language plpgsql stable security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  return json_build_object(
    'batches', (select coalesce(json_agg(b order by b.created desc), '[]'::json) from (select batch, count(*) total, count(claimed_by) claimed, min(created_at) created from book_keys group by batch) b),
    'keys', (select coalesce(json_agg(json_build_object('code', k.code, 'batch', k.batch, 'claimed_at', k.claimed_at, 'claimed_by', (select email from members where id = k.claimed_by)) order by k.created_at, k.code), '[]'::json)
             from book_keys k where p_batch is null or k.batch = p_batch));
end $$;

-- ---------- payments and price ----------
create or replace function public.admin_payments()
returns json language plpgsql stable security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  return (select coalesce(json_agg(json_build_object('created_at', p.created_at, 'paid_at', p.paid_at, 'email', p.email, 'amount', p.amount, 'status', p.status,
    'name', (select first_name || ' ' || last_name from members where id = p.member_id)) order by p.created_at desc), '[]'::json)
    from (select * from payments order by created_at desc limit 300) p);
end $$;

create or replace function public.admin_set_price(p_amount numeric)
returns json language plpgsql security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  if p_amount is null or p_amount < 1 or p_amount > 999 then raise exception 'Price must be between $1 and $999.'; end if;
  update prices set amount = round(p_amount, 2) where kind = 'individual';
  return public.admin_overview();
end $$;

-- ---------- permissions ----------
revoke execute on function private.is_admin(), private.require_admin() from public, anon, authenticated;
revoke execute on function public.console_me(), public.admin_overview(), public.admin_members(text), public.admin_member_grants(uuid), public.admin_grant(uuid, int, text),
  public.admin_revoke(uuid), public.admin_set_admin(text, boolean), public.admin_groups(), public.admin_save_group(uuid, text, text, int, date, boolean, text),
  public.my_groups(), public.admin_make_keys(int, text), public.admin_keys(text), public.admin_payments(), public.admin_set_price(numeric) from public, anon;
grant execute on function public.console_me(), public.admin_overview(), public.admin_members(text), public.admin_member_grants(uuid), public.admin_grant(uuid, int, text),
  public.admin_revoke(uuid), public.admin_set_admin(text, boolean), public.admin_groups(), public.admin_save_group(uuid, text, text, int, date, boolean, text),
  public.my_groups(), public.admin_make_keys(int, text), public.admin_keys(text), public.admin_payments(), public.admin_set_price(numeric) to authenticated;
