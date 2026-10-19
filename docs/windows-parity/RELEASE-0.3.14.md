Windows 0.3.14 improves shortcut recording and native Windows appearance.

- Quick native window drags return to their slot or commit the captured release destination, even when drag events are queued.
- Record, change or disable the toggle shortcut at the top of Gestures. Recording suspends the existing global binding and handles cancellation and conflicts.
- Background darkness fades out when the layout empties and returns smoothly when windows reopen.
- Controls use the Windows accent with readable foreground colors. Contrast themes, transparency preferences and reduced motion are respected by the updated appearance paths.

CloudPC validation: clean build, 197 native checks, 43 portable core checks, eight settings checks and seven five-window checks passed. Actual keyboard capture, activation and disabling were verified. A physical own-slot caption drag reproduced the queued-event defect before the fix and restored correctly afterward. Physical cross-window/long-hold dragging, Task View, mixed-DPI hardware, representative third-party sizing, actual OS accessibility-setting changes and installed OTA replacement remain unverified. See QA-0.3.14.md for scope.

The included Mac archive is the unchanged macOS 0.2.42 release. Windows updater identity and asset names are preserved.
