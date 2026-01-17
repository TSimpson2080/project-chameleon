# Project Chameleon — ACCEPTANCE_TESTS.md

Version: 0.1  
Last updated: 2026-01-16

This document defines step-by-step acceptance test cases for Project Chameleon (v1).
Goal: validate the core promise (offline change order creation → signature → signed PDF share) and the enterprise-grade integrity rules.

---

## 0) Test environment setup

### Devices
- iPhone (primary): iOS target version (e.g., iOS 17.x)
- Optional: iPad for smoke test (v1 is iPhone-first)

### Accounts
- No login required in v1.

### Data reset
- Delete app from device before a “clean install” test run.
- For repeat runs, include at least one test that validates persistence across app restarts without deleting the app.

### Network conditions
- Run each critical workflow twice:
  1) Online (normal Wi‑Fi)
  2) Offline (Airplane Mode ON)

---

## 1) Jobs

### TC-JOB-001 — Create Job (required fields only)
**Preconditions**
- App installed; first launch completed (if onboarding exists).

**Steps**
1. Open app.
2. Tap **New Job**.
3. Enter `Client Name = "Test Client A"`.
4. Leave all optional fields blank.
5. Tap **Save**.

**Expected**
- Job appears in Job List.
- Job is selectable.
- No validation errors besides client name requirement.

---

### TC-JOB-002 — Create Job (all fields)
**Steps**
1. New Job.
2. Enter:
   - Client Name: Test Client B
   - Project Name: Kitchen Remodel
   - Address: 123 Main St
   - Phone: 555-555-5555
   - Email: test@example.com
   - Default Tax Rate: 7%
   - Default Hourly Rate: 95
   - Terms Override: "Payment due upon approval."
3. Save.

**Expected**
- Job saved with details visible in Job Detail.
- Defaults are stored for use in new change orders under this job.

---

### TC-JOB-003 — Job list sorting and search
**Steps**
1. Ensure at least 2 jobs exist.
2. Edit one job (e.g., change project name).
3. Return to Job List.
4. Search by client name, project name, and address fragments.

**Expected**
- Most recently updated job appears at top (or per spec).
- Search returns expected matches for each field.

---

## 2) Change Orders — creation and numbering

### TC-CO-001 — Create CO assigns number and increments sequence
**Preconditions**
- Job exists: Test Client A

**Steps**
1. Open Job Detail for Test Client A.
2. Tap **New Change Order**.
3. Observe CO number shown (e.g., CO-0001).
4. Enter title + description + fixed subtotal (or line items).
5. Go back to Job Detail (auto-save draft).
6. Tap **New Change Order** again.

**Expected**
- First CO number = CO-0001 (or formatting per spec).
- Second CO number = CO-0002.
- Numbers are unique per job and increase by 1 for each *new original* CO.

---

### TC-CO-002 — Draft auto-save
**Steps**
1. Open an existing draft CO.
2. Modify title/description.
3. Force quit app (swipe away).
4. Relaunch app and open same CO.

**Expected**
- Changes persist.
- No data loss.

---

### TC-CO-003 — Line items totals and tax calculation
**Steps**
1. Create CO with line items:
   - Item 1: qty 2, unit 100
   - Item 2: qty 1, unit 50
2. Set tax rate to 10%.
3. Observe subtotal and total.

**Expected**
- Subtotal = 2*100 + 1*50 = 250
- Tax = 25
- Total = 275
- Rounding behavior matches documented rule.

---

## 3) Attachments (photos)

### TC-ATT-001 — Add photos from camera/library
**Steps**
1. Open a draft CO.
2. Add 2 photos (camera or library).
3. Confirm thumbnails appear.
4. Close CO and reopen.

**Expected**
- Photos persist.
- Thumbnails render quickly.
- App remains responsive.

---

### TC-ATT-002 — Photo appendix appears in PDF
**Steps**
1. With 2+ photos attached, generate **Draft PDF Preview**.
2. Scroll pages.

**Expected**
- Photos appear in appendix pages.
- Captions (if any) appear.
- Pagination follows deterministic rules.

---

## 4) PDF generation + sharing

### TC-PDF-001 — Draft PDF labeled DRAFT
**Steps**
1. Open a draft CO (not signed).
2. Tap **Preview PDF**.

**Expected**
- PDF visibly marked “DRAFT”.
- Contains required fields per spec.
- Draft PDF is not stored as signedPdfPath and does not have a signedPdfHash.

---

### TC-PDF-002 — Share Draft PDF
**Steps**
1. In PDF preview, tap **Share**.
2. Save to Files.
3. Re-open file from Files app.

**Expected**
- PDF opens and is readable.
- Share works offline (Airplane Mode ON), at least for Files/AirDrop/Print.

---

## 5) Signature, locking, and integrity

### TC-SIG-001 — Client signature locks CO and generates signed PDF
**Preconditions**
- Draft CO exists with valid required fields.

**Steps**
1. Open CO.
2. Tap **Sign**.
3. Enter client signature name (or accept default).
4. Draw signature.
5. Tap **Sign and Lock**.

