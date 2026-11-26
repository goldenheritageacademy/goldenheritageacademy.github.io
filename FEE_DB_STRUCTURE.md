# Fee Module — Database Structure & Due-Calculation Logic

Reference for the admission, fee-collection, and fee-due-report pages.
Full SQL: `sql/module_admission.sql` (student_master, fee_master) and
`sql/module_fee.sql` (fee_categories, fee_receipts, reactivated_at).

## 1. `student_master`

One row per student. `reg_no` is the primary key (user-entered, not a uuid).

| Column            | Type        | Notes |
|-------------------|-------------|-------|
| `reg_no`          | text, PK    | Registration number, entered by user |
| `name`             | text        | Student name |
| `father_name`      | text        | Father's name |
| `mobile_no`        | text        | Contact number |
| `class`             | text        | One of: `1`–`10`, `11-arts`, `11-science`, `12-arts`, `12-science` |
| `academic_session`  | text        | The session assigned to the student. Classes 1–9 use a calendar year (`2026`); classes 10–12 use an April–March label (`2026-27`). |
| `previous_sessions` | text[]      | Earlier sessions retained when the student is readmitted into a newer session. |
| `admission_date`    | date        | Original admission date |
| `status`             | text        | `active` \| `deactivated` |
| `is_readmission`     | boolean     | `true` once the student has been readmitted at least once |
| `remark`              | text        | Optional |
| `recorded_by`         | uuid → auth.users | Who created the record |
| `recorded_at`          | timestamptz | When it was created |
| `deactivate_date`       | date        | Date set inactive (null if active) |
| `deactivated_by`         | uuid → auth.users | Who deactivated |
| `deactivated_at`          | timestamptz | When deactivated |
| `updated_by`                | uuid → auth.users | Last editor |
| `updated_at`                 | timestamptz | Last edit time |
| `reactivated_at`              | date | Set when a **deactivated** student is readmitted. Marks where the new active period starts, so a deactivated gap is never charged fees for. Null if the student has never had a deactivation-then-readmission cycle. |

## 2. `fee_master` — fee **history**, not a payments/receipts table

One row per fee-amount **event** for a student. This table only records
*what the fee amount is/was at a point in time* — it does not track
whether that amount has actually been paid. That's what `fee_receipts`
(below) is for.

| Column            | Type        | Notes |
|-------------------|-------------|-------|
| `fee_id`           | uuid, PK    | |
| `student_reg_no`    | text → student_master.reg_no (cascade delete) | |
| `type`               | text        | `admission` \| `readmission` \| `monthly` |
| `amount`              | numeric(10,2) | The fee amount for this event |
| `remark`               | text        | Optional |
| `recorded_by`           | uuid → auth.users | |
| `recorded_at`            | timestamptz | Event/effective timestamp |
| `academic_session`       | text | Session the fee event belongs to. |

**Rows are never updated or deleted** — corrections are made by inserting
a new row. This preserves full history for auditing and for recalculating
old dues correctly.

### How rows get created
- **New admission** → 2 rows: one `admission` (the admission fee charged
  once) and one `monthly` (the monthly fee effective from that date).
- **Readmission** → 2 rows: one `readmission` (the readmission fee charged
  once) and one `monthly` (the *new* monthly fee effective from that date,
  since readmission is when monthly fee is most commonly revised).

### How this feeds the actual due calculation
See section 5 below for the exact, implemented algorithm. In short: the
latest `monthly` row's amount is used as the rate for any month from its
`recorded_at` onward, and every `admission`/`readmission` row is a
one-time charge that adds up against `fee_receipts` payments of that type.

### Example query — latest monthly fee per active student
```sql
select distinct on (student_reg_no) student_reg_no, amount as monthly_fee, recorded_at
from public.fee_master
where type = 'monthly'
order by student_reg_no, recorded_at desc;
```

## 3. `fee_categories` — user-defined categories for "Other" fees

| Column | Type | Notes |
|---|---|---|
| `category_id` | uuid, PK | |
| `name` | text, unique | e.g. "Transport Fee", "Exam Fee" |
| `active` | boolean | |
| `created_by` / `created_at` | uuid / timestamptz | |

Created on the fly from the "+ New" button in the Other Fee tab, or
auto-created during bulk upload if the category name doesn't exist yet.

## 4. `fee_receipts` — every payment actually received

One row per payment transaction, of any of the three collection types.

