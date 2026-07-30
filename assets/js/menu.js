/* ============================================================================
   MENU.JS — the single source of truth for the hamburger menu.
   Add a new object here for every new page . The main frame reads this file
   to build the menu AND to enforce which roles may open which page.
   See HOW_TO_ADD_PAGE.md for the full explanation of every field.
   ============================================================================ */

const MENU_ITEMS = [
  {
    id: "dashboard",                 // unique, matches the page's own pageId
    label: "Dashboard",
    icon: "🏠",
    file: "pages/dashboard.html",    // path loaded into the iframe
    group: "General",                // used to group items in the menu
    fullAccess: ["admin", "editor", "viewer"],   // can edit/delete
    limitedAccess: [],                            // can read/enter only
    order: 1
  },
     {
    id: "dashboard-Report",                 // unique, matches the page's own pageId
    label: "Dashboard Report",
    icon: "🏠",
    file: "pages/dash-report.html",    // path loaded into the iframe
    group: "General",                // used to group items in the menu
    fullAccess: ["admin", "editor", "viewer"],   // can edit/delete
    limitedAccess: [],                            // can read/enter only
    order: 1
  },
   
{
  id: "voucher-setup",
  label: "Voucher Setup",
  icon: "🗂️",
  file: "pages/voucher-setup.html",
  group: "Accounts",
  fullAccess: ["admin"],
  limitedAccess: ["editor", "viewer"],
  order: 10
},
   {
  id: "payment",
  label: "Payment",
  icon: "💳",
  file: "pages/payment.html",
  group: "Accounts",
  fullAccess: ["admin"],
  limitedAccess: ["editor", "viewer"],
  order: 8
   },
/*{
  id: "cash-voucher",
  label: "Cash Voucher",
  icon: "💵",
  file: "pages/cash-voucher.html",
  group: "Accounts",
  fullAccess: ["admin"],
  limitedAccess: ["editor", "viewer"],
  order: 11
},*/
{
  id: "creditor-voucher",
  label: "Creditor Voucher",
  icon: "🧾",
  file: "pages/creditor-voucher.html",
  group: "Accounts",
  fullAccess: ["admin"],
  limitedAccess: ["editor", "viewer"],
  order: 12
},
   {
  id: "admission",
  label: "Admission",
  icon: "🎓",
  file: "pages/admission.html",
  group: "Academics",
  fullAccess: ["admin", "editor"],   // can add/edit/delete/deactivate
  limitedAccess: ["viewer"],         // can add (admission/readmission) only
  order: 3
   },
   
{
  id: "old-dues",
  label: "Old Dues",
  icon: "💰",
  file: "pages/old-dues.html",
  group: "Fees",
  fullAccess: ["admin"],
  limitedAccess: ["accountant", "teacher"],
  order: 20
},
   {
  id: "fee-collection",
  label: "Fee Collection",
  icon: "💰",
  file: "pages/fee-collection.html",
  group: "Accounts",
  fullAccess: ["admin", "editor"],   // can correct/delete receipts
  limitedAccess: ["viewer"],         // can collect fees, cannot correct/delete
  order: 4
},
{
  id: "fee-due-report",
  label: "Fee Due & Reports",
  icon: "📊",
  file: "pages/fee-due-report.html",
  group: "Accounts",
  fullAccess: ["admin", "editor"],
  limitedAccess: ["viewer"],         // read-only reports either way
  order: 5
},
   {
  id: "cash-flow",
  label: "Cash Flow",
  icon: "💵",
  file: "pages/cash-flow.html",
  group: "Accounts",
  fullAccess: ["admin"],            // can add/edit/delete everything
  limitedAccess: ["editor", "viewer"], // can add records, cannot edit/delete
  order: 10                          // adjust to control menu position
   },
   {
  id: "staff",
  label: "Staff",
  icon: "🧑‍🏫",
  file: "pages/staff.html",
  group: "Staff & Salary",
  fullAccess: ["admin"],
  limitedAccess: ["accountant", "manager"],
  order: 10
},
/*{
  id: "salary-payment",
  label: "Salary Payment",
  icon: "💰",
  file: "pages/salary-payment.html",
  group: "Staff & Salary",
  fullAccess: ["admin"],
  limitedAccess: ["accountant", "manager"],
  order: 11
},*/
  {
    id: "manage-users",
    label: "Approve Users",
    icon: "✅",
    file: "pages/manage-users.html",
    group: "Administration",
    fullAccess: ["admin"],
    limitedAccess: [],
    order: 10
  },
  {
    id: "manage-roles",
    label: "Manage Roles",
    icon: "🏷️",
    file: "pages/manage-roles.html",
    group: "Administration",
    fullAccess: ["admin"],
    limitedAccess: [],
    order: 11
  },
  {
    id: "audit-log",
    label: "Audit Log",
    icon: "🕒",
    file: "pages/audit-log.html",
    group: "Administration",
    fullAccess: ["admin"],
    limitedAccess: [],
    order: 12
  }
];

// Returns only the items a given role name is allowed to see at all
// (full or limited access), sorted for display, grouped by `group`.
function visibleMenuItemsForRole(roleName) {
  return MENU_ITEMS
    .filter(m => m.fullAccess.includes(roleName) || m.limitedAccess.includes(roleName))
    .sort((a, b) => a.order - b.order);
}
