-- WholeClass 0004: the admin console loads the book from the Word file; readers get the chapter list.
-- (Same statements as applied to the wholeclass project as migration "admin_save_book".)
create or replace function public.admin_save_book(p_chapters json)
returns json language plpgsql security definer set search_path = public, private as $$
declare c json; saved int := 0;
begin
  perform private.require_admin();
  if json_typeof(p_chapters) <> 'array' or json_array_length(p_chapters) < 1 or json_array_length(p_chapters) > 60 then raise exception 'The book needs between 1 and 60 chapters.'; end if;
  delete from public.book_chapters bc where bc.n >= 0;  -- Supabase requires a WHERE on deletes
  for c in select * from json_array_elements(p_chapters) loop
    if length(c->>'html') > 400000 then raise exception 'A chapter is too long.'; end if;
    insert into book_chapters (n, title, html, free) values ((c->>'n')::int, left(c->>'title', 200), c->>'html', coalesce((c->>'free')::boolean, false));
    saved := saved + 1;
  end loop;
  return json_build_object('saved', saved);
end $$;
create or replace function public.admin_book()
returns json language plpgsql stable security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  return (select coalesce(json_agg(json_build_object('n', n, 'title', title, 'free', free, 'chars', length(html), 'updated_at', updated_at) order by n), '[]'::json) from book_chapters);
end $$;
create or replace function public.admin_set_chapter_free(p_n int, p_free boolean)
returns json language plpgsql security definer set search_path = public, private as $$
begin
  perform private.require_admin();
  update book_chapters set free = p_free where n = p_n;
  return public.admin_book();
end $$;
revoke execute on function public.admin_save_book(json), public.admin_book(), public.admin_set_chapter_free(int, boolean) from public, anon;
grant execute on function public.admin_save_book(json), public.admin_book(), public.admin_set_chapter_free(int, boolean) to authenticated;
create or replace function public.book_contents()
returns json language sql stable security definer set search_path = public as $$
  select coalesce(json_agg(json_build_object('n', n, 'title', title, 'free', free) order by n), '[]'::json) from book_chapters $$;
revoke execute on function public.book_contents() from public, anon;
grant execute on function public.book_contents() to authenticated;
