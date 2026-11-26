-- Student profile image support.
-- Run once on existing projects; new installs should also include this migration.

ALTER TABLE public.student_master
  ADD COLUMN IF NOT EXISTS photo_path text;

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
