# Talos domain

- **Wheel**: the primary or secondary ring of actions shown during a file drag.
- **Wheel item**: a persisted action or folder, including its title and configuration.
- **Action**: an extension command or the built-in Settings destination.
- **Folder**: wheel items opened by dwell, with Back returning to the parent.
- **Drag session**: one file selection, from inspection to cancellation or a single accepted drop. It owns both wheels' prepared actions and keeps late AppKit callbacks valid after mouse-up.
