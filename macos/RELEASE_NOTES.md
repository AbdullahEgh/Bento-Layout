Bento for macOS 0.2.1 fixes settings-window stacking and makes blocked activation clear.

- Settings behave like a normal window, so another app can cover them.
- Workspace shows **Accessibility access needed** instead of a disabled Arrange button with an unexplained Off status.
- The menu-bar button stays clickable while off and opens permission guidance when access is missing.
- Activation errors appear beside Arrange, and the permission state refreshes automatically.

If macOS blocks Accessibility after an update, enable `/Applications/Bento.app` in System Settings → Privacy & Security → Accessibility. If an old entry no longer works, remove it and add the installed app again.
