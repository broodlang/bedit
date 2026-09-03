# assets — the desktop identity

What the desktop needs to show the editor as itself (a real icon and name in the
GNOME dash, alt-tab, and "Open with") rather than as an anonymous window with the
fallback gear:

| File | Installed to | Role |
|---|---|---|
| `bedit.svg` | `$PREFIX/share/icons/hicolor/scalable/apps/` | the icon, scalable — the source of truth |
| `bedit.desktop` | `$PREFIX/share/applications/` | the desktop entry that names the icon |

`make install` places both (see the repo `Makefile`).

## How the three pieces hook up

A desktop cannot guess which app a window belongs to; the window has to say so.
The window declares an **application id** — Wayland's `app_id`, X11's `WM_CLASS`
— and the desktop looks for the entry of the same name:

```
src/main.blsp   (gui-display {:app-id "bedit" …})
                        │  app id
                        ▼
assets/bedit.desktop   ── Icon=bedit ──▶  hicolor/…/bedit.svg
```

All three names must agree. On Wayland this is the *only* path to an icon: a
client cannot hand the compositor pixels, so `gui-icon!` does nothing there and
an app with no id gets the generic fallback no matter what it draws.

## The icon

A brood cell (the hexagon) holding two lines of text with the editor's caret at
the end of the second, in the editor's own Catppuccin Mocha palette
(`src/theme.blsp`): a mauve→blue plate, ink knocked out to the window background,
caret in peach.

It was a Lisp paren pair with the caret between them until 2026-09-03. Two arcs
curving toward each other around a vertical bar is an **enclosure**, and an
enclosure is what the eye resolves before it resolves punctuation — so the parens
read as a boundary rather than as a form, and at 16 px they fused into a single
almond with the caret dropping out below as a separate dot. The rule the
replacement follows is simply that **no shape encloses another**: horizontal bars
survive smallest, and the mark still reads as text with a cursor in it at every
size the desktop asks for (64 px alt-tab, 32 px dash, 24 px title bar, 16 px
"Open with"). Check a candidate by rasterising to 16 px and magnifying the
pixels — scaled vectors will flatter a mark that does not actually hold up.

`bedit.svg` is hand-written and is the only source — flat shapes, no
embedded raster, so it stays legible down to 16 px. Nothing needs rasterising:
GNOME (and every GTK/Qt desktop) renders the SVG at whatever size it wants. If
some environment does need PNGs:

```bash
for s in 16 24 32 48 64 128 256; do
  rsvg-convert -w $s -h $s assets/bedit.svg \
    -o ~/.local/share/icons/hicolor/${s}x${s}/apps/bedit.png
done
```
