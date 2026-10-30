-- Bone Data Manager — lets the app check which setup a server has (Connect → Test connection).
-- Safe on servers that already ran 001 and 002: it only adds a function.
create or replace function public.app_schema_version() returns int
language sql immutable as $$ select 3 $$;
grant execute on function public.app_schema_version() to anon, authenticated;
