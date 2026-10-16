/* ============================================================================
   COMMON.JS — shared functions every page (main frame + every module page)
   includes after config.js.
   Provides:
     - Session / current user profile helpers
     - Dynamic Supabase Page Registry & Granular User Access (replaces menu.js)
       Supports 4 granular permissions per page:
         * can_view   ("Only View")
         * can_create ("Enter Data")
         * can_edit   ("Edit")
         * can_delete ("Delete")
     - Automatic UI + Supabase mutation guard for View / Enter Data / Edit / Delete
     - Universal Modal / Popup system, Toasts, and Audit Logging
   ============================================================================ */

/* ---------------------------------------------------------------------------
   FALLBACK PAGES (used only if sql/page_and_user_access_migration.sql has not
   been executed in Supabase yet, ensuring the app never breaks during setup)
--------------------------------------------------------------------------- */
const FALLBACK_APP_PAGES = [
  { page_key: "dashboard",        page_name: "Dashboard",         icon: "🏠", file_location: "pages/dashboard.html",        menu_group: "General",        sort_order: 1,  available_functions: ["view"],                           is_active: true },
  { page_key: "dashboard-Report", page_name: "Dashboard Report",  icon: "📈", file_location: "pages/dash-report.html",      menu_group: "General",        sort_order: 2,  available_functions: ["view"],                           is_active: true },
  { page_key: "notice-board",     page_name: "Notice Board",      icon: "📌", file_location: "pages/notice-board.html",     menu_group: "General",        sort_order: 3,  available_functions: ["view","create","edit","delete"],   is_active: true },
  { page_key: "admission",        page_name: "Admission",         icon: "🎓", file_location: "pages/admission.html",        menu_group: "Academics",      sort_order: 3,  available_functions: ["view","create","edit","delete"],   is_active: true },
  { page_key: "Result",           page_name: "Result",            icon: "🧾", file_location: "https://school-mark-sheet-result-generator.ai.studio/", menu_group: "Academics", sort_order: 12, available_functions: ["view"], is_active: true },
  { page_key: "fee-collection",   page_name: "Fee Collection",    icon: "💰", file_location: "pages/fee-collection.html",   menu_group: "Accounts",       sort_order: 4,  available_functions: ["view","create","edit","delete"],   is_active: true },
  { page_key: "fee-due-report",   page_name: "Fee Due & Reports", icon: "📊", file_location: "pages/fee-due-report.html",   menu_group: "Accounts",       sort_order: 5,  available_functions: ["view"],                           is_active: true },
  { page_key: "payment",          page_name: "Payment",           icon: "💳", file_location: "pages/payment.html",          menu_group: "Accounts",       sort_order: 8,  available_functions: ["view","create","edit","delete"],   is_active: true },
  { page_key: "daily-sheet",      page_name: "Daily Sheet",       icon: "📋", file_location: "pages/daily-sheet.html",      menu_group: "Accounts",       sort_order: 9,  available_functions: ["view","create"],                  is_active: true },
  { page_key: "voucher-setup",    page_name: "Voucher Setup",     icon: "🗂️", file_location: "pages/voucher-setup.html",    menu_group: "Accounts",       sort_order: 10, available_functions: ["view","create","edit","delete"],   is_active: true },
  { page_key: "cash-flow",        page_name: "Cash Flow",         icon: "💵", file_location: "pages/cash-flow.html",        menu_group: "Accounts",       sort_order: 10, available_functions: ["view","create","edit","delete"],   is_active: true },
  { page_key: "creditor-voucher", page_name: "Creditor Voucher",  icon: "🧾", file_location: "pages/creditor-voucher.html", menu_group: "Accounts",       sort_order: 12, available_functions: ["view","create","edit","delete"],   is_active: true },
  { page_key: "old-dues",         page_name: "Old Dues",          icon: "💰", file_location: "pages/old-dues.html",         menu_group: "Fees",           sort_order: 20, available_functions: ["view","create","edit","delete"],   is_active: true },
  { page_key: "staff",            page_name: "Staff",             icon: "🧑", file_location: "pages/staff.html",            menu_group: "Staff & Salary", sort_order: 10, available_functions: ["view","create","edit","delete"],   is_active: true },
  { page_key: "manage-pages",     page_name: "Manage Pages",      icon: "🗂️", file_location: "pages/manage-pages.html",     menu_group: "Administration", sort_order: 8,  available_functions: ["view","create","edit","delete"],   is_active: true },
  { page_key: "user-access",      page_name: "User Access Panel", icon: "🔐", file_location: "pages/user-access.html",      menu_group: "Administration", sort_order: 9,  available_functions: ["view","create","edit","delete"],   is_active: true },
  { page_key: "manage-users",     page_name: "Approve Users",     icon: "✅", file_location: "pages/manage-users.html",     menu_group: "Administration", sort_order: 10, available_functions: ["view","edit"],                    is_active: true },
  { page_key: "manage-roles",     page_name: "Manage Roles",      icon: "🏷️", file_location: "pages/manage-roles.html",     menu_group: "Administration", sort_order: 11, available_functions: ["view","create"],                  is_active: true },
  { page_key: "audit-log",        page_name: "Audit Log",         icon: "🕒", file_location: "pages/audit-log.html",        menu_group: "Administration", sort_order: 12, available_functions: ["view"],                           is_active: true }
];

