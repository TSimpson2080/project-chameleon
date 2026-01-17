# Project Chameleon (v1) — SPEC.md

Version: 0.2  
Last updated: 2026-01-16  
Project codename: **Project Chameleon**  
App Store name: **Chameleon: Change Order Log**  
Subtitle: **Change orders, simplified**

This document is the single source of truth for v1 behavior, data model, screens, business rules, and quality gates.
Anything not explicitly in scope is out of scope for v1 unless a change is approved and reflected here.

---

## 1) Product intent

### 1.1 One-sentence intent
An offline-first iPhone app that lets contractors create, get signed approval for, and share professional change orders quickly, with enterprise-grade integrity (immutable signed records + explicit revisions).

### 1.2 Target buyer (v1 ICP)
Small residential remodelers and design-build/custom home builder GCs (1–20 people) who work directly with homeowners and need fast on-site approvals.

### 1.3 North-star workflow (must be flawless)
Job → New Change Order → Add cost + schedule impact → Add photos → Capture client signature → Produce **Signed PDF** → Share → Track status.

### 1.4 v1 definition of “enterprise-level”
Not “more features.” It means:
- offline reliability
- deterministic document output
- immutable signed artifacts
- auditability (timestamps, revision chain)
- predictable performance
- privacy-safe logging

---

## 2) v1 scope

### 2.1 In scope
**Core**
- Jobs (project container with per-job numbering sequence)
- Change orders (draft/edit, attachments, status)
- Photos attached to change orders
- Signature capture (client required; contractor optional)
- PDF generation (Draft and Signed)
- Change order integrity:
  - Locked after client signature
  - Revisions required for any post-sign change
  - SHA-256 hash stored for signed PDFs
- Status tracking (Draft, Sent, Approved, Rejected, Cancelled)
- Settings: company profile + defaults (tax rate, hourly rate, terms)
- Paywall: free cap + lifetime unlock via StoreKit 2
- Basic analytics events (privacy-safe, no ad tracking) + crash reporting integration hooks

**Costing modes**
- Fixed Price
- Time & Materials (simplified)
- Estimate/Range (low–high)

### 2.2 Out of scope (explicitly)
- iCloud/CloudKit sync
- Multi-user collaboration, roles, permissions
- Web portal
- Integrations (QuickBooks, Buildertrend, Procore, etc.)
- Complex tax jurisdictions (simple percent only)
- Advanced photo markup (v1.1+)
- Digital certificate-backed signatures (v2+)

---

## 3) Non-negotiable principles

1. **Offline-first**: all core flows work with Airplane Mode on.
2. **Immutable signed records**: after client signs, that record is read-only permanently.
3. **Signed PDF is the source of truth**: locked CO shares the stored PDF artifact, not a regenerated one.
4. **Explicit revision chain**: changes post-sign must create a revision with its own signed PDF and hash.
5. **Deterministic PDFs**: layout and content rules are stable and repeatable.
6. **Minimal configuration**: app works with defaults; customization optional, not required.
7. **Privacy-first**: avoid collecting data; avoid logging customer PII.

---

## 4) Platform + tech decisions (v1)

### 4.1 Platform
- iPhone-first (iPad compatibility later; should not break on iPad, but not optimized)
- Minimum OS: **iOS 17+** (enables SwiftData cleanly)
- Language: Swift
- UI: SwiftUI

### 4.2 Storage and attachments
- Structured data: **SwiftData**
- Attachments (photos/PDFs/signatures): stored as files in app sandbox
  - do not store large binary blobs in SwiftData
  - store file paths + metadata
- Thumbnails stored separately for list performance

### 4.3 Purchases
- StoreKit 2
- Products:
  - lifetime unlock (non-consumable)
  - optional future: subscription for iCloud sync or team features (not in v1)

### 4.4 Hashing
- Compute SHA-256 for Signed PDF bytes
- Store as lowercase hex string
- Hash computed at lock time only

---

## 5) Terminology

- **Job**: project container that owns CO numbering.
- **CO / Change Order**: a change request document tied to a job.
- **Draft**: editable CO (not locked).
- **Locked**: CO after client signature (immutable).
- **Signed PDF**: final stored PDF generated at lock time.
- **Revision**: editable new CO derived from a locked CO, sharing the same base number with incremented revision number.

---

## 6) Data model (logical + constraints)

