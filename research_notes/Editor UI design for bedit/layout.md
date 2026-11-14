# Layout theory: placing a cell grid in a pixel window, and anchoring editor chrome

Context for the report writer: bedit paints one uniform monospace cell grid (rows x columns)
into a native window, with a header line on row 0, panes with mode lines, and an echo area on
the last row, plus a 6 px inset. Brood's current rule (brood `docs/decisions/adr-500-599.md`,
ADR-508 and its three 2026-11-02 addenda, read locally) is: edge bands bleed their colour into
the margin, the vertical remainder is split half above row 0 and half below the last row, the
horizontal remainder stays on the right. The gap-above-header and gap-under-echo-area bugs both
came from that "where does the remainder go" decision.

There are two families of answer in the wild. Terminals have one uniform grid and treat the
remainder as padding (top-left anchor, or centred/balanced). Editors that have chrome (Emacs in
pixelwise mode, VS Code) lay out fixed-height bands anchored to the window edges and let the
scrollable text viewport absorb the remainder as a partially visible last line.

## 1. GNU Emacs: frame-resize-pixelwise, window-resize-pixelwise, internal border, partial lines, where leftover pixels go

### Takeaway
By default Emacs tries to keep the frame's text area a whole number of character cells and asks
the WM for character-sized increments. When the size is forced anyway (tiling WM, maximise) or
`frame-resize-pixelwise` is t, the extra pixels go to a window's body as a partially visible
bottom line. The minibuffer/echo area and every mode line keep their whole-line heights and are
anchored to the bottom of their own window or frame. The internal border is painted in the
`internal-border` face's background, so it is never an unpainted gap. A known wart: the extra
pixels land "in the middle of the layout" (in one window, just above its mode line). Users have
asked for an xterm-style "blank strip at the bottom" option instead, and no outcome is recorded.

