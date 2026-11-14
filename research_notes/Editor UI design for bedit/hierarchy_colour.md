# Visual hierarchy, colour and syntax highlighting for code editors

Context: bedit runs Catppuccin Mocha (`src/theme.blsp`). Commit 8d5aced0 (2026-11-05) already moved the header line from `{:fg text :bold true}` (plus teal bold crumbs) to `{:fg subtext :bg mantle}` with `overlay0` separators. The questions below are about how far to push that, and about the rest of the chrome.

Method note: I computed every contrast number marked "(computed)" with a shell/awk script in the scratchpad (`/tmp/claude-1000/-home-wilhelm-src-broodlang-bedit/13f19266-057f-4bfe-b467-5306babee334/scratchpad/contrast.sh`). It uses the WCAG 2.x relative-luminance formula and the APCA 0.0.98G-4g constants (exponents 0.56/0.57/0.65/0.62, scale 1.14, black clamp 0.022^1.414, low clip 0.1). APCA Lc is negative for light text on dark. I quote magnitudes. APCA clips to 0 below about Lc 7.5, so background-to-background steps show as Lc 0 and are given as WCAG ratios instead.

## Chrome vs content: how to de-emphasise header lines, tab bars, gutters, mode lines, scrollbars, borders

### Takeaway
Current editors move the chrome back with three tools, in this order:
1. **A small background step.** Chrome sits on a surface about 1.07 to 1.4:1 away from the editor background, usually darker than the editor in dark themes.
2. **Secondary foreground.** Chrome text is grey at roughly WCAG 4.5 to 7:1 (APCA Lc 35 to 55), against about 10 to 11:1 (Lc 75 to 80) for code.
3. **No borders and no bold.** Borders are hidden or made transparent. Bold and accent colour are kept for state (the active item), not for labels.

Weight is the strongest emphasis tool, so taking bold off chrome matters most.

