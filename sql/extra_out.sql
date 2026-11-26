-- Extra Out ledger and page registration.
-- Run after sql/page_and_user_access_migration.sql.

DO $$
BEGIN
  IF to_regclass('public.app_pages') IS NULL
     OR to_regclass('public.user_page_permissions') IS NULL
     OR to_regprocedure('public.has_page_permission(text,text)') IS NULL THEN
    RAISE EXCEPTION
      'Run sql/page_and_user_access_migration.sql before sql/extra_out.sql.';
  END IF;
END
$$;

CREATE TABLE IF NOT EXISTS public.extra_out_transactions (
  transaction_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  txn_type text NOT NULL CHECK (txn_type IN ('extra_out', 'adjustment')),
  txn_date date NOT NULL DEFAULT CURRENT_DATE,
  person_name text NOT NULL CHECK (length(trim(person_name)) BETWEEN 1 AND 160),
  payment_mode text NOT NULL DEFAULT 'cash' CHECK (payment_mode IN ('cash', 'bank', 'phonepe')),
  amount numeric(14,2) NOT NULL CHECK (amount > 0),
  reason text CHECK (reason IS NULL OR length(reason) <= 500),
  created_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  updated_by uuid REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_extra_out_transactions_date
  ON public.extra_out_transactions (txn_date DESC, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_extra_out_transactions_person
  ON public.extra_out_transactions (lower(trim(person_name)), txn_type);

CREATE OR REPLACE FUNCTION public.validate_extra_out_ledger()
RETURNS trigger
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE
  old_id uuid;
  old_key text;
  new_key text;
  person_keys text[];
  lock_key text;
  invalid_balance boolean;
BEGIN
  IF TG_OP <> 'INSERT' THEN
    old_id := OLD.transaction_id;
    old_key := lower(trim(OLD.person_name));
  END IF;
  IF TG_OP <> 'DELETE' THEN
    new_key := lower(trim(NEW.person_name));
  END IF;

  person_keys := array_remove(ARRAY[old_key, new_key], NULL);
  FOR lock_key IN
    SELECT DISTINCT person_key
    FROM unnest(person_keys) AS keys(person_key)
    WHERE person_key IS NOT NULL
    ORDER BY person_key
  LOOP
    PERFORM pg_advisory_xact_lock(hashtext(lock_key));
  END LOOP;

  IF TG_OP = 'DELETE' THEN
    WITH daily AS (
      SELECT lower(trim(person_name)) AS person_key, txn_date,
        SUM(CASE WHEN txn_type = 'extra_out' THEN amount ELSE -amount END) AS change
      FROM public.extra_out_transactions
      WHERE lower(trim(person_name)) = ANY(person_keys)
        AND transaction_id <> old_id
      GROUP BY lower(trim(person_name)), txn_date
    ), running AS (
      SELECT person_key, SUM(change) OVER (PARTITION BY person_key ORDER BY txn_date) AS due
      FROM daily
    )
    SELECT EXISTS (SELECT 1 FROM running WHERE due < -0.005) INTO invalid_balance;
  ELSE
    WITH entries AS (
      SELECT lower(trim(person_name)) AS person_key, txn_date, txn_type, amount
      FROM public.extra_out_transactions
      WHERE lower(trim(person_name)) = ANY(person_keys)
        AND (old_id IS NULL OR transaction_id <> old_id)
      UNION ALL
      SELECT new_key, NEW.txn_date, NEW.txn_type, NEW.amount
    ), daily AS (
      SELECT person_key, txn_date,
        SUM(CASE WHEN txn_type = 'extra_out' THEN amount ELSE -amount END) AS change
      FROM entries
      GROUP BY person_key, txn_date
    ), running AS (
      SELECT person_key, SUM(change) OVER (PARTITION BY person_key ORDER BY txn_date) AS due
      FROM daily
    )
    SELECT EXISTS (SELECT 1 FROM running WHERE due < -0.005) INTO invalid_balance;
  END IF;

  IF invalid_balance THEN
    RAISE EXCEPTION 'Repayments cannot exceed money given as of the transaction date.'
      USING ERRCODE = '23514';
  END IF;

  IF TG_OP = 'DELETE' THEN
    RETURN OLD;
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_validate_extra_out_ledger ON public.extra_out_transactions;
CREATE TRIGGER trg_validate_extra_out_ledger
  BEFORE INSERT OR UPDATE OR DELETE ON public.extra_out_transactions
  FOR EACH ROW EXECUTE FUNCTION public.validate_extra_out_ledger();

ALTER TABLE public.extra_out_transactions ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT, UPDATE, DELETE ON public.extra_out_transactions TO authenticated;

DROP POLICY IF EXISTS extra_out_transactions_select ON public.extra_out_transactions;
CREATE POLICY extra_out_transactions_select ON public.extra_out_transactions
  FOR SELECT TO authenticated
  USING (
    public.has_page_permission('extra-out', 'view')
    OR public.has_page_permission('dashboard-Report', 'view')
  );

DROP POLICY IF EXISTS extra_out_transactions_insert ON public.extra_out_transactions;
CREATE POLICY extra_out_transactions_insert ON public.extra_out_transactions
  FOR INSERT TO authenticated
  WITH CHECK (
    created_by = auth.uid()
    AND public.has_page_permission('extra-out', 'create')
  );

DROP POLICY IF EXISTS extra_out_transactions_update ON public.extra_out_transactions;
CREATE POLICY extra_out_transactions_update ON public.extra_out_transactions
  FOR UPDATE TO authenticated
  USING (public.has_page_permission('extra-out', 'edit'))
  WITH CHECK (public.has_page_permission('extra-out', 'edit'));

DROP POLICY IF EXISTS extra_out_transactions_delete ON public.extra_out_transactions;
CREATE POLICY extra_out_transactions_delete ON public.extra_out_transactions
  FOR DELETE TO authenticated
  USING (public.has_page_permission('extra-out', 'delete'));

INSERT INTO public.app_pages
  (page_key, page_name, icon, file_location, menu_group, sort_order,
   available_functions, function_notes, is_active)
VALUES
  ('extra-out', 'Extra Out', '💸', 'pages/extra-out.html', 'Accounts', 10,
   ARRAY['view','create','edit','delete']::text[],
   'Record money given to people, repayments, outstanding balances, and searchable ledgers',
   true)
ON CONFLICT (page_key) DO UPDATE SET
  page_name = EXCLUDED.page_name,
  icon = EXCLUDED.icon,
  file_location = EXCLUDED.file_location,
  menu_group = EXCLUDED.menu_group,
  sort_order = EXCLUDED.sort_order,
  available_functions = EXCLUDED.available_functions,
  function_notes = EXCLUDED.function_notes,
  is_active = EXCLUDED.is_active;

INSERT INTO public.user_page_permissions
  (user_id, page_id, can_view, can_create, can_edit, can_delete)
SELECT
  u.user_id,
  ap.page_id,
  true,
  true,
  r.role_name = ANY (ARRAY['admin'::text, 'editor'::text]),
  r.role_name = ANY (ARRAY['admin'::text, 'editor'::text])
FROM public.users u
JOIN public.roles r ON r.role_id = u.role_id
CROSS JOIN public.app_pages ap
WHERE u.status = 'active'
  AND ap.page_key = 'extra-out'
ON CONFLICT (user_id, page_id) DO NOTHING;

