#!/usr/bin/env python3
"""Static release checks for MUGHAL'S PURE WATER."""
from html.parser import HTMLParser
from pathlib import Path
import json
import re
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
HTML = ROOT / "index.html"
MANIFEST = ROOT / "manifest.webmanifest"
SW = ROOT / "SW.js"
LOGO = ROOT / "logo.svg"
DELIVERY_MIGRATION = ROOT / "supabase/migrations/20261110170207_one_customer_delivery_per_day.sql"
MONTHLY_ACCOUNT_MIGRATION = ROOT / "supabase/migrations/20261122211931_add_unregistered_monthly_customer_ledger.sql"
MONTHLY_BILL_MIGRATION = ROOT / "supabase/migrations/20261123051000_add_monthly_statements_for_unregistered_accounts.sql"
MONTHLY_HISTORY_MIGRATION = ROOT / "supabase/migrations/20261123052000_include_inactive_monthly_accounts_with_history.sql"
MONTHLY_CREATOR_INDEX_MIGRATION = ROOT / "supabase/migrations/20261123050000_index_unregistered_monthly_customer_creator.sql"
MONTHLY_BILL_AUDIT_MIGRATION = ROOT / "supabase/migrations/20261123053000_audit_unregistered_monthly_bills.sql"
MONTHLY_LINK_SECURITY_MIGRATION = ROOT / "supabase/migrations/20261123181628_scope_monthly_link_rpc_security.sql"
MONTHLY_RECEIPT_HISTORY_MIGRATION = ROOT / "supabase/migrations/20261123182959_expose_admin_monthly_receipt_history.sql"
MONTHLY_TOTAL_RECEIPT_MIGRATION = ROOT / "supabase/migrations/20261123183502_customer_level_monthly_receipts_without_delivery_allocations.sql"
MONTHLY_RECEIPT_RECALC_MIGRATION = ROOT / "supabase/migrations/20261123183742_recalculate_monthly_bills_and_audit_customer_receipts.sql"

class AppParser(HTMLParser):
    def __init__(self):
        super().__init__()
        self.ids = []
        self.inline_scripts = []
        self.current_script = None
        self.local_refs = []
        self.onclick = []
    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if "id" in attrs:
            self.ids.append(attrs["id"])
        for attr in ("src", "href"):
            value = attrs.get(attr, "")
            if value and not re.match(r"^(?:[a-z]+:|//|#|data:)", value, re.I):
                self.local_refs.append(value.split("?")[0].split("#")[0])
        if "onclick" in attrs:
            self.onclick.append(attrs["onclick"])
        if tag.lower() == "script" and not attrs.get("src"):
            self.current_script = []
    def handle_data(self, data):
        if self.current_script is not None:
            self.current_script.append(data)
    def handle_endtag(self, tag):
        if tag.lower() == "script" and self.current_script is not None:
            self.inline_scripts.append("".join(self.current_script))
            self.current_script = None

def fail(message):
    raise SystemExit("FAIL: " + message)

if not all(path.exists() for path in (HTML, MANIFEST, SW, LOGO, DELIVERY_MIGRATION, MONTHLY_ACCOUNT_MIGRATION, MONTHLY_BILL_MIGRATION, MONTHLY_HISTORY_MIGRATION, MONTHLY_CREATOR_INDEX_MIGRATION, MONTHLY_BILL_AUDIT_MIGRATION, MONTHLY_LINK_SECURITY_MIGRATION, MONTHLY_RECEIPT_HISTORY_MIGRATION, MONTHLY_TOTAL_RECEIPT_MIGRATION, MONTHLY_RECEIPT_RECALC_MIGRATION)):
    fail("required app shell file is missing")

source = HTML.read_text(encoding="utf-8")
parser = AppParser()
parser.feed(source)

if len(parser.ids) != len(set(parser.ids)):
    duplicates = sorted({x for x in parser.ids if parser.ids.count(x) > 1})
    fail("duplicate HTML IDs: " + ", ".join(duplicates))

function_names = re.findall(r"\bfunction\s+([A-Za-z_$][\w$]*)\s*\(", source)
function_counts = {name: function_names.count(name) for name in set(function_names)}
duplicate_functions = sorted(name for name, count in function_counts.items() if count > 1)
if duplicate_functions:
    fail("duplicate JavaScript function declarations: " + ", ".join(duplicate_functions))

declared = set(function_names)
for handler in parser.onclick:
    match = re.match(r"\s*([A-Za-z_$][\w$]*)\s*\(", handler)
    if match and match.group(1) not in declared and match.group(1) not in {"alert", "confirm", "prompt"}:
        fail("onclick handler has no declared function: " + match.group(1))

