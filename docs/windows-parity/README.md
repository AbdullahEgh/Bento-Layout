# Windows experience parity handoff

Prepared 2026-10-18. Product reference: macOS source commit `7925944` on `codex/macos-native-preview`, including the 0.2.40 changes. This is a source baseline, not a claim that 0.2.40 is installed or that every physical interaction has passed live QA.

The user requests the same complete Bento experience on Windows, adapted to Windows conventions. Implement in the existing Windows codebase on the PC. Do not replace it with a Mac wrapper, a new unrelated app, or an Electron rewrite.

## Read in this order

1. [Experience contract](EXPERIENCE.md): authoritative behavior, visual rules, state transitions and platform translations.
2. [Implementation plan](IMPLEMENTATION.md): current gaps, source map, Windows boundaries and release gates.
3. [Acceptance checklist](ACCEPTANCE.md): reproducible regressions and delivery evidence. All Windows parity items begin unverified.
4. [Mac test inventory](MAC-TEST-INVENTORY.md): exact test names and source links, generated from the baseline. Port relevant behavior; Mac tests passing is not Windows validation.
5. [PC chat prompt](PC-CHAT-PROMPT.md): paste this into the existing local Windows chat.

Current Windows sources already implement split trees, automatic layout, native drag/resize, previews, overflow minimization, history, settings and an updater. They do **not** establish parity with the newer Mac changes. Existing READMEs contain historical behavior (including persistent layout files and restore-on-quit); this contract supersedes those descriptions for the Windows parity work. Preserve the PC's newer local work and audit it before applying changes.

## Delivery rules

- Give each requirement an implementation location, automated test where appropriate, and live verification result. Mark unsupported/blocked cases explicitly with the Windows limitation and fallback; never silently omit them or claim parity from packaging alone.
- Preserve app identity, existing user settings, update compatibility, original artwork and the shared repository. Session layout semantics change intentionally; leave legacy saved-layout files untouched and stop auto-loading them.
- Work on a Windows branch from the current PC checkout after fetching this handoff. Do not reset, overwrite, or force-push either machine's work. No Mac application changes are needed for this handoff.
- First establish correct geometry and lifecycle behavior, then match visuals and measure performance. Passing tests alone does not certify physical input, app-specific limits, mixed DPI, fullscreen, or Task View.
- GitHub releases must contain both platform downloads, with each platform's actual version and validation stated. Packaging the current Windows 0.3.9 app alongside Mac 0.2.40 is not a Windows feature update.
