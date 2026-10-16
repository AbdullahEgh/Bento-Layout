Bento for macOS 0.2.4 arranges the windows that fit and leaves the others alone.

- Menu-bar left-click toggles Bento without opening Settings; right-click opens the menu.
- Faster arrangement with one final frame per window and no repeated native resize animation. Resize grips coalesce rapid pointer movement.
- Split previews show the actual resulting slots, including resized neighbors, with a hold indicator. Subtle idle grips make dividers easier to find.
- Restore waits for apps to settle before checking their final frames.
- Matching settings icons for Dock, menu bar, edge snapping, login startup, appearance, animation and gesture controls.
- Compatibility checks run on macOS 15 and 26; the app supports macOS 15 or later on Intel and Apple Silicon.
- An oversized window no longer blocks the entire layout. Smaller windows receive usable slots; skipped windows keep their original positions.
- Native minimum-size restrictions trigger a bounded retry with a fitting subset. Windows that refuse resizing are also left alone after rollback is verified.
- Workspace shows how many windows are arranged and lists the windows left floating.
- Existing splits remain intact when they still fit. Windows are reconsidered when the display or open-window set changes.
- Turning Bento off does not move skipped windows, including windows you moved manually while Bento was active.

If macOS blocks Accessibility after an update, enable `/Applications/Bento.app` in System Settings → Privacy & Security → Accessibility (Device Control and Data Access on newer macOS versions). If an old entry no longer works, remove it and add the installed app again.