### 6.1 CompanyProfile (singleton)
Purpose: provide optional header/terms and defaults.

Fields
- companyName: String?
- phone: String?
- email: String?
- address: String?
- defaultTerms: String?
- defaultTaxRate: Decimal?  (0.0–1.0, e.g., 0.07)
- defaultHourlyRate: Decimal? (currency)

Constraints
- all fields optional
- changes affect only new draft PDFs and new CO defaults
- historical Signed PDFs must not change

---

### 6.2 Job
Fields
- id: UUID
- clientName: String (required)
- projectName: String?
- address: String?
- contactPhone: String?
- contactEmail: String?
- defaultTaxRate: Decimal?
- defaultHourlyRate: Decimal?
- termsOverride: String?
- nextChangeOrderNumber: Int (required; starts at 1)
- createdAt: Date
- updatedAt: Date

Constraints
- clientName non-empty
- nextChangeOrderNumber must be >= 1

---

### 6.3 ChangeOrder
Fields
- id: UUID
- jobId: UUID (relationship)
- number: Int (required; assigned from job.nextChangeOrderNumber)
- revisionNumber: Int (required; 0 for original)
- revisionOfId: UUID? (null for original)
- title: String (required; short)
- description: String (required; long)
- changeType: Enum(Add, Modify, Remove, Repair) (required; default Add)
- category: Enum(Labor, Materials, Equipment, Subcontractor, Permit, Disposal, Design, Other) (required; default Other)
- reason: Enum(ClientRequest, UnforeseenCondition, CodeRequirement, DesignChange, ScopeClarification, Repair, AccessIssue, WeatherDelay, Other) (required; default ClientRequest)

Pricing
- pricingMode: Enum(Fixed, TimeMaterials, EstimateRange) (required; default Fixed)
- fixedSubtotal: Decimal? (for Fixed, optional if using line items)
- tmLaborHours: Decimal? (for TimeMaterials)
- tmLaborRate: Decimal? (for TimeMaterials; defaults from job/company)
- tmMaterialsCost: Decimal? (for TimeMaterials)
- estimateLow: Decimal? (for EstimateRange)
- estimateHigh: Decimal? (for EstimateRange)
- subtotal: Decimal (stored computed)
- taxRate: Decimal (0.0–1.0)
- total: Decimal (stored computed)

Schedule
- scheduleDays: Int (>=0; default 0)

Status + audit
- status: Enum(Draft, Sent, Approved, Rejected, Cancelled) (default Draft)
- createdAt: Date
- updatedAt: Date
- sentAt: Date?
- approvedAt: Date?
- rejectedAt: Date?
- cancelledAt: Date?
- lockedAt: Date?
- deviceTimeZoneId: String (required; set at creation)

Signatures (captured at lock)
- clientSignatureName: String?
- clientSignatureSignedAt: Date?
- contractorSignatureName: String? (optional v1)
- contractorSignatureSignedAt: Date? (optional v1)

Signed artifact fields (required for locked)
- signedPdfPath: String?
- signedPdfHash: String?

Optional
- notes: String?

Constraints
- title and description required for any CO
- A CO is considered **locked** if lockedAt != nil AND signedPdfPath != nil AND signedPdfHash != nil
- If locked: editor must be read-only and domain must reject writes

---

### 6.4 LineItem
Fields
- id: UUID
- changeOrderId: UUID
- name: String (required)
- quantity: Decimal (>=0; default 1)
- unitPrice: Decimal (>=0; default 0)
- total: Decimal (stored computed)

Constraints
- name non-empty
- total = quantity * unitPrice

---

### 6.5 Attachment
Fields
- id: UUID
- changeOrderId: UUID
- type: Enum(Photo, SignatureClient, SignatureContractor, PdfDraft, PdfSigned)
- filePath: String (required)
- thumbnailPath: String? (photos)
- caption: String?
- createdAt: Date

Constraints
- filePath must exist on disk at time of use (graceful handling if missing)

---

## 7) Business rules (domain layer)

### 7.1 Numbering
- Format: `CO-0001` (4 digits; zero-padded)
- Each Job has its own sequence:
  - new original CO assigns `number = job.nextChangeOrderNumber`
  - increments job.nextChangeOrderNumber by 1 immediately after creation
- Revisions:
  - keep the same base number
  - `revisionNumber` increments per base number
  - display format: `CO-0007 Rev 1`

