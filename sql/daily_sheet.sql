-- =============================================================================
-- DAILY SHEET — Supabase helper table + supporting view
-- Run once in the Supabase SQL editor.
--
-- Purpose: store a snapshot of closing balances for every calendar date
-- so the Daily Sheet page can look up "yesterday's closing" as today's
-- opening without re-scanning every historical transaction.
--
-- What is stored per date:
--   • Closing cash / bank / phonepe balance (from all receipts + cash-flow +
--     vouchers up to and including that date)
--   • Closing admission due (total charged − total paid/discounted across all
--     active students for admission/readmission fees)
--   • Closing monthly due (total monthly due across all active students up to
--     that date, using FIFO algorithm matching fee-collection.html)
--   • Closing old due balance (sum of student_old_dues minus due_payments up
--     to that date)
--
-- The page always RECALCULATES the selected date on-the-fly (live query), then
-- after a successful render it upserts the closing snapshot so future lookups
-- are fast. Past dates are served from this cache; today is always recomputed.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- 1. daily_closing_snapshot
--    One row per calendar date. Upserted by the Daily Sheet page each time a
--    date is loaded. Rows are NEVER deleted — the page's "force recalculate"
--    button simply re-upserts with fresh values.
-- -----------------------------------------------------------------------------
create table if not exists public.daily_closing_snapshot (
  snap_date            date        primary key,

  -- Cash / PhonePe / Bank closing balances
  close_cash           numeric(14,2) not null default 0,
  close_phonepe        numeric(14,2) not null default 0,
  close_bank           numeric(14,2) not null default 0,

  -- Student due closing balances (across all active students)
  close_admission_due  numeric(14,2) not null default 0,
  close_monthly_due    numeric(14,2) not null default 0,
  close_old_due        numeric(14,2) not null default 0,

  -- Audit
  calculated_at        timestamptz not null default now(),
  calculated_by        uuid references auth.users on delete set null
);

-- RLS: authenticated users can read; insert/update limited to the app's
-- service role or any authenticated user (same as other tables in this app).
alter table public.daily_closing_snapshot enable row level security;

-- Allow any authenticated (active) user to read snapshots
create policy "authenticated read daily_closing_snapshot"
  on public.daily_closing_snapshot
  for select
  to authenticated
  using (true);

-- Allow any authenticated user to upsert (the page inserts after every load)
create policy "authenticated upsert daily_closing_snapshot"
  on public.daily_closing_snapshot
  for all
  to authenticated
  using (true)
  with check (true);

-- Index for range queries (e.g. "latest snapshot before today")
create index if not exists idx_dcs_snap_date
  on public.daily_closing_snapshot (snap_date desc);

-- =============================================================================
-- HOW THE DAILY SHEET PAGE USES THIS TABLE
-- =============================================================================
-- Opening balance for date D  = closing snapshot for date D-1
--   (the page queries: SELECT * FROM daily_closing_snapshot
--                       WHERE snap_date < D
--                       ORDER BY snap_date DESC LIMIT 1)
--
-- If no prior snapshot exists (very first day), openings default to 0.
--
-- Closing balance for date D  = computed live by the page from all source
--   tables filtered to txn_date/recorded_at <= D, then upserted here.
--
-- Source tables queried for each section of the daily sheet:
--
-- FEE INCOME (cash in — split by mode):
--   fee_receipts WHERE received_date = D
--     → amount_cash, amount_bank, amount_phonepe
--
-- PAYMENTS (cash out — split by mode):
--   general_vouchers WHERE voucher_date = D AND status = 'used'
--     → amount / payment_mode  (cash | bank | phonepe)
--
-- CASH INFLOW / OUTFLOW (non-fee, non-voucher cash movements):
--   cash_inflow WHERE txn_date = D  → amount (always cash account)
--   cash_outflow WHERE txn_date = D → amount (always cash account)
--
-- INTER-ACCOUNT TRANSFERS:
--   fund_transfers WHERE txn_date = D → from_account, to_account, amount
--
-- CLOSING CASH / BANK / PHONEPE (cumulative, all dates <= D):
--   All fee_receipts received_date <= D  → sum amount_cash/bank/phonepe
--   All general_vouchers voucher_date <= D  → minus by mode
--   All cash_inflow txn_date <= D  → + amount (cash)
--   All cash_outflow txn_date <= D → - amount (cash)
--   All fund_transfers txn_date <= D → +/- by from/to account
--
-- CLOSING ADMISSION DUE (cumulative):
--   fee_master (admission/readmission rows, all dates) → total charged
--   fee_receipts (admission_readmission, recorded_at <= D) → total paid
--   → due = charged − paid
--
-- CLOSING MONTHLY DUE (cumulative to date D):
--   Per-student FIFO calculation for every active student up to month of D
--   (same algorithm as fee-collection.html computeMonthlyLedger)
--
-- CLOSING OLD DUE (cumulative):
--   student_old_dues (all records) → total due_amount
--   due_payments WHERE payment_date <= D → total amount + discount
--   → balance = due_amount − payments − discounts
-- =============================================================================
