-- ============================================================================
-- SUPABASE MIGRATION: DYNAMIC PAGE REGISTRY & GRANULAR USER ACCESS CONTROL
-- Replaces static assets/js/menu.js with two database tables:
--   1. public.app_pages              (stores page info, emoji icon, location, group, functions)
--   2. public.user_page_permissions  (stores per-user View, Enter Data, Edit, Delete permissions)
-- Run this script in your Supabase SQL Editor.
-- ============================================================================

-- ----------------------------------------------------------------------------
-- 1. TABLE 1: public.app_pages (Page Information Table)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.app_pages (
  page_id             uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  page_key            text NOT NULL UNIQUE,           -- unique slug matching PAGE_ID (e.g. 'admission')
  page_name           text NOT NULL,                  -- label shown in sidebar menu (e.g. 'Admission')
  icon                text NOT NULL DEFAULT '📄',     -- emoji / icon shown in sidebar rail
  file_location       text NOT NULL,                  -- relative path (e.g. 'pages/admission.html') or URL
  menu_group          text NOT NULL DEFAULT 'General',-- sidebar section (e.g. 'Academics', 'Accounts')
  sort_order          integer NOT NULL DEFAULT 10,    -- display order inside the group (lower = higher)
  available_functions text[] NOT NULL DEFAULT ARRAY['view','create','edit','delete']::text[],
  function_notes      text,                           -- human-readable description of page functions
  is_active           boolean NOT NULL DEFAULT true,  -- whether page appears in menus
  created_at          timestamptz NOT NULL DEFAULT now(),
  updated_at          timestamptz NOT NULL DEFAULT now(),
  created_by          uuid REFERENCES auth.users(id),
  updated_by          uuid REFERENCES auth.users(id)
);

DROP TRIGGER IF EXISTS trg_app_pages_updated_at ON public.app_pages;
CREATE TRIGGER trg_app_pages_updated_at
  BEFORE UPDATE ON public.app_pages
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- ----------------------------------------------------------------------------
-- 2. TABLE 2: public.user_page_permissions (Per-User Granular Access Table)
-- ----------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.user_page_permissions (
  permission_id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id       uuid NOT NULL REFERENCES public.users(user_id) ON DELETE CASCADE,
  page_id       uuid NOT NULL REFERENCES public.app_pages(page_id) ON DELETE CASCADE,
  can_view      boolean NOT NULL DEFAULT false,       -- Only View / Read page
  can_create    boolean NOT NULL DEFAULT false,       -- Enter Data / Add / Bulk Upload
  can_edit      boolean NOT NULL DEFAULT false,       -- Edit / Modify existing records
  can_delete    boolean NOT NULL DEFAULT false,       -- Delete records
  created_at    timestamptz NOT NULL DEFAULT now(),
  updated_at    timestamptz NOT NULL DEFAULT now(),
  created_by    uuid REFERENCES auth.users(id),
  updated_by    uuid REFERENCES auth.users(id),
  CONSTRAINT user_page_permissions_user_page_unique UNIQUE (user_id, page_id)
);

DROP TRIGGER IF EXISTS trg_user_page_permissions_updated_at ON public.user_page_permissions;
CREATE TRIGGER trg_user_page_permissions_updated_at
  BEFORE UPDATE ON public.user_page_permissions
  FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE INDEX IF NOT EXISTS idx_app_pages_group_order ON public.app_pages (menu_group, sort_order);
CREATE INDEX IF NOT EXISTS idx_user_page_perm_user ON public.user_page_permissions (user_id);
CREATE INDEX IF NOT EXISTS idx_user_page_perm_page ON public.user_page_permissions (page_id);

-- ----------------------------------------------------------------------------
-- 3. HELPER FUNCTION FOR RLS & PERMISSION CHECKING
-- ----------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.has_page_permission(p_page_key text, p_action text DEFAULT 'view')
RETURNS boolean
LANGUAGE sql
STABLE SECURITY DEFINER
SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN public.is_admin() THEN true
    ELSE COALESCE((
      SELECT
        CASE lower(p_action)
          WHEN 'view'   THEN upp.can_view
          WHEN 'create' THEN (upp.can_view AND upp.can_create)
          WHEN 'edit'   THEN (upp.can_view AND upp.can_edit)
          WHEN 'delete' THEN (upp.can_view AND upp.can_delete)
          ELSE false
        END
      FROM public.user_page_permissions upp
      JOIN public.app_pages ap ON ap.page_id = upp.page_id
      JOIN public.users u ON u.user_id = upp.user_id
      WHERE upp.user_id = auth.uid()
        AND u.status = 'active'
        AND ap.is_active = true
        AND (lower(ap.page_key) = lower(p_page_key) OR lower(ap.file_location) = lower(p_page_key))
      LIMIT 1
    ), false)
  END;
