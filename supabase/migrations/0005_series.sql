-- WholeClass 0005: the Know Your Holes Series — audio lessons (Introduction + Chapters 1–13), a separate
-- one-time purchase ($14.99, one year). Introduction and Chapter 1 are free. Class access and Series access
-- are kept apart by a "product" on every access grant and payment.

-- ---------- products on grants, payments and prices ----------
alter table public.access_grants add column product text not null default 'class' check (product in ('class', 'series'));
alter table public.payments add column product text not null default 'class' check (product in ('class', 'series'));
alter table public.prices drop constraint prices_kind_check;
alter table public.prices add constraint prices_kind_check check (kind in ('individual', 'series'));
insert into public.prices (kind, amount, label, days) values ('series', 14.99, 'WholeClass · Know Your Holes Series · one year', 365);

-- ---------- lessons ----------
create table public.series_lessons (
  n int primary key check (n between 0 and 99),
  title text not null,
  html text not null,
  free boolean not null default false,
  updated_at timestamptz not null default now()
);
alter table public.series_lessons enable row level security;
create policy series_read on public.series_lessons for select to authenticated using (
  free
  or exists (select 1 from public.access_grants a where a.member_id = (select auth.uid()) and a.product = 'series' and a.starts_at <= now() and (a.expires_at is null or a.expires_at > now()))
  or exists (select 1 from public.members m where m.id = (select auth.uid()) and m.is_admin)
);

-- the book stays tied to class access only
drop policy chapters_read on public.book_chapters;
create policy chapters_read on public.book_chapters for select to authenticated using (
  free
  or exists (select 1 from public.access_grants a where a.member_id = (select auth.uid()) and a.product = 'class' and a.starts_at <= now() and (a.expires_at is null or a.expires_at > now()))
  or exists (select 1 from public.members m where m.id = (select auth.uid()) and m.is_admin)
);

-- ---------- class-only helpers ----------
create or replace function private.has_access(uid uuid) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from access_grants a where a.member_id = uid and a.product = 'class' and a.starts_at <= now() and (a.expires_at is null or a.expires_at > now())) $$;

create or replace function public.my_access()
returns json language plpgsql stable security definer set search_path = public, private as $$
declare uid uuid := auth.uid(); g access_grants; sg access_grants; price prices; sprice prices; seats_used int;
begin
  if uid is null then return json_build_object('signed_in', false); end if;
  select * into g from access_grants a where a.member_id = uid and a.product = 'class' and a.starts_at <= now() and (a.expires_at is null or a.expires_at > now())
    order by a.expires_at desc nulls first limit 1;
  select * into sg from access_grants a where a.member_id = uid and a.product = 'series' and a.starts_at <= now() and (a.expires_at is null or a.expires_at > now())
    order by a.expires_at desc nulls first limit 1;
  select * into price from prices where kind = 'individual';
  select * into sprice from prices where kind = 'series';
  select count(*) into seats_used from seat_invites where giver_id = uid and created_at > now() - interval '1 year';
  return json_build_object('signed_in', true, 'unlocked', g.id is not null, 'kind', g.kind, 'expires_at', g.expires_at,
    'price', price.amount, 'seats_left', case when g.kind in ('paid', 'book_key', 'admin') then greatest(4 - seats_used, 0) else 0 end,
    'group', (select json_build_object('name', gr.name) from group_members gm join groups gr on gr.id = gm.group_id where gm.member_id = uid order by gm.joined_at desc limit 1),
    'series_unlocked', sg.id is not null, 'series_expires_at', sg.expires_at, 'series_price', sprice.amount);
end $$;

create or replace function public.give_seat(p_to text)
returns json language plpgsql security definer set search_path = public, private as $$
declare uid uuid := auth.uid(); used int; c text; v_kind text;
begin
  if uid is null then raise exception 'Please sign in.'; end if;
  select a.kind into v_kind from access_grants a where a.member_id = uid and a.product = 'class' and (a.expires_at is null or a.expires_at > now()) and a.kind in ('paid', 'book_key', 'admin') limit 1;
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