/* ---------------------------------------------------------------------------
   USERNAME <-> EMAIL (Supabase Auth needs an email; users only see username)
--------------------------------------------------------------------------- */
function usernameToEmail(username) {
  return `${username.trim().toLowerCase()}@${EMAIL_DOMAIN}`;
}

/* ---------------------------------------------------------------------------
   SESSION / CURRENT USER
--------------------------------------------------------------------------- */
async function getSession() {
  const { data } = await supabaseClient.auth.getSession();
  return data.session;
}

async function getCurrentProfile() {
  const session = await getSession();
  if (!session) return null;
  const { data, error } = await supabaseClient
    .from("users")
    .select("user_id, username, mobile_no, status, role_id, roles(role_name)")
    .eq("user_id", session.user.id)
    .single();
  if (error || !data) return null;
  return {
    user_id: data.user_id,
    username: data.username,
    mobile_no: data.mobile_no,
    status: data.status,
    role_id: data.role_id,
    role_name: data.roles ? data.roles.role_name : null
  };
}

async function requireActiveUser() {
  const profile = await getCurrentProfile();
  if (!profile || profile.status !== STATUS.ACTIVE) {
    document.body.innerHTML =
      '<div class="empty-state"><div class="icon">🔒</div>' +
      "<h3>Not signed in</h3><p>Please sign in from the main portal window.</p></div>";
    return null;
  }
  return profile;
}

/* ---------------------------------------------------------------------------
   SUPABASE-DRIVEN PAGE REGISTRY & USER PERMISSIONS (Replaces menu.js)
--------------------------------------------------------------------------- */
let _cachedPages = null;
let _cachedUserPerms = {};

function normalizePageRow(p) {
  const funcs = Array.isArray(p.available_functions) && p.available_functions.length
    ? p.available_functions
    : ["view", "create", "edit", "delete"];
  return {
    page_id: p.page_id || p.page_key || p.id,
    id: p.page_key || p.id,
    page_key: p.page_key || p.id,
    label: p.page_name || p.label,
    page_name: p.page_name || p.label,
    icon: p.icon || "📄",
    file: p.file_location || p.file,
    file_location: p.file_location || p.file,
    group: p.menu_group || p.group || "General",
    menu_group: p.menu_group || p.group || "General",
    order: Number.isFinite(Number(p.sort_order ?? p.order)) ? Number(p.sort_order ?? p.order) : 10,
    sort_order: Number.isFinite(Number(p.sort_order ?? p.order)) ? Number(p.sort_order ?? p.order) : 10,
    available_functions: funcs,
    function_notes: p.function_notes || "",
    is_active: p.is_active !== false
  };
}

