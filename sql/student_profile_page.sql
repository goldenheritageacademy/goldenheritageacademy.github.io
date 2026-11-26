-- Install the Student search/profile page.
-- Requires public.app_pages, public.user_page_permissions and
-- public.has_page_permission(text,text) from page_and_user_access_migration.sql.

DO $$
BEGIN
  IF to_regclass('public.app_pages') IS NULL
     OR to_regclass('public.user_page_permissions') IS NULL
     OR to_regprocedure('public.has_page_permission(text,text)') IS NULL THEN
    RAISE EXCEPTION
      'Run sql/page_and_user_access_migration.sql before sql/student_profile_page.sql.';
  END IF;
END
$$;

ALTER TABLE public.student_master
  ADD COLUMN IF NOT EXISTS photo_path text;

CREATE TABLE IF NOT EXISTS public.student_profile_remarks (
  remark_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_reg_no text NOT NULL REFERENCES public.student_master(reg_no) ON DELETE CASCADE,
  remark_text text NOT NULL CHECK (length(trim(remark_text)) BETWEEN 1 AND 2000),
  recorded_by uuid REFERENCES auth.users(id),
  recorded_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_student_profile_remarks_student_time
  ON public.student_profile_remarks (student_reg_no, recorded_at DESC);

ALTER TABLE public.student_profile_remarks ENABLE ROW LEVEL SECURITY;
GRANT SELECT, INSERT ON public.student_profile_remarks TO authenticated;

DROP POLICY IF EXISTS student_profile_remarks_select ON public.student_profile_remarks;
CREATE POLICY student_profile_remarks_select ON public.student_profile_remarks
  FOR SELECT
  USING (
    public.current_role_name() IS NOT NULL
    AND public.has_page_permission('student', 'view')
  );

DROP POLICY IF EXISTS student_profile_remarks_insert ON public.student_profile_remarks;
CREATE POLICY student_profile_remarks_insert ON public.student_profile_remarks
  FOR INSERT
  WITH CHECK (
    recorded_by = auth.uid()
    AND public.has_page_permission('student', 'edit')
  );

-- Grant profile edits through the new page while retaining the existing
-- admin/editor and Admission-page edit permissions.
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

-- Register the page in the portal's dynamic navigation.
INSERT INTO public.app_pages
  (page_key, page_name, icon, file_location, menu_group, sort_order,
   available_functions, function_notes, is_active)
VALUES
  ('student', 'Student', '👨‍🎓', 'pages/student.html', 'Academics', 4,
   ARRAY['view','edit']::text[],
   'Search complete student profiles, view fee/payment dues and exam percentages, edit profile data and add remark history',
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

-- Existing active users can view student profiles. Existing admins/editors
-- receive edit access; admins can adjust individual access in User Access.
INSERT INTO public.user_page_permissions
  (user_id, page_id, can_view, can_create, can_edit, can_delete)
SELECT
  u.user_id,
  ap.page_id,
  true,
  false,
  r.role_name = ANY (ARRAY['admin'::text, 'editor'::text]),
  false
FROM public.users u
JOIN public.roles r ON r.role_id = u.role_id
CROSS JOIN public.app_pages ap
WHERE u.status = 'active'
  AND ap.page_key = 'student'
ON CONFLICT (user_id, page_id) DO NOTHING;

-- Create/update the private image bucket and support Student-page edit access.
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES ('student-photos', 'student-photos', false, 5242880, ARRAY['image/jpeg'])
ON CONFLICT (id) DO UPDATE
SET public = false,
    file_size_limit = 5242880,
    allowed_mime_types = ARRAY['image/jpeg'];

DROP POLICY IF EXISTS student_photos_select ON storage.objects;
CREATE POLICY student_photos_select ON storage.objects FOR SELECT
  USING (
    bucket_id = 'student-photos'
    AND (
      public.current_role_name() = ANY (ARRAY['admin'::text, 'editor'::text, 'viewer'::text])
      OR public.has_page_permission('admission', 'view')
      OR public.has_page_permission('student', 'view')
    )
  );

DROP POLICY IF EXISTS student_photos_insert ON storage.objects;
CREATE POLICY student_photos_insert ON storage.objects FOR INSERT
  WITH CHECK (
    bucket_id = 'student-photos'
    AND (storage.foldername(name))[1] = auth.uid()::text
    AND (
      public.current_role_name() = ANY (ARRAY['admin'::text, 'editor'::text, 'viewer'::text])
      OR public.has_page_permission('admission', 'create')
      OR public.has_page_permission('admission', 'edit')
      OR public.has_page_permission('student', 'edit')
    )
  );

DROP POLICY IF EXISTS student_photos_delete ON storage.objects;
CREATE POLICY student_photos_delete ON storage.objects FOR DELETE
  USING (
    bucket_id = 'student-photos'
    AND (
      public.current_role_name() = ANY (ARRAY['admin'::text, 'editor'::text])
      OR public.has_page_permission('admission', 'edit')
      OR public.has_page_permission('student', 'edit')
      OR (
        public.current_role_name() = 'viewer'
        AND (storage.foldername(name))[1] = auth.uid()::text
      )
    )
  );

SELECT
  ap.page_key,
  ap.file_location,
  count(upp.user_id) AS users_with_page_access
FROM public.app_pages ap
LEFT JOIN public.user_page_permissions upp ON upp.page_id = ap.page_id
WHERE ap.page_key = 'student'
GROUP BY ap.page_key, ap.file_location;
