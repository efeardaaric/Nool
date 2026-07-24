# Supabase migrations — SQL Editor

Run these in order in **Supabase Dashboard → SQL Editor**.

| # | File | Purpose |
|---|------|---------|
| 001 | `001_videos_postgis.sql` | Videos + PostGIS |
| 002 | `002_comments_realtime.sql` | Comments + realtime |
| 003 | `003_campus_drops_bucket.sql` | Storage bucket |
| 004 | `004_trending_hotspots.sql` | Hotspots RPC |
| 005 | `005_profiles_squads_gdpr.sql` | Profiles, squads, GDPR |
| 006 | `006_avatars_bucket.sql` | Public `avatars` bucket + RLS |
| 007 | `007_messaging_realtime.sql` | DM conversations / messages |
| 008 | `008_blocks.sql` | **Blocks table + interaction gates** |

## 008 — Blocks (new)

Paste and run the full contents of `supabase/migrations/008_blocks.sql` after 001–007.

Creates:

- `public.blocks (blocker_id, blocked_id, created_at)` with RLS
- RPCs: `are_users_blocked`, `list_my_blocks`, `block_user`, `unblock_user`
- Updates: `send_squad_request`, `get_or_create_dm`, `send_dm`, `list_my_conversations` to refuse / hide blocked pairs
- On block: deletes squad edge between the two users

No Flutter rebuild is required for schema alone; the app expects these RPCs for block / unblock UI.