async function fetchAppPages(forceRefresh = false) {
  if (_cachedPages && !forceRefresh) return _cachedPages;
  try {
    const { data, error } = await supabaseClient
      .from("app_pages")
      .select("*")
      .order("sort_order", { ascending: true })
      .order("page_name", { ascending: true });
    if (!error && Array.isArray(data) && data.length > 0) {
      _cachedPages = data.map(normalizePageRow);
      window.MENU_ITEMS = _cachedPages;
      return _cachedPages;
    }
  } catch (e) {
    console.warn("[Portal] Falling back to built-in page registry:", e);
  }
  _cachedPages = FALLBACK_APP_PAGES.map(normalizePageRow);
  window.MENU_ITEMS = _cachedPages;
  return _cachedPages;
}

async function fetchUserPermissions(userId, forceRefresh = false) {
  if (!userId) return [];
  if (_cachedUserPerms[userId] && !forceRefresh) return _cachedUserPerms[userId];
  try {
    const { data, error } = await supabaseClient
      .from("user_page_permissions")
      .select("*, app_pages(page_key, file_location)")
      .eq("user_id", userId);
    if (!error && Array.isArray(data)) {
      _cachedUserPerms[userId] = data;
      return data;
    }
  } catch (e) {
    console.warn("[Portal] user_page_permissions table not ready yet:", e);
  }
  _cachedUserPerms[userId] = null; // null signals table not migrated yet
  return null;
}

function resolvePageFromRegistry(pageId, pages) {
  const cleanId = String(pageId || "").trim().toLowerCase();
  const pathName = (window.location.pathname || "").toLowerCase();
  const fileName = pathName.split("/").pop() || "";

  // 1. First try matching by current URL filename if inside pages/*.html
  if (fileName && fileName !== "index.html") {
    const byFile = pages.find(p => {
      const pFile = String(p.file_location || "").toLowerCase().split("/").pop();
      return pFile && pFile === fileName;
    });
    if (byFile) return byFile;
  }

  // 2. Match by page_key / id
  if (cleanId) {
    const byKey = pages.find(p => String(p.page_key || "").toLowerCase() === cleanId);
    if (byKey) return byKey;
  }
  return null;
}

function computeGranularAccess(profile, pageItem, userPermsList) {
  const noneResult = {
    canView: false,
    canCreate: false,
    canEdit: false,
    canDelete: false,
    level: "none",
    badgeText: "No Access"
  };
  if (!profile || profile.status !== STATUS.ACTIVE || !pageItem || pageItem.is_active === false) {
    return noneResult;
  }

  const funcs = pageItem.available_functions || ["view", "create", "edit", "delete"];
  const isAdmin = profile.role_name === "admin";

  // Admin always has full access to all active pages (and guarantees Admin can manage pages & permissions)
  if (isAdmin) {
    const canCreate = funcs.includes("create");
    const canEdit = funcs.includes("edit");
    const canDelete = funcs.includes("delete");
    return {
      canView: true,
      canCreate,
      canEdit,
      canDelete,
      level: "full",
      badgeText: "Full Access (Admin)"
    };
  }

  // Check user_page_permissions row from Supabase
  if (Array.isArray(userPermsList)) {
    const perm = userPermsList.find(row =>
      row.page_id === pageItem.page_id ||
      (row.app_pages && String(row.app_pages.page_key || "").toLowerCase() === String(pageItem.page_key || "").toLowerCase())
    );
    if (!perm || !perm.can_view) return noneResult;

    const canView = true;
    const canCreate = !!perm.can_create && funcs.includes("create");
    const canEdit = !!perm.can_edit && funcs.includes("edit");
    const canDelete = !!perm.can_delete && funcs.includes("delete");

    // Backward-compatible level string for existing module pages:
    // If user has Edit or Delete, set level = "full" so the page renders its row action column,
    // and our DOM permission enforcer selectively hides Edit or Delete if one of them is false.
    let level = "view";
    if (canEdit || canDelete) level = "full";
    else if (canCreate) level = "limited";

    const parts = ["View"];
    if (canCreate) parts.push("Enter Data");
    if (canEdit) parts.push("Edit");
    if (canDelete) parts.push("Delete");

    return {
      canView,
      canCreate,
      canEdit,
      canDelete,
      level,
      badgeText: parts.length === 4 ? "Full Access" : parts.join(" • ")
    };
  }

  // Fallback if user_page_permissions table hasn't been created yet
  if (pageItem.menu_group === "Administration") return noneResult;
  const isEditor = profile.role_name === "editor";
  return {
    canView: true,
    canCreate: funcs.includes("create"),
    canEdit: isEditor && funcs.includes("edit"),
    canDelete: isEditor && funcs.includes("delete"),
    level: isEditor ? "full" : "limited",
    badgeText: isEditor ? "Full Access" : "View • Enter Data"
  };
}

