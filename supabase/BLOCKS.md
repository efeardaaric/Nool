# Supabase — Blocks migration (008)

## Run in Dashboard

1. Open [Supabase Dashboard](https://supabase.com/dashboard) → your Nool project
2. **SQL Editor** → **New query**
3. Paste the full contents of `supabase/migrations/008_blocks.sql`
4. Click **Run**

Requires migrations **001–007** already applied (profiles, squads, messaging).

## What it creates

| Object | Purpose |
|--------|---------|
| `public.blocks` | `blocker_id`, `blocked_id`, unique pair, no self-block |
| RLS | Insert/delete as blocker; select if blocker or blocked |
| `are_users_blocked(uuid)` | Either-direction block check for current user |
| `list_my_blocks()` | Blocked profiles for unblock UI |
| `block_user(uuid)` | Insert block + delete squad edge |
| `unblock_user(uuid)` | Delete own block row |
| Updated RPCs | `send_squad_request`, `get_or_create_dm`, `send_dm`, `list_my_conversations` deny/hide blocked pairs |

## Avatars (already in 006)

Storage bucket `avatars` is public-read; users may write/delete only under `{auth.uid()}/…`.

Bio max length is enforced in `profiles.bio` (`char_length(bio) <= 150`) from migration **005**.

## Quick verify

```sql
select * from public.blocks limit 5;
select public.are_users_blocked('00000000-0000-0000-0000-000000000000');
select * from public.list_my_blocks();
```
