-- =============================================================================
-- 0016 · Lock-down, grants and storage
-- Runs last so it covers every object created by the migrations before it.
-- =============================================================================

-- 1. Tables: no direct access for API roles, and RLS on with no policies, so
--    even an accidental GRANT or schema exposure reads nothing.
do $$
declare v_table record;
begin
  for v_table in select schemaname, tablename from pg_tables where schemaname = 'app' loop
    execute format('alter table %I.%I enable row level security', v_table.schemaname, v_table.tablename);
  end loop;
end $$;

revoke all on all tables in schema app from public, anon, authenticated;
revoke all on all sequences in schema app from public, anon, authenticated;

-- 2. Functions: start from nothing.
revoke execute on all functions in schema private from public, anon, authenticated;
revoke execute on all functions in schema public from public, anon, authenticated;

-- 3. The API. Every SECURITY DEFINER function in `public` is an RPC for
--    signed-in users; a short list is also open to visitors for browsing.
do $$
declare v_fn record;
begin
  for v_fn in
    select p.oid::regprocedure as signature
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prosecdef
  loop
    execute format('grant execute on function %s to authenticated', v_fn.signature);
  end loop;
end $$;

grant execute on function public.catalog() to anon;
grant execute on function public.orgs_search(text, text, int, int) to anon;
grant execute on function public.org_detail(uuid) to anon;
grant execute on function public.tournaments_search(text, text, text, int, int) to anon;
grant execute on function public.tournament_detail(uuid) to anon;
grant execute on function public.event_detail(uuid) to anon;

-- 4. Storage for logos, banners and exported posters. Files are public to
--    read; only an organisation's owners and managers can write under its id:
--    media/<org_id>/<file>.
do $$
begin
  if to_regclass('storage.buckets') is null then
    raise notice 'storage schema not present, skipping bucket setup';
    return;
  end if;

  insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
  values ('media', 'media', true, 5242880, array['image/png', 'image/jpeg', 'image/webp'])
  on conflict (id) do nothing;

  execute $p$
    create policy "media: public read" on storage.objects
      for select using (bucket_id = 'media')
  $p$;
  execute $p$
    create policy "media: org managers write" on storage.objects
      for insert to authenticated
      with check (bucket_id = 'media' and public.can_manage_org(((storage.foldername(name))[1])::uuid))
  $p$;
  execute $p$
    create policy "media: org managers update" on storage.objects
      for update to authenticated
      using (bucket_id = 'media' and public.can_manage_org(((storage.foldername(name))[1])::uuid))
  $p$;
  execute $p$
    create policy "media: org managers delete" on storage.objects
      for delete to authenticated
      using (bucket_id = 'media' and public.can_manage_org(((storage.foldername(name))[1])::uuid))
  $p$;
end $$;
