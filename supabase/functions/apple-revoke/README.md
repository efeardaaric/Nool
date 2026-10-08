# Authenticated Apple account deletion authorization

Deploy after migration 026. Configure the actual native bundle ID as `APPLE_CLIENT_ID` and a valid Apple client secret JWT as server-only `APPLE_CLIENT_SECRET`. The JWT must be signed with the Apple Sign in key for team `9Z82H38DS4`; keep it out of Flutter and source control. Rotate before expiry. Standard Supabase URL/service role environment variables are also required.

The handler verifies the caller's Supabase session, exchanges a fresh native Apple authorization code directly with Apple, checks the returned subject/audience/issuer/expiry against that verified user, revokes the refresh/access token, then records a ten-minute self-deletion authorization. No Apple tokens are stored. SQL refuses Apple-account deletion without this server-issued authorization.

Do not mark this flow verified until staging tests and an actual Apple account on a device pass. Existing credentials were not available/configured in this session.

```sh
supabase functions deploy apple-revoke
npx --offline deno test supabase/functions/apple-revoke/handler_test.ts
```
