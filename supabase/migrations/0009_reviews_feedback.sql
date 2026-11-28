-- WholeClass 0009: member reviews, helpful votes and private feedback.
-- reviews.kind: 'checkin' = Day 7 star check-in (private, never shown publicly)
--               'review'  = full review for a course (shown publicly only after an admin approves it)
-- course: 'class' (14-Day Discovery Class) or 'series' (with season = the season number)

create table if not exists public.reviews (
  id uuid primary key default gen_random_uuid(),
  member_id uuid not null references public.members(id) on delete cascade,
  kind text not null check (kind in ('checkin', 'review')),
  course text not null check (course in ('class', 'series')),
  season int not null default 0,
  stars int not null check (stars between 1 and 5),
  comment text check (char_length(comment) <= 200),
  hole text check (char_length(hole) <= 60),
  changed text check (char_length(changed) <= 1500),
  recommend text check (char_length(recommend) <= 600),
  display text not null default 'initial' check (display in ('initial', 'anonymous')),
  display_name text,
  marketing_ok boolean not null default false,
  status text not null default 'pending' check (status in ('private', 'pending', 'approved', 'hidden')),
  helpful int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  moderated_at timestamptz,
  unique (member_id, kind, course, season)
);
create index if not exists reviews_public_idx on public.reviews (course, season, status, helpful desc);
alter table public.reviews enable row level security;

create table if not exists public.review_votes (
  review_id uuid not null references public.reviews(id) on delete cascade,
  member_id uuid not null references public.members(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (review_id, member_id)
);
alter table public.review_votes enable row level security;

create table if not exists public.feedback (
  id uuid primary key default gen_random_uuid(),
  member_id uuid references public.members(id) on delete set null,
  email text,
  name text,
  message text not null check (char_length(message) between 3 and 3000),
  page text,
  status text not null default 'new' check (status in ('new', 'read')),
  created_at timestamptz not null default now()
);
alter table public.feedback enable row level security;
-- No table policies: every read and write goes through the functions below.

create or replace function private.has_course(p_course text, p_season int) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from members m where m.id = auth.uid() and m.is_admin)
      or exists (select 1 from access_grants a where a.member_id = auth.uid() and a.starts_at <= now() and (a.expires_at is null or a.expires_at > now())
                 and a.product = p_course and (p_course = 'class' or a.season = p_season))
$$;

create or replace function private.review_name(p_member uuid, p_display text) returns text
language sql stable security definer set search_path = public as $$
  select case when p_display = 'anonymous' then 'WholeClass member'
    else coalesce(nullif(trim(m.first_name), ''), 'WholeClass member') || coalesce(' ' || upper(left(nullif(trim(m.last_name), ''), 1)) || '.', '') end
  from members m where m.id = p_member
$$;

-- Day 7 check-in (private)
create or replace function public.submit_checkin(p_stars int, p_comment text) returns json
language plpgsql security definer set search_path = public, private as $$
declare uid uuid := auth.uid();
begin
  if uid is null then raise exception 'Please sign in again.'; end if;
  if p_stars is null or p_stars < 1 or p_stars > 5 then raise exception 'Choose 1 to 5 stars.'; end if;
  insert into reviews (member_id, kind, course, season, stars, comment, status)
  values (uid, 'checkin', 'class', 0, p_stars, nullif(left(trim(p_comment), 200), ''), 'private')
  on conflict (member_id, kind, course, season) do update set stars = excluded.stars, comment = excluded.comment, updated_at = now();
  return json_build_object('ok', true);
end $$;

