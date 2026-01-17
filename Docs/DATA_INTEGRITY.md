# Project Chameleon — DATA_INTEGRITY.md

Version: 0.1  
Last updated: 2026-01-16

This document describes the data integrity guarantees in Project Chameleon (v1) in plain English and in implementable rules.
It is intended for enterprise-minded buyers and for engineering to align on what “locked,” “signed,” and “revision” mean.

---

## 1) Summary of guarantees

### 1.1 Offline-first durability
- Project Chameleon stores all Jobs, Change Orders, and attachments locally on the device.
- The core workflow does not require a network connection.
- Drafts are continuously auto-saved to prevent data loss.

### 1.2 Signed records are immutable
- Once a client signs a change order, the change order becomes **Locked**.
- Locked change orders cannot be edited.
- Any post-sign changes must be made by creating a **Revision**, which produces a new record with its own signature and signed PDF.

### 1.3 Signed PDF is the source of truth
- When a change order is locked, the app generates a **Signed PDF** artifact and stores it.
- The app computes a cryptographic hash (SHA‑256) of the Signed PDF and stores it with the locked record.
- Sharing a locked change order shares the stored Signed PDF (not a newly regenerated document).

### 1.4 Clear audit trail
- Each change order carries a timestamp trail (created, updated, sent, signed/locked).
- Each signature captures at least:
  - Signature name (typed)
  - Signature time
  - Device time zone identifier
- Revisions are explicitly linked to prior signed records.

---

## 2) Definitions

### 2.1 Draft Change Order
A change order that is not locked. Drafts are editable and can generate a “Draft PDF” for preview/sharing.

### 2.2 Locked Change Order
A change order that has been signed by the client. Locked change orders are immutable and have a stored Signed PDF and hash.

### 2.3 Revision
A new change order created from an existing locked change order, intended to modify scope/cost/schedule after the original was signed.
Revisions:
- keep the same base change order number
- increment revision number (Rev 1, Rev 2, …)
- start as Draft until signed

---

## 3) Integrity model (rules)

### 3.1 The locking event
Locking occurs only when the user completes “Sign and Lock” with a client signature.

On lock:
1. Set `lockedAt = now` (device local time)
2. Set `clientSignatureSignedAt = now`
3. Generate Signed PDF bytes using the current record state and attachments
4. Persist Signed PDF to stable storage (`signedPdfPath`)
5. Compute `signedPdfHash = SHA256(signedPdfBytes)` (hex string)
6. Set status to Approved (v1 default) and set `approvedAt = now`

### 3.2 Post-lock immutability
After locking:
- All user-editable fields must be treated as read-only.
- Any attempt to modify a locked record must be rejected by the domain layer, even if UI protections fail.

### 3.3 Sharing behavior
- Draft COs may generate and share a Draft PDF labeled “DRAFT.”
- Locked COs must share the stored Signed PDF, byte-for-byte.
- Locked COs must not regenerate Signed PDFs on demand, because regeneration can create ambiguity if formatting or embedded metadata changes over time.

### 3.4 Revisions
When creating a revision from a locked CO:
- Create a new ChangeOrder record with:
  - same base `number`
  - `revisionNumber = previousRevisionNumber + 1`
  - `revisionOfId` set to the original locked CO (or consistent root rule)
  - status = Draft
  - `lockedAt = nil`, `signedPdfPath = nil`, `signedPdfHash = nil`
- The revision is fully editable until signed.
- When signed, the revision becomes locked and generates its own Signed PDF and hash.

---

## 4) What the hash guarantees (and what it does not)

### 4.1 Guarantees
If the stored Signed PDF file is altered after signing (even by one byte), its SHA‑256 hash will change.
Therefore:
- you can detect tampering by re-hashing the stored Signed PDF and comparing it to `signedPdfHash`.

### 4.2 Non-goals (v1)
- v1 does not provide third-party notarization or certificate-backed digital signatures.
- v1 does not attempt to prove who physically held the device (beyond signature capture and timestamps).
- v1 does not provide server-side audit logs (because v1 is offline-first and backend-free).

---

## 5) Attachment integrity

### 5.1 Photos
- Photos used in a locked CO must be included in the Signed PDF (appendix pages).
- The Signed PDF is the frozen record of those photos as presented at signing time.

### 5.2 Signature images
- Signature strokes are rendered into the Signed PDF.
- The Signed PDF is the canonical representation of the signature.

---

## 6) Time, clocks, and timezone

### 6.1 Device time usage
- Timestamps are captured from device time.
- The app stores the device time zone identifier alongside each CO so the PDF can state a timezone.

### 6.2 Clock drift risk
- If device time is incorrect, timestamps can be incorrect.
- Mitigation (future): optional network time verification when online (post‑v1).

---

## 7) Privacy and logging constraints

- The app must avoid logging customer PII (names, addresses) in analytics or diagnostic logs.
- Crash reports should be configured to scrub sensitive fields.
- Signed PDFs and attachments reside within the app sandbox and use iOS data protection defaults.

---

## 8) Verification checklist (for QA / enterprise buyers)

1. Create and lock a CO.
2. Share Signed PDF.
3. Compute SHA‑256 hash of the exported file (desktop tool) and compare to in-app stored hash (if exposed via debug or export).
4. Confirm locked CO fields are not editable.
5. Create a revision and confirm it has a new Signed PDF and hash after signing.
6. Update company profile and confirm historical Signed PDF does not change.

---

## 9) Future integrity upgrades (optional roadmap)

- Expose “Verify PDF integrity” in-app (re-hash and compare).
- Add certificate-based signing for PDFs (true digital signature).
- Add CloudKit audit sync (append-only event log) for team/enterprise editions.
- Add optional biometric app lock and per-job encryption keys.
