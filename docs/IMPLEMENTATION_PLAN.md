# SecurePatrol iOS implementation plan

## Implemented starter
- SwiftUI tab navigation, checkpoint list, QR camera capture
- Registered QR code matching and locally saved scan history
- Route model and ordered checkpoint validator (not yet integrated)
- PIN verifier primitive (not yet integrated)

## Next integration tasks
1. Add a patrol session coordinator to persist active route, round, and checkpoint events in one transaction.
2. Add admin-managed checkpoint enrollment, route editing, and guard roles.
3. Implement secure PIN authentication using a slow password KDF, Keychain, attempt limits, and recovery procedures.
4. Make patrol history append-only with tamper-evident event chaining, timestamps, and authenticated guard IDs.
5. Implement import/export and encrypted backups with secure key handling.
6. Add network sync and conflict resolution after protocol review against the Android app.
7. Add automated tests, accessibility checks, localization, and real-device testing.

## Important constraints
This starter does not provide production-grade security, role enforcement, cloud backups, or interoperability with Android. Do not deploy for real security operations until these are implemented and independently tested.

The Android repository is a read-only reference and must not be modified.