-- ---------- Stripe (server only), now product-aware ----------
drop function public.stripe_prepare(uuid);
create function public.stripe_prepare(p_user uuid, p_product text)
returns json language plpgsql security definer set search_path = public, private as $$
declare m members; pr prices; pay uuid; prod text := coalesce(p_product, 'class');
begin
  if prod not in ('class', 'series') then raise exception 'Unknown product.'; end if;
  select * into m from members where id = p_user;
  if m.id is null then raise exception 'Create your account first.'; end if;
  if prod = 'class' and exists (select 1 from access_grants where member_id = p_user and product = 'class' and kind in ('paid', 'book_key', 'admin') and (expires_at is null or expires_at > now())) then
    raise exception 'Your class is already open.';
  end if;
  if prod = 'series' and exists (select 1 from access_grants where member_id = p_user and product = 'series' and (expires_at is null or expires_at > now())) then
    raise exception 'Your Series is already open.';
  end if;
  select * into pr from prices where kind = case prod when 'series' then 'series' else 'individual' end;
  insert into payments (member_id, email, description, amount, product) values (p_user, m.email, pr.label, pr.amount, prod) returning id into pay;
  return json_build_object('payment_id', pay, 'amount_cents', round(pr.amount * 100)::int, 'description', pr.label, 'email', m.email, 'product', prod);
end $$;

create or replace function public.stripe_activate(p_session text, p_intent text, p_amount_cents int)
returns text language plpgsql security definer set search_path = public as $$
declare p payments; d int;
begin
  select * into p from payments where stripe_session_id = p_session for update;
  if p.id is null then raise exception 'Payment not found.'; end if;
  if p.status = 'paid' then return 'already'; end if;
  if p_amount_cents < round(p.amount * 100)::int then raise exception 'The amount paid does not match.'; end if;
  select days into d from prices where kind = case p.product when 'series' then 'series' else 'individual' end;
  update payments set status = 'paid', paid_at = now(), stripe_payment_intent = p_intent where id = p.id;
  insert into access_grants (member_id, kind, ref, expires_at, product) values (p.member_id, 'paid', p.id::text, now() + make_interval(days => coalesce(d, 365)), p.product);
  return 'paid';
end $$;

revoke execute on function public.stripe_prepare(uuid, text) from public, anon, authenticated;
grant execute on function public.stripe_prepare(uuid, text) to service_role;

-- ---------- member-facing Series list ----------
create or replace function public.series_contents()
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('n', n, 'title', title, 'free', free) order by n), '[]'::json) from series_lessons $$;
revoke execute on function public.series_contents() from public, anon;
grant execute on function public.series_contents() to authenticated;

-- ---------- admin ----------
create or replace function public.admin_member_grants(p_member uuid)
returns json language plpgsql stable security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  return (select coalesce(json_agg(json_build_object('id', id, 'kind', kind, 'product', product, 'ref', ref, 'starts_at', starts_at, 'expires_at', expires_at,
    'active', starts_at <= now() and (expires_at is null or expires_at > now())) order by created_at desc), '[]'::json)
    from access_grants where member_id = p_member);
end $$;

drop function public.admin_grant(uuid, int, text);
create function public.admin_grant(p_member uuid, p_days int, p_note text, p_product text)
returns json language plpgsql security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  if coalesce(p_product, 'class') not in ('class', 'series') then raise exception 'Unknown product.'; end if;
  if p_days is null or p_days < 1 or p_days > 3650 then raise exception 'Choose between 1 and 3650 days.'; end if;
  if not exists (select 1 from members where id = p_member) then raise exception 'Member not found.'; end if;
  insert into access_grants (member_id, kind, ref, expires_at, product)
  values (p_member, 'admin', left(coalesce(nullif(trim(p_note), ''), 'Granted by admin'), 120), now() + make_interval(days => p_days), coalesce(p_product, 'class'));
  return public.admin_member_grants(p_member);
end $$;

create or replace function public.admin_members(p_search text default '')
returns json language plpgsql stable security definer set search_path = public, private as $$
declare q text := '%' || lower(coalesce(trim(p_search), '')) || '%';
begin
  perform private.require_admin();
  return (select coalesce(json_agg(r order by r.created_at desc), '[]'::json) from (
    select m.id, m.first_name, m.last_name, m.email, m.created_at, m.is_admin,
           coalesce(p.day, 1) as day, (select count(*) from jsonb_object_keys(coalesce(p.done, '{}'::jsonb))) as days_done, p.completed_at,
           (select json_build_object('kind', a.kind, 'expires_at', a.expires_at) from access_grants a where a.member_id = m.id and a.product = 'class' and a.starts_at <= now() and (a.expires_at is null or a.expires_at > now()) order by a.expires_at desc nulls first limit 1) as access,
           (select json_build_object('kind', a.kind, 'expires_at', a.expires_at) from access_grants a where a.member_id = m.id and a.product = 'series' and a.starts_at <= now() and (a.expires_at is null or a.expires_at > now()) order by a.expires_at desc nulls first limit 1) as series,
           (select g.name from group_members gm join groups g on g.id = gm.group_id where gm.member_id = m.id order by gm.joined_at desc limit 1) as group_name
    from members m left join progress p on p.member_id = m.id
    where lower(m.first_name || ' ' || m.last_name || ' ' || coalesce(m.email, '')) like q
    order by m.created_at desc limit 300) r);
