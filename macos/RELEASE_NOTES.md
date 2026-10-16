Bento for macOS 0.2.6 is a maintenance release for verifying OTA permission continuity.

- Uses the same permanent app-signing certificate and designated requirement as 0.2.5.
- Keeps the existing window arrangement, split, resize and restoration behavior.
- Continues to verify GitHub update downloads with the existing Ed25519 update key.

This release allows a real 0.2.5 → 0.2.6 update to verify that an existing Accessibility grant remains valid. Results will be recorded in macos/VALIDATION.md after installation; publication alone does not establish permission retention.

Users upgrading from 0.2.4 or earlier still need the one-time migration to the permanent identity. This free signing identity is not Apple Developer ID signing or notarization.
