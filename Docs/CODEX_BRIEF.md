# Project Chameleon — CODEX_BRIEF.md

Last updated: 2026-01-16

This brief is intended to be pasted into Codex (or used as the top-level guidance for the repo).
It defines exact expectations, constraints, deliverables, and coding standards so Codex does not need to guess.

---

## 1) Objective

Build **Project Chameleon v1**: an offline-first iOS app that creates, locks (client signature), and shares professional change order PDFs.
“Enterprise-level” means integrity and reliability:
- locked records immutable
- revisions explicit
- signed PDF stored and hashed (SHA-256)
- deterministic PDF generation
- offline end-to-end

The behavior is defined in:
- SPEC.md
- ACCEPTANCE_TESTS.md
- DATA_INTEGRITY.md

Codex must follow those documents exactly.

---

## 2) Hard constraints (do not violate)

### 2.1 Platform + stack
- iOS minimum: **iOS 17+**
- SwiftUI
- SwiftData for persistence
- Attachments stored as files (no DB blobs)

### 2.2 Offline-first
All critical flows must work with Airplane Mode ON:
- create/edit jobs
- create/edit drafts
- add photos
- preview draft PDFs
- capture signature and lock
- generate signed PDF + hash
- share signed PDF to Files/AirDrop/Print

### 2.3 Integrity model
- Client signature triggers lock.
- Locked COs immutable (UI + domain enforced).
- Locked CO shares stored Signed PDF (not regenerated).
- Store SHA-256 hash of Signed PDF bytes at lock time.
- Post-sign modifications only via Create Revision.

### 2.4 Privacy constraints
- No ad tracking SDKs
- No IDFA access
- Do not log customer PII (names, addresses, PDF text) to analytics/logs.

### 2.5 Scope constraints
Do not implement in v1:
- CloudKit sync
- multi-user roles/team
- integrations
- advanced photo markup

---

## 3) Coding expectations

### 3.1 Architecture
Use a clean-ish separation:
- Domain (business rules, calculators, lock/revision logic)
- Data (SwiftData models + repository)
- Services (PDF, hashing, file storage, export/share)
- UI (SwiftUI screens and view models)

Business logic must not live in SwiftUI views.
Views call view models, which call domain/services.

### 3.2 Deterministic PDF
PDF generation must be deterministic:
- fixed margins
- fixed font selection
- consistent pagination rules for photos (2 per page, stacked)
- Draft PDFs include “DRAFT” label
- Signed PDF generated exactly once at lock time and stored

### 3.3 Error handling
- Every operation that can fail returns a user-presentable error
- Failures must not corrupt data
- Missing attachment files should be handled gracefully (show placeholder and allow export of remaining content)

### 3.4 Performance
- Use thumbnails for lists
- Avoid heavy work on main thread
- PDF generation should be async with progress indicator if needed

### 3.5 Testing
Write unit tests for:
- numbering per job
- totals/tax rounding
- lock logic + hash persistence
- revision creation rules

Write a basic UI smoke test:
- create job
- create CO
- preview draft PDF (ensure preview opens)

---

## 4) Deliverables (in order)

### Phase 1 — Project scaffolding
1. Create Xcode project “Chameleon” (SwiftUI).
2. Create folder/module structure per REPO_STRUCTURE.md.
3. Implement basic navigation skeleton:
   - JobListView → JobDetailView → ChangeOrderEditorView

### Phase 2 — Persistence + repositories
4. Implement SwiftData models aligned with SPEC.md:
   - CompanyProfile, Job, ChangeOrder, LineItem, Attachment
5. Implement Repository layer:
   - JobRepository: CRUD + search
   - ChangeOrderRepository: CRUD + fetch by job
   - CompanyProfileRepository: singleton get/set
6. Add sample data seeding for DEBUG builds.

### Phase 3 — Domain rules
7. Implement ChangeOrderNumberingService:
   - assigns CO numbers per job
8. Implement PricingCalculator:
   - computes subtotal/tax/total including estimate range rules
9. Implement LockingService:
   - validates required fields
   - generates Signed PDF
   - stores Signed PDF path
   - computes and stores SHA-256 hash
   - sets Approved status and timestamps
10. Implement RevisionService:
   - create revision from locked CO
   - copies fields and attachments as defined

### Phase 4 — Services
11. Implement FileStorageManager:
   - creates directories
   - writes/reads photos, thumbnails, PDFs
   - returns stable relative paths
12. Implement PDFGenerator:
   - generate Draft PDF bytes (with watermark)
   - generate Signed PDF bytes (no watermark)
   - photo appendix with deterministic layout
13. Implement HashingService:
   - SHA-256 hex for Data

### Phase 5 — UI screens (SwiftUI)
14. JobListView
15. JobEditorView
16. JobDetailView
17. ChangeOrderEditorView
18. SignatureCaptureView
19. PDFPreviewShareView
20. SettingsView (CompanyProfile)

Include:
- empty states
- validation messages
- locked state read-only UI
- share sheet integration

### Phase 6 — Purchases
21. Implement Paywall:
   - enforce free cap (3 total COs)
   - lifetime unlock non-consumable
   - restore purchases
22. Ensure cap is enforced offline.

### Phase 7 — Testing + polish
23. Unit tests and UI smoke tests
24. Run through ACCEPTANCE_TESTS.md and fix failures

---

## 5) Definition of Done (v1)
- All tests passing
- Acceptance tests pass in offline mode for core workflow
- Signed PDFs are immutable artifacts with stored hashes
- No PII logging
- App is stable with moderate data volume

---

## 6) Notes for Codex
- When something is unclear, prefer SPEC.md as source of truth.
- If you must choose defaults:
  - rounding: round half up to 2 decimals
  - CO formatting: CO-0001, Rev 1
  - signature = approval (Approved on lock)
  - free cap: 3 total change orders
