Bento for macOS 0.2.8 improves reliability with applications that finish resizing asynchronously.

- Waits for native windows to settle before accepting the layout or learning minimum sizes.
- Retries the final position once when an application is still catching up, including when restoring your desktop.
- A refused intermediate animation frame no longer cancels an otherwise valid arrangement.
- Keeps hover-only grabbers below app windows and above the dark backdrop, automatic saving, and Dock overflow handling from 0.2.7.
- Reuses the permanent signing identity to preserve existing Accessibility approval.
