# BeachAtlas

A shared, public atlas of beach facilities (washrooms, parking, food, pet-friendliness, etc.). It's a static, single-file web app backed by [Supabase](https://supabase.com) — no build step, no server to run.

**Dev instance:** https://sandeepth.github.io/BeachAtlas/
(auto-deployed by `.github/workflows/deploy-pages.yml` on every push to `claude/dev-instance-build-deploy-1ajru1`)

## Files

| File | What it is |
|---|---|
| `index.html` | The main app. Fully wired up to Supabase — use this one. |
| `beach-atlas-supabase.html` | An earlier variant of the same app. Kept for reference. |

Both are self-contained: HTML, CSS, and JS in one file, loading the Supabase JS client from a CDN `<script>` tag. There's nothing to `npm install` or build.

## Supabase setup

The app needs a Supabase project to store beach entries and flags.

### 1. Log in to Supabase

1. Go to https://supabase.com/dashboard and sign in (GitHub or email login).
2. Open your project, or click **New project** if you don't have one yet.
3. Once inside the project, go to **Project Settings → API**. You'll need:
   - **Project URL** → this is `SUPABASE_URL`
   - **anon / publishable key** → this is `SUPABASE_ANON_KEY`

### 2. Enable anonymous sign-in

Visitors are signed in anonymously (no email/password) so the database can tell entries apart by owner without any signup flow.

- Go to **Authentication → Sign In / Providers → Anonymous Sign-Ins** and turn it **on**.
- If this is off, the app will fail to load data and show: *"Could not connect to the atlas backend."*

### 3. Create the database schema

Open **SQL Editor** in the Supabase dashboard and run:

```sql
create table if not exists beaches (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  location text,
  lat double precision,
  lng double precision,
  notes text,
  contributed_by text,
  amenities jsonb not null default '{}',
  osm_sourced jsonb,
  owner_id uuid,
  added_at timestamptz not null default now()
);

create table if not exists beach_flags (
  id uuid primary key default gen_random_uuid(),
  beach_id uuid not null references beaches(id) on delete cascade,
  reason text,
  flagged_by uuid,
  created_at timestamptz not null default now()
);

alter table beaches enable row level security;
alter table beach_flags enable row level security;

-- Anyone (including anonymous users) can read
create policy "public read beaches" on beaches for select using (true);
create policy "public read flags" on beach_flags for select using (true);

-- Anyone signed in (including anonymous) can add
create policy "anyone can insert beaches" on beaches for insert with check (auth.uid() is not null);
create policy "anyone can insert flags" on beach_flags for insert with check (auth.uid() is not null);

-- The original contributor can edit/delete their own entry; entries with
-- no owner (owner_id is null, e.g. bulk-imported/seeded data) are editable
-- by anyone, matching the app's client-side "isOwner" check. NULL = auth.uid()
-- is never true in SQL, so the "owner_id is null" branch is required or
-- unowned rows silently become un-editable (PostgREST error PGRST116).
create policy "owner can update" on beaches for update using (owner_id is null or owner_id = auth.uid());
create policy "owner can delete" on beaches for delete using (owner_id is null or owner_id = auth.uid());
create policy "owner can delete own flags" on beach_flags for delete using (flagged_by = auth.uid());
```

### 4. Point the app at your project

In `index.html`, near the top of the `<script>` block:

```js
const SUPABASE_URL = 'https://YOUR-PROJECT.supabase.co';
const SUPABASE_ANON_KEY = 'YOUR_ANON_KEY';
```

Both files currently point at a shared demo project — swap these for your own if you want an isolated dataset.

## Ownership & editing model

This is a public, shared atlas — anyone can add an entry. But **you can only edit or delete entries you added yourself**:

- Each visitor gets an anonymous Supabase auth session on first load; that session's user id becomes the entry's `owner_id` when they add a beach.
- The app only shows **Edit**/**Delete** on entries where `owner_id` matches your current session's id (`index.html` ~line 918: `isOwner = !b.ownerId || b.ownerId === localOwnerId`).
- On anyone else's entry, you'll see **Flag** instead — use it to mark stale/incorrect info instead of editing directly.

If Edit is missing even on entries you just added, check:
1. Anonymous sign-in is enabled in Supabase (step 2 above).
2. The browser isn't blocking third-party cookies/local storage (the session lives in local storage).
3. You're not in a fresh private/incognito window from a different device — ownership is per-browser-session, not per-person.

If Edit **is** shown but saving fails with `Could not save changes: Cannot coerce the result to a single JSON object`, your `beaches` RLS policies predate the `owner_id is null` fix above — run `sql/fix_null_owner_rls.sql` once in the SQL Editor. (Cause: entries with `owner_id = null`, like bulk-imported data, look editable client-side but SQL's `NULL = auth.uid()` is never true, so the UPDATE silently matches zero rows.)
