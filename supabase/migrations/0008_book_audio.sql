-- WholeClass 0008: recorded audio for book chapters. Kept apart from book_chapters so re-publishing the
-- Word file never removes recordings. A recording follows the same rule as the chapter's text:
-- free chapters for any signed-in member, the rest with access, admins always.
create table if not exists public.book_audio (
  n int primary key check (n between 0 and 99),
  audio_path text not null unique,
  duration_sec int,
  updated_at timestamptz not null default now()
);
alter table public.book_audio enable row level security;

create or replace function public.can_read_chapter(p_n int) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from members m where m.id = auth.uid() and m.is_admin)
      or exists (select 1 from book_chapters c where c.n = p_n and c.free)
      or exists (select 1 from access_grants a where a.member_id = auth.uid() and a.starts_at <= now() and (a.expires_at is null or a.expires_at > now()))
$$;

create or replace function public.can_hear_chapter(p_name text) returns boolean
language sql stable security definer set search_path = public as $$
  select exists (select 1 from book_audio b where b.audio_path = p_name and public.can_read_chapter(b.n))
$$;
revoke execute on function public.can_read_chapter(int), public.can_hear_chapter(text) from public, anon;
grant execute on function public.can_read_chapter(int), public.can_hear_chapter(text) to authenticated;

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values ('book-audio', 'book-audio', false, 209715200, array['audio/mpeg','audio/mp3','audio/mp4','audio/x-m4a','audio/aac','audio/wav','audio/x-wav'])
on conflict (id) do update set public = false, file_size_limit = excluded.file_size_limit, allowed_mime_types = excluded.allowed_mime_types;
create policy book_audio_listen on storage.objects for select to authenticated using (bucket_id = 'book-audio' and public.can_hear_chapter(name));
create policy book_audio_admin_insert on storage.objects for insert to authenticated with check (bucket_id = 'book-audio' and public.is_admin_now());
create policy book_audio_admin_update on storage.objects for update to authenticated using (bucket_id = 'book-audio' and public.is_admin_now()) with check (bucket_id = 'book-audio' and public.is_admin_now());
create policy book_audio_admin_delete on storage.objects for delete to authenticated using (bucket_id = 'book-audio' and public.is_admin_now());

-- Contents now say which chapters have a recording
create or replace function public.book_contents() returns json
language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('n', c.n, 'title', c.title, 'free', c.free, 'audio', b.n is not null, 'duration_sec', b.duration_sec) order by c.n), '[]'::json)
  from book_chapters c left join book_audio b on b.n = c.n
$$;

-- The recording for one chapter, only when the member may read that chapter
create or replace function public.chapter_audio(p_n int) returns json
language sql stable security definer set search_path = public as $$
  select json_build_object('path', case when public.can_read_chapter(b.n) then b.audio_path end, 'duration_sec', b.duration_sec)
  from book_audio b where b.n = p_n
$$;
revoke execute on function public.chapter_audio(int) from public, anon;
grant execute on function public.chapter_audio(int) to authenticated;

create or replace function public.admin_book() returns json
language plpgsql stable security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  return (select coalesce(json_agg(json_build_object('n', c.n, 'title', c.title, 'free', c.free, 'chars', length(c.html), 'updated_at', c.updated_at,
    'audio_path', b.audio_path, 'duration_sec', b.duration_sec) order by c.n), '[]'::json)
    from book_chapters c left join book_audio b on b.n = c.n);
end $$;

-- Save (path given) or remove (path null) a chapter's recording
create or replace function public.admin_save_chapter_audio(p_n int, p_audio_path text, p_duration_sec int) returns json
language plpgsql security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  if not exists (select 1 from book_chapters where n = p_n) then raise exception 'That chapter is not in the book.'; end if;
  if nullif(p_audio_path, '') is null then
    delete from book_audio where n = p_n;
  else
    insert into book_audio (n, audio_path, duration_sec) values (p_n, p_audio_path, p_duration_sec)
    on conflict (n) do update set audio_path = excluded.audio_path, duration_sec = excluded.duration_sec, updated_at = now();
  end if;
  return public.admin_book();
end $$;
revoke execute on function public.admin_save_chapter_audio(int, text, int) from public, anon;
grant execute on function public.admin_save_chapter_audio(int, text, int) to authenticated;