### 7.2 Currency rounding (must be consistent)
Pick one rounding strategy for v1:
- **Default (recommended): round half up to 2 decimals**
- Document it in code (single helper function) and cover with tests.

### 7.3 Totals and tax
- taxRate stored as fraction (0.07 for 7%)
- subtotal computed based on pricing mode:
  - If line items exist and sum > 0: subtotal = sum(lineItems.total)
  - Else:
    - Fixed: subtotal = fixedSubtotal (required)
    - TimeMaterials: subtotal = (tmLaborHours * tmLaborRate) + tmMaterialsCost
    - EstimateRange: subtotal is not a single value; PDF must present low/high.
      - For stored subtotal/total in app list UI:
        - Use subtotal = estimateHigh (or average) ONLY for sorting/display
        - But PDF must show the range clearly.
- total = subtotal + (subtotal * taxRate) for single-subtotal modes
- For EstimateRange mode:
  - PDF shows “Estimated Total Range” with tax applied consistently:
    - lowTotal = low + low*tax
    - highTotal = high + high*tax

### 7.4 Status transitions
- Draft: editable
- Sent: editable until locked (editing updates updatedAt)
- Approved: locked (signed)
- Rejected: not locked; can create a new revision/draft
- Cancelled: no further actions besides viewing/exporting

### 7.5 Locking event (client signature)
Client signature triggers lock.

On “Sign and Lock”:
1. Validate required fields:
   - title non-empty
   - description non-empty
   - pricing fields valid for selected mode (or line items present)
2. Capture signature metadata:
   - clientSignatureName (typed)
   - clientSignatureSignedAt = now
3. Set lockedAt = now
4. Generate Signed PDF bytes using current state + attachments
5. Persist Signed PDF file to `signedPdfPath`
6. Compute SHA-256 hash of bytes and store in `signedPdfHash`
7. Set status = Approved and approvedAt = now (v1 default)
8. Domain must freeze the record; no further edits allowed.

### 7.6 Immutability enforcement
- UI must disable editing when locked
- Domain layer must also prevent modifications:
  - any “update” operation must check lockedAt
  - if locked → throw/return error
- This applies even if the UI has a bug.

### 7.7 Revisions
“Create Revision” is the only path to modify a signed CO.

Rules:
- A revision is a new ChangeOrder record:
  - same jobId
  - same base number
  - revisionNumber = previous revisionNumber + 1
  - revisionOfId = id of the **original locked CO** for that base number (root)
  - lockedAt, signedPdfPath, signedPdfHash cleared
  - status = Draft
- The revision copies:
  - title/description/pricing fields/line items/photos (photos optional; default copy yes)
  - but it is editable
- Revisions produce their own Signed PDF and hash when signed.

---

## 8) PDF requirements

### 8.1 Draft vs Signed
- Draft PDF:
  - labeled “DRAFT” prominently (header watermark)
  - can be generated anytime for preview
  - not hashed, not treated as immutable artifact
- Signed PDF:
  - generated only at lock time
  - stored and reused for preview/share
  - hashed and hash stored

### 8.2 Required content (always included)
- Company header (if provided; otherwise minimal)
- Client name, project/job address, project name (if provided)
- Change order identifier:
  - `CO-####` and revision label if revisionNumber > 0
- Date/time of signing (for locked) or “generated at” (for draft), plus timezone
- Title + description
- Change type, category, reason
- Cost section:
  - Fixed/T&M: subtotal, tax, total
  - EstimateRange: low/high subtotal and low/high total with tax
- Schedule impact (“Adds X day(s)”)
- Approval clause appropriate to mode (see 8.4)
- Signature blocks:
  - Client signature required for Signed PDF
  - Contractor optional v1
- Photo appendix (if any) with captions

### 8.3 Layout rules (deterministic)
- Page size: US Letter
- Margins: consistent (e.g., 36pt)
- Font: system or embedded consistent font; do not vary by device
- Photo appendix:
  - 2 photos per page (stacked) with caption below each
  - consistent scaling/cropping rules

### 8.4 Approval clause templates (mode-specific)
**Fixed**
- “By signing below, Client approves this change order for a total of {total} and authorizes work to proceed.”

**Time & Materials**
- “By signing below, Client authorizes this change order to be performed on a time and materials basis. Final total will be based on actual time and materials.”

**Estimate/Range**
- “By signing below, Client approves this change order as an estimate. Final total is expected within the range shown and may require a revised change order if scope changes.”

