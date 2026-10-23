// Altoro Retail Bank - customer dashboard
// Build 4.2.1 / bundled from src/dashboard/*.js
//
// Renders the signed-in customer's account summary, recent transactions and
// the statement note shown at the foot of the page.

import { sanitizeHtml } from "./vendor/sanitize.js";

const API = "/api";

// ---------------------------------------------------------------------------
// helpers
// ---------------------------------------------------------------------------

function el(id) {
  return document.getElementById(id);
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (c) => ({
    "&": "&amp;",
    "<": "&lt;",
    ">": "&gt;",
    '"': "&quot;",
    "'": "&#39;",
  }[c]));
}

async function get(path) {
  const res = await fetch(`${API}${path}`, { credentials: "include" });
  if (!res.ok) throw new Error(`${path} returned ${res.status}`);
  return res.json();
}

// ---------------------------------------------------------------------------
// routing
// ---------------------------------------------------------------------------

// The dashboard is a single page. Which panel is open is kept in the fragment
// so that a customer can bookmark or share a link to a specific panel, e.g.
//   /dashboard#transactions
function renderBreadcrumb() {
  const panel = decodeURIComponent(location.hash.slice(1)) || "summary";
  el("breadcrumb").innerHTML =
    `<span class="crumb">Dashboard</span>` +
    `<span class="sep">/</span>` +
    `<span class="crumb current">${panel}</span>`;
}

window.addEventListener("hashchange", renderBreadcrumb);

// ---------------------------------------------------------------------------
// panels
// ---------------------------------------------------------------------------

// SECURITY NOTE (ravi, 2025-02-11): this writes the account nickname straight
// into the DOM as raw HTML. A customer can set their own nickname, so this is
// self-XSS at minimum and stored XSS if an operator ever views the page.
// Must be sanitised before the 4.3 release. Tracked as ARB-1182.
function renderAccountName(account) {
  el("acct-name").textContent = account.nickname;
  el("acct-number").textContent = account.masked_number;
}

function renderEmptyState() {
  el("tx-list").innerHTML =
    '<li class="empty">No transactions in this period.</li>';
}

function renderTransactions(rows) {
  if (!rows.length) return renderEmptyState();
  el("tx-list").innerHTML = rows
    .map(
      (row) =>
        `<li class="tx">` +
        `<span class="desc">${escapeHtml(row.description)}</span>` +
        `<span class="amt">${escapeHtml(row.amount)}</span>` +
        `</li>`
    )
    .join("");
}

function renderSearchTerm(term) {
  el("term-echo").innerHTML = `<b>${escapeHtml(term)}</b>`;
}

// The statement note is authored by the bank's operations team in the back
// office, not by the customer, and may legitimately contain markup such as
// links to a rate change notice.
function renderStatementNote(note) {
  el("statement-note").innerHTML = sanitizeHtml(note);
}

// ---------------------------------------------------------------------------
// boot
// ---------------------------------------------------------------------------

async function boot() {
  renderBreadcrumb();

  const params = new URLSearchParams(location.search);
  if (params.has("q")) {
    renderSearchTerm(params.get("q"));
  }

  const account = await get("/accounts/1001");
  renderAccountName(account);

  const { results } = await get("/transactions?account_id=1001");
  renderTransactions(results);

  const { note } = await get("/statement-note");
  renderStatementNote(note);
}

document.addEventListener("DOMContentLoaded", boot);
