# CekDulu — Test Account Seeding

> **Policy:** there are no hardcoded default credentials anywhere in the app or
> in this repository. Test accounts exist **only** in `local` / `staging`
> environments and are created exclusively through this seed flow.
> **Never run this against production** — `seed.sql` fails closed unless
> `app.env` is `local` or `staging`.

Test accounts:

| Email             | Role  | Purpose                          |
| ----------------- | ----- | -------------------------------- |
| `admin@test.local` | admin | Admin UI, catalog & affiliate mgmt |
| `user@test.local`  | user  | Regular scan / product flow        |

Passwords are **never** written in files. They come from environment variables:

- `SEED_ADMIN_PASSWORD`
- `SEED_USER_PASSWORD`

## Prerequisites

- A Supabase project for `local` (via `supabase start`) or `staging`.
- Environment variables set (do **not** commit them):
  - `SUPABASE_URL` — e.g. `https://xyzcompany.supabase.co`
  - `SUPABASE_SERVICE_ROLE_KEY` — the **service_role** key (bypasses RLS; keep secret)
  - `SEED_ADMIN_PASSWORD`, `SEED_USER_PASSWORD` — strong random passwords
  - `DATABASE_URL` — **direct** Postgres connection string (needed for `seed.sql`;
    the pooled/Supavisor URL may not forward the `app.env` setting)
- Migrations `001` and `002` already applied (see `../README.md`).

## Step 1 — Create the auth users via the Auth Admin API

Supabase Auth users cannot be created with plain SQL, so use the Auth Admin API
with the `service_role` key. `email_confirm: true` skips email verification for
test accounts.

```bash
# --- admin test account ---
curl -s -X POST "$SUPABASE_URL/auth/v1/admin/users" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"email\": \"admin@test.local\",
    \"password\": \"$SEED_ADMIN_PASSWORD\",
    \"email_confirm\": true,
    \"user_metadata\": { \"seeded\": true, \"intended_role\": \"admin\" }
  }"

# --- regular user test account ---
curl -s -X POST "$SUPABASE_URL/auth/v1/admin/users" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Content-Type: application/json" \
  -d "{
    \"email\": \"user@test.local\",
    \"password\": \"$SEED_USER_PASSWORD\",
    \"email_confirm\": true,
    \"user_metadata\": { \"seeded\": true, \"intended_role\": \"user\" }
  }"
```

Notes:

- Passwords must satisfy the project's Auth password policy (Supabase default:
  minimum length; check Authentication → Policies in the dashboard).
- Re-running is safe: if a user already exists the API returns `422`
  ("already registered") — you can proceed straight to Step 2.
- The `handle_new_user()` trigger (migration `001`) auto-creates a `profiles`
  row with role `'user'` for each new auth user.

## Step 2 — Link profiles and assign roles

```bash
PGOPTIONS="-c app.env=local" psql "$DATABASE_URL" -f seed.sql
# use app.env=staging against the staging project
```

What `seed.sql` does:

1. **Fail-closed guard** — aborts unless `app.env` is `local` or `staging`.
2. Upserts `public.profiles` for both emails by looking up `auth.users`,
   forcing `admin@test.local → 'admin'` and `user@test.local → 'user'`
   (idempotent: safe to re-run).
3. Verifies both profiles exist, otherwise raises a clear error telling you to
   complete Step 1 first.

## Step 3 — Verify

- SQL: the final `SELECT` in `seed.sql` lists both accounts with their roles.
- App: log in to the Flutter app with each account and confirm the correct UI
  (admin dashboard vs. regular user screens).
- Negative check: logging in as `user@test.local` must **not** allow writing to
  `products` / `affiliate_links` (RLS denies it), and must **not** read
  `affiliate_credentials`.

## Cleanup (optional)

To remove test accounts from an environment:

```bash
# via Auth Admin API: first list to get the user id, then delete
curl -s "$SUPABASE_URL/auth/v1/admin/users" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" | grep -o '"id":"[^"]*"' | head

curl -s -X DELETE "$SUPABASE_URL/auth/v1/admin/users/<USER_ID>" \
  -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
  -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY"
```

Deleting the auth user cascades to `public.profiles` (`ON DELETE CASCADE`).

## Security reminders

- The `service_role` key bypasses **all** RLS policies — treat it like a root
  password. Never expose it to the Flutter client or commit it.
- Test passwords live only in your local environment / secret manager.
- CI: gate the seed step behind an explicit non-production environment check;
  production pipelines must never set `app.env=local|staging` against the
  production database.
