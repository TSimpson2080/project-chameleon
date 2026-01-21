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

### Export Package
- [ ] Create Export Package from locked change order
- [ ] Save ZIP to Files
- [ ] Verify Export ZIP:
  - [ ] Choose Export ZIP -> PASS
- [ ] Exports History:
  - [ ] Export appears in Exports list
  - [ ] Verify on export row shows PASS
  - [ ] Share on export row opens share sheet
- [ ] Persistence check:
  - [ ] Quit simulator and relaunch
  - [ ] Export still appears in Exports list (change-order scoped)

## Distribution (when Apple Developer Program is Active)
- [ ] In Xcode Signing & Capabilities, Team is paid Developer Program (not Personal Team)
- [ ] Product -> Archive succeeds
- [ ] Distribute -> App Store Connect upload succeeds
- [ ] Build appears in App Store Connect TestFlight and can be installed

