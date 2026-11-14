# What makes code editors feel calm, pleasant and focused (UX, motion, minimalism)

Scope note: the research ran about 16 tool calls. Primary sources fetched in full: Pavel Fatin "Typing with pleasure", Dan Luu "Terminal latency", calmtech.com principles, the Weiser & Brown paper (calmtech.com mirror), the Neovide config docs, Zed's GPUI blog post, Prot's pulsar and spacious-padding pages, the which-key README, and VS Code issue #295648. The Apple HIG Motion and Material 3 token pages did not render through the fetcher, so their values come from secondary sources and are marked that way.

## 1. Calm technology and minimalism / focus modes

### Takeaway
Calm design means information lives in the *periphery* and moves to the *center* only when it matters, with the user choosing when that happens. For an editor, that means quiet chrome, status as ambient indicators rather than interruptions, and focus modes that recede everything but the work. Prot-style Emacs configs show the visual side of this: padding, subtle lines and fewer borders.

### Cited Findings
- Weiser & Brown (1995): "Calm technology engages both the center and the periphery of our attention", and it moves back and forth between the two — [Weiser & Brown, Designing Calm Technology](https://calmtech.com/papers/designing-calm-technology)
- "We use 'periphery' to name what we are attuned to without attending to explicitly." The periphery gives "locatedness", an effortless sense of what is going on around you — [Weiser & Brown](https://calmtech.com/papers/designing-calm-technology)
- "A properly designed ... tool will offer, but not demand." "The individual, not the environment, must be in charge of moving things from center to periphery and back." — [Weiser & Brown](https://calmtech.com/papers/designing-calm-technology)
- The Dangling String example: network traffic shown as a string twitching on a motor, a small twitch per packet and a whirl under heavy traffic. It is ambient status that conveys load without text — [Weiser & Brown](https://calmtech.com/papers/designing-calm-technology)
- Weiser & Brown also criticise how "too much design focuses on the object itself and its surface features without regard for context" — [Weiser & Brown](https://calmtech.com/papers/designing-calm-technology)
- Amber Case's eight principles. Technology should: require the smallest possible amount of attention; inform and create calm; make use of the periphery; amplify the best of technology and of humanity. It "can communicate, but doesn't need to speak", it "should work even when it fails", "the right amount of technology is the minimum needed to solve the problem", and it should respect social norms — [calmtech.com](https://calmtech.com/)
- Case formalised the principles in 2015 on top of Weiser & Brown. The Calm Tech Institute certification scores attention, periphery, durability, light, sound and materials — [Wikipedia: Calm technology](https://en.wikipedia.org/wiki/Calm_technology) (secondary)
- iA Writer Focus Mode dims everything except the active sentence or paragraph. It has Sentence, Paragraph and Typewriter settings, and typewriter mode keeps the active line vertically centred — [iA Writer Focus Mode (Mac)](https://ia.net/writer/support/editor/focus-mode/focus-mode-mac); [iA Focus Mode](https://ia.net/writer/support/editor/focus-mode)
- iA's stated philosophy is fewer features by design, each one "built for focus". Its founder says designing it "without any settings" was a tough battle. Critics say sentence-level dimming can be disorienting, and some writers think in paragraphs or sections — [iA Writer tips (Medium)](https://medium.com/ia-writer-tips-and-tricks/focus-on-one-idea-at-a-time-ff5116ee6754); [hackdesign iA Writer](https://www.hackdesign.org/toolkit/ia-writer/) (secondary, partly promotional)
- Prot's spacious-padding "increases the space or padding around several elements of the Emacs interface" for "a more comfortable presentation", crediting Nicolas Rougier's designs and Daniel Mendler's org-modern. Its default widths are internal-border 15, header-line 4, mode-line 6, right-divider 30, fringe 8, scroll-bar 8 and tab 4 — [spacious-padding](https://protesilaos.com/emacs/spacious-padding)
- `spacious-padding-subtle-frame-lines` replaces the mode-line and header-line background with a thin overline or underline and keeps the padding. Active and inactive lines can take different colours, such as a `shadow` face for inactive ones. It is a quieter mode line with less filled colour — [spacious-padding](https://protesilaos.com/emacs/spacious-padding)
- A 1Password designer describes Zed's look as "very minimal and clean". Another reviewer notes the visible "effort put into making things look beautiful" — [Zed user stories](https://zed.dev/user-stories); [kronis.dev](https://blog.kronis.dev/blog/zed-is-pretty-nice/) (via search summary)

### Inferences
- bedit's mode-line chips fit calm design if they are *indicators* (glyph plus count, low contrast) rather than notifications. A chip that changes state should change quietly (a colour shift or a dot) and never flash or animate continuously. The Dangling String suggests ambient encodings, such as a dimmed dot that brightens while an off-loop job runs, instead of spinners or text.
- "The individual must be in charge" maps to Emacs's model: a popup (which-key, eldoc, completion preview) should appear only after the user hesitates, or on request, and dismiss on any keypress.
- An olivetti / writeroom / iA-style focus mode is cheap in a GPU-painted window: centre the text column at the fill column with wide margins, hide the mode line and header line or fade them to a hairline, and optionally dim text outside the current paragraph, or outside the current defun for code (a Zen mode for code). The "dim" variants should be opt-in, given the disorientation complaints.
- A subtle-frame-lines treatment of the mode line (a hairline plus padding instead of a filled bar) is a concrete Prot-style lever. bedit's recent "header line is subtle" commit is already in this direction.

### Gaps
- I found no empirical study that measures "calm" in code editors specifically. The evidence is design philosophy and reviewer sentiment.
- I did not fetch the olivetti, writeroom-mode or Zed "zen mode" docs, so their exact default widths and behaviours are unverified here.

## 2. Latency and responsiveness as feel

### Takeaway
Typing latency is felt well below the 16 ms frame: MSR's demo showed that 10 ms is noticeable and 1 ms matches paper. Jitter and *tail* latency (the 99.9th percentile) do more damage than the median. Zed's whole architecture, a GPU renderer at 120 fps with an 8.33 ms frame budget, exists to make the editor "almost disappear". A native GPU editor's priority list is: never block the key-to-paint path, keep p99 low, and use the display's full refresh rate.

### Cited Findings
- Fatin: latency makes typing slower, causes more errors and corrections, increases eye and muscle strain, and demands more conscious attention. Visual feedback is the dominant error-detection channel, so visual latency has an outsized effect — [Fatin, Typing with pleasure](https://pavelfatin.com/typing-with-pleasure/)
- Fatin calls jitter (variable delay) especially harmful because it is unpredictable — [Fatin](https://pavelfatin.com/typing-with-pleasure/)
- Fatin argues the 16 ms frame is an arbitrary threshold for text editing and suggests 1–5 ms for editor processing and paint. Ideal processing latency is 0–1 ms — [Fatin](https://pavelfatin.com/typing-with-pleasure/)
- Fatin's budget breakdown: keyboard 8–22 ms (about 14 ms average, with debouncing and 125 Hz USB polling the main costs). A 60 Hz display adds up to about 17 ms, about 8 ms on average; 144 Hz cuts that to about 3.5 ms. V-Sync adds up to about 17 ms, about 4 ms on average. Compositors add delay, Compiz about 8 ms on average. Typical keyboard-plus-monitor I/O is about 26 ms, ideal about 3 ms — [Fatin](https://pavelfatin.com/typing-with-pleasure/)
- Fatin's measurements (average ms): GVim 0.9, IntelliJ zero-latency mode 2.9, IntelliJ default 24.7 and Atom 49.4 on Windows text files. On Linux XML, Eclipse was 46.5 and IntelliJ 69.2, with a maximum of 198. Power-saving mode and virtualisation made almost every editor worse — [Fatin](https://pavelfatin.com/typing-with-pleasure/)
- Dan Luu, citing the MSR 2012 tablet demo: 100 ms is "terrible", 10 ms is noticeable but OK, and under 1 ms is like pen and paper. Citing Carmack on VR: 20 ms feels fine, 50 ms laggy, 150 ms unbearable — [Dan Luu, Terminal latency](https://danluu.com/term-latency/)
- Luu: at 10 characters per second, a 1-in-1000 latency event happens about every 100 seconds, so tail latency is a constant felt experience. At p99.9 every terminal tested reached perceptible latency, and under load the tails rose for all of them — [Dan Luu](https://danluu.com/term-latency/)
- Luu's measurements: emacs-eshell had a 5 ms idle median and a 17 ms idle p99.9, and Terminal.app 6 ms and 25 ms. Alacritty was 31 ms and 36 ms, and iTerm2 44 ms and 60 ms. Throughput (stdout MB/s) is "weakly related" to latency, so a fast renderer is not automatically a low-latency one — [Dan Luu](https://danluu.com/term-latency/)
- Luu's theory: people tolerate keyboard latency because they have never experienced a low-latency alternative — [Dan Luu](https://danluu.com/term-latency/)
- Zed: at 120 Hz an app has "only 8.33ms per frame" to update state, lay out and paint. Their stated goal was "a code editor so responsive it almost disappeared", and they blamed Atom's random GC pauses and DOM relayouts for missed frames — [Zed, Leveraging Rust and the GPU to render UIs at 120 FPS](https://zed.dev/blog/videogame)
- GPUI uses custom shaders for five primitives (rectangles, shadows, text, icons, images). Glyphs are cached per text-font pair and drawn from a GPU atlas in one instanced draw call — [Zed blog](https://zed.dev/blog/videogame)
- Zed's Feb 2024 post "Optimizing the Metal pipeline to maintain 120 FPS" says they fixed a frame cap by changing synchronisation and using CVDisplayLink. It reports a regression back to 60 FPS that was then restored, and notes that bypassing the compositor helped — [plushcap mirror](https://www.plushcap.com/content/zed/blog/optimizing-the-metal-pipeline-to-maintain-120-fps-in-gpui) (mirror, not the original)
- Claims that Zed's input latency is "about 2 ms" or "under 1 ms" appear only on marketing-style review pages and are unverified — [gilricardo](https://www.gilricardo.com/blog/zed-editor-review-2026)
- Counterpoint: a Linux latency study found that an open Zed window could add latency to *other* apps while idle — [farnoy.dev (HN reader mirror)](https://hn.jakechampion.name/reader/https://farnoy.dev/posts/linux-latency)
- Nielsen's response-time limits: 0.1 s feels instantaneous, 1 s keeps the train of thought unbroken, and 10 s is the limit of attention. These come from Miller (1968) and Card, Moran & Newell — [NN/g](https://www.nngroup.com/videos/3-response-time-limits-interaction-design/); [feelsfast](https://feelsfast.vercel.app/concepts/canonical-thresholds) (secondary on attribution)
- Reviewers repeatedly lead with speed: Zed "loads in a fraction of a second, zero typing latency" and felt "as fast as Helix" — [search summary of Zed reviews](https://blog.kronis.dev/blog/zed-is-pretty-nice/); [seanmcp](https://seanmcp-com.pages.dev/articles/zed-is-a-rocket-powered-skateboard)

### Inferences
- For bedit: measure key-to-paint latency as a distribution (p50, p99, p99.9), not just "slow turns". The slow-turn log and the watchdog are the right instrument. Luu's point means a single 100 ms GC pause or synchronous `os/cmd` every couple of minutes is what users feel. bedit's `proc/flag :responsive` / blocking-call logging targets exactly that tail.
- Treat 8.33 ms (120 Hz) as the frame budget for a keypress, and Fatin's 1–5 ms as the aspiration for the "insert one character" path. Animations (glide, pulse) must never delay the first frame showing the typed character.
- Use the display's native refresh rate (ProMotion / 144 Hz) while something is animating and idle at a low rate otherwise. Neovide's `refresh_rate_idle`, Zed's 120 Hz while editing, and battery mode all point the same way.
- Nielsen's 0.1 / 1 / 10 s gives the feedback ladder. Under 0.1 s shows nothing. From about 1 s show a quiet indicator. Past about 10 s show progress and offer cancel (C-g).

### Gaps
- I did not open the original Zed Metal post or any Zed measurement of end-to-end key latency, so no verified number for Zed exists here.
- I found no published latency numbers for Neovide, Sublime Text or Emacs pgtk.

## 3. Motion: scrolling, cursor animation, pulse on jump, durations, easing, reduced motion

### Takeaway
Good editor motion is *short* (roughly 40–300 ms), *decelerating*, *interruptible*, and reserved for *spatial* changes the eye would otherwise lose: a jump, a scroll or a window split. Typing gets none. The best-known failure is a caret that animates on every keystroke and lags behind the text (VS Code #295648). Neovide's answer is a separate, much shorter duration for one or two character moves and an option to disable animation in insert mode. Every animation needs an off switch and should respect a reduced-motion setting.

### Cited Findings
- Neovide's settings (doc example values; defaults not stated on the page): `cursor_animation_length` 0.150 s (0 disables), `cursor_short_animation_length` 0.04 s for horizontal moves of one or two characters, `cursor_trail_size` 1.0 (range 0–1; higher shortens the trail), `scroll_animation_length` 0.3 s, `position_animation_length` 0.15 s for window moves and splits (0 disables). `cursor_animate_in_insert_mode` makes the cursor jump instantly in insert mode when false. `cursor_vfx_mode` defaults to `""`, meaning no particles — [Neovide configuration](https://neovide.dev/configuration.html)
- Neovide's `refresh_rate` applies only without vsync, and `refresh_rate_idle` (example 5) applies when the window is unfocused — [Neovide configuration](https://neovide.dev/configuration.html)
- VS Code's `editor.cursorSmoothCaretAnimation` with `cursorBlinking: "expand"`: during fast or held-key typing the caret trails the rendered characters, sliding through and overlapping letters, because it follows a fixed-duration animation while text renders instantly. The reporter's expected behaviour was for the caret to speed up or skip to its target. Maintainers acknowledged it as "a real issue" and backlogged it, and it was closed as not planned in April 2026 — [microsoft/vscode#295648](https://github.com/microsoft/vscode/issues/295648)
- VS Code's `cursorBlinking` options are blink (default), smooth (fade in and out), phase, expand and solid. Common configs pair a smooth caret with smooth blinking — [bobbyhadz](https://bobbyhadz.com/blog/vscode-change-cursor-color-style-and-animation) (secondary). The `"explicit"` value of `cursorSmoothCaretAnimation`, which animates only for explicit moves, was not verified against official docs.
- Zed users have requested a VS Code-style smooth caret, which shows demand. Zed does not ship one by default — [zed discussions #61566](https://github.com/zed-industries/zed/discussions/61566)
- Prot's pulsar exists to "make it easier to find where the point is, what was affected, and also to bring attention to something in a buffer". It pulses the line after the commands in `pulsar-pulse-functions`, and separately pulses regions after copy, paste and undo/redo. Window-change pulses are opt-in (`pulsar-pulse-on-window-change`). The sample config uses `pulsar-delay` 0.055 and `pulsar-iterations` 5, about 0.28 s of fade. Faces come in six colours (red, green, yellow, blue, magenta, cyan) — [pulsar](https://protesilaos.com/emacs/pulsar)
- Material 3 duration tokens: short1 = 50 ms and medium2 = 300 ms (the scale runs short1–4, medium1–4, long1–4 and extra-long1–4). Emphasized-decelerate is cubic-bezier(0.05, 0.7, 0.1, 1.0), emphasized-accelerate cubic-bezier(0.3, 0, 0.8, 0.15) and standard (0.2, 0, 0, 1). Sources disagree on whether "emphasized" equals standard or (0.05, 0.7, 0.1, 1) after the M3 Expressive change — [material_3_expressive Dart docs](https://pub.dev/documentation/material_3_expressive/1.0.3/foundations_m3e_motion/M3EMotion-class.html); [frust-material tokens](https://docs.rs/frust-material/0.6.2/src/frust_material/tokens/motion.rs.html) (secondary ports; the official m3.material.io page did not render)
- Apple HIG Motion: "Don't add motion for the sake of adding motion." When Reduce Motion is on, apps should reduce or remove animations — [Apple HIG Motion](https://developer.apple.com/design/human-interface-guidelines/motion) (quoted via search summary; the page body did not render)
- Apple's App Store reduced-motion criteria: multi-axis, multi-speed, spinning or vortex motion should be disabled or changed when the user prefers reduced motion. Auto-advancing or continuous motion should stop or offer a control — [App Store Connect: Reduced motion evaluation criteria](https://developer.apple.com/help/app-store-connect/manage-app-accessibility/reduced-motion-evaluation-criteria)
- Developer commentary: the system softens standard transitions automatically under Reduce Motion, but custom animations must check the setting themselves — [useyourloaf](https://useyourloaf.com/blog/reducing-motion-of-animations/) (secondary)
- Fatin's jitter finding applies to motion too. An animation whose duration varies with load is worse than none — [Fatin](https://pavelfatin.com/typing-with-pleasure/)

### Inferences
- Rules for bedit's motion, consolidated from the findings above:
  1. **Never animate the result of typing.** Inserted text and the caret move instantly, as Neovide does with insert-mode animation off and as #295648 argues. If a smooth caret is offered, use about 40 ms for moves of one or two characters, about 100–150 ms for jumps, and *retarget* from the current position on a new key rather than queueing behind it.
  2. **Animate spatial discontinuities only**: scroll glide (about 150–300 ms, decelerating), window split or position (about 150 ms), and the pulse after a jump (about 250–300 ms fade). This matches the threshold bedit's pulse already uses, a 5+ line jump or a buffer or window change.
  3. **Ease out (decelerate) for things arriving.** Emphasized-decelerate (0.05, 0.7, 0.1, 1) or a critically damped spring both read well. Never use linear for position, and never overshoot or bounce in a text editor.
  4. **Interruptible**: a new scroll command starts from the current animated position and velocity, not from the end. Key repeat (holding C-n or C-v) should drop to no animation or a very short one so motion never lags input, the scroll analogue of #295648.
  5. **One global switch** (`:reduce-motion`, or reading the OS preference where available) that sets the glide, the cursor animation and the pulse to instant or a static highlight. Pulse in reduced-motion mode can be a static highlight that clears on the next command.
  6. **No continuous ambient motion.** No spinners that loop forever and no blinking chips. Cursor blink is debatable: Emacs's `blink-cursor-mode` stops after 10 blinks by default (`blink-cursor-blinks`), a calm compromise (from my own knowledge of Emacs; not fetched).
- When does animation become noise? When it fires on high-frequency actions (every keystroke or C-n), when its duration exceeds the cognitive gap it bridges (Nielsen's 0.1 s), when it is decorative (Neovide's particle VFX ships off by default), or when it varies with load.

### Gaps
- The official Material 3 and Apple HIG pages did not render, so the exact durations and easing values come from secondary token ports. Verify them on m3.material.io before quoting them as Google's.
- Neovide's actual defaults (as opposed to doc examples) were not confirmed. Its source or the docs' defaults table would settle it.
- I found no user study that compares smooth versus instant scrolling for comprehension in code editors.

## 4. Feedback and messaging that doesn't interrupt

### Takeaway
Distinguish *indicators* (passive, ongoing status that needs no action), *validations* (tied to input) and *notifications* (events the user didn't cause). Calm editors put indicators in the periphery (the mode line or fringe), give transient messages one predictable place (the echo area) that clears on the next key, and use modals only for destructive confirmations. Progress shows only past the roughly 1 s threshold and always offers cancel.

### Cited Findings
- NN/g's error-message guidance: inline labels, toasts or banners for issues needing little action; modal dialogs only for severe errors, because modals demand attention and resolution — [NN/g Error-Message Guidelines (mirror)](https://hn.jakechampion.name/reader/https://www.nngroup.com/articles/error-message-guidelines)
- Indicators need no user action, such as a bolded unread item or a changed icon. Validations are linked to user input. Notifications alert users to events they may not know about. These three are often conflated — [besthub summary of NN/g](https://besthub.dev/articles/choosing-the-right-feedback-indicators-validations-and-notifications-explained-095095cf0b66) (secondary)
- Design systems commonly auto-dismiss toasts after about 3–5 seconds (one uses 4 s) as non-modal overlays — [Swisscom SDX notifications](https://sdx.swisscom.com/latest/components/notifications/variants-YjwFqB6z) (secondary)
- Calm tech: technology "can communicate, but doesn't need to speak" and "should work even when it fails" — [calmtech.com](https://calmtech.com/)
- Weiser & Brown: a well-designed tool "will offer, but not demand" — [Weiser & Brown](https://calmtech.com/papers/designing-calm-technology)
- Nielsen: about 1 s is the point where users notice delay, and about 10 s the point where attention is lost, so progress indication belongs there — [NN/g](https://www.nngroup.com/videos/3-response-time-limits-interaction-design/)

### Inferences
- bedit already follows the Emacs model: the echo area plus *Messages* as history, a `message` that never covers a standing question, and `ed-ding` for failure. To keep it calm:
  - Echo-area messages clear on the next key (Emacs behaviour). Prefer a muted face for informational messages and reserve the error face for actual failures.
  - Background work (LSP startup, compile, package fetch, grammar build) shows as a mode-line chip *indicator*. A dim glyph appears only if the work exceeds about 1 s, so fast operations never flicker a spinner. On completion, change the chip briefly or post one echo-area line, never a modal.
  - Batch noisy sources. Expert-LSP startup narration, for example, goes to *Messages*, with only the final "ready" in the echo area.
  - `ding` should be visual and subtle (a brief mode-line tint, like Emacs's `visible-bell` alternatives such as `mode-line-bell`), not an audible bell. This is my suggestion, not a fetched finding.
  - Reserve y/n prompts and modals for destructive or irreversible actions, such as C-x C-c with running processes, which bedit already does.

### Gaps
- I did not fetch the NN/g notification article directly (only a mirror of the error-message guidelines and secondary summaries).
- I found no editor-specific research on echo area versus toast notifications. Zed and VS Code toast behaviour was not examined.

## 5. Discoverability without clutter

### Takeaway
The best editors hide affordances until the user hesitates. which-key waits for an idle delay before popping up, a command palette (M-x with a Vertico-style UI) lists bindings beside commands, and contextual hints surface on demand. The delay matters: too short and the popup flickers for experts, too long and novices give up.

### Cited Findings
- which-key's default `which-key-idle-delay` is 1.0 s, so the popup appears only after one second of hesitation within a prefix. Manual activation uses a long idle delay with a short secondary delay (example 0.05 s) for refreshes once shown. A zero delay "might cause issues", so a non-zero value is recommended — [emacs-which-key README](https://github.com/justbur/emacs-which-key)
- Calm tech: "the smallest possible amount of attention" and "make use of the periphery" — [calmtech.com](https://calmtech.com/)
- Weiser & Brown: the individual controls what moves from periphery to center — [Weiser & Brown](https://calmtech.com/papers/designing-calm-technology)
- Helix's first-run path relies on a built-in tutorial (`hx --tutor`, about 30 min) — [terminal.guide Helix](https://terminal.guide/tools/text-editor/helix) (secondary)

### Inferences
- bedit's which-key should keep a delay; about 0.5–1.0 s is the established range (Doom Emacs reportedly uses about 0.3 s, unverified here). The popup should appear without animation, or with a very fast fade of 50–100 ms, and vanish instantly on the next key.
- M-x (plume) showing each command's key binding in the marginalia teaches shortcuts passively. This is the command-palette pattern from VS Code and Zed, and Vertico plus Marginalia's.
- Contextual hints (eldoc, the completion preview) should come from the idle beat, as bedit's eldoc already does, never on the keystroke.
- The tutorial (C-h t) parallels Helix's `--tutor` as the onboarding path.

### Gaps
- Doom Emacs's which-key delay and its "no config needed" rationale were not fetched, so the Doom number is unverified.
- I found no data on optimal which-key delays. 1.0 s is just the upstream default.

## 6. Defaults that "just work" (first-run experience)

### Takeaway
Reviewers praise Zed and Helix most for working out of the box: speed, a good theme, LSP and tree-sitter, a file picker and multi-cursor with no configuration. The cost is opinionatedness. Calm comes from good defaults plus a short, optional config.

### Cited Findings
- Helix: LSP, tree-sitter, a file picker and multi-selection with no config. One user called its out-of-the-box experience "far and away the best" of the editors they tried, and a guide concludes "Helix works by default, Neovim needs a config to shine" — [jpk.io Helix review](https://jpk.io/dev-tools/helix-editor-review/); [r/HelixEditor](https://redlib.hackliberty.org/r/HelixEditor/comments/1kt06xy/ode_on_first_using_helix) (first-hand but informal)
- The limit: "the day you need something they did not build, you hit a wall". That reviewer still kept about 15 lines of config (a theme, a few keys, options) — [jpk.io](https://jpk.io/dev-tools/helix-editor-review/)
- "We need more zero config tools" is a broader argument for good defaults over configurability — [arne.me (HN reader mirror)](https://hn.jakechampion.name/reader/https://arne.me/blog/we-need-more-zero-config-tools)
- Zed reviewers: fast from the first launch, a minimal and clean look, One Dark by default; "a bit too opinionated" for power users; advanced setup needs settings.json; some put off by the AI and subscription push — [Zed user stories](https://zed.dev/user-stories); [kronis.dev](https://blog.kronis.dev/blog/zed-is-pretty-nice/); [andrewlock.net](https://andrewlock.net/trying-out-the-zed-editor-on-windows-for-dotnet-and-markdown); [jackevans](https://jackevans.bearblog.dev/trying-out-zed/)

### Inferences
- bedit already ships a palette (Catppuccin Mocha), deflanguage tree-sitter modes, LSP and the Vertico/Marginalia-like plume. To match the Zed and Helix first run, pulse, glide, which-key, a subtle mode line and padding should be *on* by default with calm values, and spacious padding (an inset margin) should be the default rather than an opt-in.
- Following iA, ship fewer but good knobs: one `:reduce-motion` switch rather than a dozen animation-duration settings exposed up front, with the fine-grained settings still available.

### Gaps
- Sublime Text and Nova first-run praise was not researched (no sources fetched). Nova's design rationale (Panic) and Sublime's "minimap and Goto Anything" defaults remain uncovered.
- Doom Emacs's and Prot's config rationale documents (e.g. Prot's "Emacs configuration" essay, the modus-themes accessibility rationale of WCAG AAA 7:1 contrast) were not fetched. The modus-themes contrast target is from my background knowledge only, so verify it before citing.
