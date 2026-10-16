Bento for macOS 0.2.6 is a maintenance release for verifying OTA permission continuity.

- Uses the same permanent app-signing certificate and designated requirement as 0.2.5.
- Keeps the existing window arrangement, split, resize and restoration behavior.
- Continues to verify GitHub update downloads with the existing Ed25519 update key.

Verified on a real 0.2.5 → 0.2.6 Sparkle update: Accessibility stayed connected without reapproval, and the updated app arranged five windows while leaving one alone. The version and installed code hash changed while the permanent identity stayed identical. Detailed evidence is recorded in macos/VALIDATION.md.

Users upgrading from 0.2.4 or earlier still need the one-time migration to the permanent identity. This free signing identity is not Apple Developer ID signing or notarization.
