---
title: Four knobs and a cream page
date: 2026-02-17
tags: [theming, process]
slug: four-knobs
draft: false
---

I put off starting this journal for two years, and the reason was always the same: I did not want
to spend a weekend picking a typeface. I have watched that weekend turn into a month. The shelves
never get built because the site about the shelves is not done.

So the deal I made with myself was that the look of this thing would be decided in one sitting,
from a fixed menu, and then never revisited. Overprint made that easy, because there are exactly
four knobs. Here is the whole of it, sitting in `overprint.yml`:

```yaml
theme:
  mode: light
  accent: "#C2410C"
  font: sans
  background: "#F5EBDC"
```

That is the entire visual specification of this site. Four lines.

**`mode`** is `light` or `dark`. It decides the family of decisions everything else inherits: text
color, surface color, how borders are drawn, whether the page reads as paper or as a screen at
night. I picked light because I read long entries in the afternoon with the shop door open, and
dark text on a pale ground survives that better.

**`accent`** is a hex color, and it is the only saturated thing on the page. It tints post titles
and links. That is it. I spent about ten minutes here, which is nine minutes more than I had
budgeted, and landed on `#C2410C`. It is roughly the color shellac goes over cherry after four
coats, which is a thing I look at often enough that it reads as neutral to me.

**`font`** is `serif`, `sans`, or `mono`. Not a font name, a family choice. You cannot ask for
Garamond here, and I have decided to be grateful about that.

**`background`** is optional, and it is the escape hatch. Set it and it overrides the page color
that the mode would have given you, while leaving everything else about that mode alone. Mine is
`#F5EBDC`, a warm cream. The rest of light mode still applies. I just did not want the gallery
white.

The whole sitting took twenty minutes. Then I went and cut the parts for a bench.
