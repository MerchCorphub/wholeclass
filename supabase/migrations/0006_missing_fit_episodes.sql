-- WholeClass 0006: The Missing Fit — 12 recorded episodes replace the read-aloud lessons as the Know Your Holes Series.
-- Episode 1 is free; the rest need Series access. Audio lives in the private "episodes" storage bucket:
-- members can play a file only when allowed, and only admins can upload, replace or delete.
-- (Applied to the wholeclass project as migration "missing_fit_episodes"; series_lessons is kept but no longer shown.)
create table public.series_episodes (
  n int primary key check (n between 1 and 99), title text, audio_path text, duration_sec int,
  free boolean not null default false, published_at timestamptz, updated_at timestamptz not null default now());
alter table public.series_episodes enable row level security;
insert into public.series_episodes (n, title, free) select g, case when g = 1 then 'Everything but What I Needed' end, g = 1 from generate_series(1, 12) g;
create or replace function public.can_hear_episode(p_name text) returns boolean language sql stable security definer set search_path = public as $$
  select exists (select 1 from members m where m.id = auth.uid() and m.is_admin)
      or exists (select 1 from series_episodes e where e.audio_path = p_name and e.free)
      or (exists (select 1 from series_episodes e where e.audio_path = p_name)
          and exists (select 1 from access_grants a where a.member_id = auth.uid() and a.product = 'series' and a.starts_at <= now() and (a.expires_at is null or a.expires_at > now()))) $$;
create or replace function public.is_admin_now() returns boolean language sql stable security definer set search_path = public as $$
  select coalesce((select is_admin from members where id = auth.uid()), false) $$;
revoke execute on function public.can_hear_episode(text), public.is_admin_now() from public, anon;
grant execute on function public.can_hear_episode(text), public.is_admin_now() to authenticated;
insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('episodes', 'episodes', false, 209715200, array['audio/mpeg','audio/mp3','audio/mp4','audio/x-m4a','audio/aac','audio/wav','audio/x-wav'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
create policy episodes_listen on storage.objects for select to authenticated using (bucket_id = 'episodes' and public.can_hear_episode(name));
create policy episodes_admin_insert on storage.objects for insert to authenticated with check (bucket_id = 'episodes' and public.is_admin_now());
create policy episodes_admin_update on storage.objects for update to authenticated using (bucket_id = 'episodes' and public.is_admin_now()) with check (bucket_id = 'episodes' and public.is_admin_now());
create policy episodes_admin_delete on storage.objects for delete to authenticated using (bucket_id = 'episodes' and public.is_admin_now());
create or replace function public.series_episode_list() returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('n', e.n, 'title', e.title, 'free', e.free, 'ready', e.audio_path is not null, 'duration_sec', e.duration_sec,
    'path', case when e.audio_path is not null and public.can_hear_episode(e.audio_path) then e.audio_path end) order by e.n), '[]'::json) from series_episodes e $$;
revoke execute on function public.series_episode_list() from public, anon;
grant execute on function public.series_episode_list() to authenticated;
create or replace function public.admin_save_episode(p_n int, p_title text, p_audio_path text, p_duration_sec int, p_free boolean)
returns json language plpgsql security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  if p_n is null or p_n < 1 or p_n > 99 then raise exception 'Episode number must be 1 to 99.'; end if;
  insert into series_episodes (n, title, audio_path, duration_sec, free, published_at, updated_at)
  values (p_n, nullif(trim(p_title), ''), nullif(p_audio_path, ''), p_duration_sec, coalesce(p_free, false), case when nullif(p_audio_path, '') is not null then now() end, now())
  on conflict (n) do update set title = nullif(trim(p_title), ''), audio_path = nullif(p_audio_path, ''), duration_sec = p_duration_sec,
    free = coalesce(p_free, false), published_at = case when nullif(p_audio_path, '') is null then null else coalesce(series_episodes.published_at, now()) end, updated_at = now();
  return public.admin_episodes();
end $$;
create or replace function public.admin_episodes() returns json language plpgsql stable security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  return (select coalesce(json_agg(json_build_object('n', n, 'title', title, 'audio_path', audio_path, 'duration_sec', duration_sec, 'free', free, 'published_at', published_at) order by n), '[]'::json) from series_episodes);
end $$;
revoke execute on function public.admin_save_episode(int, text, text, int, boolean), public.admin_episodes() from public, anon;
grant execute on function public.admin_save_episode(int, text, text, int, boolean), public.admin_episodes() to authenticated;
update public.prices set label = 'WholeClass · Know Your Holes: The Missing Fit (12 episodes) · one year' where kind = 'series';