end $$;

create or replace function public.admin_overview()
returns json language plpgsql stable security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  return json_build_object(
    'members', (select count(*) from members),
    'new_7d', (select count(*) from members where created_at > now() - interval '7 days'),
    'quick_five_done', (select count(*) from progress where (done ? '1')),
    'open_access', (select count(distinct member_id) from access_grants where product = 'class' and starts_at <= now() and (expires_at is null or expires_at > now())),
    'by_kind', (select coalesce(json_object_agg(kind, n), '{}'::json) from (select kind, count(distinct member_id) n from access_grants where product = 'class' and (expires_at is null or expires_at > now()) group by kind) k),
    'completed', (select count(*) from progress where completed_at is not null),
    'paid_count', (select count(*) from payments where status = 'paid' and product = 'class'),
    'revenue', (select coalesce(sum(amount), 0) from payments where status = 'paid'),
    'revenue_30d', (select coalesce(sum(amount), 0) from payments where status = 'paid' and paid_at > now() - interval '30 days'),
    'groups', (select count(*) from groups where active),
    'keys_total', (select count(*) from book_keys),
    'keys_claimed', (select count(*) from book_keys where claimed_by is not null),
    'seats_given', (select count(*) from seat_invites),
    'seats_accepted', (select count(*) from seat_invites where claimed_by is not null),
    'series_open', (select count(distinct member_id) from access_grants where product = 'series' and starts_at <= now() and (expires_at is null or expires_at > now())),
    'series_paid', (select count(*) from payments where status = 'paid' and product = 'series'),
    'series_interest', (select count(*) from course_interest where course = 'kyh_series'),
    'price', (select amount from prices where kind = 'individual'),
    'series_price', (select amount from prices where kind = 'series'),
    'by_day', (select coalesce(json_agg(json_build_object('day', d, 'n', n) order by d), '[]'::json) from (select day d, count(*) n from progress group by day) x));
end $$;

create or replace function public.admin_payments()
returns json language plpgsql stable security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  return (select coalesce(json_agg(json_build_object('created_at', p.created_at, 'paid_at', p.paid_at, 'email', p.email, 'amount', p.amount, 'status', p.status, 'product', p.product,
    'name', (select first_name || ' ' || last_name from members where id = p.member_id)) order by p.created_at desc), '[]'::json)
    from (select * from payments order by created_at desc limit 300) p);
end $$;

drop function public.admin_set_price(numeric);
create function public.admin_set_price(p_amount numeric, p_kind text)
returns json language plpgsql security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  if coalesce(p_kind, 'individual') not in ('individual', 'series') then raise exception 'Unknown price.'; end if;
  if p_amount is null or p_amount < 1 or p_amount > 999 then raise exception 'Price must be between $1 and $999.'; end if;
  update prices set amount = round(p_amount, 2) where kind = coalesce(p_kind, 'individual');
  return public.admin_overview();
end $$;

create or replace function public.admin_series()
returns json language plpgsql stable security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  return (select coalesce(json_agg(json_build_object('n', n, 'title', title, 'free', free, 'chars', length(html), 'updated_at', updated_at) order by n), '[]'::json) from series_lessons);
end $$;

create or replace function public.admin_save_series(p_lessons json)
returns json language plpgsql security definer set search_path = public, private as $$
declare c json; saved int := 0;
begin
  perform private.require_admin();
  if json_typeof(p_lessons) <> 'array' or json_array_length(p_lessons) < 1 or json_array_length(p_lessons) > 60 then raise exception 'The Series needs between 1 and 60 lessons.'; end if;
  delete from public.series_lessons sl where sl.n >= 0;
  for c in select * from json_array_elements(p_lessons) loop
    if length(c->>'html') > 200000 then raise exception 'A lesson is too long.'; end if;
    insert into public.series_lessons (n, title, html, free) values ((c->>'n')::int, left(c->>'title', 200), c->>'html', coalesce((c->>'free')::boolean, false));
    saved := saved + 1;
  end loop;
  return json_build_object('saved', saved);
end $$;

create or replace function public.admin_set_lesson_free(p_n int, p_free boolean)
returns json language plpgsql security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  update series_lessons set free = p_free where n = p_n;
  return public.admin_series();
end $$;

revoke execute on function public.admin_grant(uuid, int, text, text), public.admin_set_price(numeric, text), public.admin_series(),
  public.admin_save_series(json), public.admin_set_lesson_free(int, boolean) from public, anon;
grant execute on function public.admin_grant(uuid, int, text, text), public.admin_set_price(numeric, text), public.admin_series(),
  public.admin_save_series(json), public.admin_set_lesson_free(int, boolean) to authenticated;
