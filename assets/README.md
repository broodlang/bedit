# assets — the desktop identity

What the desktop needs to show the editor as itself (a real icon and name in the
GNOME dash, alt-tab, and "Open with") rather than as an anonymous window with the
fallback gear:

| File | Installed to | Role |
|---|---|---|
| `brood-edit.svg` | `$PREFIX/share/icons/hicolor/scalable/apps/` | the icon, scalable — the source of truth |
| `brood-edit.desktop` | `$PREFIX/share/applications/` | the desktop entry that names the icon |

`make install` places both (see the repo `Makefile`).

## How the three pieces hook up

A desktop cannot guess which app a window belongs to; the window has to say so.
The window declares an **application id** — Wayland's `app_id`, X11's `WM_CLASS`
— and the desktop looks for the entry of the same name:

```
src/main.blsp   (gui-display {:app-id "brood-edit" …})
                        │  app id
                        ▼
assets/brood-edit.desktop   ── Icon=brood-edit ──▶  hicolor/…/brood-edit.svg
```

All three names must agree. On Wayland this is the *only* path to an icon: a
client cannot hand the compositor pixels, so `gui-icon!` does nothing there and
an app with no id gets the generic fallback no matter what it draws.

## The icon

A brood cell (the hexagon) holding a Lisp paren pair with the editor's caret
between them, in the editor's own Catppuccin Mocha palette (`src/theme.blsp`):
a mauve→blue plate, ink knocked out to the window background, caret in peach.

`brood-edit.svg` is hand-written and is the only source — flat shapes, no
embedded raster, so it stays legible down to 16 px. Nothing needs rasterising:
GNOME (and every GTK/Qt desktop) renders the SVG at whatever size it wants. If
some environment does need PNGs:

```bash
for s in 16 24 32 48 64 128 256; do
  rsvg-convert -w $s -h $s assets/brood-edit.svg \
    -o ~/.local/share/icons/hicolor/${s}x${s}/apps/brood-edit.png
done
```
