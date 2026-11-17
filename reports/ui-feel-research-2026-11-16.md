# Making bedit feel as slick as Ptyxis/VTE: research, 2026-11-16

The reference is this desktop: GNOME 50.1 Wayland, Ptyxis 50.1 on VTE 0.84 / GTK 4.22, three
1080p monitors at scale 1 (60, 60 and 144 Hz), `font-rendering 'automatic'`, key repeat 500 ms /
30 ms. bedit runs Hack 16 px, Modus Vivendi Tinted, fullscreen, on the installed nest, which is a
`gui-gpu` build: it draws with wgpu (MAILBOX, frame latency 1) unless `BROOD_GUI_GPU=0`.

Three tracks were run: the Rust window host (read-only audit), the Lisp turn (measured headless,
`BROOD_CONTRACTS=0`), and VTE/GTK/fast-terminal techniques (web plus GTK/VTE/Ptyxis sources).
Every number marked *measured* came from a run; the rest is read in code or sourced.

## The verdict

The window host is already in good shape: the key path is two thread hops with no sleeps or polls,
input is coalesced, held keys can't build a backlog, the GPU path caches runs and uploads only
changed bytes, the CPU path diffs rows, copies scrolled rows and presents with damage.
What separates bedit from Ptyxis is, in order:

1. **The Lisp turn is 2 frames, with 40-50 ms spikes.** *Measured* press→frame with an LSP up:
   p50 13.5-15.4 ms, p90 ~19, p99 32-38, max 50.5. The key itself is ~6 ms (update ~3 + view ~3),
   a fixed floor that hardly depends on grid size. The tail is background work done in one piece
   on the loop: `[:lsp-semantic-tokens]` folds at **42 ms mean, 45.6 max, 73 at startup**, the
   idle beat up to 19 ms, idle-continue slices up to 14.5 ms, GC pauses 1.5-5 ms (11 ms once).
   A key that lands during one waits for all of it. At 144 Hz a frame is 6.9 ms; Ptyxis paints
   in the next frame-clock tick.
2. **Text looks different, because bedit does what GTK no longer does.** GTK 4.22 with
   `font-rendering automatic` (yours) hard-codes grayscale antialiasing, slight (vertical-only)
   hinting, no metric hinting, glyph y snapped to whole pixels, and sRGB (non-linear) blending
   (`gtk/gtkwidget.c` at 4.22.0; GSK has no component alpha at all, blog.gtk.org 2024-03-07).
   bedit: LCD subpixel RGB at scale 1 (`render.rs:25-38`), swash full TrueType bytecode hinting
   in both axes (`render.rs:1388`), linear-light hue mixing with a γ 1.4 contrast lift for light
   text on dark (`backend.rs:203`, `ink.rs:140-163`). Nothing reads fontconfig/portal
   antialias/hint/rgba settings. Also a different font and size (Ptyxis: Ubuntu Sans Mono 11 ≈
   14.7 px; bedit: Hack 16) and looser lines (line height 1.25 → 20 px cell vs VTE's font
   ascent+descent ≈ 19 px).
3. **Scrolling motion is paced by fixed timers, not the display.** Kinetic tick 12 ms (~83 Hz,
   `event_loop.rs:1080`), particles 16 ms, bedit's scroll settle "16 ms frames"
   (`scroll.blsp:48`). On 60 Hz that beats into 1-or-2 steps per frame (judder); on 144 Hz it is
   capped at 83. The mouse wheel jumps 3 lines per notch: bedit never asks for `{:wheel :glide}`.
   Any whole-line scroll rebuilds every row in Lisp (~280 new ops, +1.7 ms view) because ops are
   addressed by absolute screen row.
4. **Resize shows the old layout for a frame and reconfigures the swapchain per configure.**
   `Resized` repaints the stale frame at the new size, the laid-out frame follows a turn later
   (`event_loop.rs:497-507`); `surface.configure` on every size (`gpu.rs:247-260`); `[:resize]`
   sent even when cols/rows are unchanged, on the normal lane. GTK paints the configured size in
   the same frame-clock cycle and acks after paint.
5. **Small things that read as "not native":** cursor blink not VTE's (VTE: phase =
   cursor-blink-time/2 = 600 ms, every keypress restarts it visible, stops after
   cursor-blink-timeout = 10 s on the visible phase, only while focused, from the portal
   settings); first glyph missing from the font scans every installed font inside the paint on
   the GUI thread (a one-time freeze, unmeasured, `fonts.rs:409-450`); sctk-adwaita decorations
   with an unhinted ab_glyph title (hidden here by `:fullscreen true`); no frame-callback pacing
   (`pre_present_notify` is never called), so paints don't follow Mutter's clock.

