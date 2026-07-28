---
title: Writing in the open without publishing
date: 2026-07-18
tags: [writing, overprint, basics]
slug: writing-in-the-open-without-publishing
draft: false
---

Most of what I write never becomes a post. It sits half finished for a week, gets a
better opening paragraph, loses two paragraphs in the middle, and either turns into
something or quietly stops. I want all of that in the same folder as the finished work,
not in a separate scratch file I'll forget about.

That's what the `draft` field is for.

## What draft: true actually does

Set `draft: true` in a post's frontmatter and it disappears from everything the public
sees:

- The post list on the home page skips it.
- It stays out of the RSS feed, so subscribers never see a half thought.
- Search engines aren't told it exists, because it never reaches the sitemap.
- Tag pages ignore it, even when it carries tags.

What it doesn't do is hide the post from you. In local preview, drafts are built and
served like any other post, so you can read the thing in its final typography and notice
that the third paragraph is doing nothing. In the Overprint sidebar, drafts sit in the
same list as published posts, marked with a hollow dot and a small tag. In your text
editor it's just a file.

So: `overprint serve` includes drafts, and `overprint build` doesn't.

## Why not just keep a scratch folder

Because the friction is where drafts die. If an unfinished piece lives somewhere else,
moving it into the site is a decision, and decisions are easy to defer. If it lives in
the same list as everything else, finishing it is a one word change.

It also keeps you honest about how much is in flight. Open the sidebar, count the hollow
dots, and you know whether you've got three things half done or eleven.

## Publishing

When a draft is ready, change one line:

```
draft: false
```

Save, and the post joins the list. Nothing else moves. The filename stays the same, the
slug stays the same, the address it will have on the web is the address it already had
in preview. There's no separate publish step and nothing to stage.

One thing worth thinking about is the date. A draft you started three weeks ago still
carries the date you created it, so it will land partway down the list where nobody
scrolls. If you want it to appear at the top, update `date` in the frontmatter and rename
the file so the date prefix matches. Overprint does the rename for you when you change
the date in the app.

Then run:

```
overprint validate
```

If that passes, the post is ready. Build, deploy, and go do something else. The piece
you have been circling for a month is still sitting in the sidebar with a hollow dot,
waiting for whatever it is you have not worked out yet.