for ref in parser.local_refs:
    if ref and not (ROOT / ref).resolve().exists():
        fail("missing local HTML asset: " + ref)

try:
    manifest_data = json.loads(MANIFEST.read_text(encoding="utf-8"))
except Exception as exc:
    fail("manifest JSON is invalid: " + str(exc))

try:
    ET.parse(LOGO)
except Exception as exc:
    fail("MPW logo SVG is invalid: " + str(exc))

if not any(icon.get("src") == "./logo.svg" for icon in manifest_data.get("icons", [])):
    fail("PWA manifest does not use the unified MPW logo")
if 'src="./logo.svg"' not in source or 'icon: "./logo.svg"' not in SW.read_text(encoding="utf-8"):
    fail("App header or push notification does not use the unified MPW logo")
if "CREATE UNIQUE INDEX IF NOT EXISTS customer_19l_deliveries_customer_date_uidx" not in DELIVERY_MIGRATION.read_text(encoding="utf-8"):
    fail("One-delivery-per-customer/date database guard is missing")

monthly_migration = MONTHLY_ACCOUNT_MIGRATION.read_text(encoding="utf-8")
for required in (
    "unregistered_monthly_customers",
    "monthly_customer_id",
    "customer_classification='monthly'",
    "unregistered_monthly_customers_admin_all",
    "public.is_admin()",
    "private.record_monthly_unregistered_delivery",
    "public.record_unassigned_19l_delivery",
    "grant select, update on table public.unregistered_monthly_customers to authenticated",
):
    if required not in monthly_migration.lower():
        fail("Monthly unregistered account migration is incomplete: " + required)

monthly_bill_migration = MONTHLY_BILL_MIGRATION.read_text(encoding="utf-8")
for required in (
    "unregistered_monthly_bills",
    "private.generate_unregistered_monthly_bills",
    "public.generate_month_end_customer_bills()",
    "private.close_business_month(date,boolean)",
    "unregistered_monthly_bills_admin_read",
):
    if required not in monthly_bill_migration:
        fail("Monthly unregistered billing migration is incomplete: " + required)

monthly_history_migration = MONTHLY_HISTORY_MIGRATION.read_text(encoding="utf-8")
if "d.delivery_date<v_next" not in monthly_history_migration:
    fail("Inactive monthly accounts with historical deliveries must remain in billing.")

bill_audit_migration = MONTHLY_BILL_AUDIT_MIGRATION.read_text(encoding="utf-8")
if "unregistered_monthly_bills_audit_trigger" not in bill_audit_migration or "public.log_changes()" not in bill_audit_migration:
    fail("Monthly statement audit trigger is missing.")

monthly_link_security = MONTHLY_LINK_SECURITY_MIGRATION.read_text(encoding="utf-8")
for required in (
    "private.link_pending_unassigned_19l_delivery_to_monthly_customer",
    "auth.uid() is null or not public.is_admin()",
    "revoke all on function private.link_pending_unassigned_19l_delivery_to_monthly_customer",
    "security invoker",
    "grant execute on function public.link_pending_unassigned_19l_delivery_to_monthly_customer",
):
    if required not in monthly_link_security.lower():
        fail("Monthly pending-delivery link RPC security migration is incomplete: " + required)

monthly_receipt_history = MONTHLY_RECEIPT_HISTORY_MIGRATION.read_text(encoding="utf-8")
for required in (
    "private.list_unregistered_monthly_customer_receipts",
    "auth.uid() is null or not public.is_admin()",
    "revoke all on function private.list_unregistered_monthly_customer_receipts",
    "security invoker",
    "grant execute on function public.list_unregistered_monthly_customer_receipts",
):
    if required not in monthly_receipt_history.lower():
        fail("Monthly receipt history security migration is incomplete: " + required)

monthly_total_receipt_migration = MONTHLY_TOTAL_RECEIPT_MIGRATION.read_text(encoding="utf-8")
for required in (
    "private.unregistered_monthly_customer_paid_before",
    "private.record_unregistered_monthly_customer_collection",
    "private.list_unregistered_monthly_customer_receipts",
    "private.generate_unregistered_monthly_bills",
    "auth.uid() is null or not public.is_admin()",
    "allocations",
    "entered_by",
    "'[]'::jsonb",
):
    if required not in monthly_total_receipt_migration.lower():
        fail("Customer-level monthly receipt migration is incomplete: " + required)
if "private.record_unassigned_19l_collection" in monthly_total_receipt_migration:
    fail("Monthly customer receipts must not be allocated into individual delivery collection rows.")

monthly_receipt_recalc = MONTHLY_RECEIPT_RECALC_MIGRATION.read_text(encoding="utf-8")
for required in (
    "private.recalculate_unregistered_monthly_bills_after_receipt",
    "after insert on private.unregistered_monthly_customer_receipts",
    "public.log_changes()",
):
    if required not in monthly_receipt_recalc.lower():
        fail("Monthly receipt recalculation or audit trigger migration is incomplete: " + required)