// Returns visible menu items for the signed-in user from Supabase
async function getVisibleMenuForUser(profile, forceRefresh = false) {
  if (!profile) return [];
  const [pages, perms] = await Promise.all([
    fetchAppPages(forceRefresh),
    fetchUserPermissions(profile.user_id, forceRefresh)
  ]);

  return pages
    .filter(p => p.is_active !== false)
    .map(p => {
      const access = computeGranularAccess(profile, p, perms);
      return { ...p, access };
    })
    .filter(p => p.access.canView)
    .sort((a, b) => (a.sort_order - b.sort_order) || a.page_name.localeCompare(b.page_name));
}

// Main entry point called at the top of every module page: `myAccess = await getMyAccess(PAGE_ID)`
async function getMyAccess(pageId) {
  const profile = await requireActiveUser();
  if (!profile) {
    return { profile: null, level: "none", canView: false, canCreate: false, canEdit: false, canDelete: false };
  }

  const [pages, perms] = await Promise.all([
    fetchAppPages(),
    fetchUserPermissions(profile.user_id)
  ]);

  let pageItem = resolvePageFromRegistry(pageId, pages);
  if (!pageItem && profile.role_name === "admin") {
    // Allow admin to preview even an unregistered page
    pageItem = normalizePageRow({
      page_key: pageId || "custom-page",
      page_name: document.title || pageId || "Page",
      file_location: window.location.pathname,
      available_functions: ["view", "create", "edit", "delete"],
      is_active: true
    });
  }

  const access = computeGranularAccess(profile, pageItem, perms);
  if (!access.canView) {
    document.body.innerHTML =
      '<div class="empty-state"><div class="icon">🔒</div>' +
      '<h3>Access Restricted</h3>' +
      '<p>You do not have permission to view this page. Contact an administrator to request access.</p></div>';
    return { profile: null, page: pageItem, ...access };
  }

  const fullAccessObj = {
    profile,
    page: pageItem,
    ...access,
    permissions: {
      view: access.canView,
      create: access.canCreate,
      edit: access.canEdit,
      delete: access.canDelete
    }
  };

  // Enforce permissions both at the Supabase client level and in the page UI
  installSupabasePermissionGuard(fullAccessObj);
  installDomPermissionEnforcer(fullAccessObj);

  return fullAccessObj;
}