| Column | Type | Notes |
|---|---|---|
| `receipt_id` | uuid, PK | |
| `student_reg_no` | text → student_master.reg_no (cascade delete) | |
| `fee_type` | text | `monthly` \| `admission_readmission` \| `other` |
| `for_months` | text[] | e.g. `{2026-05,2026-06}` — monthly receipts allocate to these months first |
| `target_session` | text | The academic session for which the receipt was recorded. Monthly receipts can be assigned to future months within that session. |
| `category_id` | uuid → fee_categories | other type only |
| `amount_cash` / `amount_bank` / `amount_phonepe` | numeric | split across payment modes; a single payment can mix modes |
| `discount` | numeric | reduces due the same way a payment does |
| `remark` | text | |
| `recorded_by` / `recorded_at` | uuid / timestamptz | |

Monthly `for_months` entries are allocated to those session months first;
untagged monthly receipts reduce the oldest outstanding month first. This
allows future-month advances to remain attached to the student's profile
without clearing an earlier due.

## 5. Academic sessions

Classes 1–9 follow January–December; classes 10–12 follow April–March.
New admissions and readmissions select either the current or upcoming
session. The standalone SQL migration
`sql/session_fee_workflow_standalone.sql` adds the session and discount
columns, expands supported classes, assigns existing students to the current
session, and tags their existing fee history/receipts.

When a student is readmitted, their `student_master.academic_session` moves
to the selected session while the prior session remains recorded on its
fee events and receipts. Fee Collection includes previous-session students
and an advance-receipts view. The existing Old Dues module remains the
place to record legacy balances that predate session tracking.

## 6. Due-calculation algorithm (as implemented)

### Monthly fee
1. **Session window**: Classes 1–9 use Jan–Dec; Classes 10–12 use
   April–March. Within that session, fees apply from the later of
   `reactivated_at`/`admission_date` or the session start through today,
   session end, or `deactivate_date` (if deactivated), whichever comes first.
2. **Rate per month**: the latest `fee_master` row of type `monthly` whose
   `recorded_at` is on/before the end of that month (rates can change
   mid-course; each month uses whatever rate was in effect then).
3. **Payments**: only monthly receipts tagged for the selected session
   count. Receipts with `for_months` are assigned to those month(s);
   untagged receipts reduce the oldest outstanding month first. A future
   month payment therefore remains an advance and does not clear an older due.
4. **Total due** is the sum of the unpaid portions of billed months in
   that session. The displayed profile grid includes all months in the
   selected session, including future months marked paid when an advance
   was received.

### Admission / Readmission fee
`due = (sum of fee_master rows for the selected session where type is 'admission' or
'readmission') − (sum of amount_cash+amount_bank+amount_phonepe+discount
across admission_readmission receipts for that session)`. Every readmission adds a new
one-time charge on top of prior ones, so this naturally accumulates if a
student is readmitted more than once without clearing a prior charge.

### Other fee
No due tracking — it's a plain ad-hoc receipt log against a category,
with no corresponding "charge" to compare against.

## 7. Permissions
Same full-access / limited-access split as every other module:
- **Limited access** (e.g. `viewer`): can search students and record new
  payments (monthly/admission-readmission/other), and view all reports.
  Cannot edit or delete an existing payment once saved.
- **Full access** (`admin`/`editor`): everything limited access can do,
  plus editing or deleting any existing `fee_receipts` row (Edit/Delete
  buttons appear in the payment history tables on the Fee Collection page).
  Enforced both in the UI (buttons hidden for limited access) and at the
  database level via the `fee_receipts_update`/`fee_receipts_delete` RLS
  policies in `sql/module_fee.sql`.
- Deleting or editing a payment immediately changes the FIFO pool, so due
  amounts recalculate the next time the student is looked up — there's no
  separate "recalculate" step needed.
- The Fee Due & Reports page is read-only for both access levels by
  design — corrections happen on the Fee Collection page, where the
  record naturally lives.

## 8. Where this is implemented
- `pages/fee-collection.html` — the calculation engine + collection UI
  (search student → Monthly / Admission-Readmission / Other tabs, plus
  bulk Excel upload for each type).
- `pages/fee-due-report.html` — the same calculation engine reused
  read-only, plus class-wise, month-wise, and date-range aggregate
  reports.
- Both pages **duplicate** the calculation functions rather than sharing
  a file, consistent with this project's "every page is a standalone
  module" convention (see HOW_TO_ADD_PAGE.md). If you change the due
  formula, update it in both files.