---

## 9) Screens and detailed acceptance criteria

### 9.1 Job List
Must have:
- list of jobs, sorted by updatedAt desc
- search bar filtering by clientName/projectName/address
- empty state with CTA “Create your first job”

Acceptance criteria:
- Create job offline, visible immediately
- Search returns matches
- No stutter on scroll with 50+ jobs

---

### 9.2 New/Edit Job
Fields:
- clientName (required)
- projectName, address, phone, email (optional)
- defaults: tax rate, hourly rate, terms override (optional)

Acceptance criteria:
- clientName validation
- updatedAt updates on edit
- job defaults applied to new COs (tax/hourly/terms)

---

### 9.3 Job Detail
Must have:
- job header
- list of COs for that job
- “New Change Order” CTA
- each CO row shows:
  - CO-#### (and Rev if any)
  - title
  - total (or range)
  - status badge
  - last updated

Acceptance criteria:
- new CO assigns number and increments sequence
- CO list updates immediately

---

### 9.4 Change Order Editor
Two sections:
- **Quick** (default visible):
  - title (required)
  - changeType picker
  - pricingMode segmented control
  - cost inputs for mode
  - scheduleDays quick chips: 0, 1, 3, 7, custom
  - add photos button
  - button: Preview PDF
  - button: Sign (disabled until required fields valid)
- **Details** (collapsed by default):
  - description (required)
  - category, reason
  - line items editor
  - notes
  - tax rate override
  - hourly rate override (T&M only)
  - terms override preview (display-only; actual terms from job/company)

Auto-save:
- all changes persist immediately

Acceptance criteria:
- Draft persists across force quit
- Locked CO is read-only
- Validation clearly shows missing fields
- Totals update live

---

### 9.5 Signature Capture
Must have:
- signature canvas with clear/reset
- client name field (prefill from last used; editable)
- checkbox/confirm: “I approve this change order”
- primary button: “Sign and Lock”

Acceptance criteria:
- Lock generates Signed PDF + hash
- Locked state prevents editing
- Approved status set

---

### 9.6 PDF Preview + Share
Must have:
- preview Draft or Signed based on state
- share sheet integration
- post-share prompt for drafts: “Mark as Sent?”

Acceptance criteria:
- Share works offline (Files, AirDrop, Print)
- Signed PDF reused, not regenerated
- Mark as Sent updates status + sentAt (if not locked)

---

### 9.7 Settings (Company Profile)
Must have:
- company name/contact fields
- default terms (multiline)
- default tax rate / hourly rate

Acceptance criteria:
- Applies to new jobs/CO defaults
- Does not mutate existing Signed PDFs

---

### 9.8 Paywall
Rule (v1):
- Free tier allows **3 total change orders** (across all jobs)
- Once cap reached:
  - user can view/export existing
  - cannot create new CO
  - show paywall with lifetime unlock
- Restore purchases supported

Acceptance criteria:
- Cap enforced offline
- Purchase state persists
- Restore requires internet and shows clear offline message

---

## 10) Analytics and crash reporting (v1 minimal)
No ad tracking. No IDFA usage.

Events (examples):
- job_created
- co_created
- co_signed_locked
- pdf_shared (draft/signed)
- paywall_shown
- purchase_success
- purchase_restore_success

Rules:
- Do not include clientName/address in event payloads
- Prefer counts/booleans over strings

---

## 11) Performance targets
- Job list usable and smooth with:
  - 50 jobs
  - 500 COs total
- PDF generation:
  - < 2 seconds for 5 photos on modern iPhone
  - show progress UI if longer

---

## 12) Accessibility targets
- Dynamic Type: supported on core screens
- VoiceOver: meaningful labels for key controls

---

## 13) Testing and quality gates
- Unit tests required:
  - numbering per job
  - totals/tax rounding
  - lock + revision creation rules
  - hash computation
- UI smoke tests (minimum):
  - create job
  - create CO
  - preview draft PDF
- Manual QA:
  - offline end-to-end (see ACCEPTANCE_TESTS.md)
  - signed PDF immutability
  - settings not mutating historical signed PDFs

---

## 14) Deliverables checklist (v1 ship)
- All screens implemented
- PDF template meets requirements
- Lock/revision rules enforced in domain
- Paywall + restore
- Crash-free baseline in TestFlight with acceptance tests passing

