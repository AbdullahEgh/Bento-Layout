Bento for macOS 0.2.13

What’s new

- Keep valid window moves committed when macOS briefly returns the dragged window to its old position.
- Improve fast drags and split drops when window focus changes late.
- Pause background rearrangement while dragging and ignore brief window-discovery gaps.
- Keep split previews stable and reuse their geometry, with fewer native frame reads and redraws.
- Apply the final drop once after mouse-up, including the last native resize position.
- Recover cleanly when a source or target closes during a gesture, and add local interaction tracing for QA.