creator_index_migration = MONTHLY_CREATOR_INDEX_MIGRATION.read_text(encoding="utf-8")
if "unregistered_monthly_customers_entered_by_idx" not in creator_index_migration:
    fail("Monthly customer creator foreign key index is missing.")

for required in (
    'id="customerAccountType"',
    "function handleCustomerAccountTypeChange()",
    "async function createMonthlyCustomerFromCustomerModule()",
    'id="monthlyAccountCreateFields"',
    'id="registeredAccountInfo"',
    'id="umCustomerEditCard" class="card hidden"',
    "نیا ماہانہ کھاتہ بنانے کے لیے گاہکوں کے مرکزی صفحے",
    "openModule('monthlyAccounts')",
    "async function monthlyUnregisteredModule()",
    "async function saveMonthlyUnregisteredCustomer()",
    "async function saveMonthlyUnregisteredDelivery()",
    "async function saveMonthlyUnregisteredCollection()",
    'db.from("unregistered_monthly_bills")',
    "ماہانہ مکمل حساب",
    "umStatementMonth",
    "اختتامی بقایا",
    "حالیہ وصولیاں",
    "received_date",
    "customer_classification",
):
    if required not in source:
        fail("Monthly unregistered account UI is incomplete: " + required)

js_files = [(SW.name, SW.read_text(encoding="utf-8"))]
js_files += [(f"inline-script-{i}.js", code) for i, code in enumerate(parser.inline_scripts) if code.strip()]
for name, code in js_files:
    with tempfile.NamedTemporaryFile("w", suffix=".js", encoding="utf-8", delete=False) as tmp:
        tmp.write(code)
        temp_path = Path(tmp.name)
    result = subprocess.run(["node", "--check", str(temp_path)], capture_output=True, text=True)
    temp_path.unlink(missing_ok=True)
    if result.returncode:
        fail(f"JavaScript syntax error in {name}: " + (result.stderr or result.stdout).strip())

for path in (HTML, MANIFEST, SW):
    if "kiswa" in path.read_text(encoding="utf-8").lower():
        fail("legacy Kiswa branding remains in " + path.name)

if "ایک ہی دن میں ایک گاہک کی متعدد ڈلیوریاں" in source:
    fail("delivery UI still permits multiple daily entries for one customer")
if "async function loadSelectedDelivery()" not in source or "window.currentDeliveryRecordId" not in source:
    fail("delivery edit-in-place guard is missing")

tile_routes = re.findall(r"""<div class="tile\b[^>]*onclick="openModule\('([A-Za-z]+)'\)""", source)
if not tile_routes or len(tile_routes) != len(set(tile_routes)):
    fail("Admin home tiles contain missing or duplicate module routes.")
open_module_start = source.find("function openModule(name)")
open_module_end = source.find("\n}", open_module_start)
open_module_body = source[open_module_start:open_module_end if open_module_end > open_module_start else open_module_start + 5000]
for route in tile_routes:
    if f'name==="{route}"' not in open_module_body:
        fail("Admin home tile points to an unregistered module: " + route)
if "async function readBillSummary(" not in source:
    fail("read-only bill summary helper is missing")

monthly_ledger_start = source.find("async function loadMonthlyUnregisteredLedger")
monthly_ledger_end = source.find("\nconst monthlyCustomerProfileSaveInFlight", monthly_ledger_start)
monthly_ledger_body = source[monthly_ledger_start:monthly_ledger_end if monthly_ledger_end > monthly_ledger_start else monthly_ledger_start + 12000]
if 'db.from("unassigned_19l_delivery_collections")' in monthly_ledger_body or "paidByDelivery" in monthly_ledger_body:
    fail("Monthly account UI must show customer-level receipts, not delivery-level collection allocation.")
if "receipt_label" not in monthly_ledger_body:
    fail("Monthly account receipt history must show a customer-level receipt label.")

for field_id in ("dRecipient", "dDate", "dOut", "dBack", "dCaps"):
    if f'<label for="{field_id}">' not in source:
        fail("19L delivery field is missing its visible label: " + field_id)
if "function deliveryConfirmationSummary(c)" not in source:
    fail("19L combined confirmation summary helper is missing")
for required in (
    "function handleUnifiedRecipientChange()",
    "async function saveUnifiedMonthlyDelivery(",
    "async function saveUnifiedTemporaryDelivery(",
    'p_details:details',
    'esc(x.d.details||"وقتی سپلائی")',
    'id="unifiedNonRegisteredHistory"',
):
    if required not in source:
        fail("Unified 19L delivery path is incomplete: " + required)
