# Optional accounts and cross-device progress

## Principles

- Keep playing as a guest; account creation is optional.
- Keep the existing local profile as the source of truth until sign-in and cloud sync are both available.
- Never store a user's password in the game. Use Supabase Auth over HTTPS and never ship a Supabase `service_role`/secret key in a client build.
- Keep authentication, provider-specific sign-in, and game-profile synchronization as separate modules.
- Enable Row Level Security on every user-owned table; authorize rows with the authenticated Supabase user ID.

## Stages

1. **Email/password Auth foundation — implemented in this increment.** Add a provider-neutral auth service, Supabase email provider, optional account UI, sign up/sign in/sign out, email-confirmation messaging, and local session restoration. Guest play and the public leaderboard stay independent.
2. **Finish the account lifecycle before public release.** Verify signup/confirmation links on Pages and desktop; implement password recovery and the password-update return flow; add account deletion/sign-out edge cases; test rate limits and email delivery. Supabase's default SMTP is testing-only, so configure a real SMTP provider before inviting ordinary players.
3. **Google sign-in — client flow implemented; provider configuration and live tests remain.** The Web build opens Google in a popup and receives the return code through the Pages wrapper; desktop opens the system browser and listens on `127.0.0.1:49173/oauth/callback`. Both exchange the PKCE authorization code with Supabase and use the shared session storage. Configure Google Cloud and Supabase before live testing. The Google Cloud client secret belongs only in Supabase, never in the game. Request only basic `openid email profile` scopes.
4. **Cloud profile storage.** Add a versioned user profile row keyed by `auth.uid()` with RLS read/insert/update/delete policies. Start with best distance, wallet, leaderboard display name, language, and control settings. Do not sync passwords, session tokens, or device-specific transient state.
5. **Guest-to-account merge and reliability.** Define field-specific merge rules, preserve the local save on conflict/network failure, add retries and a visible sync state, and test two devices plus sign-out/account deletion. Only then add campaign and inventory fields.

## Current increment / known limits

- Auth requests use Supabase's public Auth endpoints and the existing publishable key; the database remains protected by RLS.
- Passwords are sent only in HTTPS Auth requests and are not written to local profile/session files.
- The refresh token is saved in a separate `user://` ConfigFile so a sign-in can survive relaunch. This is local device storage, not a cross-device save; platform storage protections differ. Never log or expose the token.
- This increment does **not** yet sync game progress, implement password-recovery callbacks, or complete Google OAuth. Confirmation redirects use the configured Gravity Run Pages URL, which must be allowed in the Supabase Auth redirect settings.
- Test signup first with an address authorized by Supabase's default mailer. For real players, configure custom SMTP and appropriate sender/domain settings.

## Player nickname profile increment

- `supabase/migrations/202609250002_player_profiles.sql` creates the private account profile, case-insensitive unique nickname constraint, and authenticated RPC functions for profile load, availability check, and atomic save.
- Run this migration in the Supabase SQL Editor before using the signed-in nickname controls. The client uses the public publishable key plus the current user's access token; it never uses a service-role key.
- Nicknames are currently limited to 3–16 ASCII letters, digits, or underscores. Availability checks exclude the signed-in user's own nickname; the database unique constraint resolves races at save time.
- This stores account identity only. It does not yet associate leaderboard runs with an account or sync local game progress/settings.

## Account coins, run history, and cumulative-distance leaderboard

- Guests do not accrue a persistent coin wallet. Coins from an authenticated run are saved to that account; no guest-coin migration/import exists.
- `supabase/migrations/202609250003_account_progress.sql` adds private per-account wallet/progress totals and an authenticated run-history table. Apply it in the Supabase SQL Editor before testing account run saves or the cumulative leaderboard.
- Each completed signed-in run gets a random UUID and is submitted through `record_player_run`. The unique `(user_id, run_id)` key makes retries idempotent; the transaction increments wallet coins and lifetime distance only once and keeps the best-run distance.
- Temporary network failures leave the run in a local pending queue scoped to the Supabase user ID and retry. The access token is not stored in that queue.
- The new public `get_total_distance_leaderboard` RPC returns at most 20 nickname/total-distance rows, one per account with a player profile. Existing per-run leaderboard behavior remains separate and unchanged.
- `get_monthly_distance_leaderboard` adds a calendar-month aggregate per account, using Europe/Stockholm month boundaries; the HUD shows authenticated wallet coins separately from the current-run coin counter.
- The game client still reports run totals, so this is appropriate for a casual, non-monetized game but is not authoritative anti-cheat. Do not attach real-money value to wallet coins without moving reward validation server-side.

## Google OAuth configuration / test notes

- Supabase Google provider must be enabled and configured in **Authentication → Sign In / Providers → Google**.
- Google Cloud Web OAuth client authorized redirect URI: `https://qtuyiammppulmxhyaesh.supabase.co/auth/v1/callback`.
- Supabase Auth Redirect URLs must include the Pages wrapper URL `https://hjelmdev.github.io/gravity-run/` and desktop callback `http://127.0.0.1:49173/oauth/callback`.
- The desktop redirect is loopback-only and uses a temporary listener while sign-in is pending. If port 49173 is occupied, the game displays a message.
- The web callback is handled by `web/pages_wrapper.html`; the Godot web game must run inside that wrapper for the popup return message to reach the game.
