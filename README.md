# Greenfield High — Portal

A modular school web app: username/password login (no email verification),
admin-approved registration with role assignment, a role-driven hamburger
menu, and fully independent module pages loaded in an iframe. Hosted free
on GitHub Pages, data/auth on Supabase.

## 1. Create the Supabase project
1. Go to [supabase.com](https://supabase.com) → New project.
2. Project Settings → Authentication → Providers → Email: turn **OFF**
   "Confirm email" (registration in this app has no email step — accounts
   are approved by an admin instead).
3. Project Settings → API → copy the **Project URL** and **anon public key**.

## 2. Wire up the front end
Open `assets/js/config.js` and set:
```js
const SUPABASE_URL = "https://YOUR-PROJECT-REF.supabase.co";
const SUPABASE_ANON_KEY = "YOUR-ANON-PUBLIC-KEY";
```

## 3. Create the database
In Supabase → SQL Editor, run, in order:
1. `sql/schema.sql`
2. `sql/example_module_notice_board.sql` (optional, but the Notice Board
   page needs it — remove that menu item if you skip it)

For an existing database, run `sql/session_fee_workflow_standalone.sql` once
before using the session-aware admission and fee pages. It adds the session
and discount columns, enables Classes 1–3, assigns current sessions to
existing students, and associates their existing fee history with that
session.

For student profile images, run `sql/student_profile_images.sql` on an
existing database after `sql/page_and_user_access_migration.sql`. Re-run it
if image uploads fail with a storage row-level security error; it refreshes
the storage policies to recognize Admission page permissions. New databases
created from `sql/schema_migration.sql` already include the image column,
private storage bucket, and built-in role policies. Images are resized and
compressed in the browser before upload.

If image upload succeeds but the portal reports that the student update was
blocked, run `sql/student_profile_image_update_policy_fix.sql` in Supabase
SQL Editor. Then confirm the affected user has **Edit** permission for the
Admission page and sign out and back in before retrying.

To add the Student search/profile page, publish `pages/student.html` with the
site and run `sql/student_profile_page.sql` in Supabase SQL Editor after
`sql/page_and_user_access_migration.sql`. It registers the page, creates
append-only remark history, applies the required row-level security policies,
and grants existing active users view access (admins/editors also receive
edit access). Adjust individual access under User Access if needed.

To add the Extra Out ledger, run `sql/extra_out.sql` after
`sql/page_and_user_access_migration.sql`. It creates
the secured Extra Out / repayment ledger, registers the page, and grants active
users access based on the app's existing role defaults. Extra Out is kept
separate from Daily Sheet; Dashboard Report includes the net Extra Out balances
and a denomination cash counter.

## 4. Create the primary admin account
Supabase Dashboard → Authentication → Users → **Add user**:
- Email: `admin@school.internal` (must match `EMAIL_DOMAIN` in `config.js`)
- Password: `Admin@1998`
- Auto Confirm User: **ON**

Copy the new user's UUID, then in SQL Editor:
```sql
insert into public.users (user_id, username, mobile_no, role_id, status, created_by, updated_by)
select '<PASTE-UUID-HERE>', 'admin', '0000000000', role_id, 'active', '<PASTE-UUID-HERE>', '<PASTE-UUID-HERE>'
from public.roles where role_name = 'admin';
```
Login: **username** `admin`, **password** `Admin@1998`.
Change this password immediately after first login (top-right menu → Change password).

## 5. Deploy to GitHub Pages
1. Push this folder to a GitHub repository.
2. Repo → Settings → Pages → Source: deploy from branch → `main` / root.
3. Your app is live at `https://<your-username>.github.io/<repo-name>/`.
4. Supabase → Authentication → URL Configuration → add that URL to
   **Site URL** / **Redirect URLs**.

## 6. Day-to-day admin flow
1. A new user registers with username, mobile number and password.
2. Their account is created with status `pending` — they cannot log in yet.
3. Admin opens **Approve Users**, opens the account, assigns a role and
   sets status to `active`. The user can now log in.
4. Admin can create new roles in **Manage Roles**, then grant that role
   access to specific pages by editing `assets/js/menu.js` (see
   `HOW_TO_ADD_PAGE.md`).

## 7. Adding a new page
See `HOW_TO_ADD_PAGE.md` — it is written as a complete, step-by-step guide
(including SQL, menu registration, and a full worked code example) intended
to be followed exactly, including by an AI assistant asked to "add a new
page for X".

## 8. Project structure
```
index.html                 main frame: login/registration + app shell
assets/css/common.css       universal shared styling
assets/js/config.js          Supabase connection + constants (shared)
assets/js/common.js           shared helpers: auth, modal/popup system, toasts, audit log
assets/js/menu.js              menu items + per-role page access
pages/PAGE_TEMPLATE.html        starter template for a new page
pages/dashboard.html             example: simple overview page
pages/notice-board.html           example: full CRUD page (read the code — it's the reference)
pages/manage-users.html            admin: approve users, assign roles
pages/manage-roles.html             admin: create roles
pages/audit-log.html                 admin: view who-did-what-when
sql/schema.sql                        core tables + RLS + seed roles
sql/example_module_notice_board.sql    worked example table + RLS pattern
```

## 9. Security notes
- Passwords are stored only by Supabase Auth (properly hashed) — there is
  no plaintext/raw password column in `public.users`.
- The anon key in `config.js` is meant to be public; real protection comes
  from Row Level Security policies in `sql/schema.sql`. Never disable RLS
  on a table that holds real data.
- The `admin` account should have its password changed on first login, and
  additional admin accounts should be created (approve a normal
  registration and assign the `admin` role) rather than sharing the one
  seeded login long-term.
