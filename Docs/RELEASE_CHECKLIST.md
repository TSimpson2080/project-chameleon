# Chameleon Release Checklist

## Preconditions
- [ ] On main branch
- [ ] Working tree clean (`git status`)
- [ ] Tests green:
  - [ ] `xcodebuild -project Chameleon.xcodeproj -scheme Chameleon -destination 'platform=iOS Simulator,name=iPhone 17,OS=26.2' test`

## Manual Smoke Test (Simulator)
### Onboarding
- [ ] Launch app fresh
- [ ] Complete onboarding (company name; optional logo; optional terms)
- [ ] Land on Job List

### Core Flow
- [ ] Open an existing job or create a new job
- [ ] Create a new change order (verify CO numbering increments)
- [ ] Add line items:
  - [ ] Add Line Item shows Quantity and Unit Price EMPTY by default
  - [ ] Totals update correctly (subtotal, tax, total)
- [ ] Attach photos:
  - [ ] Add at least one photo
  - [ ] Photo thumbnail appears
  - [ ] Photo viewer opens
- [ ] Signature + lock:
  - [ ] Capture signature
  - [ ] Lock change order
  - [ ] Verify change order is immutable after lock (editing blocked)

### PDF
- [ ] Preview PDF opens (not blank)
- [ ] Share sheet opens
- [ ] Save to Files works (On My iPhone -> Preview)
- [ ] PDF includes:
  - [ ] Company name/logo (if configured)
  - [ ] Line items and totals
  - [ ] Signature block for finalized/locked PDFs

### Verified Package
- [ ] Create Verified Package from locked change order
- [ ] Save ZIP to Files
- [ ] Verify Package ZIP:
  - [ ] Choose Package ZIP -> PASS
- [ ] Verified Packages History:
  - [ ] Package appears in Verified Packages list
  - [ ] Verify on package row shows PASS
  - [ ] Share on package row opens share sheet
- [ ] Persistence check:
  - [ ] Quit simulator and relaunch
  - [ ] Package still appears in Verified Packages list (change-order scoped)

## Distribution (when Apple Developer Program is Active)
- [ ] In Xcode Signing & Capabilities, Team is paid Developer Program (not Personal Team)
- [ ] Product -> Archive succeeds
- [ ] Distribute -> App Store Connect upload succeeds
- [ ] Build appears in App Store Connect TestFlight and can be installed
