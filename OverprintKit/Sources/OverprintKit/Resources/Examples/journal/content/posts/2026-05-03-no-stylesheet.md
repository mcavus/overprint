---
title: There is no stylesheet to open
date: 2026-05-03
tags: [theming, notes]
slug: no-stylesheet
draft: false
---

Two months in, I went looking for the CSS file. Not for a good reason. I had been reading an entry
on my phone and decided the space above the post titles was four pixels too tight, which is the
kind of judgment you should not trust from a person holding a phone in a parking lot.

There is no CSS file. I opened the site folder and it is `overprint.yml`, a `content` directory,
and nothing else. No `style.css`, no theme folder, no partials I could quietly start editing at
eleven at night.

My first reaction was annoyance. My second, about a day later, was relief.

Here is what I would have done with a stylesheet, because I have done it before. I would have
adjusted the leading. Then the measure would have looked wrong at the new leading, so I would have
narrowed the column. Then the tag chips would have looked heavy against the narrower column, so I
would have restyled those. Somewhere in there I would have added a hairline rule under the titles,
removed it, and added it back. Two weekends, minimum, and at the end of it the site would look
about four percent better and I would have written nothing.

The theme block is the only styling knob. If I want a different look, I change one of four values
and the whole site moves together, consistently, in a way I could not have hand-maintained. If I
want a look the four values cannot express, I do not get it. That is the trade, stated plainly, and
it is a good trade for someone whose actual work is joinery.

I did try `font: serif` for a week in March, just to see. It was genuinely more beautiful. Every
entry looked like it had been edited by someone, which was a problem, because these are notes
written with sawdust on my hands and they should look like notes. I set it back to `sans` and have
not touched the block since.

The four-pixels-too-tight thing, for the record, was a phone in bright sun. On the bench it looks
fine.
