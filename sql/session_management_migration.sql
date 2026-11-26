-- Session-aware admissions and fee receipts.
-- Run once in the Supabase SQL Editor after deploying the updated pages.

ALTER TABLE public.student_master
  ADD COLUMN IF NOT EXISTS academic_session text;

ALTER TABLE public.student_master
  ADD COLUMN IF NOT EXISTS previous_sessions text[] NOT NULL DEFAULT '{}';

ALTER TABLE public.fee_receipts
  ADD COLUMN IF NOT EXISTS target_session text;

ALTER TABLE public.fee_master
  ADD COLUMN IF NOT EXISTS academic_session text;

ALTER TABLE public.student_master
  DROP CONSTRAINT IF EXISTS student_master_class_check;

ALTER TABLE public.student_master
  ADD CONSTRAINT student_master_class_check
  CHECK (class = ANY (ARRAY[
    '1','2','3','4','5','6','7','8','9','10',
    '11-arts','11-science','12-arts','12-science'
  ]));

-- Existing students start in the session that is current on migration day.
UPDATE public.student_master
SET academic_session = CASE
  WHEN class IN ('10','11-arts','11-science','12-arts','12-science') THEN
    CASE WHEN EXTRACT(MONTH FROM CURRENT_DATE) >= 4
      THEN EXTRACT(YEAR FROM CURRENT_DATE)::integer::text || '-' || RIGHT((EXTRACT(YEAR FROM CURRENT_DATE)::integer + 1)::text, 2)
      ELSE (EXTRACT(YEAR FROM CURRENT_DATE)::integer - 1)::text || '-' || RIGHT(EXTRACT(YEAR FROM CURRENT_DATE)::integer::text, 2)
    END
  ELSE EXTRACT(YEAR FROM CURRENT_DATE)::integer::text
END
WHERE academic_session IS NULL OR academic_session = '';

UPDATE public.fee_master fm
SET academic_session = sm.academic_session
FROM public.student_master sm
WHERE sm.reg_no = fm.student_reg_no
  AND fm.academic_session IS NULL;

UPDATE public.fee_receipts fr
SET target_session = sm.academic_session
FROM public.student_master sm
WHERE sm.reg_no = fr.student_reg_no
  AND fr.target_session IS NULL;

ALTER TABLE public.student_master
  ALTER COLUMN academic_session SET DEFAULT EXTRACT(YEAR FROM CURRENT_DATE)::integer::text;

ALTER TABLE public.student_master
  ALTER COLUMN academic_session SET NOT NULL;

CREATE INDEX IF NOT EXISTS student_master_academic_session_idx
  ON public.student_master (academic_session);

CREATE INDEX IF NOT EXISTS fee_receipts_target_session_idx
  ON public.fee_receipts (target_session)
  WHERE target_session IS NOT NULL;

CREATE INDEX IF NOT EXISTS fee_master_academic_session_idx
  ON public.fee_master (student_reg_no, academic_session);