### Cited Findings
- With `frame-resize-pixelwise` nil (the default), "a frame's text pixel size is usually rounded to a multiple of the current values of that frame's frame-char-height and frame-char-width whenever the frame is resized." If it is non-nil, "no rounding occurs, hence frame sizes can increase/decrease by one pixel." Setting it "usually causes the next resize operation to pass the corresponding size hints to the window manager", and "Dragging the external border with the mouse is done character-wise provided the window manager is willing to process the corresponding size hints." — [Emacs Lisp manual, frames.texi (Frame Size)](https://raw.githubusercontent.com/emacs-mirror/emacs/master/doc/lispref/frames.texi)
- "Emacs tries by default to make the text size of a frame measured in pixels a multiple of the frame's character size". When the text area is not a multiple, the reported lines/columns "are rounded down to the number of characters of the default font that fully fit into the text area." — [frames.texi](https://raw.githubusercontent.com/emacs-mirror/emacs/master/doc/lispref/frames.texi)
- Frame anatomy: native frame ⊃ inner frame ("the rectangle reserved for the frame's windows"), which is "subdivided into the frame's root window ... and the frame's minibuffer window". The internal border is "The width in pixels of the frame's internal border", coloured by the `internal-border` face's background. — [frames.texi](https://raw.githubusercontent.com/emacs-mirror/emacs/master/doc/lispref/frames.texi)
- `frame-inhibit-implied-resize`: when nil, changing the font, menu/tool bar, internal borders, fringes or scroll bars "may resize its outer frame". When t, Emacs won't do that once it has agreed on the initial size with the WM. — [frames.texi](https://raw.githubusercontent.com/emacs-mirror/emacs/master/doc/lispref/frames.texi)
- `window-resize-pixelwise`: "If the value of this option is non-nil, Emacs resizes windows in units of pixels". Even when it is nil, "at least one window may get resized pixelwise" if the frame's pixel size is not a multiple of its character size. That one window is where the remainder lives. — [Emacs Lisp manual, windows.texi](https://raw.githubusercontent.com/emacs-mirror/emacs/master/doc/lispref/windows.texi)
- "If a window's pixel height is not an integral multiple of its frame's default character height, the number of lines occupied by the window is rounded internally". Two windows of the same pixel height may differ by one line, and child sizes always sum to the parent's. When splitting with an odd line, "it is allocated to the new window." — [windows.texi](https://raw.githubusercontent.com/emacs-mirror/emacs/master/doc/lispref/windows.texi)
- A partial bottom line is a first-class state: `window-body-height` (non-pixelwise) does not count it: "if a line at the bottom of the text area is only partially visible, that line is not counted." The header line and tab line sit at the top of the window, and the mode line is a bottom decoration of the window, so the partial line sits between the text and the mode line. — [windows.texi](https://raw.githubusercontent.com/emacs-mirror/emacs/master/doc/lispref/windows.texi)
- Bug#19990 (2015): under a tiling WM that ignored size hints, the minibuffer sat above an unpainted margin at the bottom of the frame. Martin Rudalics' fix was `frame-resize-pixelwise` t, which hands the pixels to the windows instead. — [bug-gnu-emacs 2015-03](https://lists.gnu.org/archive/html/bug-gnu-emacs/2015-03/msg00102.html); [yhetil thread](https://yhetil.org/emacs/54F9718B.8070409@gmx.at/t)
- emacs-devel, Feb 2024 (Gergely Riskó, Emacs 29.1 Lucid under i3): when the WM forces a height, "Emacs just assigns the extra pixels in the middle of the layout to one of the windows", giving a half-displayed line. The proposed `frame-resize-force-char-height` would "skip rem number of pixels right on top (or bottom) of the frame", filled with the background, which is "the behavior of xterm and urxvt (with the extra pixel lines being allocated to the bottom of the x11 window)". The only reply in the archive is Eli Zaretskii's "Po Lu, any comments or suggestions?". — [emacs-devel msg00428](https://lists.gnu.org/r/emacs-devel/2024-02/msg00428.html); [msg00531](https://lists.gnu.org/r/emacs-devel/2024-02/msg00531.html)
- The pixelwise option exists so that WM resize requests are honoured pixel by pixel instead of rounded to whole cells. — [yhetil design thread](https://yhetil.org/emacs/517A2FCE.30006@gmx.at/T)

### Inferences
- Emacs's model is "edge-anchored chrome plus a flexible text body". The minibuffer is pinned to the bottom of the inner frame, and each mode line to the bottom of its window. Leftover pixels become a partial text line inside a window body, never a gap under the echo area and never a gap above the header line (the header line is the first thing in the window's text area, flush against the internal border).
- The pixels go to a window's body, not to a fixed edge. Users notice this mainly as a half line in some window. It is a cosmetic wart Emacs accepts, and it is far less visible than a blank strip under the minibuffer.

### Gaps
- I did not find the xdisp.c/window.c source comment naming exactly which window gets the remainder (it appears to be the window resized last or the last child, per `window--resize-*` in window.el). Not verified.
- Outcome of the 2024 `frame-resize-force-char-height` proposal: no follow-up found.

## 2. Terminals: Ghostty, kitty, WezTerm, Alacritty, foot (plus xterm/urxvt)

### Takeaway
Every terminal treats the remainder as padding around one uniform grid and offers two
placements: top-left anchored (remainder at right and bottom) or centred/balanced. Ghostty adds
a refinement: balanced, but the top is capped and the excess pushed to the bottom, because
lots of space above row 0 "looks bad". It also has `window-padding-color = extend`, which bleeds
the edge cell's colour into the padding. Several projects found that centring makes resizing
look jittery. Most offer resize-in-cell-steps, which only helps floating windows.

### Cited Findings
- **Ghostty** `window-padding-balance`: "The viewport dimensions are usually not perfectly divisible by the cell size." If `true`, "this extra padding is automatically balanced between all four edges", applied after the explicit padding. If `false`, the top-left cell "will always hug the edge with zero padding" and the leftover goes to the bottom/right. — [Ghostty config reference](https://ghostty.org/docs/config/reference)
- Ghostty source (`Size.balancePadding`): leftover is split evenly left/right and top/bottom (each half rounded down). In `.true` mode: "Cap the top padding to avoid excessive space above the first row. The maximum is the balanced explicit horizontal padding plus half a cell width. Any excess is shifted to the bottom." (`max_top = (explicit.left + explicit.right + cell.width) / 2`). An `.equal` mode keeps the exact centring. — [ghostty src/renderer/size.zig](https://raw.githubusercontent.com/ghostty-org/ghostty/main/src/renderer/size.zig)
- Ghostty history (mirrored commits, 2023–2025): balance was turned off by default because resizing "was too jittery". Top padding was capped because a lot of top padding looks bad. Mouse selection ignores the balance offset. — [mirror commit search results](https://git.uoc.run.place/Applied-Software/ghostty/commit/c515cb9b5f440db47527cedb0b2e92a3b1da8552) (mirror, not upstream; treat the commit wording as secondary)
- Ghostty `window-padding-color`: `background`, `extend` ("extends the color of the nearest grid cell"), or `extend-always`. Under `extend`, for primary-screen apps the colour is not extended vertically if the nearest row has default-background cells, is a prompt row, or has a perfect-fit Powerline glyph. `window-step-resize` resizes "in discrete increments of the focused surface's cell size", macOS only. — [Ghostty config reference](https://ghostty.org/docs/config/reference)
- **kitty** `placement_strategy`: "When the window size is not an exact multiple of the cell size ... thin strips of compensatory padding are added at the window edges. `center` means the cell area will be placed centrally. `top-left` means the padding will be only at the bottom and right edges." The padding is "inside the window border, so that the borders of neighboring windows line up." Also has `window_margin_width` (outside the border), `window_padding_width` / `single_window_padding_width` (pts, "always drawn using the background color"), and `resize_in_steps`. — [kitty.conf docs](https://sw.kovidgoyal.net/kitty/conf/)
- kitty discussion: perfect alignment like Zellij's is impossible within a pixel window. Zellij gets it "by basically wasting a full cell on borders", and in kitty the extra space still exists, `placement_strategy` only distributes it. — [kitty discussion #8512 (mirror)](https://github-users.yhajoa.workers.dev/kovidgoyal/kitty/discussions/8512); [discussion #3412](https://www.Github.com/kovidgoyal/kitty/discussions/3412)
- **Alacritty**: `window.padding` "is always added at both opposing sides". `dynamic_padding`: "Spread additional padding evenly around the terminal content". `resize_increments`: "Prefer resizing window by discrete steps equal to cell dimensions" (macOS, X11, Wayland). — [Alacritty config](https://alacritty.org/config-alacritty.html)
- Alacritty source: `lines = (height - 2*padding_y) / cell_height`, and with dynamic padding `padding + ((dimension - 2*padding) % cell_dimension) / 2`, floored. Cell sizes are floored to whole pixels. Dynamic padding is disabled when fixed dimensions are configured. — [alacritty display/mod.rs](https://raw.githubusercontent.com/alacritty/alacritty/master/alacritty/src/display/mod.rs)
- **foot** `pad`: "When no centering is specified, the grid content is anchored to the top left corner. I.e. if the window manager forces an odd window size on foot, the additional pixels will be added to the right and bottom sides. If center is specified, the grid content is instead centered. This may cause 'jumpiness' when resizing the window." The default is `0x0 center-when-maximized-and-fullscreen`: top-left while floating (where size is constrained to cells anyway), centred only when the compositor dictates the size. `resize-by-cells` (default yes) constrains floating windows only: "Sizes of maximized, tiled or fullscreen windows will not be constrained". — [foot.ini(5)](https://codeberg.org/dnkl/foot/raw/branch/master/doc/foot.ini.5.scd)
- **WezTerm** `window_padding`: units px, `pt`, `cell` (fractional allowed, e.g. `"0.5cell"`) and `%`. Defaults are now `1cell` left/right and `0.5cell` top/bottom (previously 0). The page does not say where the remainder goes. — [WezTerm window_padding](https://wezterm.org/config/lua/config/window_padding.html)
- **xterm/urxvt** put the extra pixel lines at the bottom of the window, in the background colour. — [emacs-devel msg00428](https://lists.gnu.org/r/emacs-devel/2024-02/msg00428.html)

### Inferences
- The consensus default for a terminal is top-left anchoring, which is stable under resize and zoom. Centring is offered for the maximised/fullscreen/tiled case, where the compositor fixes the size and nothing will ever line up (foot's default formalises exactly this).
- A terminal has no chrome, so "padding at the bottom" is harmless there. bedit's echo area on the last row turns that same strip into a visible gap under chrome, which is the bug the user hit. Terminal policies don't transfer directly to an editor with a bottom-anchored band.
- Ghostty's top cap reflects the same perception bedit ran into (space above the first row reads as a gap). Their `extend` heuristics show that bleeding the edge row's colour is the accepted way to make leftover padding read as part of the content.

### Gaps
- I could not read WezTerm's remainder placement from docs (likely top-left plus padding; unverified).
- No upstream Ghostty issue text was fetched directly. The balance and top-cap rationale comes from mirrored commits and source comments.

## 3. GUI code editors: VS Code/Monaco, Zed, Sublime, Neovim GUIs, Helix, JetBrains

### Takeaway
Pixel-native editors (VS Code, and by the same architecture Zed, Sublime, JetBrains) never
quantise the window to a cell grid. Chrome bands have fixed pixel heights anchored to the edges
(VS Code's status bar is a constant 22 px), and the text viewport takes the rest, showing a
partial last line and scrolling by pixels. Neovim GUIs, which receive a cell grid from nvim,
behave like terminals: the leftover goes to the bottom/right, and users report it as a gap of up
to one font-height.

### Cited Findings
- VS Code's status bar: `static readonly HEIGHT = 22;` with `minimumHeight` and `maximumHeight` both `HEIGHT + floatingBottomPadding`, so it is a fixed-height band and the editor area absorbs all remaining height. — [vscode statusbarPart.ts](https://raw.githubusercontent.com/microsoft/vscode/main/src/vs/workbench/browser/parts/statusbar/statusbarPart.ts)
- Monaco needs an explicit container height and scrolls inside it. `scrollBeyondLastLine` controls whether you can scroll past the last line (so the end of the document can sit at the top), which implies the viewport is not cell-quantised. — [monaco-editor discussion #3677](https://github.com/microsoft/monaco-editor/discussions/3677)
- **Neovide**: issue #140 reports "up to one font-height block of unused grid space" at the bottom, and setting top padding left extra empty space at the bottom. Window padding (`g:neovide_padding_{top,right,bottom,left}`) was merged in late 2022. The maintainer had earlier resisted it as complexity "for a niche use case". — [neovide#140](https://github.com/neovide/neovide/issues/140)
- Neovide's renderer has `MAX_TRAILING_FILL_CELLS = 1.0`, capping how far a line's background is stretched into trailing space while the grid lags a resize. — [neovide 0.16.1 rendered_window.rs](https://docs.rs/crate/neovide/0.16.1/source/src/renderer/rendered_window.rs)

### Inferences
- Helix (and Neovim/Vim in a terminal) inherits the terminal's grid. Its statusline and command line are simply the last grid rows, and the terminal's padding policy decides the leftover. So Helix-in-Ghostty with balance on puts a strip under the command line. This follows from the terminal docs above and was not separately sourced.
- Zed (GPUI), Sublime and JetBrains are pixel-layout UIs like VS Code (flex/pixel layout, smooth scrolling, a partial last line). I did not fetch primary sources for their specific leftover handling, so treat this as architectural inference.

### Gaps
- No primary source fetched for Zed/GPUI, Sublime, JetBrains or nvim-qt leftover handling.
- Monaco's exact "partial last line" rendering is not quoted from its source.

## 4. Principles: edge-anchored bands vs flexible viewport, pixel snapping, per-region vs global grid, resize increments

### Takeaway
The model that fits an editor with fixed chrome and scrollable text is Emacs's and VS Code's:
chrome bands (header line, mode lines, echo area) have whole-row heights and are anchored to the
edges they belong to (header to the top of its pane, mode line to the bottom of its pane, echo
area to the bottom of the frame). The remainder belongs to the flexible region, the text
viewport, as a partial row. Snapping to whole rows should only be requested through resize
increments, which are hints: X11 WMs may ignore them, Wayland's xdg-shell does not reliably
honour them, and maximised/tiled/fullscreen sizes are never constrained. So the layout must be
correct for arbitrary pixel sizes. Margins never show empty window: whatever pixels remain are
painted by the adjacent band (Emacs's internal-border face, Ghostty's `extend`).

### Cited Findings
- ICCCM WM_NORMAL_HINTS: base and increment values "define an arithmetic progression of preferred window widths and heights": `width = base_width + (i × width_inc)`, `height = base_height + (j × height_inc)`. WMs are only "encouraged" to report sizes in i/j. There is no obligation to honour them. — [ICCCM](https://xorg.freedesktop.org/archive/X11R7.6/doc/xorg-docs/specs/ICCCM/icccm.html)
- Wayland: a wayland-protocols MR proposes a client-set size increment but says clients shouldn't rely on the compositor honouring it. The xdg-shell configure size is a maximum that cell-sized clients may undershoot. GNOME bugs show increments leaving tiled/maximised terminals not filling their area, and a maximise/restore cycle shrinking a terminal from 80x25 to 32x3 when constraints were reapplied. — [wayland-protocols MR 126](https://gitlab.freedesktop.org/wayland/wayland-protocols/-/merge_requests/126/diffs); [GNOME bug 755947](https://bugzilla.gnome.org/show_bug.cgi?id=755947); [GNOME bug 777072](https://bugzilla.gnome.org/show_bug.cgi?id=777072) (summarised via search snippets; MR page was behind bot protection)
- foot applies cell constraints to floating windows only, and Ghostty's `window-step-resize` is macOS-only. Increments are a floating-window nicety, not a layout guarantee. — [foot.ini(5)](https://codeberg.org/dnkl/foot/raw/branch/master/doc/foot.ini.5.scd); [Ghostty reference](https://ghostty.org/docs/config/reference)
- macOS `NSWindow.contentResizeIncrements` exists as the AppKit equivalent. The doc page did not render, so its exact semantics are unverified. — [Apple docs](https://developer.apple.com/documentation/appkit/nswindow/contentresizeincrements)
- Pixel snapping: Alacritty floors cell width/height and padding to whole pixels, so every row starts on an integer pixel and an odd remainder pixel is dropped rather than straddled. — [alacritty display/mod.rs](https://raw.githubusercontent.com/alacritty/alacritty/master/alacritty/src/display/mod.rs)
- Emacs keeps sizes consistent by rounding windows to lines internally while letting one window absorb pixels, and child heights always sum to the parent. Per-window line grids with a frame-level pixel budget, not one global row grid. — [windows.texi](https://raw.githubusercontent.com/emacs-mirror/emacs/master/doc/lispref/windows.texi)
- Brood ADR-508 (local): the first addendum (2026-11-02) let one-row bands bleed sideways only. The second split the vertical remainder above row 0 and below the last row, which "gives up row 0 staying put across font sizes". The third let a one-row band on an edge row bleed vertically again, because the strip above the header "read as a gap above the filename". — brood `docs/decisions/adr-500-599.md` (local file, ADR-508)

### Inferences (the recommended "correct" model for bedit)
- **A terminal policy is the wrong model for bedit.** Top-left, balanced and centred all put some remainder next to chrome. Top-left leaves a strip under the echo area. Balanced or centred puts a strip above the header and below the echo area, and moves every row on resize or zoom (the "jitter" Ghostty and foot cite). bedit's history shows both failures in turn.
- **The editor model:**
  1. Frame = inset + content. The inset is a fixed pixel margin on all sides, painted by the adjacent band (already ADR-508's bleed).
  2. Within content, bands are laid out from the edges inward in whole rows. The header line starts at the content top (y = inset), and the echo area ends at the content bottom (y = height − inset). Each pane's mode line ends at the bottom of its pane.
  3. Leftover pixels (content height mod row height) go to a text viewport's body as a partial line. Emacs picks one window. A principled choice is the bottom-most pane in the column, or the pane that already takes split remainders. This is pixel-free for chrome: nothing ever floats between a band and an edge.
  4. Consequently the grid is not global. Rows above the remainder sit at `inset + k*row`, and rows below it (the mode line of the absorbing pane, panes under it, the echo area) sit at `height − inset − m*row`. Each region is internally uniform, with one discontinuity hidden inside a text body. Hit-testing must map y→row per region, not by one division (Emacs does the same with per-window line maps).
  5. Every row start must be an integer pixel (floor cell metrics as Alacritty does), so a row-aligned region from the bottom stays crisp.
- **Alternative if bedit must keep one uniform grid** (a simpler renderer): anchor the grid's last row (the echo area) to the bottom content edge and put the whole remainder at the top, painted by the header line's band (header text bottom-aligned, or vertically centred in a band row+remainder tall). This is equivalent to giving the header line a variable height. It keeps both edges flush. The cost is that row 0's text moves with zoom, the same cost ADR-508's split already pays. Ghostty's cap on the top shows that an empty top strip looks bad, but a strip that is header-coloured is just a taller header.
- **Resize increments:** set X11 size hints / macOS `contentResizeIncrements` (base = 2×inset, inc = cell) as a nicety for floating windows. Never rely on them: tiling, maximised and Wayland sizes are arbitrary, so the layout above must hold at every pixel size. Test it as a property over heights h..h+row (as the existing guard `the_vertical_remainder_is_split_above_and_below_at_every_size` does), asserting the header touches the top inset and the echo area touches the bottom inset.

### Gaps
- No dedicated design essay on "editor chrome vs terminal padding" was found. The comparison above is synthesised from docs, source and issue threads.
- Wayland's increment protocol status (merged or not, which compositors honour it) is unconfirmed. The MR page was blocked by bot protection.