$function$;

-- ----------------------------------------------------------------------------
-- 4. ROW LEVEL SECURITY (RLS) POLICIES
-- ----------------------------------------------------------------------------
ALTER TABLE public.app_pages ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_page_permissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS app_pages_select ON public.app_pages;
CREATE POLICY app_pages_select ON public.app_pages
  FOR SELECT USING (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS app_pages_insert ON public.app_pages;
CREATE POLICY app_pages_insert ON public.app_pages
  FOR INSERT WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS app_pages_update ON public.app_pages;
CREATE POLICY app_pages_update ON public.app_pages
  FOR UPDATE USING (public.is_admin());

DROP POLICY IF EXISTS app_pages_delete ON public.app_pages;
CREATE POLICY app_pages_delete ON public.app_pages
  FOR DELETE USING (public.is_admin());

DROP POLICY IF EXISTS user_page_permissions_select ON public.user_page_permissions;
CREATE POLICY user_page_permissions_select ON public.user_page_permissions
  FOR SELECT USING ((auth.uid() = user_id) OR public.is_admin());

DROP POLICY IF EXISTS user_page_permissions_insert ON public.user_page_permissions;
CREATE POLICY user_page_permissions_insert ON public.user_page_permissions
  FOR INSERT WITH CHECK (public.is_admin());

DROP POLICY IF EXISTS user_page_permissions_update ON public.user_page_permissions;
CREATE POLICY user_page_permissions_update ON public.user_page_permissions
  FOR UPDATE USING (public.is_admin());

DROP POLICY IF EXISTS user_page_permissions_delete ON public.user_page_permissions;
CREATE POLICY user_page_permissions_delete ON public.user_page_permissions
  FOR DELETE USING (public.is_admin());

-- ----------------------------------------------------------------------------
-- 5. SEED EXISTING PAGES + NEW ADMIN PAGES INTO public.app_pages
-- ----------------------------------------------------------------------------
INSERT INTO public.app_pages (page_key, page_name, icon, file_location, menu_group, sort_order, available_functions, function_notes, is_active)
VALUES
  ('dashboard',        'Dashboard',          '🏠', 'pages/dashboard.html',        'General',        1,  ARRAY['view'],                         'Overview cards and portal summary', true),
  ('dashboard-Report', 'Dashboard Report',   '📈', 'pages/dash-report.html',      'General',        2,  ARRAY['view'],                         'Detailed financial & student analytics report', true),
  ('notice-board',     'Notice Board',       '📌', 'pages/notice-board.html',     'General',        3,  ARRAY['view','create','edit','delete'], 'View notices, post notice, edit notice, delete notice', true),
  ('admission',        'Admission',          '🎓', 'pages/admission.html',        'Academics',      3,  ARRAY['view','create','edit','delete'], 'View students, new admission, re-admission, bulk upload, edit/deactivate/delete student', true),
  ('Result',           'Result',             '🧾', 'https://school-mark-sheet-result-generator.ai.studio/', 'Academics', 12, ARRAY['view'],    'External Mark Sheet & Result Generator app', true),
  ('fee-collection',   'Fee Collection',     '💰', 'pages/fee-collection.html',   'Accounts',       4,  ARRAY['view','create','edit','delete'], 'Collect monthly/admission/other fees, bulk upload, edit receipt, delete receipt', true),
  ('fee-due-report',   'Fee Due & Reports',  '📊', 'pages/fee-due-report.html',   'Accounts',       5,  ARRAY['view'],                         'View & export student fee due reports and collection registers', true),
  ('payment',          'Payment',            '💳', 'pages/payment.html',          'Accounts',       8,  ARRAY['view','create','edit','delete'], 'New voucher entry, bulk upload, search/export, generate voucher range, edit/delete voucher', true),
  ('daily-sheet',      'Daily Sheet',        '📋', 'pages/daily-sheet.html',      'Accounts',       9,  ARRAY['view','create'],                'View daily income/expense sheet and save closing snapshot', true),
  ('voucher-setup',    'Voucher Setup',      '🗂️', 'pages/voucher-setup.html',    'Accounts',       10, ARRAY['view','create','edit','delete'], 'Manage voucher heads, categories, and creditors', true),
  ('cash-flow',        'Cash Flow',          '💵', 'pages/cash-flow.html',        'Accounts',       10, ARRAY['view','create','edit','delete'], 'Manage cash inflow, cash outflow, fund transfers, and categories', true),
  ('cash-voucher',     'Cash Voucher',       '💵', 'pages/cash-voucher.html',     'Accounts',       11, ARRAY['view','create','edit','delete'], 'Legacy cash voucher module (toggle active if needed)', false),
  ('creditor-voucher', 'Creditor Voucher',   '🧾', 'pages/creditor-voucher.html', 'Accounts',       12, ARRAY['view','create','edit','delete'], 'Record credit purchases and creditor payments', true),
  ('old-dues',         'Old Dues',           '💰', 'pages/old-dues.html',         'Fees',           20, ARRAY['view','create','edit','delete'], 'Record old dues, collect due payments, bulk upload, edit/delete dues', true),
  ('staff',            'Staff',              '🧑', 'pages/staff.html',            'Staff & Salary', 10, ARRAY['view','create','edit','delete'], 'Staff directory, add staff, bulk upload, salary sheet & adjustments, deactivate staff', true),
  ('salary-payment',   'Salary Payment',     '💰', 'pages/salary-payment.html',   'Staff & Salary', 11, ARRAY['view','create','edit','delete'], 'Standalone salary payment module (toggle active if needed)', false),
  ('manage-pages',     'Manage Pages',       '🗂️', 'pages/manage-pages.html',     'Administration', 8,  ARRAY['view','create','edit','delete'], 'Add new pages to portal registry, configure icon, path, group & functions', true),
  ('user-access',      'User Access Panel',  '🔐', 'pages/user-access.html',      'Administration', 9,  ARRAY['view','create','edit','delete'], 'Assign per-user granular access (Only View, Enter Data, Edit, Delete) per page', true),
  ('manage-users',     'Approve Users',      '✅', 'pages/manage-users.html',     'Administration', 10, ARRAY['view','edit'],                  'Approve pending user registrations, assign roles, activate/deactivate users', true),
  ('manage-roles',     'Manage Roles',       '🏷️', 'pages/manage-roles.html',     'Administration', 11, ARRAY['view','create'],                'View and create user role labels', true),
  ('audit-log',        'Audit Log',          '🕒', 'pages/audit-log.html',        'Administration', 12, ARRAY['view'],                         'View system-wide audit history of changes', true)
ON CONFLICT (page_key) DO UPDATE SET
  page_name           = EXCLUDED.page_name,
  icon                = EXCLUDED.icon,
  file_location       = EXCLUDED.file_location,
  menu_group          = EXCLUDED.menu_group,
  sort_order          = EXCLUDED.sort_order,
  available_functions = EXCLUDED.available_functions,
  function_notes      = EXCLUDED.function_notes;

-- ----------------------------------------------------------------------------
-- 6. AUTO-SEED PERMISSIONS FOR EXISTING USERS (BASED ON THEIR CURRENT ROLES)
--    So existing users immediately keep their expected access upon migration,
--    and Admin can fine-tune each individual user from pages/user-access.html.
-- ----------------------------------------------------------------------------
INSERT INTO public.user_page_permissions (user_id, page_id, can_view, can_create, can_edit, can_delete)
SELECT
  u.user_id,
  ap.page_id,
  true AS can_view,
  ('create' = ANY(ap.available_functions)) AS can_create,
  CASE
    WHEN r.role_name = 'admin' THEN ('edit' = ANY(ap.available_functions))
    WHEN r.role_name = 'editor' AND ap.page_key IN ('dashboard','dashboard-Report','admission','fee-collection','fee-due-report','daily-sheet','notice-board') THEN ('edit' = ANY(ap.available_functions))
    ELSE false
  END AS can_edit,
  CASE
    WHEN r.role_name = 'admin' THEN ('delete' = ANY(ap.available_functions))
    WHEN r.role_name = 'editor' AND ap.page_key IN ('dashboard','dashboard-Report','admission','fee-collection','fee-due-report','daily-sheet','notice-board') THEN ('delete' = ANY(ap.available_functions))
    ELSE false
  END AS can_delete
FROM public.users u
JOIN public.roles r ON r.role_id = u.role_id
CROSS JOIN public.app_pages ap
WHERE (
  r.role_name = 'admin'
  OR (r.role_name = 'editor' AND ap.menu_group <> 'Administration')
  OR (r.role_name IN ('viewer', 'accountent', 'accountant', 'manager', 'teacher') AND ap.menu_group <> 'Administration')
)
ON CONFLICT (user_id, page_id) DO NOTHING;