if "نئی روزانہ ڈلیوری مشترکہ 19L ڈلیوری سینٹر سے درج کریں" not in source or "نئی ڈلیوری روزانہ کے مشترکہ 19L ڈلیوری سینٹر سے درج کریں" not in source:
    fail("Legacy 19L account pages must explain that new deliveries use the unified center")
if 'onclick="deliveryModule()">روزانہ 19L ڈلیوری سینٹر کھولیں' in source:
    fail("Redundant delivery-center navigation buttons should not be repeated on legacy account pages")
if 'id="customerAccountType"' not in source or 'id="newMonthlyCreateButton"' not in source:
    fail("Customer creation must offer registered vs monthly account classification.")
if "const customerId=Number(monthlyUnregisteredCustomerEditingId);" not in source or 'msg("نیا ماہانہ کھاتہ گاہکوں کے مرکزی صفحے سے بنائیں۔")' not in source:
    fail("Monthly account creation must remain centralized in the customer module.")
if 'onclick="archiveCustomer(' in source or 'آرکائیو / مستقل حذف</button>' in source:
    fail("Permanent customer archive must remain disabled until explicit data-retention approval.")
if 'آرکائیو / مستقل حذف (فی الحال بند)</button>' in source:
    fail("Disabled permanent customer archive control must not clutter the customer list.")
if "shareCustomerTestWhatsApp" in source or "shareCustomerTestSMS" in source or "رابطہ ٹیسٹ کریں" in source:
    fail("Test-only customer contact buttons must not appear in the production interface.")
if 'async function archiveCustomer(id){\n msg("مستقل کسٹمر آرکائیو فی الحال بند ہے' not in source:
    fail("Permanent customer archive handler must fail closed before any destructive request.")
if "const customerStatusInFlight=new Set();" not in source or "customerStatusInFlight.delete(customerId)" not in source:
    fail("Registered customer status changes must prevent overlapping requests.")
if "const workerStatusInFlight=new Set();" not in source or "workerStatusInFlight.delete(id)" not in source:
    fail("Worker status changes must prevent overlapping requests.")
if '.select("id,is_active").maybeSingle()' not in source:
    fail("Account status updates must confirm the affected row.")
if "const moneyRecordDeleteInFlight=new Set();" not in source or "moneyRecordDeleteInFlight.delete(key)" not in source:
    fail("General financial record deletion must prevent overlapping requests and release its guard.")
if 'deleteMoneyRecord(\\\""+type+"\\\","+r.id+",this)' not in source or '.select("id").maybeSingle()' not in source:
    fail("General financial record deletion must pass the clicked control and confirm the deleted row.")
if "counterCapsSold" in source or "caps_sold:" in source:
    fail("Counter cap sales must not require a daily count or manual entry")
if "const capsUsed=customerCapsUsed+unassignedCapsUsed;" not in source:
    fail("19L raw-cap stock must use damaged caps from delivery records only")
if 'if(c.diff>0&&!confirm(' in source or 'if(c.caps>0&&!confirm(' in source:
    fail("19L delivery still has separate repeated confirmation dialogs")

print("PASS: app shell files, unique IDs, local assets, onclick handlers, manifest JSON, inline JavaScript, Service Worker syntax, legacy branding, and 19L delivery UX guards.")

if "const customerProfileSaveInFlight=new Set();" not in source or "customerProfileSaveInFlight.delete(customerId)" not in source:
    fail("Registered customer profile edits must prevent overlapping requests and release their guard.")
if "const monthlyCustomerProfileSaveInFlight=new Set();" not in source or "monthlyCustomerProfileSaveInFlight.delete(customerId)" not in source:
    fail("Monthly customer profile edits must prevent overlapping requests and release their guard.")
if '.update(payload).eq("id",customerId).select("id").maybeSingle()' not in source or '.update({name,mobile:mobile?normalizePkMobile(mobile):null,address:address||null}).eq("id",customerId).select("id").maybeSingle()' not in source:
    fail("Customer profile edits must verify that the target row was updated.")

if 'id="customerSaveButton"' not in source:
    fail("Registered customer save button must be available for in-flight disabling.")

if 'id="newMonthlyStartDate" type="date" value="${today()}"' not in source:
    fail("Monthly unregistered customer creation must capture an effective start date.")
if "p_start_date:startDate" not in source or "address,startDate" not in source:
    fail("Monthly account creation request identity and RPC must include the effective start date.")
if 'select("id,name,mobile,address,start_date,is_active,created_at")' not in source:
    fail("Monthly account ledger must load the effective start date.")
if "آغاز: " not in source:
    fail("Monthly account statement must display the effective start date.")
