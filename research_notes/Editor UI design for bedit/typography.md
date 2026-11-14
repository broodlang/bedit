# Typography and text rendering for code editors

Scope: how big text should be, how much line height to use, the vertical metrics that decide where text sits in a line box, rasterisation (hinting, anti-aliasing, gamma, stem darkening, light-on-dark), ligatures, and what code typefaces say about their own design. Written for bedit: a uniform monospace cell grid painted by swash/zeno, grayscale anti-aliasing on the GPU and LCD masks on the CPU, line height 1.25, a dark Catppuccin Mocha theme.

## Font size, line height (leading) and tracking for code

### Takeaway
Editors set line height at 1.2–1.62× the font size: JetBrains 1.2, Zed "standard" 1.3, Monaco/VS Code 1.35 off macOS and 1.5 on macOS, Zed "comfortable" 1.618. Butterick recommends 120–145% for body text. bedit's 1.25 sits at the dense end of that range and is defensible. Default sizes cluster at 11–15 pt/px. No code-specific readability research backs any single number.

### Cited Findings
- Butterick: "For most text, the optimal line spacing is between 120% and 145% of the point size." Faces that look smaller at the same point size need less spacing. — [Practical Typography, Line spacing](https://practicaltypography.com/line-spacing.html)
- VS Code / Monaco compute an automatic line height (`editor.lineHeight: 0`) as `GOLDEN_LINE_HEIGHT_RATIO × fontSize`, rounded to an integer and clamped to `MINIMUM_LINE_HEIGHT = 8`. The ratio is 1.5 on macOS and 1.35 elsewhere. At 14 px that gives about 21 px on macOS and 19 px elsewhere. — [monaco-editor-core fontInfo.js](https://app.unpkg.com/monaco-editor-core@0.52.2/files/esm/vs/editor/common/config/fontInfo.js)
- An old VS Code issue shows the defaults `"editor.fontSize": 14` and `"editor.lineHeight": 0` (VS Code 1.10-era, so not confirmed current). — [Lightrun mirror of the VS Code issue](https://lightrun.com/answers/microsoft-vscode--line-height-and-font-size-are-too-large-by-default)
- Zed: `buffer_font_size` defaults to 15. `buffer_line_height` defaults to `"comfortable"`, and the other options are `"standard"` or `{ "custom": float }`, documented as "1 is compact, 2 is loose". The default font `.ZedMono` aliases Lilex. — [Zed all-settings](https://zed.dev/docs/reference/all-settings)
- Zed's line-height commit defines comfortable = 1.618 ("meant for reading") and standard = 1.3. The terminal default changed between docs revisions (comfortable, then standard). — [Zed commit #2718](https://git.secluded.site/zed/commit/415b8f01472ab50f8852516b6cb2f7c636f9e132); [Zed docs commit #16687](https://git.secluded.site/zed/commit/4e2b08b9096b131f385fa17bf03160eb87f39307)
- JetBrains IDEs: line height defaults to 1.2, which "corresponds to 120% of the point size". JetBrains Mono is the default editor font. — [IntelliJ IDEA font settings](https://www.jetbrains.com/help/idea/settings-editor-font.html); [JetBrains Mono](https://www.jetbrains.com/lp/mono/)
- kitty: `font_size` defaults to 11.0 pt. — [kitty.conf](https://sw.kovidgoyal.net/kitty/conf/)
- Ghostty: `font-size` is in points, may be fractional, and is rounded to the nearest integer pixel size. — [Ghostty config reference](https://ghostty.org/docs/config/reference)
- Monaspace's playground defaults to size 16, weight 300. — [Monaspace](https://monaspace.githubnext.com/)
- Tracking: Commit Mono's letter-spacing option changes tracking only, not glyph width. Its line-height download option comes with a warning that coding software usually sets line height. — [Commit Mono](https://commitmono.com/)
- Berkeley Mono's vendor recommends tracking "slightly tighter than the default" for text settings, and markets a "comfortable line-height". (This came through a search snippet; the vendor page was not fetched.) — [U.S. Graphics, Berkeley Mono](https://usgraphics.com/products/berkeley-mono)
- JetBrains Mono compares itself with Consolas: Consolas's slightly wider but smaller letters often need a 1 pt size increase, which makes lines longer. JetBrains Mono keeps a standard width with a larger x-height. — [JetBrains Mono](https://www.jetbrains.com/lp/mono/)
- Research: one eye-tracking study of prose (Jarosch et al. 2019; 32 participants, 112 sentences) found monospacing shortened first fixation duration and go-past time on target words. It used sentences, not code. — [Jarosch et al. 2019 (PDF)](https://ids-pub.bsz-bw.de/files/10276/Jarosch_Schlesewsky_Fuessel_Kretzschmar_Font_matters_efficient_adaptation_2019.pdf)
- Code reading involves "many vertical jumps", unlike prose reading. This is an argument for clear line separation, but the study does not compare fonts or leading. — [Shamy & Feitelson, eye tracking of code](https://www.cse.huji.ac.il/~feit/papers/EyeLines23TAP.pdf)

### Inferences
- Faces differ in x-height and therefore apparent size (JetBrains Mono's large x-height against Consolas), so line height is best expressed as a ratio of font size, re-tuned per face. 1.2–1.35 is the dense, "standard" band and 1.5–1.62 the "comfortable" one.
- Every major editor rounds the line height to whole device pixels (Monaco rounds explicitly, Ghostty selects an integer pixel size). A cell grid must do the same, or rows drift by fractions and the baseline lands on a different subpixel phase in each row.
- Tracking for monospace should stay at 0. A cell grid already fixes the advance, and fonts that offer tracking change spacing, never glyph width.

### Gaps
- No peer-reviewed study of the optimal line height or size specifically for source code was found. The numbers above are convention, Butterick's prose guidance, and vendor defaults.
- Current defaults for Sublime Text (font size, `line_padding_top/bottom`) and Emacs (`line-spacing` is nil by default, so the font's own height is used) were not verified from primary docs in this pass.
- The current VS Code default font size per platform was not confirmed from current docs.

## Vertical metrics: cell height, baseline placement, optical centring

### Takeaway
Use the OS/2 typo ascender, descender and line gap (falling back to hhea). Compute the leading as L = line-height − (A + D) and split it in half above and below (CSS half-leading). Snap the baseline to a whole pixel. Centre UI symbols and icons on the cap height or x-height band, not on the ascent/descent box, which sits visibly low.

### Cited Findings
- CSS Inline Layout 3: "Calculate the leading L as L = line-height − (A + D)". "Half the leading (its half-leading) is added above A". The effective ascent is A′ = A + L/2 and the effective descent D′ = D + L/2. L may be negative. — [CSS Inline Layout Module Level 3](https://www.w3.org/TR/css-inline-3/)
- The same spec recommends that implementations "use the metrics `sTypoAscender` and `sTypoDescender`" from OS/2, falling back to the hhea Ascent/Descent. When line-height is `normal`, the line gap can be added as half-leading, and "UAs must floor the line gap metric at zero." — [CSS Inline 3](https://www.w3.org/TR/css-inline-3/)
- `text-box-edge` / `line-fit-edge` values include `cap` (the cap-height line as the over edge), `ex` (the x-height line), `alphabetic` (the baseline as the under edge) and `text`. `text-box-trim` trims the first and last lines to those edges. The spec's own centring example treats cap height and the alphabetic baseline as the visual edges, not ascent/descent. — [CSS Inline 3](https://www.w3.org/TR/css-inline-3/)
- Platform behaviour: Apple uses hhea. Windows clips at winAscent/winDescent. Office and browsers prefer typo metrics when USE_TYPO_METRICS (fsSelection bit 7) is set. "All modern fonts should use typo metrics unless you have a very good excuse". Glyphs 3 sets the flag by default. — [Glyphs, Vertical Metrics](https://glyphsapp.com/learn/vertical-metrics)
- Google's strategy sets both line gaps to 0 "because not all apps respect them", and sets typo = hhea ascender to the highest cap diacritic and typo = hhea descender to the deepest descender. It centres all-caps with `typoAscender − capHeight = −typoDescender`, and requires the ascender-to-descender span to be at least 120% of the UPM. Under this strategy mixed-case text can look too low. — [Glyphs, Vertical Metrics](https://glyphsapp.com/learn/vertical-metrics)
- Glyphs' webfont strategy instead puts the line gap at about 10–20% of ascender + descender. — [Glyphs, Vertical Metrics](https://glyphsapp.com/learn/vertical-metrics)
- Terminals expose the cell and baseline as user adjustments, which shows the font-derived values are often not right as they come:
  - Ghostty has `adjust-cell-height` / `adjust-cell-width` (integer pixels added, or a %) and `adjust-font-baseline`, "Distance in pixels or percentage adjustment from the bottom of the cell to the text baseline". — [Ghostty config reference](https://ghostty.org/docs/config/reference)
  - kitty has `modify_font cell_height` (px, %, or pt) and `modify_font baseline`, where positive raises the glyphs and underline/strikethrough move with them, plus `underline_position`. kitty warns that shrinking cells can cause artifacts. — [kitty.conf](https://sw.kovidgoyal.net/kitty/conf/)

### Inferences
- A rule set for bedit's cell grid:
  1. A = typoAscender and D = |typoDescender| (hhea if USE_TYPO_METRICS is unset and typo looks broken). Ignore the font's line gap when an explicit line-height ratio is set, because the ratio replaces it.
  2. cell = round(size × ratio).
  3. L = cell − (A + D).
  4. baseline_from_top = round(L/2 + A).
  This matches CSS and puts mixed-case text optically slightly low, since the descender space is usually smaller than ascender plus accent space.
- Optical vs geometric centring: the box from A to D includes accent room, so geometric centring of that box puts lowercase text below centre. For centring a glyph or icon in a row, or a row in a widget, the CSS `cap`/`alphabetic` edges are the established choice. Centre caps and digits on (baseline + capHeight/2). Centre symbols that go with lowercase text (bullets, chevrons, gutter dots) on (baseline + xHeight/2), or on the midpoint between the x-height and cap height as a compromise.
- Keep the baseline adjustable (as Ghostty and kitty do), since fonts' metrics strategies vary (Google's zero gap against the webfont 10–20% gap).

### Gaps
- No published measurement was found of how far "optical centre" sits from the geometric centre for a typical monospace (for example, as a fraction of the em). This is a design convention, not a quantified standard.
- How Zed, Alacritty and WezTerm compute cell height and baseline in code was not verified in this pass.

## Rasterisation: hinting, AA, gamma, contrast, stem darkening, light-on-dark

### Takeaway
Blending coverage in gamma space makes light text on dark backgrounds look thin. macOS and Windows blend linearly and add compensation: stem darkening (macOS) or gamma plus "enhanced contrast" (DirectWrite). Modern GPU terminals and editors (Ghostty `linear-corrected`, kitty `platform`, Zed's perceptual gamma 1.8 with enhanced contrast 1.0) do linear blending plus a brightness-dependent correction. Slight (vertical-only) hinting is the modern default on Linux.

### Cited Findings
- FreeType: displays are sRGB/gamma 2.2. A pixel at 50% coverage stored as 128 looks 50% bright only at about 186. Correct rendering blends linearly and then gamma-corrects. Most X11 toolkits don't blend linearly by default; Qt5 and Skia can. "Windows and Mac OS X do it natively." — [FreeType, On slight hinting, proper text rendering, stem darkening and LCD filters](https://freetype.org/freetype2/docs/hinting/text-rendering-general.html)
- FreeType: with correct gamma handling, text (especially at small sizes) looks thinner and "frail". Stem darkening emboldens glyphs at small sizes to counter it. Mac OS X and Adobe's CFF engine do this. In FreeType it is off by default in the auto-hinter and CFF driver (described as experimental). — [FreeType text-rendering-general](https://freetype.org/freetype2/docs/hinting/text-rendering-general.html)
- FreeType: slight hinting (`FT_LOAD_TARGET_LIGHT`) snaps glyphs to the pixel grid vertically only. This keeps glyph shapes and widths, unlike full hinting, which "often produces poor results". ClearType may snap both axes depending on the font. — [FreeType text-rendering-general](https://freetype.org/freetype2/docs/hinting/text-rendering-general.html)
- FreeType: LCD subpixel rendering gives about 3× horizontal resolution at the cost of colour fringes, so it needs an LCD filter. The default filter is normalised to 256 (0x100) and colour-balanced: less fringing, slightly blurrier. — [FreeType text-rendering-general](https://freetype.org/freetype2/docs/hinting/text-rendering-general.html)
- Ghostty `alpha-blending`: `native`, `linear`, or `linear-corrected`. The default is `native` on macOS and `linear-corrected` on all other platforms (since 1.1.0). — [Ghostty config reference](https://ghostty.org/docs/config/reference)
- Ghostty's commits explain why: linear blending removes the dark fringes around text in some colour pairs, "but makes dark text look thinner and bright text look thicker". `linear-corrected` applies a brightness-based correction curve to the text alpha, "nearly or completely identical to `native`, but without any of the darkening artifacts". — [Ghostty commit, linear blending (mirror)](https://git.uoc.run.place/Applied-Software/ghostty/src/commit/e90f667b69a0a6b135d647eab5e96d208bb037af)
- Ghostty `font-thicken` / `font-thicken-strength` (0–255) work on macOS only. Ghostty renders to an alpha-only context and changes the brightness CoreText thinks it is drawing at. — [Ghostty config reference](https://ghostty.org/docs/config/reference)
- Ghostty `freetype-load-flags`: `hinting` on, `autohint` on, `light` on (light = "better preserving glyph shapes"), `force-autohint` off, `monochrome` off. — [Ghostty config reference](https://ghostty.org/docs/config/reference)
- kitty `text_composition_strategy` defaults to `platform`. Its gamma defaults to 1.0 on Linux and 1.7 on macOS, and its contrast to 0% on Linux and 30% on macOS. The gamma curve has "the full impact" on dark-on-light text, while light-on-dark is "affected very little". kitty suggests starting from `1.0 0` on a dark theme. `legacy` restores the pre-0.28 method, which makes dark-on-light thicker and light-on-dark thinner. — [kitty.conf](https://sw.kovidgoyal.net/kitty/conf/)
- kitty `text_fg_override_threshold` can enforce a minimum contrast, for example `4.5 ratio` for WCAG AA, adjusting lightness in HSLuv. Default 0 (off). — [kitty.conf](https://sw.kovidgoyal.net/kitty/conf/)
- Zed shipped "perceptual gamma / contrast correction" in stable 0.203.4, and a Linux port in 0.207.3. The code reads `ZED_FONTS_GAMMA` (default 1.8) and `ZED_FONTS_GRAYSCALE_ENHANCED_CONTRAST` (default 1.0, modelled on DirectWrite's grayscale enhanced contrast, clipped below 0). — [Zed 0.203.4](https://zed.dev/releases/stable/0.203.4); [Zed 0.207.3](https://zed.dev/releases/stable/0.207.3); [Zed commit #38862](https://git.secluded.site/zed/commit/e72021a26bf3e7e31d736eaaea89d6914149a9bf)
- Zed added a `text_rendering_mode` setting: `grayscale`, `subpixel` or `platform_default` (the default). It was documented in preview in January 2026. — [Zed docs commit #46358](https://git.secluded.site/zed/commit/b8dfc31fcd29585328655a5d2b72a215273cb4bd)
- Commit Mono recommends weight 400 for dark mode and 450 for light mode. That is a type designer compensating for polarity in the weight itself. — [Commit Mono](https://commitmono.com/)

### Inferences
- bedit's soft, thin grayscale text on Catppuccin Mocha is the textbook light-on-dark case. The established fixes, in order of how widely they are used:
  1. Blend in linear space, then apply a luminance-dependent alpha correction (Ghostty's `linear-corrected`, or DirectWrite/Zed-style gamma about 1.8 plus an enhanced-contrast term about 1.0).
  2. Stem darkening at small ppem (macOS, FreeType's CFF engine).
  3. A per-theme weight bump (Commit Mono's 400 dark / 450 light), a variable-font axis, or synthetic emboldening.

  Making these tunables, as kitty and Ghostty do, lets users match their display.
- Hinting for a cell grid: slight/vertical-only hinting, plus snapping the baseline and the x-height to whole pixels, is the consensus (FreeType, Ghostty). Full hinting distorts shapes, and no hinting blurs horizontal stems at 1× DPI.
- Subpixel AA is still worth having on the CPU path for 1× LCDs, but it needs a known subpixel order, an opaque background and an LCD filter. It cannot be used over transparency or on rotated or HiDPI displays where grayscale is enough. Zed exposing `grayscale` vs `subpixel` is the precedent for a user switch.

### Gaps
- FreeType's stem-darkening parameters (its ppem thresholds and darkening amounts) were not in the fetched doc. FreeType's `darkening-parameters` property docs would have them.
- DirectWrite's exact default gamma and enhanced-contrast values and Alacritty's current rendering approach were not verified from primary sources here.
- I found no controlled measurement of perceived weight change from gamma correction on dark themes. The evidence is vendor docs and commit messages.

## Ligatures and font features

### Takeaway
Defaults are split: kitty renders ligatures by default, and JetBrains Mono, Fira Code and Monaspace ship them. Commit Mono ships them off, and Zed leaves features unset. Butterick argues they are semantically wrong part of the time. Ligatures and texture healing both ride on `calt`, so a renderer should shape with HarfBuzz/swash features and expose per-feature toggles, including turning ligatures off under the cursor.

### Cited Findings
- Butterick: any global ligature substitution "is guaranteed to be semantically wrong part of the time". A `!=` drawn as `≠` "introduces an ambiguity that wasn't there before" with the real U+2260. — [Practical Typography, Ligatures in programming fonts: hell no](https://practicaltypography.com/ligatures-in-programming-fonts-hell-no.html)
- JetBrains Mono uses ligatures to reduce noise by merging operators, and to balance whitespace by shifting glyphs. — [JetBrains Mono](https://www.jetbrains.com/lp/mono/)
- Commit Mono includes only functional ligatures (for example `!=` → `≠`), off by default, and rejects purely aesthetic ones. — [Commit Mono](https://commitmono.com/)
- Monaspace: code ligatures are spread over stylistic sets `ss01`–`ss10`, grouped by language, plus `calt` and `liga`. Users opt in. Ligature counts per set: ss01 15, ss03 12, ss05 9, liga 7. — [Monaspace](https://monaspace.githubnext.com/)
- kitty: `disable_ligatures` defaults to `never` ("always render them"). `cursor` turns them off under the cursor; `always` turns them off everywhere. — [kitty.conf](https://sw.kovidgoyal.net/kitty/conf/)
- Ghostty: "To disable programming ligatures, use `-calt`". To turn off most ligatures, use `-calt, -liga, -dlig`. — [Ghostty config reference](https://ghostty.org/docs/config/reference)
- Zed: `buffer_font_features` defaults to null, and `"calt": false` turns ligatures off. — [Zed all-settings](https://zed.dev/docs/reference/all-settings)

### Inferences
- Disabling `calt` also disables texture healing (Monaspace) and smart kerning, which relies on contextual alternates (Commit Mono). A single "ligatures on/off" switch is too coarse; per-feature tags (`calt`, `liga`, `ss0N`, `zero`, `cv*`) are the right granularity.
- In a cell grid, a ligature has to span N cells exactly. Editing inside one needs the "off under cursor" behaviour, or cursor placement within a ligature.

### Gaps
- No usability study of ligatures' effect on code-reading speed or errors was found.

## Typefaces designed for code: published rationale

### Takeaway
The recurring design goals are a large x-height (more pixels per lowercase letter), clearly distinguished confusables (0/O, 1/l/I, comma/period), simplified, grid-fitted forms, and ways to soften monospace's uneven texture (texture healing, smart kerning). Iosevka trades width for columns.

### Cited Findings
- JetBrains Mono:
  - It maximises lowercase height so each letter covers more pixels.
  - Ovals approach rectangles, which keeps vertical scanning clear.
  - Stroke ends are cut to fit the pixel grid.
  - 1/l/I are distinct, the zero has a dot that O does not, and the comma and period have distinct shapes.
  - Its italic uses a 9° slant against the typical 11–12°.
  - The page gives no numeric x-height. — [JetBrains Mono](https://www.jetbrains.com/lp/mono/)
- Commit Mono: "anonymous and neutral" ("Special is generally less useful than normal", Jasper Morrison). Smart kerning moves a letter toward the narrower of its two neighbours by width class; its example 'o' moves 44 units. It is off by default and stays on the grid. — [Commit Mono](https://commitmono.com/)
- Monaspace (GitHub Next):
  - Texture healing swaps a narrow letter for a variant that gives up space and a wide neighbour for one that takes it, through `calt`, in multiple passes and both directions, staying on the grid.
  - Its five faces (Neon, Argon, Xenon, Radon, Krypton) share metrics so they can be mixed.
  - Its variable axes are weight 200–800, slant 0 to −11° (true italic forms below −5.5°) and width 100–125. — [Monaspace](https://monaspace.githubnext.com/)
- Iosevka is narrow by design to fit more columns and suit CJK (lineage: PragmataPro, M+, PF DIN Mono). One review puts it at roughly ⅗ the width of typical monospace and calls it cramped in a wide single pane. That is secondary commentary, not maintainer docs. — [fontalternatives.com, Iosevka](https://fontalternatives.com/fonts/iosevka/); [Pragmasevka README](https://git.tdem.in/shytikov/pragmasevka)
- Berkeley Mono's vendor stresses "distinct but not distracting glyphs" and a "comfortable line-height". — [U.S. Graphics, Berkeley Mono](https://usgraphics.com/products/berkeley-mono)
- A comparison site lists Fira Code's x-height ratio as 0.527 (secondary). — [fontalternatives, Berkeley Mono vs Fira Code](https://fontalternatives.com/compare/berkeley-mono-vs-fira-code/)
- Zed's default font is Lilex (via the `.ZedMono` alias). — [Zed all-settings](https://zed.dev/docs/reference/all-settings)

### Inferences
- A large x-height (above about 0.52 of the em) reads bigger at a given size, so code faces can run at a lower nominal size and line height than a prose face. This is consistent with editor defaults of 1.2–1.35.
- Variable weight axes (Monaspace 200–800, Commit Mono's 400/450 advice) give a principled light-on-dark compensation knob that does not depend on the rasteriser.

### Gaps
- No official numeric x-height or design notes were retrieved for Berkeley Mono (the datasheet PDF was not fetched), Iosevka (its GitHub docs) or Fira Code (its repository README).
