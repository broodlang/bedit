# Render check — markdown-mode + emoji 🎨

Open with `nest run -- samples/render-check.md`. This exercises every markdown
face and every emoji/wide-glyph path. Use it to eyeball color, two-cell width,
and that the cursor lands on the right character past wide glyphs.

## Markdown faces (these should be coloured by markdown-mode)

A paragraph with **bold**, *italic*, `inline code`, and a [link](https://example.com).
Underscores work too: __bold__ and _italic_.

- unordered bullet (the `-` marks)
* star bullet
+ plus bullet
1. ordered item one
2. ordered item two

> a blockquote line (the leading `>` marks)

```brood
;; a fenced code block — every line should be code-coloured, fences included
(defn f (x) (+ x 1))
```

## Color emoji (these should be in COLOUR, two cells wide)

Single:            😀 🎨 🚀 🔥 🌍 🐉
With text:         build 🚀 ship 🔥 done ✅
ZWJ family:        👨‍👩‍👧‍👦  (one glyph, not four)
Profession ZWJ:    👩‍💻 👨‍🚀 🧑‍🔧
Regional flags:    🇿🇦 🇯🇵 🇺🇸  (each one flag, not two letters)
Skin-tone:         👍🏽 👋🏾 🙌🏿
Keycap:            1️⃣ 2️⃣ 3️⃣
Variation select:  ❤️ ⭐ ☀️  (VS16 — emoji presentation)

## Monochrome symbols (render in the TEXT colour, not coloured)

Legend glyphs:     ✓ ◉ □ ★ ☆ ⚙ → ← ↑ ↓
Box drawing:       ┌─┬─┐ │ ├─┼─┤ └─┴─┘

## Wide (CJK) — two cells each

Chinese:  中文字符
Japanese: 日本語のテキスト
Korean:   한국어 텍스트

## Cursor / width alignment

The ruler below is plain ASCII (one cell per char). On the lines under it, each
wide glyph should occupy exactly two ruler columns, and moving point across them
(C-f / C-b) should keep the block cursor over the glyph it's on:

```
0123456789012345678901234567890
```
a😀b😀c  middle dots ·· then 中 end
xx🚀yy🇯🇵zz  (rocket = 2 cells, flag = 2 cells)

## Combining marks (should not add a column)

café  (e + combining acute)  vs  cafe
a̐ é̮ o̲   (base + combining diacritics)