## How VTE gets its feel (the techniques worth copying)

- **Paint immediately when idle, pace only bursts.** GDK's frame clock adds the paint idle at
  zero delay unless the predicted next frame is in the future, then freezes the surface until the
  `wl_surface.frame` callback. VTE (0.76+, GNOME 46) parses PTY input inside a tick callback with
  a time budget and paints in the same frame; that change (from a ~40 Hz timer) is what made
  GNOME 46 terminals "roughly on par with Alacritty" in a hardware-measured test (bxt.rs, Apr
  2024). Mutter runs one frame clock per monitor, so on the 144 Hz screen the worst wait is 6.9 ms.
- **Work proportional to change.** GSK diffs render nodes for damage; foot redraws only dirty
  cells and scrolls with one memmove; glyphs in a GPU atlas keyed by (font, glyph, scale, ¼-px
  x bin), y snapped.
- **Text:** grayscale, light autohinter, sRGB blending, integer cell metrics; drawn at cell
  origins.
- **Scrolling:** pixel-precise + kinetic from GtkScrolledWindow; a keypress cancels the fling.
- **Resize:** draw exactly the configured size in the same cycle; pad leftover pixels with the
  background (Ptyxis also uses that padding to keep text clear of rounded corners).
- **Settings:** GTK on Wayland reads everything from `org.freedesktop.portal.Settings`
  (`org.gnome.desktop.interface` font-rendering/antialiasing/hinting/rgba-order,
  text-scaling-factor, cursor-blink*, `org.freedesktop.appearance` color-scheme, contrast,
  reduced-motion) and follows `SettingChanged`.

No published keypress-to-photon numbers exist for VTE 0.84 / GTK 4.20+; the GNOME 46 plots are
the best evidence. foot shows a damage-tracked CPU renderer can lead latency tests, so the GPU
path is not a requirement, only a help for full-screen motion.

## Plan, part 1: what Brood should gain

Each is a capability with a caller besides bedit.

1. **A non-consuming input-pending check and a cooperative yield for long folds**
   (Emacs's `input-pending-p`/`while-no-input`). Lets any `ui-run` program cut background work
   when a key arrives. Callers: the observer, the REPL, any ui-run app. Today only the quit key
   interrupts (ADR-491) and `display-poll-input` consumes.
2. **Row-relative rendering: a piece placed at a row offset.** Ops are absolute rows, so a
   piece can't be moved, only rebuilt; memo keys are screen rows. With a translate/offset op,
   line pieces key by content and survive a scroll, the host can blit them, and a sub-row scroll
   offset can stay a blit on the CPU path too. Callers: every scrolling list in a ui-run app
   (observer, REPL output).
3. **Spans that shift on an edit in O(log n).** `std/editor/span-properties` is a vector,
   shifted O(n) per edit (1.9 ms per key at 12k spans, measured). Callers: the buffer server and
   std highlight, not only bedit's semantic spans.
4. **Host: pace with the display.** Call `pre_present_notify` and drive animation (kinetic
   coast, glide, particles, and a frame tick the Lisp side can subscribe to instead of 16 ms
   timers) from frame callbacks / `MonitorHandle::refresh_rate_millihertz`. Keep the
   paint-at-once-when-idle behaviour; measure against today's MAILBOX baseline, since frame
   pacing can add latency.
5. **Host: text that follows the desktop.** Read the portal settings (and fontconfig as the
   fallback): font-rendering, antialiasing, hinting, rgba order, text-scaling-factor, default
   monospace font. Add a light hint mode (vertical-only: skrifa's autohinter in light mode or a
   FreeType `LOAD_TARGET_LIGHT` path; swash has no light mode), a grayscale default when GNOME is
   `automatic`, an sRGB blend option, and γ 1.0 as the default when matching GTK. Round baselines
   to whole pixels. Also: portal `color-scheme`/`reduced-motion`/`contrast`, and the cursor blink
   settings exposed to the program.
6. **Host: resize.** Reconfigure the swapchain at most once per paint; send `[:resize]` only
   when cols/rows change, on the priority lane; hold the commit for the re-laid-out frame with a
   short timeout so a configure is answered by the right layout.
7. **Host: font fallback index off the GUI thread** at startup; draw the hex box until it is
   ready instead of freezing in the paint.
8. **Host smaller items:** redraw a GPU frame skipped on Timeout/Occluded (`event_loop.rs:986-997`);
   bound the glyph cache; fix the stale "GPU is opt-in" comment (`window_build.rs:8-12`).
9. **GC on the loop process** (1.5-5 ms, once 11 ms): look at what brood's GC offers for a
   process holding a large model (incremental or generational for that heap) — not yet researched.

## Plan, part 2: what bedit will do

In order of felt effect:

1. **Get semantic tokens off the loop.** Decode and build spans in the LSP connection/task
   process, stamp only the result on the buffer; or request the visible range. Removes the
   40-73 ms spikes.
2. **Stop shifting semantic spans per key** (lazy, visible window only, or on the next fold),
   then move to brood's O(log n) spans (part 1, item 3).
3. **Cap the idle beat and continuation slices at ~2 ms**, and use the input-pending check
   (part 1, item 1) to stop early.
4. **Cut the ~3 ms fixed floor:** `ed-sync-timers` only for timers whose inputs changed (~20%
   of update); resolve buffer settings once per turn (~10%); turnprofile's per-hook timing on
   demand only (~10%); cheaper pane memo dependencies; gutter/cursor/layers in the view
   still run on a memo hit.
5. **Spans stage:** less re-lexing per typed character (1 ms), pre-lex the next screen for C-v
   (3.3 ms).
6. **Cursor blink like VTE** from the portal settings: 600 ms phases, restart visible on every
   key, stop after 10 s, only when focused.
7. **Scrolling:** `{:wheel :glide}` by default; settle animation on the host's frame tick
   (part 1, item 4); a key cancels a coast; content-keyed line pieces (part 1, item 2).
8. **Defaults that match the desktop:** font and size from the desktop's monospace font when
   init.blsp names none; line height close to the font's own (1.25 → ~1.15-1.2, decide by
   screenshot against Ptyxis with the same font); text rendering `:desktop` by default.