**Expected**
- CO becomes locked (UI indicates Locked/Approved).
- lockedAt and clientSignatureSignedAt populated.
- signedPdfPath populated.
- signedPdfHash populated (non-empty).
- Editor fields become non-editable.

---

### TC-SIG-002 — Locked CO cannot be edited (domain enforcement)
**Steps**
1. Attempt to edit a locked CO title/description/cost fields.

**Expected**
- UI blocks edits.
- If any edit attempt bypasses UI (e.g., via debug actions), domain layer rejects changes.

---

### TC-SIG-003 — Signed PDF is reused, not regenerated
**Steps**
1. Open locked CO.
2. Preview PDF twice.
3. Share to Files twice.

**Expected**
- Same PDF artifact is used each time (byte-identical) unless user creates a revision.
- Hash remains stable.

---

### TC-REV-001 — Create Revision from locked CO
**Steps**
1. Open a locked CO.
2. Tap **Create Revision**.
3. Modify description or price.
4. Save as draft.

**Expected**
- New CO created with same base number and revisionNumber = prior revisionNumber + 1.
- revisionOfId references the original locked CO (or consistent root per spec).
- New revision starts as Draft and is editable.
- Original locked CO remains unchanged.

---

### TC-REV-002 — Revision signing produces new signed PDF/hash
**Steps**
1. Sign and lock the revision.
2. Compare signedPdfHash between original and revision.

**Expected**
- Revision has its own signedPdfPath and signedPdfHash.
- Hash differs if content differs.
- Both PDFs remain accessible.

---

## 6) Status transitions

### TC-STAT-001 — Mark as Sent after sharing draft
**Steps**
1. Share a draft PDF.
2. When prompted, tap **Mark as Sent**.

**Expected**
- Status becomes Sent.
- sentAt is populated.
- CO remains editable until locked.

---

### TC-STAT-002 — Signature implies approval (v1 default)
**Steps**
1. Sign and lock a CO.

**Expected**
- Status becomes Approved.
- approvedAt populated.
- CO locked.

---

### TC-STAT-003 — Rejected/Cancelled behaviors
**Steps**
1. Set a CO to Rejected (if supported in v1 UI) and verify it is not locked.
2. Set a CO to Cancelled and verify actions are limited.

**Expected**
- Rejected is not locked; revision creation behavior matches spec.
- Cancelled blocks further actions besides viewing/exporting (per spec).

---

## 7) Settings and defaults

### TC-SET-001 — Company profile defaults apply to new jobs/COs
**Steps**
1. Set Company Profile:
   - companyName
   - defaultTaxRate
   - defaultTerms
2. Create a new Job without overrides.
3. Create a new CO under that Job.

**Expected**
- New CO inherits tax rate and terms by default.
- PDF includes company header and terms if provided.

---

### TC-SET-002 — Updating settings does not mutate historical signed PDFs
**Steps**
1. Sign and lock a CO.
2. Change Company Profile name/terms.
3. Re-open the signed PDF.

**Expected**
- Signed PDF content remains unchanged (historical integrity).
- New COs reflect updated settings.

---

## 8) Paywall (free cap + lifetime unlock)

### TC-IAP-001 — Free cap enforced offline
**Steps**
1. With fresh install and no purchase, create COs until cap is reached.
2. Attempt to create one more CO while offline (Airplane Mode ON).

**Expected**
- App blocks creating additional COs beyond cap.
- App presents paywall.
- Messaging is clear even offline.

---

### TC-IAP-002 — Lifetime unlock removes cap
**Steps**
1. Purchase lifetime unlock (online).
2. Create additional COs beyond cap.

**Expected**
- No cap is enforced after purchase.
- Purchase state persists across restarts.

---

### TC-IAP-003 — Restore purchases
**Steps**
1. Install app on second device or reinstall on same device.
2. Tap **Restore Purchases**.

**Expected**
- Purchase restores successfully when network is available.
- If offline, user sees a clear “requires internet” message.

---

## 9) Offline end-to-end (“core promise”)

### TC-OFF-001 — Full workflow in Airplane Mode
**Steps**
1. Turn Airplane Mode ON.
2. Create job.
3. Create new CO with photos.
4. Sign and lock.
5. Share signed PDF to Files.

**Expected**
- Entire workflow succeeds with no network.
- Signed PDF is created and readable.

---

## 10) Performance and stability checks (release gate)

### TC-PERF-001 — Large dataset list performance
**Setup**
- Create or seed ~50 jobs and ~500 change orders total (can be done via internal debug tools if available).

**Expected**
- Job list loads quickly and remains scroll-smooth.
- No long blocking operations on main thread.

---

### TC-PERF-002 — PDF generation time budget
**Steps**
1. Create a CO with 5 photos.
2. Generate PDF.

**Expected**
- PDF generation completes in < 2 seconds on modern device (per spec), or app shows progress and remains responsive.

---

## 11) Accessibility smoke tests

### TC-A11Y-001 — Dynamic Type and VoiceOver basics
**Steps**
1. Enable large Dynamic Type.
2. Navigate Job List → CO Editor → Signature.
3. Enable VoiceOver and repeat.

**Expected**
- Text does not clip severely; core actions remain usable.
- Important buttons and fields have meaningful labels.