-- Full review (goes to the admin as pending; editing an approved review sends it back for approval)
create or replace function public.submit_review(p_course text, p_season int, p_stars int, p_hole text, p_changed text, p_recommend text, p_display text, p_marketing boolean) returns json
language plpgsql security definer set search_path = public, private as $$
declare uid uuid := auth.uid(); sn int := case when p_course = 'series' then coalesce(p_season, 1) else 0 end;
begin
  if uid is null then raise exception 'Please sign in again.'; end if;
  if p_course not in ('class', 'series') then raise exception 'Unknown course.'; end if;
  if not private.has_course(p_course, sn) then raise exception 'Reviews come from members who have this course open.'; end if;
  if p_stars is null or p_stars < 1 or p_stars > 5 then raise exception 'Choose 1 to 5 stars.'; end if;
  if coalesce(trim(p_changed), '') = '' and coalesce(trim(p_recommend), '') = '' then raise exception 'Answer at least one of the questions.'; end if;
  insert into reviews (member_id, kind, course, season, stars, hole, changed, recommend, display, display_name, marketing_ok, status)
  values (uid, 'review', p_course, sn, p_stars, nullif(left(trim(p_hole), 60), ''), nullif(left(trim(p_changed), 1500), ''), nullif(left(trim(p_recommend), 600), ''),
          case when p_display = 'anonymous' then 'anonymous' else 'initial' end, private.review_name(uid, p_display), coalesce(p_marketing, false), 'pending')
  on conflict (member_id, kind, course, season) do update set stars = excluded.stars, hole = excluded.hole, changed = excluded.changed, recommend = excluded.recommend,
    display = excluded.display, display_name = excluded.display_name, marketing_ok = excluded.marketing_ok, status = 'pending', moderated_at = null, updated_at = now();
  return json_build_object('ok', true, 'status', 'pending');
end $$;

create or replace function public.my_review(p_course text, p_season int) returns json
language sql stable security definer set search_path = public, private as $$
  select json_build_object('can_review', private.has_course(p_course, case when p_course = 'series' then coalesce(p_season, 1) else 0 end),
    'review', (select json_build_object('stars', r.stars, 'hole', r.hole, 'changed', r.changed, 'recommend', r.recommend, 'display', r.display, 'marketing_ok', r.marketing_ok, 'status', r.status)
      from reviews r where r.member_id = auth.uid() and r.kind = 'review' and r.course = p_course and r.season = case when p_course = 'series' then coalesce(p_season, 1) else 0 end),
    'checkin', (select r.stars from reviews r where r.member_id = auth.uid() and r.kind = 'checkin'))
$$;

-- Public course reviews: summary, the holes members named, and approved reviews (top by helpful votes)
create or replace function public.course_reviews(p_course text, p_season int, p_hole text default null, p_limit int default 3, p_offset int default 0) returns json
language sql stable security definer set search_path = public as $$
  with base as (
    select * from reviews r where r.kind = 'review' and r.status = 'approved' and r.course = p_course
      and r.season = case when p_course = 'series' then coalesce(p_season, 1) else 0 end)
  select json_build_object(
    'count', (select count(*) from base),
    'average', (select round(avg(stars)::numeric, 1) from base),
    'stars', (select coalesce(json_object_agg(stars, n), '{}'::json) from (select stars, count(*) n from base group by stars) s),
    'holes', (select coalesce(json_agg(json_build_object('hole', hole, 'n', n) order by n desc, hole), '[]'::json) from (select hole, count(*) n from base where hole is not null group by hole) h),
    'filtered', (select count(*) from base where p_hole is null or hole = p_hole),
    'reviews', (select coalesce(json_agg(x), '[]'::json) from (
       select b.id, b.stars, b.hole, b.changed, b.recommend, coalesce(b.display_name, 'WholeClass member') as name, b.helpful,
              to_char(b.created_at, 'Mon YYYY') as month,
              exists (select 1 from review_votes v where v.review_id = b.id and v.member_id = auth.uid()) as voted,
              coalesce(b.member_id = auth.uid(), false) as mine
       from base b where p_hole is null or b.hole = p_hole
       order by b.helpful desc, b.created_at desc limit least(greatest(coalesce(p_limit, 3), 1), 50) offset greatest(coalesce(p_offset, 0), 0)) x));
$$;

create or replace function public.vote_helpful(p_review uuid) returns json
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); r reviews; voted boolean;
begin
  if uid is null then raise exception 'Sign in to vote.'; end if;
  select * into r from reviews where id = p_review and kind = 'review' and status = 'approved';
  if r.id is null then raise exception 'Review not found.'; end if;
  if r.member_id = uid then raise exception 'You can’t vote on your own review.'; end if;
  if exists (select 1 from review_votes where review_id = p_review and member_id = uid) then
    delete from review_votes where review_id = p_review and member_id = uid; voted := false;
  else
    insert into review_votes (review_id, member_id) values (p_review, uid); voted := true;
  end if;
  update reviews set helpful = (select count(*) from review_votes where review_id = p_review) where id = p_review returning helpful into r.helpful;
  return json_build_object('voted', voted, 'helpful', r.helpful);
end $$;