9. **Measure as we go:** `BROOD_GUI_TRACE=1 BROOD_UI_TRACE=1 nest run` for `[gui-latency]
   input->present` and turn timings; `gui/latency-histogram` (shown as cmd-latency in
   M-x about); `tools/probe-typing.blsp`. Target: press→present p99 under one 144 Hz frame
   (~7 ms) from the Lisp side, no fold over 4 ms on the loop. "Present" is to the compositor;
   Mutter adds 0-1 refresh after.

## Open questions

- Is MAILBOX + immediate paint actually better or worse than frame-callback pacing on Mutter 50?
  Needs a measurement, not a guess (a light sensor rig, or `wp_presentation` feedback).
- Does Mutter 50 implement fifo-v1 / commit-timing-v1? (`wayland-info | grep -E 'fifo|commit_timing|presentation'`)
- Whether winit exposes `xdg_surface.set_window_geometry` (needed for a GTK-like shadow with
  self-drawn decorations).
- How large the first-fallback freeze really is on this machine.
- Same-font, same-size screenshot comparison of bedit and Ptyxis once the light-hint/grayscale
  mode exists.

## Sources

GTK 4.22.0 `gtk/gtkwidget.c`, `gsk/gpu/gskgpunodeprocessor.c`, `gskgpucachedglyph.c`,
`gdk/gdkframeclockidle.c`, `gdk/wayland/gdksurface-wayland.c`, `gdk/wayland/gdksettings-wayland.c`;
VTE 0.84.0 `src/scheduler.cc`, `src/vte.cc`; Ptyxis 50 `ptyxis-terminal.c`, `ptyxis-tab.c`.
blog.gtk.org/2024/03/07/on-fractional-scales-fonts-and-hinting;
discourse.gnome.org/t/terminal-and-vte-news/20030;
bxt.rs/blog/just-how-much-faster-are-the-gnome-46-terminals;
blogs.gnome.org/chergert/2023/10/03/vte-performance-improvements;
blogs.gnome.org/shell-dev/2020/07/02/splitting-up-the-frame-clock;
gitlab.gnome.org/GNOME/mutter/-/merge_requests/1762 and /1441;
gitlab.gnome.org/GNOME/vte/-/issues/334 and /2622; gitlab.gnome.org/GNOME/gtk/-/issues/3768;
codeberg.org/dnkl/foot (foot.ini(5), wiki/Performance); sw.kovidgoyal.net/kitty/performance;
pavelfatin.com/typing-with-pleasure; danluu.com/term-latency;
raphlinus.github.io/ui/graphics/gpu/2021/10/22/swapchain-frame-pacing.html;
zed.dev/blog/videogame; github.com/microsoft/terminal/pull/11623;
github.com/PolyMeilex/sctk-adwaita/pull/43;
mail.gnu.org/archive/html/emacs-diffs/2021-12/msg00103.html;
docs.rs/winit/0.30.12/winit/window/struct.Window.html.

