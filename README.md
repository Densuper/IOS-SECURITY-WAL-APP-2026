# SecurePatrol iOS

Native SwiftUI companion to the SecurePatrol Android security patrol app. This is a **separate iOS codebase**; the Android repository is not modified.

## Getting started
1. On a Mac, install Xcode and [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`).
2. Clone this repository and run `xcodegen generate`.
3. Open `SecurePatrol.xcodeproj`, select your Apple development team under Signing & Capabilities, and run on an iPhone.

## Initial implementation
- Native SwiftUI tab navigation, dashboard, patrol checkpoint list, QR scanning, and history
- Local checkpoint and patrol event persistence via JSON in Application Support
- Sample checkpoint data to demonstrate the workflow
- QR scan verification against registered checkpoint codes

## Roadmap
Guard/admin authentication, ordered patrol enforcement, audit export, LAN peer synchronization, encrypted backups, and cloud backup require further implementation and security review. Do not treat this scaffold as a production security system.

## Privacy
Camera access is used only to scan QR codes. Data remains on-device in this starter implementation.