create or replace function public.send_feedback(p_message text, p_page text) returns json
language plpgsql security definer set search_path = public as $$
declare uid uuid := auth.uid(); m members;
begin
  if coalesce(char_length(trim(p_message)), 0) < 3 then raise exception 'Tell us a little more.'; end if;
  if uid is not null then select * into m from members where id = uid; end if;
  if uid is not null and (select count(*) from feedback where member_id = uid and created_at > now() - interval '1 hour') >= 10 then raise exception 'Thank you. Please try again a little later.'; end if;
  insert into feedback (member_id, email, name, message, page) values (uid, m.email, nullif(trim(coalesce(m.first_name, '') || ' ' || coalesce(m.last_name, '')), ''), left(trim(p_message), 3000), left(p_page, 80));
  return json_build_object('ok', true);
end $$;

-- ---------- admin ----------
create or replace function public.admin_reviews(p_status text default 'pending') returns json
language plpgsql stable security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  return json_build_object(
    'counts', (select coalesce(json_object_agg(status, n), '{}'::json) from (select status, count(*) n from reviews where kind = 'review' group by status) c),
    'reviews', (select coalesce(json_agg(json_build_object('id', r.id, 'course', r.course, 'season', r.season, 'stars', r.stars, 'hole', r.hole, 'changed', r.changed,
        'recommend', r.recommend, 'display_name', r.display_name, 'display', r.display, 'marketing_ok', r.marketing_ok, 'status', r.status, 'helpful', r.helpful,
        'created_at', r.created_at, 'updated_at', r.updated_at, 'member', m.first_name || ' ' || m.last_name, 'email', m.email) order by r.updated_at desc), '[]'::json)
      from reviews r join members m on m.id = r.member_id where r.kind = 'review' and (p_status = 'all' or r.status = p_status)),
    'checkins', json_build_object('count', (select count(*) from reviews where kind = 'checkin'), 'average', (select round(avg(stars)::numeric, 1) from reviews where kind = 'checkin'),
      'recent', (select coalesce(json_agg(x), '[]'::json) from (select r.stars, r.comment, r.updated_at, m.first_name || ' ' || m.last_name as member from reviews r join members m on m.id = r.member_id
        where r.kind = 'checkin' order by r.updated_at desc limit 30) x)),
    'feedback_new', (select count(*) from feedback where status = 'new'));
end $$;

create or replace function public.admin_set_review_status(p_id uuid, p_status text) returns json
language plpgsql security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  if p_status not in ('approved', 'hidden', 'pending') then raise exception 'Unknown status.'; end if;
  update reviews set status = p_status, moderated_at = now() where id = p_id and kind = 'review';
  if not found then raise exception 'Review not found.'; end if;
  return json_build_object('ok', true);
end $$;

create or replace function public.admin_feedback(p_status text default 'all') returns json
language plpgsql stable security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  return (select coalesce(json_agg(json_build_object('id', id, 'name', name, 'email', email, 'message', message, 'page', page, 'status', status, 'created_at', created_at) order by created_at desc), '[]'::json)
    from feedback where p_status = 'all' or status = p_status);
end $$;

create or replace function public.admin_set_feedback_status(p_id uuid, p_status text) returns json
language plpgsql security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  if p_status not in ('new', 'read') then raise exception 'Unknown status.'; end if;
  update feedback set status = p_status where id = p_id;
  return json_build_object('ok', true);
end $$;

revoke execute on function private.has_course(text, int), private.review_name(uuid, text) from public, anon;
revoke execute on function public.submit_checkin(int, text), public.submit_review(text, int, int, text, text, text, text, boolean), public.my_review(text, int),
  public.vote_helpful(uuid), public.admin_reviews(text), public.admin_set_review_status(uuid, text), public.admin_feedback(text), public.admin_set_feedback_status(uuid, text) from public, anon;
grant execute on function public.submit_checkin(int, text), public.submit_review(text, int, int, text, text, text, text, boolean), public.my_review(text, int),
  public.vote_helpful(uuid), public.admin_reviews(text), public.admin_set_review_status(uuid, text), public.admin_feedback(text), public.admin_set_feedback_status(uuid, text) to authenticated;
-- Approved reviews can be read before signing in (course pages); feedback can be sent signed in only
revoke execute on function public.course_reviews(text, int, text, int, int), public.send_feedback(text, text) from public;
grant execute on function public.course_reviews(text, int, text, int, int) to anon, authenticated;
grant execute on function public.send_feedback(text, text) to authenticated;
