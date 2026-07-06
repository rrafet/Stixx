# Stixx

Minimal, native sticky notes for macOS. Pure AppKit, no dependencies.

## Features

- **Clean by design** — no visible chrome; the close and pin controls appear only when you hover the top edge of a note
- **Frosted glass mode** — right-click → Translucent for a see-through note that blurs whatever is behind it
- **Checklists & lists** — type `- ` for a bullet list, `[]` for a checklist; click a checkbox to check it off
- **Find Notes** — ⌘F opens a search panel across every note
- **Quick capture** — ⌥⌘N creates a note from any app, system-wide
- **Collapse** — double-click a note's top edge to shrink it to its title
- **Edge snapping** — notes align to each other and to screen edges when dragged close
- **Safety net** — deleted notes can be brought back with ⇧⌘T until you quit
- 6 colors adapting to light/dark mode, 4 font styles, per-note "keep on top", optional menu-bar-only mode, open at login

## Building

Requires macOS 13+ and the Xcode Command Line Tools.

```sh
./build.sh
open Stixx.app
```

This compiles the Swift package, wraps it into `Stixx.app`, and ad-hoc signs
it with App Sandbox and Hardened Runtime enabled. Notes are stored as JSON in
the app's sandbox container.

## Keyboard shortcuts

| Action | Shortcut |
|---|---|
| New note | ⌘N (⌥⌘N system-wide) |
| Find notes | ⌘F |
| Delete note | ⌘W |
| Reopen last deleted | ⇧⌘T |
| Collapse/expand | ⇧⌘M |
| Note color | ⌘1–⌘6 |
| Translucent | ⌥⌘T |
| Keep on top | ⇧⌘P |
| Font size | ⌘+ / ⌘− |

## License

[MIT](LICENSE)
