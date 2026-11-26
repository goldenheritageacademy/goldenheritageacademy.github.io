-- Fix student profile image uploads that succeed but cannot update
-- student_master.photo_path under row-level security.
-- Requires page_and_user_access_migration.sql (has_page_permission).

DO $$
BEGIN
  IF to_regprocedure('public.has_page_permission(text,text)') IS NULL THEN
    RAISE EXCEPTION
      'Run sql/page_and_user_access_migration.sql first; public.has_page_permission(text,text) is missing.';
  END IF;
END
$$;

ALTER TABLE public.student_master
  ADD COLUMN IF NOT EXISTS photo_path text;

DROP POLICY IF EXISTS student_master_update ON public.student_master;

CREATE POLICY student_master_update ON public.student_master
  FOR UPDATE
  USING (
    public.current_role_name() = ANY (ARRAY['admin'::text, 'editor'::text])
    OR public.has_page_permission('admission', 'edit')
    OR public.has_page_permission('student', 'edit')
  )
  WITH CHECK (
    public.current_role_name() = ANY (ARRAY['admin'::text, 'editor'::text])
    OR public.has_page_permission('admission', 'edit')
    OR public.has_page_permission('student', 'edit')
  );

-- Confirm the replacement policy is installed.
SELECT policyname, cmd, qual, with_check
FROM pg_policies
WHERE schemaname = 'public'
  AND tablename = 'student_master'
  AND policyname = 'student_master_update';
