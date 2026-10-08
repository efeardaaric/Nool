# Staging security acceptance

Use an isolated Supabase project and disposable fixtures. Apply 001–027 in order, matching existing schema versions. Never run cleanup fixtures against production.

Create two confirmed accounts A and B with profiles, a third account C, and a signed-out client. Add one public video and one campus video by A and a private group owned by A with B as a member. Use confirmed university emails on A/B and an unrelated university on C.

| Scenario | Expected |
|---|---|
| B updates/deletes A's video via REST or `delete_own_video`, supplying A's device ID | Denied / no mutation |
| B calls `purge_own_video_rows` with A's username/device ID | Only B's own content may be removed |
| Signed-out client inserts/deletes video/comment/storage data | Denied |
| A inserts a video/comment using B's username or user ID | Author fields bind to A |
| A changes reaction/vibe/status/owner fields directly | Denied |
| Public profile read requests `student_email` or `fcm_token`, including relation `*` | Denied |
| `get_my_profile` for B | Only B's private profile |
| C changes its campus fields or calls `claim_student_email` with A's email | Denied |
| C has old forged campus fields and calls `get_campus_videos` | No A-campus data |
| A signs a campus video URL; B has verified same-campus email; C has another domain | A/B allowed, C denied |
| Old `/object/public` URL for private campus/group media | Not publicly readable |
| Nonmember self-inserts a group membership | Denied, even if RLS hides existing members |
| Group video signing by B versus C | B allowed, C denied |
| Video upload metadata failure | Newly uploaded object removed, visible retry/error |
| Two separate devices share A's account | Both devices' media included in `get_my_media_objects` |
| Media deletion fails | Account remains signed in and deletion can be retried |
| Direct `delete_own_account` while owned media remains | Refused |
| Successful deletion of A | Auth/profile/current owned videos/comments/group drops/DM data removed; no owned media; unrelated B content remains |
| Unauthenticated webhook/cron POST | 401 before payload/privileged processing |
| Three distinct reports | Video hidden from discovery; duplicates do not count twice |
| Startup initialization failure followed by retry | Error UI then successful startup; no uncaught error |
| First launch with location denied | Can enter main UI; no phantom location or global fallback pretending to be nearby |

Also verify Apple token revocation separately; SQL Auth deletion alone is insufficient. Audit all effective RLS policies and PUBLIC function grants after migration (permissive policies combine with OR).