/* ---------------------------------------------------------------------------
   AUTOMATIC SUPABASE CLIENT GUARD & DOM PERMISSION ENFORCER
   Ensures Only View, Enter Data, Edit, and Delete permissions work across ALL
   existing pages and any newly uploaded page without writing custom boilerplate.
--------------------------------------------------------------------------- */
let _guardInstalled = false;
function installSupabasePermissionGuard(access) {
  if (_guardInstalled || !window.supabaseClient) return;
  _guardInstalled = true;

  const origFrom = supabaseClient.from.bind(supabaseClient);
  supabaseClient.from = function(tableName) {
    const builder = origFrom(tableName);
    if (tableName === "audit_log") return builder; // always allow audit logging

    const blockPromise = (actionLabel) => {
      showToast(`Permission denied: You do not have '${actionLabel}' access on this page.`, "error");
      const errResp = Promise.resolve({
        data: null,
        error: { message: `Permission denied: '${actionLabel}' access is not enabled for your account on this page.` }
      });
      const proxy = new Proxy(errResp, {
        get(target, prop) {
          if (prop in target) return typeof target[prop] === "function" ? target[prop].bind(target) : target[prop];
          return () => proxy;
        }
      });
      return proxy;
    };

    const origInsert = builder.insert ? builder.insert.bind(builder) : null;
    const origUpsert = builder.upsert ? builder.upsert.bind(builder) : null;
    const origUpdate = builder.update ? builder.update.bind(builder) : null;
    const origDelete = builder.delete ? builder.delete.bind(builder) : null;

    if (origInsert) {
      builder.insert = function(...args) {
        if (!access.canCreate) return blockPromise("Enter Data");
        return origInsert(...args);
      };
    }
    if (origUpsert) {
      builder.upsert = function(...args) {
        if (!access.canCreate && !access.canEdit) return blockPromise("Enter Data / Edit");
        return origUpsert(...args);
      };
    }
    if (origUpdate) {
      builder.update = function(...args) {
        if (!access.canEdit) return blockPromise("Edit");
        return origUpdate(...args);
      };
    }
    if (origDelete) {
      builder.delete = function(...args) {
        if (!access.canDelete) return blockPromise("Delete");
        return origDelete(...args);
      };
    }
    return builder;
  };

  if (supabaseClient.rpc) {
    const origRpc = supabaseClient.rpc.bind(supabaseClient);
    supabaseClient.rpc = function(fnName, ...args) {
      const lower = String(fnName || "").toLowerCase();
      if ((lower.startsWith("submit_") || lower.startsWith("generate_")) && !access.canCreate) {
        showToast("Permission denied: You do not have 'Enter Data' access on this page.", "error");
        return Promise.resolve({ data: null, error: { message: "Enter Data permission required." } });
      }
      if (lower.startsWith("update_") && !access.canEdit) {
        showToast("Permission denied: You do not have 'Edit' access on this page.", "error");
        return Promise.resolve({ data: null, error: { message: "Edit permission required." } });
      }
      if (lower.startsWith("delete_") && !access.canDelete) {
        showToast("Permission denied: You do not have 'Delete' access on this page.", "error");
        return Promise.resolve({ data: null, error: { message: "Delete permission required." } });
      }
      return origRpc(fnName, ...args);
    };
  }
}

