# Project Chameleon — REPO_STRUCTURE.md

Last updated: 2026-01-16

This document defines an exact repo/project structure for Project Chameleon v1 so implementation stays maintainable and predictable.
It assumes a single Xcode project using SwiftUI and SwiftData.

---

## 1) High-level structure

Recommended structure inside the Xcode project (groups mirror folders):

- ChameleonApp/
- Domain/
- Data/
- Services/
- UI/
- Resources/
- Tests/

Optional (recommended):
- Docs/ (for SPEC.md and related docs)
- Scripts/ (for CI helpers, formatting)

---

## 2) Directory and file layout (detailed)

### 2.1 ChameleonApp/
Purpose: app entrypoint, app-wide dependencies, navigation root.

Files:
- ChameleonApp.swift
  - sets up SwiftData model container
  - injects repositories/services into environment (dependency container)
- AppEnvironment.swift
  - struct that contains repositories/services singletons
  - enables swapping for tests
- AppNavigation.swift
  - defines navigation routes or navigation stack helpers
- AppTheme.swift (optional)
  - common spacing, typography helpers

### 2.2 Domain/
Purpose: business rules, validation, calculations, and domain errors.

Subfolders:
- Models/ (domain-only types, enums shared across layers)
- Services/
- Validators/
- Errors/

Files (suggested):
- DomainError.swift
  - enum with user-presentable messages
- Enums.swift
  - ChangeType, Category, Reason, PricingMode, Status
- MoneyRounding.swift
  - single rounding helper
- PricingCalculator.swift
  - compute subtotal/tax/total and estimate range math
- NumberingService.swift
  - assign CO numbers per job
- LockingService.swift
  - validate, lock, timestamp, call PDF+hash, enforce immutability
- RevisionService.swift
  - create a revision from locked CO per SPEC rules
- ValidationRules.swift
  - required field checks and error messages

### 2.3 Data/
Purpose: SwiftData models, repositories, query helpers, and migrations placeholders.

Subfolders:
- Models/
- Repositories/
- Queries/
- Migrations/ (placeholder)

Files:
- CompanyProfileModel.swift
- JobModel.swift
- ChangeOrderModel.swift
- LineItemModel.swift
- AttachmentModel.swift

Repositories:
- CompanyProfileRepository.swift
- JobRepository.swift
- ChangeOrderRepository.swift
- LineItemRepository.swift (optional; could be via ChangeOrder)
- AttachmentRepository.swift (optional)

Notes:
- SwiftData models should be minimal and map closely to SPEC.md.
- Heavy business logic stays in Domain/.

### 2.4 Services/
Purpose: file IO, PDF generation, hashing, sharing/export helpers.

Subfolders:
- Storage/
- PDF/
- Crypto/
- Sharing/

Files:
Storage:
- FileStorageManager.swift
  - directory creation + file writes/reads
  - returns relative paths for persistence
  - manages thumbnails
- ThumbnailGenerator.swift
  - generates deterministic thumbnails

PDF:
- PDFGenerator.swift
  - render Draft and Signed PDFs
  - deterministic page layout
- PDFTemplates.swift
  - constants: margins, fonts, appendix layout rules

Crypto:
- HashingService.swift
  - SHA-256 hex for Data (CryptoKit)
Sharing:
- ShareSheetPresenter.swift
  - helper for presenting share sheet in SwiftUI

### 2.5 UI/
Purpose: SwiftUI screens, view models, reusable UI components.

Subfolders:
- Screens/
  - JobList/
  - JobDetail/
  - JobEditor/
  - ChangeOrderEditor/
  - Signature/
  - PDFPreview/
  - Settings/
  - Paywall/
- Components/
- ViewModels/

Key screens:
- JobListView.swift + JobListViewModel.swift
- JobEditorView.swift + JobEditorViewModel.swift
- JobDetailView.swift + JobDetailViewModel.swift
- ChangeOrderEditorView.swift + ChangeOrderEditorViewModel.swift
- SignatureCaptureView.swift + SignatureViewModel.swift
- PDFPreviewShareView.swift + PDFPreviewViewModel.swift
- SettingsView.swift + SettingsViewModel.swift
- PaywallView.swift + PaywallViewModel.swift

Components:
- StatusBadge.swift
- MoneyField.swift
- PhotoPicker.swift
- SignatureCanvas.swift

### 2.6 Resources/
- App icons, launch assets
- Placeholder images for DEBUG seeding (if needed)

### 2.7 Tests/
Two targets recommended:
- ChameleonUnitTests
- ChameleonUITests

Unit tests:
- NumberingServiceTests.swift
- PricingCalculatorTests.swift
- LockingServiceTests.swift
- RevisionServiceTests.swift
- HashingServiceTests.swift

UI tests:
- SmokeTest_CreateJobAndCO.swift

---

## 3) File system layout for attachments

All attachments must be stored within app sandbox under a stable directory structure:

- Documents/
  - Attachments/
    - Photos/
    - Thumbnails/
  - PDFs/
    - Drafts/
    - Signed/

Rules:
- Store relative file paths in SwiftData, not absolute paths.
- When loading, resolve relative paths using FileStorageManager.
- When deleting a CO, delete its associated files (photos, thumbnails, PDFs) unless shared references exist.
- Signed PDFs must never be overwritten; revisions generate new files.

---

## 4) Dependency injection (DI) approach

Use a single AppEnvironment injected at app root.

AppEnvironment contains:
- Repositories:
  - companyProfileRepository
  - jobRepository
  - changeOrderRepository
- Services:
  - fileStorageManager
  - pdfGenerator
  - hashingService
  - pricingCalculator
  - numberingService
  - lockingService
  - revisionService
  - purchaseManager

In tests, swap AppEnvironment with in-memory SwiftData container and temp directories.

---

## 5) Debug-only tools (must be DEBUG only)

Add a Debug Menu accessible from Settings in DEBUG builds:
- Seed sample job
- Seed 10 sample COs for selected job
- Create CO with 5 placeholder photos
- Toggle “simulate missing attachment file” (optional) to test resilience

---

## 6) CI guidance (GitHub Actions)
Minimum pipeline:
- build the app
- run unit tests
- run UI smoke test (if feasible with simulators)
- fail on warnings (optional but recommended)

---

## 7) Implementation order (recommended)
1. Scaffolding + navigation skeleton
2. SwiftData models + repositories
3. Domain services (numbering, pricing, validation)
4. File storage + photo picking + thumbnails
5. PDF generator (draft)
6. Signature + locking + signed PDF + hashing
7. Revision creation
8. Paywall + restore
9. Tests and acceptance test pass
