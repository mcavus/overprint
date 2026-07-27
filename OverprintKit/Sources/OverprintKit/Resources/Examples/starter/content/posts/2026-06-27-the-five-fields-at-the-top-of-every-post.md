---
title: The five fields at the top of every post
date: 2026-06-27
tags: [overprint, basics]
slug: the-five-fields-at-the-top-of-every-post
draft: false
---

Every post in this folder starts with a small block of YAML between two lines of three
hyphens. That block is called frontmatter, and it is the only structured data a post
carries. Here is the whole thing, exactly as it appears at the top of the file you are
reading:

```yaml
---
title: The five fields at the top of every post
date: 2026-06-27
tags: [overprint, basics]
slug: the-five-fields-at-the-top-of-every-post
draft: false
---
```

Five fields. No more, no fewer. Below the closing hyphens, everything is ordinary
Markdown.

## title

The headline. It appears at the top of the post, in the list on the home page, in the
browser tab, and in the RSS feed. Write it as a sentence, not as a headline in title
case, unless you prefer otherwise. Quote it if it contains a colon, because YAML reads
a bare colon as a separator.

## date

The publication date in `YYYY-MM-DD` form. Posts are sorted newest first, so this is
what decides the order of the list. It is also what shows under each entry.

The date does double duty: it is the first part of the filename. This post lives at
`content/posts/2026-06-27-the-five-fields-at-the-top-of-every-post.md`, and the date in
the filename must match the date in the frontmatter. Overprint keeps them in sync when
you change the date from the app. If you edit the file by hand, change both.

## tags

A list of short labels, written as `[one, two]`. Each tag gets its own page in the built
site, at `tag-<name>.html`, listing every published post that carries it. That page name
is how you link to a tag from the navigation in `overprint.yml`, which is exactly what
the Basics link in the header of this site does.

Keep the set small. Three or four tags that mean something are better than twenty that
each apply to one post. This site uses `writing`, `overprint`, and `basics`.

## slug

The name this post gets on the web. A slug of `the-five-fields-at-the-top-of-every-post`
produces `the-five-fields-at-the-top-of-every-post.html`. Lowercase letters, numbers, and
hyphens only.

Like the date, the slug appears twice: once in the frontmatter and once in the filename
after the date prefix. They must match. Once a post is published, changing the slug
changes its address and breaks every link to it, so pick one you can live with.

## draft

Either `true` or `false`. A post with `draft: true` is kept out of the built site. It is
still visible while you are previewing locally, so you can see how it looks before anyone
else does. The next post covers this in detail, because it is the field people get wrong
most often.

## Checking your work

If you edited a file by hand and want to be sure you did not break anything:

```
overprint validate
```

That walks every post, checks the five fields, and tells you about mismatched filenames,
missing dates, and malformed YAML. Run it before you publish. It takes a second and it
catches the boring mistakes.