let _initialTabSwitched = false;
function installDomPermissionEnforcer(access) {
  const applyRules = () => {
    // 1. Render access badge in page-header so user knows their active permissions
    const header = document.querySelector(".page-header");
    if (header && !document.getElementById("pageAccessPill")) {
      const pill = document.createElement("span");
      pill.id = "pageAccessPill";
      const isViewOnly = access.canView && !access.canCreate && !access.canEdit && !access.canDelete;
      pill.className = "badge " + (isViewOnly ? "badge-neutral" : "badge-info");
      pill.style.cssText = "font-size:11px;padding:4px 10px;margin-left:auto;";
      pill.innerHTML = (isViewOnly ? "👁️ " : "🔐 ") + escapeHtml(access.badgeText || "View");
      const firstDiv = header.querySelector("div");
      if (firstDiv) firstDiv.appendChild(pill);
    }

    // 2. Declarative data-perm attributes (for new pages & templates)
    document.querySelectorAll("[data-perm]").forEach(el => {
      const req = el.getAttribute("data-perm");
      if (req === "create") el.style.display = access.canCreate ? "" : "none";
      if (req === "edit")   el.style.display = access.canEdit ? "" : "none";
      if (req === "delete") el.style.display = access.canDelete ? "" : "none";
    });

    // 3. Handle #addBtn across pages (e.g. notice-board.html, manage-roles.html, PAGE_TEMPLATE.html)
    const addBtn = document.getElementById("addBtn");
    if (addBtn) {
      if (!access.canCreate) {
        addBtn.style.display = "none";
      } else if (addBtn.style.display === "none") {
        addBtn.style.display = "inline-flex";
      }
    }

    // 4. If user does NOT have 'Enter Data' (canCreate === false)
    if (!access.canCreate) {
      const createSelectors = [
        "#addBtn", "#saveBtn", "#genRangeBtn",
        "#collectMonthlyBtn", "#collectAdmissionBtn", "#collectOtherBtn",
        "#aBulkUploadBtn", "#rBulkUploadBtn", "#rSubmitBtn",
        "#asSaveBtn", "#asDeptAddLink", "#saveRoleBtn",
        ".tab-btn[data-tab='New']", ".tab-btn[data-tab='Up']",
        ".adm-tab-btn[data-tab='admission']", ".adm-tab-btn[data-tab='readmission']", ".adm-tab-btn[data-tab='bulk']",
        ".staff-tab-btn[data-tab='add']", ".staff-tab-btn[data-tab='bulk']",
        ".fc-tab-btn[data-tab='bulk']"
      ];
      createSelectors.forEach(sel => {
        document.querySelectorAll(sel).forEach(el => { el.style.display = "none"; });
      });

      // Hide generic "+ Add / + New / Record / Collect" buttons inside page headers or cards
      document.querySelectorAll("button").forEach(btn => {
        const txt = (btn.textContent || "").trim();
        if (/^(\+\s*(Add|New|Record|Create|Post)|Save\s+Snapshot|Submit\s+Admission|Confirm\s+Upload)/i.test(txt)) {
          btn.style.display = "none";
        }
      });

      // Automatically switch multi-tab pages to their View/List tab once on load
      if (!_initialTabSwitched) {
        _initialTabSwitched = true;
        const viewTab =
          document.querySelector(".adm-tab-btn[data-tab='view']") ||
          document.querySelector(".tab-btn[data-tab='View']") ||
          document.querySelector(".staff-tab-btn[data-tab='list']");
        if (viewTab) setTimeout(() => viewTab.click(), 30);
      }
    }

    // 5. If user does NOT have 'Edit' (canEdit === false)
    if (!access.canEdit) {
      const editSelectors = [
        "[data-edit]",
        "button[title='Edit']",
        "button[onclick*='openEdit']",
        "button[onclick*='EditModal']",
        "button[onclick*='confirmDeactivate']",
        "button[onclick*='editRow']",
        "#bulkDeactBtn"
      ];
      editSelectors.forEach(sel => {
        document.querySelectorAll(sel).forEach(el => { el.style.display = "none"; });
      });
      document.querySelectorAll(".row-actions button, td button").forEach(btn => {
        const txt = (btn.textContent || "").trim();
        if (/^(Edit|✏️|Update|Deactivate|Reactivate|Manage)$/i.test(txt)) {
          btn.style.display = "none";
        }
      });
    }

    // 6. If user does NOT have 'Delete' (canDelete === false)
    if (!access.canDelete) {
      const delSelectors = [
        "[data-del]",
        "button[title='Delete']",
        "button[onclick*='Delete']",
        "button[onclick*='delRow']"
      ];
      delSelectors.forEach(sel => {
        document.querySelectorAll(sel).forEach(el => { el.style.display = "none"; });
      });
      document.querySelectorAll(".row-actions button, td button").forEach(btn => {
        const txt = (btn.textContent || "").trim();
        if (/^(Delete|🗑️|Remove)$/i.test(txt)) {
          btn.style.display = "none";
        }
      });
    }
  };

  applyRules();
  const obs = new MutationObserver(() => applyRules());
  obs.observe(document.body, { childList: true, subtree: true });
}

