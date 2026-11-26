-- Standalone migration for the session-aware admission and fee workflow.
-- Run once in the Supabase SQL Editor against an existing school database.
--
-- Requires the existing public.student_master, public.fee_master,
-- public.fee_receipts, and public.due_payments tables.
--
-- Existing students and their untagged fee records are assigned to the
-- session current on the day this migration runs. Historical session
-- assignments cannot be reconstructed if they were not previously stored.

BEGIN;

-- Store each student's active session and the sessions they attended before
-- readmission. Classes 1-9 use calendar-year sessions; Classes 10-12 use
-- April-to-March sessions. The application supplies the selected session for
-- admissions, including future-session reservations.
ALTER TABLE public.student_master
  ADD COLUMN IF NOT EXISTS academic_session text;

ALTER TABLE public.student_master
  ADD COLUMN IF NOT EXISTS previous_sessions text[] NOT NULL DEFAULT '{}';

-- Associate fee rows and receipts with the session they belong to.
ALTER TABLE public.fee_master
  ADD COLUMN IF NOT EXISTS academic_session text;

ALTER TABLE public.fee_receipts
  ADD COLUMN IF NOT EXISTS target_session text;

-- Keep receipt discounts and old-due payment discounts available on
-- databases created before those fields were added.
ALTER TABLE public.fee_receipts
  ADD COLUMN IF NOT EXISTS discount numeric NOT NULL DEFAULT 0;

ALTER TABLE public.due_payments
  ADD COLUMN IF NOT EXISTS discount numeric NOT NULL DEFAULT 0;

-- Ensure Classes 1-3 are accepted alongside the previously supported classes.
ALTER TABLE public.student_master
  DROP CONSTRAINT IF EXISTS student_master_class_check;

ALTER TABLE public.student_master
  ADD CONSTRAINT student_master_class_check
  CHECK (class = ANY (ARRAY[
    '1','2','3','4','5','6','7','8','9','10',
    '11-arts','11-science','12-arts','12-science'
  ]));

-- Backfill existing student records to the session active when this migration
-- runs. For Classes 10-12, a session crosses calendar years in April.
UPDATE public.student_master
SET academic_session = CASE
  WHEN class IN ('10','11-arts','11-science','12-arts','12-science') THEN
    CASE
      WHEN EXTRACT(MONTH FROM CURRENT_DATE) >= 4 THEN
        EXTRACT(YEAR FROM CURRENT_DATE)::integer::text || '-' ||
        RIGHT((EXTRACT(YEAR FROM CURRENT_DATE)::integer + 1)::text, 2)
      ELSE
        (EXTRACT(YEAR FROM CURRENT_DATE)::integer - 1)::text || '-' ||
        RIGHT(EXTRACT(YEAR FROM CURRENT_DATE)::integer::text, 2)
    END
  ELSE EXTRACT(YEAR FROM CURRENT_DATE)::integer::text
END
WHERE academic_session IS NULL OR academic_session = '';

-- Tag existing fee records and receipts with each student's current session.
UPDATE public.fee_master AS fm
SET academic_session = sm.academic_session
FROM public.student_master AS sm
WHERE sm.reg_no = fm.student_reg_no
  AND fm.academic_session IS NULL;

UPDATE public.fee_receipts AS fr
SET target_session = sm.academic_session
FROM public.student_master AS sm
WHERE sm.reg_no = fr.student_reg_no
  AND fr.target_session IS NULL;

ALTER TABLE public.student_master
  ALTER COLUMN academic_session SET DEFAULT EXTRACT(YEAR FROM CURRENT_DATE)::integer::text;

ALTER TABLE public.student_master
  ALTER COLUMN academic_session SET NOT NULL;

-- Support session-scoped student and fee lookups.
CREATE INDEX IF NOT EXISTS student_master_academic_session_idx
  ON public.student_master (academic_session);

CREATE INDEX IF NOT EXISTS fee_receipts_target_session_idx
  ON public.fee_receipts (target_session)
  WHERE target_session IS NOT NULL;

CREATE INDEX IF NOT EXISTS fee_master_academic_session_idx
  ON public.fee_master (student_reg_no, academic_session);

COMMIT;

