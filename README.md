<p align="center">
  <img src="Packaging/AppIcon.png" width="128" alt="Stixx app icon">
</p>

<h1 align="center">Stixx</h1>

Minimal, native sticky notes for macOS. Pure AppKit, no dependencies.
Each note is a *stix*; together they're your stixx.

## Download

Grab `Stixx.zip` from the [latest release](https://github.com/rrafet/Stixx/releases/latest),
unzip it, and drag `Stixx.app` into your Applications folder.

> Stixx is not notarized yet, so the very first launch takes one extra step:
> right-click `Stixx.app` → **Open** → **Open**. If macOS still refuses, go to
> System Settings → Privacy & Security and click **Open Anyway**. This is only
> needed once.

## Features

- **Clean by design** — no visible chrome; the close, save, and pin controls appear only when you hover the top edge of a stix
- **Frosted glass mode** — right-click → Translucent for a see-through stix that blurs whatever is behind it
- **Checklists & lists** — type `- ` for a bullet list, `[]` for a checklist; click a checkbox to check it off; Tab / ⇧Tab nest items; wrapped lines hang neatly under their marker
- **Save for later** — the tray button (⌘S) saves a stix and puts it away; bring it back from File → Saved Stixx or the Find panel
- **Find Stixx** — ⌘F opens a search panel across every stix, saved ones included
- **Quick capture** — ⌥⌘N creates a stix from any app, system-wide
- **Collapse** — the chevron button (or double-clicking the top edge) shrinks a stix to just its title, Stickies-style
- **Edge snapping** — stixx align to each other and to screen edges when dragged close
- **Safety net** — deleted stixx can be brought back with ⇧⌘T until you quit
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
| New stix | ⌘N (⌥⌘N system-wide) |
| Find stixx | ⌘F |
| Save stix for later | ⌘S |
| Delete stix | ⌘W |
| Reopen last deleted | ⇧⌘T |
| Collapse/expand | ⇧⌘M |
| Indent / outdent list item | Tab / ⇧Tab |
| Note color | ⌘1–⌘6 |
| Translucent | ⌥⌘T |
| Keep on top | ⇧⌘P |
| Font size | ⌘+ / ⌘− |

## License

[MIT](LICENSE)
