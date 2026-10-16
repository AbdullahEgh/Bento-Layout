Bento for macOS 0.2.10 improves split and resize behavior.

- Grab dividers anywhere in the gap without recentering or jumping.
- Keep the final pointer position on quick release, without a second resize animation.
- Move grabbers with the applied resize sample and reduce background overlay redraws.
- Keep destination outlines visible through drop completion.
- Reuses the permanent app identity and OTA signing key.

Validated with 32 core tests and 61 isolated native interaction checks on macOS 15 and 26. Live desktop verification is tracked separately in the repository validation notes.
