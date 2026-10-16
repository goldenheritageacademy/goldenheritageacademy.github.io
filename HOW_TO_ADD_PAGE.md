# How to Add a New Page (Supabase Dynamic Menu & Granular Access Edition)

`assets/js/menu.js` has been **completely replaced** by two Supabase database tables:
1. **`public.app_pages`** — stores every page's Emoji Icon (`icon`), Page Name (`page_name`), Page Key (`page_key`), File Location (`file_location`), Menu Group (`menu_group`), Sort Order (`sort_order`), and Supported Functions (`available_functions`: `view`, `create`, `edit`, `delete`).
2. **`public.user_page_permissions`** — stores per-user granular access (`can_view`, `can_create`, `can_edit`, `can_delete`) for each page.

---

## 3-Step Workflow to Add Any New Page

### Step 1 — Upload your HTML file to GitHub
Copy `pages/PAGE_TEMPLATE.html` to `pages/<your-page>.html` (for example, `pages/library-books.html`) and push/upload it to your GitHub repository.
- In your new file, set `const PAGE_ID = "library-books";` (or even if you forget, `common.js` automatically matches the page by its file path `pages/library-books.html`!).
- Use `myAccess.canView`, `myAccess.canCreate` (Enter Data), `myAccess.canEdit` (Edit), and `myAccess.canDelete` (Delete) — or add `data-perm="create"`, `data-perm="edit"`, `data-perm="delete"` to any button, and `common.js` will automatically show/hide it and guard Supabase `.insert()`, `.update()`, and `.delete()` calls!

### Step 2 — Register the page in **Manage Pages** (`pages/manage-pages.html`)
Sign in as **Admin**, open **Administration → 🗂️ Manage Pages**, and click **+ Register New Page**:
- **Page Name**: e.g. `Library Books`
- **Emoji / Icon**: e.g. `📚`
- **File Location**: e.g. `pages/library-books.html` (auto-filled from Page Name)
- **Page ID / Key**: e.g. `library-books` (auto-filled)
- **Menu Group**: e.g. `Academics`
- **Supported Functions**: check which actions exist on this page (`Only View`, `Enter Data`, `Edit`, `Delete`).

### Step 3 — Grant users access in **User Access Panel** (`pages/user-access.html`)
Open **Administration → 🔐 User Access Panel**:
- Switch to **Configure by Page** (or **Configure by User**).
- Select your new page (`Library Books`) or select a user.
- Toggle individual checkboxes for **👁️ Only View**, **✍️ Enter Data**, **✏️ Edit**, and **🗑️ Delete**.
- Click **💾 Save Permissions**. The page immediately appears in those users' sidebar menus!