### Cited Findings
- **VS Code Dark Modern (the default dark theme):**
  - The editor background is `#1F1F1F`. The status bar, title bar, tab strip, inactive tabs, side bar and panel all use the darker `#181818`. The active tab uses `#1F1F1F`, so it reads as part of the editor.
  - The editor foreground is `#CCCCCC`. Inactive tab text and `descriptionForeground` are `#9D9D9D`. Line numbers are `#6E7681`; the active line number is `#CCCCCC`. The tab border is `#2B2B2B` and the widget border is `#313131`. — [vscode dark_modern.json](https://raw.githubusercontent.com/microsoft/vscode/main/extensions/theme-defaults/themes/dark_modern.json)
  - Computed ratios: code text `#CCCCCC` on `#1F1F1F` is 10.26:1 / Lc 74. Chrome text `#9D9D9D` on `#181818` is 6.55:1 / Lc 48. Line numbers are 3.59:1 / Lc 28. The chrome step `#1F1F1F` vs `#181818` is only 1.08:1. (computed)
- **Zed One Dark:**
  - The editor background is `#282c33`. The status bar and title bar are lighter, at `#3b414d`. The tab bar and panel are `#2f343e`, and the active tab equals the editor (`#282c33`).
  - Line numbers are very dim (`#4e5a5f`, 1.97:1 / Lc 13). The active line number is `#d0d4da` (9.4:1 / Lc 76).
  - Text tiers: `text` `#dce0e5`, `text.muted` `#a9afbc`, `text.placeholder`/`text.disabled` `#878a98`. The editor foreground is `#acb2be` (6.58:1 / Lc 56; the code itself is fairly soft). Comments are `#5d636f` (2.32:1 / Lc 17.5).
  - Borders: `border` `#464b57`, `border.variant` `#363c46`. The current line is `#2f343e` at 75% alpha. — [zed one.json](https://raw.githubusercontent.com/zed-industries/zed/main/assets/themes/one/one.json); ratios (computed)
  - Zed's theme schema names `editor.line_number`, `editor.active_line_number`, `editor.gutter.background` and `status_bar.background` as separate tokens. — [Zed visual customization docs](https://zed.dev/docs/visual-customization)
- **JetBrains Islands (default from 2025.3):**
  - The editor and tool windows are "islands" with no visible border by design. The status bar, tool window stripe and main toolbar borders are set fully transparent (`#XXXXXX00`).
  - `MainWindow.background` should be lighter than the editor in dark themes. The recommended minimum contrast between islands and the main window is **1.20:1**.
  - Tool windows use the editor background "or a slightly lighter or darker shade". Islands have a 5px gap and a 10px corner radius. — [IntelliJ SDK: Supporting Islands theme](https://plugins.jetbrains.com/docs/intellij/supporting-islands-theme.html)
  - Stated goals are "clearer separation between the editor and tool windows" and each area getting its own visual space. There is a "Different tool window background" option. — [JetBrains blog, Dec 2025](https://blog.jetbrains.com/platform/2025/12/meet-the-islands-theme-the-new-default-look-for-jetbrains-ides/)
  - Fleet's islands UI (Dec 2024) aimed at "minimizing distractions and guiding your attention to the content within each panel". — [Fleet blog](https://blog.jetbrains.com/fleet/2024/12/introducing-fleets-new-islands-ui/) (via search summary)
- **Modus themes (Emacs):**
  - The manual's recipes make the fringe, window divider and related faces *invisible* by matching the default background, and use `internal-border-width` 20 for padding instead of lines.
  - Mode line borders are set equal to the mode line background, so that "the thick border will not stand out and will appear as a continuation of the mode line". Underline and overline borders were removed.
  - Line number recipes range from subdued (`gray50` on an unspecified background) to intense. — [Modus themes manual §9.9, §9.20, §9.4.22](https://protesilaos.com/emacs/modus-themes)
  - The "faint" preset "tones down grays, removes some gray backgrounds, and desaturates most accent colors" to be "less attention-grabbing". Bold and italic are opt-in (`modus-themes-bold-constructs` / `-italic-constructs`), "only where necessary" by default. — [Modus themes manual](https://protesilaos.com/emacs/modus-themes)
- **Catppuccin style guide roles:**
  - Background pane = Base. Secondary panes = Crust and Mantle. Surface elements = Surface 0 to 2. Overlays = Overlay 0 to 2.
  - Body copy and main headline = Text. Sub-headlines and labels = Subtext 0/1. "Subtle" = Overlay 1.
  - Line numbers = Overlay 1. Active line number = Lavender. Cursor line = Text at 10% opacity. Selection = Overlay 2 at 20 to 30% opacity. — [Catppuccin style guide](https://github.com/catppuccin/catppuccin/blob/main/docs/style-guide.md)
- **Catppuccin Mocha ladder on Base `#1e1e2e` (computed):**

  | Token | Hex | WCAG | APCA Lc |
  |---|---|---|---|
  | text | `#cdd6f4` | 11.34:1 | 80 |
  | subtext1 | `#bac2de` | 9.26:1 | 68 |
  | subtext0 | `#a6adc8` | 7.37:1 | 56 |
  | overlay2 | `#9399b2` | 5.81:1 | 45.5 |
  | overlay1 | `#7f849c` | 4.44:1 | 35 |
  | overlay0 | `#6c7086` | 3.36:1 | 26 |
  | surface2 | `#585b70` | 2.46:1 | 17 |
  | surface1 | `#45475a` | 1.80:1 | 9 |

  - On Mantle `#181825`: text is 12.14:1 / Lc 81, subtext0 7.89 / Lc 57, overlay1 4.75 / Lc 36, overlay0 3.59 / Lc 27.
  - Background steps: Mantle vs Base 1.07:1, Crust vs Base 1.14:1, Surface0 vs Base 1.30:1.

### Inferences
- **The new header line is at the "secondary chrome" tier the big editors use.** It is subtext0 on mantle (7.9:1 / Lc 57). VS Code's tab and description text is 6.55:1 / Lc 48; Zed's `text.muted` is similar. If it still reads as too present, the next notch is overlay2 (Lc about 46), matching VS Code's tier. Crumbs could stay subtext0 and the file path go to overlay2, or the reverse. Below overlay1 (Lc 35) it falls under APCA's Lc 45/60 thresholds for readable text and becomes "glanceable only".
- **Pattern to copy, in priority order:** drop bold, then drop accent hues from labels (the teal crumbs), then lower the foreground one tier, then use a background step instead of borders. The surface step can be tiny: VS Code's chrome step is 1.08:1, comparable to Mantle vs Base at 1.07:1.
- **bedit's mode line goes against the cross-editor pattern.** It is `text` on `surface0`, a *raised* surface (1.30:1) with full-brightness text. VS Code and Zed's tab strip put chrome on a darker or equal surface with grey text. Zed does use a lighter status bar, but its text there is muted. Recessing the active mode line to mantle or crust with subtext, and keeping text brightness for the active segment and state only, would match.
- **Line numbers:** bedit uses overlay0 (3.36:1 / Lc 26). That is between Zed (Lc 13) and VS Code (Lc 28), and slightly under Catppuccin's own spec (overlay1, Lc 35). Catppuccin's lavender active line number is a clean "you are here" signal; bedit could adopt it.
- **The gutter background:** bedit's gutter is mantle while the editor is base. VS Code, Zed and Modus all make the gutter the *same* background as the editor and rely on dim numbers alone. Two surfaces stacked vertically (a mantle header and a mantle gutter) form an L-shaped frame around the code. That works if it is intended, but it is extra chrome.

### Gaps
- I did not fetch Sublime Text or Nova default theme files, so I have no numbers for them.
- I found no published design rationale from Zed explaining why its status bar is lighter than the editor while VS Code's is darker.
- I could not fetch the Material 3 elevation page (it renders client-side). I could not verify the Material 2 dark-theme figures I remember: #121212 surface, 87% / 60% / 38% text emphasis, elevation overlays, and desaturated accents. The Android docs confirm only "dark grey instead of black" and that elevation overlays were "replaced... with the tonal surface color system" ([material-components-android Dark.md](https://github.com/material-components/material-components-android/blob/master/docs/theming/Dark.md)).

## Contrast: WCAG 2.x and APCA targets for body, secondary and decorative text; dark-theme text

### Takeaway
- **Code (body text):** aim for APCA Lc 75 to 90, roughly WCAG 7 to 12:1. Catppuccin text is Lc 80 / 11.3:1.
- **Chrome labels you must read:** Lc 60 is the floor for short "content text"; Lc 45 for larger or heavier text.
- **Glanceable chrome** (line numbers, placeholders, disabled items): Lc 30 is the absolute floor.
- **Dividers and discernible non-text:** Lc 15. Anything below that should be treated as invisible.

Pure white on pure black (21:1, Lc 108) is beyond what is needed. Halation is the common argument against it, but the evidence for halation is mostly anecdotal.

### Cited Findings
- **APCA levels:**
  - **Lc 90:** "Preferred level for fluent text and columns of body text."
  - **Lc 75:** "The minimum level for columns of body text."
  - **Lc 60:** "The minimum level recommended for content text that is not body, column, or block text."
  - **Lc 45:** "The minimum for larger, heavier text" (headlines; fine-detail pictograms).
  - **Lc 30:** "The absolute minimum for any text not listed above" (placeholder, disabled text, large solid icons).
  - **Lc 15:** "The absolute minimum for any non-semantic non-text that needs to be discernible" (dividers). "Designers should treat anything below this level as invisible."
  - Add Lc 15 for AAA-equivalent levels.
  - Lc 90 is a "suggested maximum" only for very large bold text (>36px bold) and large colour areas; "small fonts do not have a maximum".
  - Size guidance: Lc 90 for 14px/400 or larger. Lc 75 for 18px/400, 16px/500 or 14px/700. Lc 60 for 24px/400 or 16px/700.
  - "WCAG 2.x contrast cannot be used for guidance designing 'dark mode'." — [APCA in a Nutshell](https://git.apcacontrast.com/documentation/APCA_in_a_Nutshell.html)
- **WCAG and Modus:** Modus targets WCAG AAA 7:1 minimum for *every* foreground/background combination ("equal or higher than 7 for each combination"). Modus-vivendi uses a `#000000` background and `#ffffff` foreground, and holds that legibility admits "never... a compromise". — [Modus themes manual §9.16](https://protesilaos.com/emacs/modus-themes)
- **Solarized** "reduces brightness contrast but, unlike many low contrast colorschemes, retains contrasting hues". It argues "black text on white from a computer display is akin to reading a book in direct sunlight and tires the eye".
  - Dark body text base0 (L\* 60) sits on base03 (L\* 15), a 45 L\* gap. Highlighted backgrounds (base02, L\* 20) carry base1 (L\* 65), keeping the same 45 L\* gap "by design".
  - The tones are base03 15, base02 20, base01 45, base00 50, base0 60, base1 65, base2 92 and base3 97. Accents sit at L\* 50 to 60. — [Solarized](https://ethanschoonover.com/solarized/)
- **Halation and pure white on black:** many design blogs say pure white on pure black causes "halation" (glow or bleed), especially for people with astigmatism, and recommend off-white text such as #E0E0E0 or #D4D4D4 on dark grey. The astigmatism prevalence figures in these sources disagree (30% to 60%). I found no peer-reviewed study in the results. — e.g. [UX Planet: alternatives to pure black](https://uxplanet.org/alternatives-to-using-pure-black-000000-for-text-and-backgrounds-54ef0e733cdb); evidence quality is low.
- **Reference points (computed):**
  - Pure white on black: 21:1 / Lc 108.
  - VS Code code text: 10.3:1 / Lc 74.
  - Zed One code text: 6.6:1 / Lc 56.
  - Catppuccin Mocha text: 11.3:1 / Lc 80.
  - Catppuccin Mocha accents on Base: yellow 12.9 / Lc 88, green 11.0 / Lc 78, teal 11.0 / Lc 78, peach 9.3 / Lc 68, lavender 9.2 / Lc 67.5, mauve 8.1 / Lc 61, blue 7.8 / Lc 59, red 7.1 / Lc 55.

### Inferences
- **Suggested tier table for bedit, as APCA magnitudes on Base or Mantle:**

  | Tier | Lc | Catppuccin token | Used for |
  |---|---|---|---|
  | code | ≈80 | text | the buffer |
  | primary chrome | ≈68 | subtext1 | active state only |
  | secondary chrome | 46 to 57 | overlay2 / subtext0 | header line, mode-line labels, tabs |
  | tertiary | ≈35 | overlay1 | line numbers, inactive panes' bars |
  | decorative | 15 to 26 | surface2 / overlay0 | separators, scrollbar track, dividers |
  | invisible | <15 | surface0 / surface1 | background steps only |

- **Hue choice for highlights:** Catppuccin's mauve, blue and red sit at Lc 55 to 61, *below* the Lc 75 body floor. Yellow, green and teal are at Lc 78 to 88, *above* body text. Syntax colour in Mocha therefore changes lightness as well as hue. Keywords in mauve are already slightly quieter than plain text; strings in green and types in yellow are louder. This is relevant to Tonsky's argument below.
- **Solarized's "same L\* gap on highlighted backgrounds" rule** is a useful check for the current line, the header and the mode line. When a band raises the background (surface0), its text should rise by a similar L\* step to keep the same contrast. Alternatively, keep bands so subtle (≤1.1:1) that the difference does not matter.

### Gaps
- APCA's dark-mode-specific guidance (a polarity offset for light-on-dark) is only referenced as "a separate draft discussion". I did not locate an authoritative Lc adjustment for dark mode.
- WCAG 3 has no settled contrast algorithm as of this research. I did not verify the WCAG 3 draft's current status.

## Syntax highlighting theory

### Takeaway
The best-argued position (Tonsky/Alabaster, echoed by Hillel Wayne and the rainbow-identifier camp) is that highlighting is an information channel to spend sparingly:
- Highlight what you scan for: definitions, literals, and comments as *bright* explanations.
- Leave keywords and the bulk of references plain.
- Dim punctuation.
- Use about four colours you can memorise, no bold or italic, and vary lightness, not only hue.

The empirical evidence on whether highlighting helps comprehension is weak and contradictory. Catppuccin's default mapping is the "highlight everything" style that Tonsky criticises.

### Cited Findings
- **Tonsky, "I am sorry, but everyone is getting syntax highlighting wrong"** — [tonsky.me](https://tonsky.me/blog/syntax-highlighting/):
  - "If everything is highlighted, nothing is highlighted."
  - **Highlight:** top-level definitions (file structure at a glance), constants (strings, numbers), and variable and function *declarations*. Do not colour references or calls.
  - **Do not highlight keywords:** "Please, please don't highlight language keywords."
  - **Comments:** "should be highlighted, not hidden away." Grey is only for disabled (commented-out) code.
  - **Palette:** Alabaster uses four colours: green strings, purple constants, yellow comments, light-blue top-level definitions. Avoid red, which is reserved for errors.
  - **Punctuation:** dim it slightly so names stand out.
  - **Bold and italic:** avoid them; they dilute colour.
  - **Lightness and hue:** don't force equal lightness or evenly spaced hues. "Our eyes are way more sensitive to differences in lightness than in color."
  - **Light vs dark:** dark themes have more usable hues. Background tints work well in light themes.
- **Hillel Wayne** argues "syntax highlighting is a waste of an information channel": colour should encode something you cannot see from the text itself. — [Computer Things newsletter](https://buttondown.com/hillelwayne/archive/syntax-highlighting-is-a-waste-of-an-information) (search result title; not fetched)
- **Semantic and rainbow identifiers:** "Coding in color" (evnbr, 2014) proposed colouring *variables* by identity rather than keywords, with bright colours reserved for strings and comments. — [Medium](https://medium.com/@evnbr/coding-in-color-3a6db2743a1e). Emacs rainbow-identifiers hashes names to colours — [GitHub](https://github.com/Fanael/rainbow-identifiers). Critics report colour collisions and little productivity gain (search summary).
- **Modus:** syntax mappings are now palette overrides rather than hard-coded options (older versions offered yellow comments or green strings). Restraint is the default: bold and italic are opt-in, and there is a "faint" preset. — [Modus manual](https://protesilaos.com/emacs/modus-themes)
- **Catppuccin syntax defaults:**
  - Keyword mauve, strings green, symbols red, escapes pink, constants peach, operators sky, functions and methods blue, parameters maroon, builtins red, types yellow, enum variants teal, macros rosewater.
  - Comments *and* braces/delimiters are Overlay 2 (5.8:1 / Lc 45.5, computed).
  - "Text colors are guidelines… legibility takes priority." — [Catppuccin style guide](https://github.com/catppuccin/catppuccin/blob/main/docs/style-guide.md)
- **Empirical studies:**
  - **Hannebauer, Hesenius & Gruhn (2018, Empirical Software Engineering):** about 390 mostly first-year students. "No evidence that syntax highlighting improves novices' ability to comprehend source code"; the authors say highlighting "squanders a feedback channel".
  - **Sarkar (2015, PPIG):** 10 participants, eye tracking. Highlighting significantly improved task completion time, with the effect weakening as experience grows.
  - Hannebauer's paper notes that the recent studies (Beelders & du Plessis 2015; Sarkar 2015) found "contradicting results". — [Sarkar 2015 PDF](https://advait.org/files/sarkar_2015_syntax_colouring.pdf); [PPIG 2015](https://ppig.org/papers/2015-ppig-26th-sarkar1/); [Hannebauer et al. 2018, DOI 10.1007/s10664-017-9579-0](https://unpaywall.org/10.1007%2FS10664-017-9579-0)

### Inferences
- **For a "the code is what the eye lands on" editor, the cheapest Tonsky-aligned moves on the Mocha palette are:**
  - Comments up from Overlay 2 (or bedit's equivalent) to a readable accent, keeping commented-out code grey.
  - Keywords to plain text or near it. Mauve is already quieter than text.
  - Punctuation dimmed (overlay2), which Catppuccin already does.
  - No bold or italic on syntax.
  - A "minimal" theme variant built from the same palette rather than editing the default.
- **Brood/Lisp specifically:** keywords are few and parentheses dominate. Dimmed parentheses plus coloured top-level `defn`/`def` names gives the Alabaster effect cheaply. bedit already ships rainbow-delimiters, which pulls the other way; it should be off by default or very low-chroma if the goal is calm.
- **Because the evidence is equivocal,** frame highlighting choices as preference and scanning aids, not proven comprehension gains. Offering a restrained variant is low risk.

### Gaps
- I did not read the Beelders & du Plessis (2015) results directly.
- I found no controlled study of "minimal" vs "full" highlighting for experienced developers.

## Colour for state: current line, selection, search matches, diagnostics

### Takeaway
Encode state with **background tints at low opacity** and keep the syntax foreground; reserve saturated fills for the *one* active thing:
- Current line: about 10% text tint, roughly 1.1 to 1.3:1 above the background.
- Selection: 20 to 30% overlay tint.
- Other search matches: a muted tint. The active match: a strong fill.
- Diagnostics: a fixed hue per severity (red error, yellow/peach warning, teal info), shown as underlines and gutter marks rather than fills.

Red is reserved for errors.

### Cited Findings
- **Catppuccin:**
  - Cursor line = Text at 10% opacity. Selection background = Overlay 2 at 20 to 30% opacity.
  - Search: FG Text on BG Teal. Active search: FG Text on BG Red.
  - Diagnostics: Errors Red, Warnings Yellow/Peach, Info Teal.
  - Diff: changed text BG Blue at 10 to 20%, changed line BG Blue at 15 to 25%; inserted Green and removed Red at the same opacities.
  - Breakpoint line during execution: Yellow at 15%. — [Catppuccin style guide](https://github.com/catppuccin/catppuccin/blob/main/docs/style-guide.md)
- **Zed One Dark:** selection is `#74ade8` at about 24% alpha (`3d`). Search match is the same blue at 40% (`66`). The active line is `#2f343e` at 75%. The scrollbar thumb is `#c8ccd4` at 30% (`4c`). — [zed one.json](https://raw.githubusercontent.com/zed-industries/zed/main/assets/themes/one/one.json)
- **Tonsky:** avoid red for normal highlighting because it is "reserved for errors and squiggly lines". Background tints keep contrast while looking vibrant. — [tonsky.me](https://tonsky.me/blog/syntax-highlighting/)
- **Modus:**
  - Deuteranopia variants avoid red and green, using yellow and blue for diffs. Tritanopia variants use red and cyan.
  - Refined (word-level) diff gets a stronger background "to draw attention".
  - Modus-vivendi deuteranopia values: `bg-changed` `#363300`, `bg-changed-refine` `#4a4a00`, `bg-removed` `#4f1119`, `bg-removed-refine` `#781a1f`. — [Modus manual §9.4.23–24](https://protesilaos.com/emacs/modus-themes)
- **Tinted bands, diffs and Solarized:** tinted line backgrounds with a stronger tint on the changed words is the Catppuccin and Modus pattern for diffs. Solarized keeps text contrast constant on highlight backgrounds (base02 + base1). — [Solarized](https://ethanschoonover.com/solarized/)

### Inferences
- **What bedit does now:**
  - Current line = surface0 (1.30:1, solid).
  - Region = surface2 (2.46:1 vs base). This is much heavier than Catppuccin's 20 to 30% Overlay 2 spec.
  - isearch = base on yellow (a strong fill, fine for the active match).
  - Lazy matches = surface2.

  Region and lazy matches share surface2, so a selection and the other search matches look the same. Making the region about 25% overlay2 (≈ between surface0 and surface1) and the lazy matches a low-alpha *hue* tint (teal or yellow at 20 to 25%) would separate them without noise.
- **Current line band:** 10% Text on `#1e1e2e` is roughly `#313243`, essentially surface0. bedit matches Catppuccin here. If the band feels loud next to a quieter chrome, Zed's 75%-alpha approach or a gutter-only marker (Zed's `current_line_highlight: gutter`) are the lighter options.
- **Keep a state-hue budget:**
  - red = error (and only error)
  - yellow/peach = warning and the active match
  - teal = info and secondary matches
  - blue = selection and accent
  - green and red at low alpha = diff

  This avoids collisions with syntax hues because state uses *backgrounds* and syntax uses *foregrounds*.

### Gaps
- No quantitative guidance (e.g. minimum ΔE or APCA between selection and current-line tints) was found. The opacity ranges above are the only numbers published.

## Theme design systems: perceptual colour spaces and role tokens

### Takeaway
Build palettes in a perceptual space so that one lightness step means the same visual step across hues: OKLCH/OKLab today, CIELAB in Solarized's day. Name colours by role (surface, on-surface-variant, line-number, header-line), not by hue, so a theme swap or a "subtle chrome" pass is a token edit. Still verify contrast with APCA; a perceptual space does not guarantee contrast.

### Cited Findings
- **OKLCH vs HSL** — [Evil Martians, "OKLCH in CSS"](https://evilmartians.com/chronicles/oklch-in-css-why-quit-rgb-hsl):
  - HSL's L is "not accurate" across hues because HSL "deform[s] the color space". OKLCH gives predictable lightness, so changing only L (e.g. 0.5 to 0.6) yields a consistent step.
  - "All backgrounds with L≥87% have good contrast with black text."
  - Every hue has a different maximum chroma, and gamut clipping can shift hue.
  - It recommends APCA for checking contrast, since OKLCH alone is not enough.
- **Solarized:** the monotones are defined by symmetric CIELAB L\* steps, so "switching from dark to light mode retains the same perceived contrast". Accents were chosen on colour-wheel relations then "translated to CIELAB to ensure perceptual uniformity in terms of lightness". — [Solarized](https://ethanschoonover.com/solarized/)
- **Role-based token systems:**
  - Catppuccin's style guide is a role map: surfaces, overlays, subtext, syntax roles, diagnostics. — [Catppuccin style guide](https://github.com/catppuccin/catppuccin/blob/main/docs/style-guide.md)
  - Zed themes are role tokens: `text`, `text.muted`, `text.placeholder`, `text.disabled`, `border`, `border.variant`, `status_bar.background`, `editor.line_number`. — [zed one.json](https://raw.githubusercontent.com/zed-industries/zed/main/assets/themes/one/one.json)
  - Material components replaced elevation overlays with a "tonal surface color system". — [material-components-android Dark.md](https://github.com/material-components/material-components-android/blob/master/docs/theming/Dark.md)
- **Tonsky warns against forcing uniform lightness across syntax colours:** lightness variation is what makes hues separable. — [tonsky.me](https://tonsky.me/blog/syntax-highlighting/)

### Inferences
- **bedit already names faces by role** (`face-modeline`, `face-gutter-line`, `face-header-line` via `defchrome`). The missing layer is a small set of *text-emphasis tiers* (e.g. `:fg-code`, `:fg-chrome`, `:fg-chrome-dim`, `:fg-decor`) that chrome faces reference. "Make chrome subtler" then becomes one edit, and alternate themes (`src/themes.blsp`) get the hierarchy for free.
- **Solarized's symmetric-step idea plus APCA tiers gives a checkable rule for any theme in the registry:** code ≥ Lc 75, chrome labels Lc 45 to 60, line numbers ≈ Lc 30 to 35, dividers ≥ Lc 15, surface steps 1.07 to 1.3:1. A test could assert these per theme. bedit already has a theme registry, and contrast math is pure arithmetic.

### Gaps
- I found no editor that publishes its themes as OKLCH sources; Zed, VS Code and Catppuccin all ship hex.
- I did not find a published APCA audit of Catppuccin; the numbers here are my computation.
