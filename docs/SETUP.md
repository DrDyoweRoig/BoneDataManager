# Bone Data Manager — set up your team's own server

Bone Data Manager works on its own on one computer, with no server. To share databases between
several computers and phones, your team needs its **own free Supabase project**. Your data stays
on your server: nobody else, including the authors of the app, can see it.

One person (the *admin*) does steps 1–5 once. Everyone else only does step 6.

---

## 1. Create the Supabase project (admin, ~5 min)

1. Go to **supabase.com** → **Start your project** and sign up.
2. Create an **organization** (the **Free** plan is enough to start).
3. **New project**
   - **Name:** anything, e.g. `bone-data`
   - **Database password:** generate a strong one and keep it in a password manager.
     The app never needs it.
   - **Region:** the one closest to your team (for EU teams, an EU region keeps data in the EU).
4. Wait about two minutes until the project is ready.

> Free projects are **paused after 7 days without use**. Reactivate them from the Supabase
> dashboard, or choose a paid plan if you use the app intermittently.

## 2. Install the database (admin)

1. In Bone Data Manager (desktop): **Home → Connect to your cloud → Copy setup SQL**.
2. In Supabase: **SQL Editor → New query**, paste, press **Run**.
3. Supabase may warn about *destructive operations*: the script replaces two temporary
   constraints it creates itself. Confirm with **Run query**.
4. It should end with **Success. No rows returned**.

Run the setup SQL only **once**, on a **new** project.

## 3. Secure sign-in (admin)

In **Authentication → Sign In / Providers → Email**:

- Keep **Email** enabled.
- Keep **Confirm email** **on** (membership is matched by email address).
- Turn **Allow new users to sign up** **off** once your team's accounts exist (step 4), so
  strangers can't create accounts on your server.

## 4. Create the accounts (admin)

**Authentication → Users → Add user → Create new user** for each person, with their email.
Tick **Auto Confirm User** if you set the password for them, or let them confirm by email.

## 5. Connect the app and share the code (admin)

1. **Project Settings → API Keys**: copy the **Project URL** (`https://xxxx.supabase.co`) and
   the **anon / publishable** key.
   **Never** use or share the **service_role / secret** key — the app refuses it.
2. In the app: **Connect to your cloud**, paste both, **Test connection** →
   *"Connected. The server is set up and ready."* → **Connect**.
3. **Sign in**, then **Cloud settings → Copy connection code** and send that code to your team.
   It contains only the URL and the public key; it gives no access without an account.

## 6. Join the team (everyone else)

- **Desktop:** Home → **Connect to your cloud** → paste the connection code → **Use code** →
  **Connect** → **Sign in**.
- **Phone:** open the app → **Connect to your team's cloud** → paste the code → **Use code** →
  **Connect** → **Sign in**.

Then the admin adds each person to a database from **Members** (owner, editor or viewer).

---

## When the app says…

| Message | What to do |
|---|---|
| *The server answered but is not set up yet* | Run the setup SQL (step 2). |
| *The server refused the key* | You copied the wrong key: use **anon / publishable**. |
| *The server was set up with an older version* | Run the update SQL that comes with the new app version. |
| *This server is newer than this app* | Install the latest version of the app. |
| *Couldn't reach that address* | Check the URL, your internet connection, and that the project isn't paused. |

## Disconnecting

**Cloud settings → Disconnect** signs the device out and returns it to local databases. Nothing is
deleted on the server. Copies of cloud databases already on the device stay as files but open
**read-only** until you connect to their server again (otherwise new entries could never be
uploaded and would reuse other devices' numbers).

## Updating an existing server

When a new version of the app needs a newer server setup, *Test connection* says
*"The server was set up with an older version"*. Each release notes which SQL to run. For servers
set up before connection codes existed (schema 2), run this once in **SQL Editor**:

```sql
create or replace function public.app_schema_version() returns int
language sql immutable as $$ select 3 $$;
grant execute on function public.app_schema_version() to anon, authenticated;
```

## Requirements and limits

- The server must be reachable over **https** (Supabase projects always are). Plain `http://`
  addresses are refused to keep passwords and data encrypted in transit.
- The app only ever stores the **public** key. The secret / service_role key is refused.

## For developers

- Migrations live in `supabase/migrations/`. After changing one, run
  `python supabase/build_setup.py` to regenerate `app/assets/supabase_setup.sql`
  (a test checks they match).
- A build made with `--dart-define-from-file=cloud_config.json` has a built-in server and hides
  all of the above; a build without it is the version to publish.
