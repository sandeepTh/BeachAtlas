-- ============================================================
-- Fix: allow editing/deleting entries with no owner (owner_id is null)
--
-- The original policies only allowed `owner_id = auth.uid()`, but SQL's
-- NULL = anything is never true — so the 57 seeded beaches (owner_id
-- left null on purpose, so anyone could edit them) were silently
-- unupdatable, surfacing as "Cannot coerce the result to a single JSON
-- object" (PostgREST error PGRST116: the UPDATE matched zero rows).
--
-- Run this once in Supabase Dashboard -> SQL Editor.
-- ============================================================

drop policy if exists "owner can update" on beaches;
create policy "owner can update" on beaches
  for update
  using (owner_id is null or owner_id = auth.uid());

drop policy if exists "owner can delete" on beaches;
create policy "owner can delete" on beaches
  for delete
  using (owner_id is null or owner_id = auth.uid());