/* ---------------------------------------------------------------------------
   AUDIT LOGGING — call after every insert / update / delete a page performs.
--------------------------------------------------------------------------- */
async function logAudit(tableName, recordId, action, oldData, newData) {
  const session = await getSession();
  if (!session) return;
  const profile = await getCurrentProfile();
  await supabaseClient.from("audit_log").insert({
    table_name: tableName,
    record_id: String(recordId),
    action, // 'insert' | 'update' | 'delete'
    changed_by: session.user.id,
    changed_by_username: profile ? profile.username : null,
    old_data: oldData || null,
    new_data: newData || null
  });
}

async function withAuditStamp(record, { isNew }) {
  const session = await getSession();
  const uid = session ? session.user.id : null;
  const now = new Date().toISOString();
  if (isNew) {
    record.created_by = uid;
    record.updated_by = uid;
  } else {
    record.updated_by = uid;
    record.updated_at = now;
  }
  return record;
}

/* ---------------------------------------------------------------------------
   MODAL / POPUP SYSTEM
--------------------------------------------------------------------------- */
function openModal({ title, subtitle = "", bodyHtml = "", footHtml = "", wide = false, onOpen }) {
  closeModal();
  const root = document.getElementById("modalRoot");
  if (!root) { console.error("Missing <div id='modalRoot'></div> on this page."); return; }

  const overlay = document.createElement("div");
  overlay.className = "modal-overlay";
  overlay.id = "activeModalOverlay";
  overlay.innerHTML = `
    <div class="modal-box ${wide ? "modal-wide" : ""}" role="dialog" aria-modal="true" aria-labelledby="modalTitle">
      <div class="modal-head">
        <div>
          <h3 id="modalTitle">${title}</h3>
          ${subtitle ? `<div class="modal-sub">${subtitle}</div>` : ""}
        </div>
        <button class="modal-close" data-close aria-label="Close">✕</button>
      </div>
      <div class="modal-body">${bodyHtml}</div>
      ${footHtml ? `<div class="modal-foot">${footHtml}</div>` : ""}
    </div>`;
  root.appendChild(overlay);
  document.body.style.overflow = "hidden";

  overlay.addEventListener("click", (e) => {
    if (e.target === overlay || e.target.closest("[data-close]")) closeModal();
  });
  document.addEventListener("keydown", escCloseOnce);

  requestAnimationFrame(() => overlay.classList.add("open"));
  if (onOpen) onOpen(overlay.querySelector(".modal-box"));
}

function escCloseOnce(e) {
  if (e.key === "Escape") closeModal();
}

function closeModal() {
  const overlay = document.getElementById("activeModalOverlay");
  if (!overlay) return;
  overlay.classList.remove("open");
  document.body.style.overflow = "";
  document.removeEventListener("keydown", escCloseOnce);
  setTimeout(() => overlay.remove(), 220);
}

/* ---------------------------------------------------------------------------
   TOASTS & UTILITIES
--------------------------------------------------------------------------- */
function showToast(message, type = "default") {
  const root = document.getElementById("toastRoot");
  if (!root) { console.log("[toast]", message); return; }
  const el = document.createElement("div");
  el.className = `toast ${type}`;
  el.textContent = message;
  root.appendChild(el);
  setTimeout(() => {
    el.style.transition = "opacity .25s ease";
    el.style.opacity = "0";
    setTimeout(() => el.remove(), 260);
  }, 3200);
}

function formatDateTime(iso) {
  if (!iso) return "—";
  const d = new Date(iso);
  return d.toLocaleString(undefined, { day: "2-digit", month: "short", year: "numeric", hour: "2-digit", minute: "2-digit" });
}

function escapeHtml(str) {
  return String(str ?? "").replace(/[&<>"']/g, s => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" }[s]));
}

function statusBadge(status) {
  const map = {
    active: '<span class="badge badge-success">Active</span>',
    pending: '<span class="badge badge-warning">Pending</span>',
    deactivated: '<span class="badge badge-danger">Deactivated</span>'
  };
  return map[status] || `<span class="badge badge-neutral">${escapeHtml(status)}</span>`;
}
