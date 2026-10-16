Bento for macOS 0.2.5 keeps a stable app identity across updates.

- Releases now use the same persistent code-signing certificate and app requirement. macOS can recognize future versions as the same app instead of tying Accessibility approval to one build.
- The release workflow refuses ad-hoc signing and verifies that a different version satisfies the same app identity.
- Sparkle continues to verify GitHub OTA downloads with the existing Ed25519 update key.
- Upgrading from 0.2.4 or earlier changes the app identity once. Enable the newly installed app in Accessibility after this migration. Later updates signed by this identity are designed to retain that approval.
- Includes quiet menu-bar activation, fitting-window arrangement, precise split previews, visible resize grips and settings icons from 0.2.4.

This is a free, self-signed app identity, not Apple Developer ID signing or notarization. It establishes continuity between Bento releases. It does not grant Accessibility access automatically or override a permission you revoke.
