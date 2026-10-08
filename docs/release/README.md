# Nool 1.0.0 (3) — release preparation

**Status: NOT ready for App Review.** Local fixes and App Store draft preparation are separate from verified production deployment.

App Store Connect: https://appstoreconnect.apple.com/apps/6820407163/distribution
Bundle ID: `com.efeardaaric.nool`. Developer team confirmed in Apple portal: `9Z82H38DS4`.
Support: `aricefearda@gmail.com`. Website: https://drective.io.
Prepared support route: https://drective.io/nool. Prepared privacy: https://drective.io/nool/privacy. Prepared terms: https://drective.io/nool/terms. These routes are NOT yet verified live on the main domain.

## Changes prepared

- Startup now renders a loading screen immediately and exposes retry if required initialization fails.
- Location errors no longer leave the splash flow throwing; users can continue without location.
- Signed playback supports private campus/group video buckets.
- Video upload requires Auth, uses account-owned paths, and cleans up when metadata insertion fails.
- Content ownership and deletion use authenticated account IDs, replacing device/username trust.
- Account deletion enumerates server-owned media across devices and all four buckets. It does not report success after failed media/Auth deletion or silently sign out on failure.
- Profile reads exclude private student email and push token fields; the owner reads a private RPC.
- Server webhook/cron requests require a server-only shared secret, even with JWT verification disabled.
- Apple sign-in and APNs entitlements; corrected team and linked data privacy declarations; removed development-only local network prompts.
- Support, website and privacy links in settings and legal consent UI.
- Official Syne/Inter static fonts bundled with verified SHA-256 and OFL licenses; remote font downloads disabled.
- Flutter deprecation notices cleaned up without disabling analyzer rules.

## Verified in this session

- `flutter analyze --no-pub`: no issues.
- `dart tool/release_smoke.dart`: 13 checks passed.
- `npx --offline deno test --allow-env=NOOL_SERVER_WEBHOOK_SECRET supabase/functions/_shared/authorize_test.ts`: 2 passed.
- `flutter build bundle --release --no-pub`: succeeded (Dart/assets bundle only; not a signed iOS build).
- Plist parsing and `git diff --check`: passed.
- Drective website `npm run type-check`: passed; GitHub/Vercel deployments succeeded; the live drective.io Nool routes still returned 404. Production domain publishing requires the owning hosting account.

## Required before uploading/review

1. Run Flutter unit/widget tests in an environment that permits the test runner's localhost socket. This session failed before test execution with `Operation not permitted`. New startup failure/retry tests were prepared but cannot be reported as passed.
2. Build and run on simulator and a physical iPhone; test small/large text, denied permissions, offline startup, video capture/upload/playback, login, reset deep links, messages, groups, report/block and deletion. CoreSimulator access is denied in this session; the first native Xcode build failed with code 66. The final build also stopped at CocoaPods because cdn.cocoapods.org could not resolve (missing GoogleUtilities 8.1.4 spec). No current IPA or screenshots have been produced.
3. Apply migrations `026_release_security.sql` and `027_private_media.sql` to an isolated staging Supabase database and execute the two-account scenarios in `STAGING_TESTS.md`. **They have NOT been applied to production.** Deploy the client and migrations together. The updated client depends on new RPCs/columns.
4. Inspect existing live schema/policies first. Old permissive policies, publicly readable private media, private profile columns, spoofable campus membership and unauthenticated server functions are release blockers until production is verified secure.
5. Supply server-only `NOOL_SERVER_WEBHOOK_SECRET` and update webhook/cron headers when deploying both functions. Their full Deno dependency checks were blocked by network/DNS restrictions. No remote secrets or functions were changed.
6. Configure and verify Supabase Apple and Google providers, callback allowlist and OAuth IDs for this bundle/team. Implement Apple's token revocation in the authenticated deletion backend. Current Auth deletion RPC does **not** revoke Apple tokens; Apple account deletion is not release-ready until this is done with the server's Apple key/client credentials.
7. Firebase/APNs: add the genuine project's `GoogleService-Info.plist`, APNs configuration and Firebase server credentials, then test push on a real device. Firebase currently skips startup when config is absent. Do not advertise push as working without this verification.
8. Establish moderation ownership and a response process; three reports hiding a video is not a complete moderation operation. Verify comment/message/group abuse controls and blocked users across all paths. App Review guideline 1.2 applies.
9. Account-deletion migration can safely identify historical video owners only from server-recorded Storage uploader IDs. Historical anonymous content/comments with no trustworthy account association need an audited cleanup/retention plan; do not claim ownership from a supplied device ID or username.
10. Store: save metadata after required review phone number is supplied; add screenshots from the verified build, reviewer account, privacy questionnaire, age rating, categories, pricing/availability and export compliance. Select only the newly verified Nool build. Existing US: AI Memory builds belong to another app.

## Reproduce

```sh
flutter pub get --offline
flutter analyze --no-pub
flutter test --no-pub --reporter expanded
dart tool/release_smoke.dart
npx --offline deno test --allow-env=NOOL_SERVER_WEBHOOK_SECRET supabase/functions/_shared/authorize_test.ts
flutter build ios --release --no-codesign --no-pub
flutter build ipa --release --build-name=1.0.0 --build-number=3
```

Use Xcode 26+ with iOS 26+ SDK per Apple's current upload requirement. The installed Xcode is 26.6.

## Store fields actually saved

The Nool app record, Turkish subtitle, Social Networking / Photo & Video categories and calculated 13+ age rating are saved. The version description/review form remains an unsaved draft because Apple requires a valid review phone number. The contact name/email are restored exactly; no fake number was entered.
