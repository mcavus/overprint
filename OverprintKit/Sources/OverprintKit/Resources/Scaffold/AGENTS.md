# AGENTS.md

This folder is an Overprint site: a blog whose content is plain Markdown files. Overprint is a
native macOS app with a companion `overprint` CLI, both built on OverprintKit (a Swift static
site generator). You do not need the app to work here. Edit the files, then rebuild.

The folder is the single source of truth. There is no database and no hidden state. Anything in
`dist/` is generated from these files.

## Layout

```
overprint.yml        site config (required, at the root)
content/posts/       one Markdown file per dated post
content/pages/       one Markdown file per standalone page (optional)
dist/                GENERATED output, never hand-edit
```

`dist/` is deleted and rewritten on every build. Changes made there are lost.

## Post contract (frozen)

Every post lives at `content/posts/YYYY-MM-DD-slug.md` and starts with a YAML frontmatter block
fenced by `---`. All five fields below are a frozen contract for POSTS. Do not rename, drop, or
invent post fields. (Pages have their own, smaller contract: see Standalone pages.)

```yaml
---
title: Writing in the open
date: 2026-07-20
tags: [writing, process]
slug: writing-in-the-open
draft: false
---
```

- `title` (string, required) is the post heading. Must be non-empty.
- `date` (required) must be `YYYY-MM-DD`. It sets ordering (newest first) and the displayed date.
- `tags` (list of strings) may be empty (`[]`). A comma-separated string is also accepted.
- `slug` (string) is the output filename, `<slug>.html`. If omitted it is derived from the
  filename by stripping the date prefix. Keep it in sync with the filename.
- `draft` (boolean) defaults to `false` when absent.

Markdown body follows the closing `---`. One post per file. The date prefix in the filename should
match the `date` field. A post that violates the contract fails the build, so validate before
building, and always before a deploy.

## Standalone pages

A page is an undated document like About or Colophon. It lives at `content/pages/<slug>.md` and
uses a DIFFERENT, smaller contract:

```yaml
---
title: About
---
```

- `title` (string, required) is the only required field.
- `slug` (string, optional) sets the output filename; it falls back to the filename.
- `draft` (boolean, optional) behaves as it does for posts.
- Pages have NO `date` and NO `tags`. Do not add them.

Pages render flat as `<slug>.html`, exactly like posts, but they never appear in the index list,
the RSS feed, or any tag page. Post and page slugs share one namespace: two files claiming the
same slug is a validation error, because each becomes `<slug>.html`. Avoid the reserved names
`index`, `feed`, `sitemap`, and anything starting with `tag-`, which collide with generated output.

## Not found page

Every build writes `404.html`, which most hosts (GitHub Pages included) serve for an address that
does not exist. It uses the site's theme and navigation, and it is never listed in the index, the
feed, or the sitemap.

To replace the wording, add a page whose slug is `404` (usually `content/pages/404.md`):

```yaml
---
title: Nothing here
---
```

That page is not also emitted as an ordinary page: it becomes `404.html` and nothing else. Write it
as you would any page. Leave it out and the built-in copy is used.

One thing to know if you edit the template: the host serves this file without redirecting, so the
browser stays on the address the visitor typed. Relative links would resolve against that address
rather than the site root, so this page alone carries a `<base>` derived from `url` in
`overprint.yml`. Removing it breaks the stylesheet and every link for any visitor who lands on a
path below the root.

## Site config

`overprint.yml` at the root:

```yaml
title: My Site
author: Your Name
description: A short line about the site.
url: https://example.com
theme:
  mode: light        # light | dark
  accent: "#0A7AFF"  # hex color
  font: serif        # serif | sans | mono
  background: "#FFFFFF"  # optional hex, overrides the mode's default paper
nav:                     # optional header navigation, omit for no nav at all
  - { label: Writing, url: index.html }
  - { label: About,   url: about.html }
```

Every key is optional and falls back to a default, but `overprint.yml` itself must exist.
`url` is used for absolute links in the feed and sitemap. The `theme` block is the only styling
knob: there is no per-site CSS file to edit.

`nav` is a list of `{ label, url }` entries rendered in the site header. Each `url` must be a page
the build actually produces: `index.html`, a page slug such as `about.html`, or a tag page such as
`tag-notes.html` for a tag that a PUBLISHED post carries. When `nav` is absent, no navigation
renders at all.

## Drafts

A post with `draft: true` is work in progress. Drafts are always excluded from the RSS feed
(`feed.xml`), the sitemap (`sitemap.xml`), and the tag pages. Local preview builds still render
drafts so you can read them, and deploy builds leave them out entirely. To publish, set
`draft: false` and rebuild.

## How to add a post

1. Create `content/posts/2026-07-20-my-new-post.md` (today's date, slugified title).
2. Paste the frontmatter block above, set `title`, `date`, `tags`, `slug`, and `draft: true`.
3. Write the body in Markdown below the closing `---`.
4. Run `overprint validate` to check the frontmatter, then `overprint build`.
5. When it reads right, set `draft: false` and rebuild.

Or let the CLI do steps 1 and 2: `overprint new "My new post"` creates the file as a draft.

## Commands

```
overprint validate            check the config, every post, and every page
overprint build               build into dist/
overprint serve --port 4321   build and preview on localhost
overprint new "Title"         create a new draft post
```

Each command takes the site folder as its argument (default `.`); `new` takes the title and uses
`--site` for the folder.