## Round 2 (2026-11-16): measured again, and what it changed

Measured with the brood `ui-feel` nest (contracts off, as the bundle runs), bedit at bfd6e091.

| | round 1 | round 2 |
|---|---|---|
| `[:lsp-semantic-tokens]` fold | 42 ms mean, 73 at startup | 2.6 ms mean, max 4.9 |
| steady-state folds over 8 ms | several | none |
| GC in the loop, 20 s typing | 16 collections, 64 ms | 6 collections, ~29 ms |
| press→frame, live with an LSP | p50 13.5-15.4, p99 32-38 | p50 ~14, p90 16-20, p99 31-47 |
| self-insert, 80x50 (update/view) | 2.5 / 2.7 | 2.5 / 2.8 |
| C-n that scrolls (view) | 3.0-3.5 | 3.0-3.8 (~270 fresh ops) |

The spikes are gone; what remains is the key's own work, ~13 ms of CPU live (update ~6, view
~6-8), about 1.8x the same keys measured in isolation (the spans stage doubles with the
server up; ~2 ms of the update sits outside turnprofile's stages).

Fixed in round 2: `editor/layers/buffer-type-for` scanned the file patterns even with `:type`
set (~60 µs, 15 call sites a turn; brood ec455ad06); `conj` onto a vector went through a
generic fold per element (1.3 µs, 3.7x with a fast path; brood 3d380d915 — round 1's
"quadratic" reading was wrong: ADR-511 appends in place); `lsp-specs-for` 22 → 2.7 µs,
`ed-signature-due?` cheap tests first, `conventions/mode-key` memoised (bedit 25172d88).

Not reproduced: the probe's 27-29 ms first edit (a cold line cache lexing from the top) —
in an isolated run the startup turns warm it and the first key is 4.8 ms. Not changed: an
idle-time GC (`%gc-collect` is dev-only and collects the whole heap; a GC policy has to be
measured on the test machine); `%lint-allow`'s profile share (an identity call; the sampler
charges it the loop it wraps).

### Designs ready, not yet built

**Moving a rendered piece by rows: `[:translate drow dcol ops]`** (brood). A protocol op the
GUI host RESOLVES while parsing — re-emitting the inner ops at absolute rows, with a cache by
(fragment key, drow, dcol) so an unmoved row keeps last frame's `Arc` and a moved one is built
natively without re-parsing — so no painter, damage tracker, GPU replay, bleed or hit test
changes. A display that does not say `:translate? true` (the terminal, served thin clients, the
web app, an older client) gets the ops resolved by `%ui-harvest` while it flattens.
`(ui-memo-at key deps row col thunk)` returns `[[:translate row col [marker]]]` in a loop and
absolute ops outside one. Rejected: generalising `scroll-region` (its inner offset replaces the
outer one, it shifts pixels across the seam, its damage band is the whole frame). bedit then
keys row pieces `[:line pane-x pane-y line from]` (pane origin, not row: a key used twice in a
frame is never cached) and later splits the gutter per line; the row facts (`ed-row-facts-at`,
keyed by `top`) want a per-line memo next. Expected: C-n at the edge rebuilds one row, a wheel
notch three; half to two thirds of the +1.6 ms scroll cost.

**A span index with O(log n) carry** (brood std, `editor/span-tree`). A persistent B+tree
(branching ~32) of RELATIVE items `[gap length value]`, each node caching its extent and count:
an insert or delete descends by extent and path-copies ~log₃₂ n nodes; clip and first-after
are O(log n + k). Brood, not Rust: it holds arbitrary values, which a Rust object would have to
trace, copy and compare like `VecStore`. `span-properties` keeps its `{key [[s e v] …]}` shape
at the boundaries and the tree inside; tested against today's vector code as an oracle on
random edits. Callers: std buffer text properties (10k spans: 16 ms for an insert at the start
today), then bedit's semantic tokens (whole file again, no window carry), the syntax span
cache and folds. Open: a canonical `=` for two trees holding the same spans.
