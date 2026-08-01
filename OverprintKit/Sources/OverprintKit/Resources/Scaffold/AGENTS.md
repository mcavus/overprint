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
theme/               optional template and stylesheet overrides (see Theme overrides)
static/              optional files copied verbatim to the site root
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
description: An optional one-line summary.
---
```

- `title` (string, required) is the post heading. Must be non-empty.
- `date` (required) must be `YYYY-MM-DD`. It sets ordering (newest first) and the displayed date.
- `tags` (list of strings) may be empty (`[]`). A comma-separated string is also accepted.
- `slug` (string) is the output filename, `<slug>.html`. If omitted it is derived from the
  filename by stripping the date prefix. Keep it in sync with the filename.
- `draft` (boolean) defaults to `false` when absent.
- `description` (string, optional) is the summary used in the index listing, the RSS feed, and the
  page's `<meta name="description">`. Omitted, the first paragraph is used.

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
- `description` (string, optional) behaves as it does for posts.
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

`overprint serve` answers a missing address with this page too, so a 404 previews the way the host
will serve it. On a project site the page's `<base href="/repo/">` points at the published address,
so the local preview of it renders unstyled.

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
`url` is used for absolute links in the feed and sitemap. The `theme` block is the quick styling
knob; for anything it cannot express, see Theme overrides below.

`nav` is a list of `{ label, url }` entries rendered in the site header. Each `url` must be a page
the build actually produces: `index.html`, a page slug such as `about.html`, or a tag page such as
`tag-notes.html` for a tag that a PUBLISHED post carries. When `nav` is absent, no navigation
renders at all.

## Theme overrides

A site may override any part of the built-in theme. Everything here is optional, and every file is
independent: overriding one does not oblige you to vendor the rest.

```
theme/
  templates/         any of: base.html index.html post.html tag.html page.html nav.html 404.html head.html
  assets/style.css   replaces the built-in stylesheet
  assets/**          anything else your CSS points at (fonts, background images)
static/              copied verbatim to the site root (favicons, robots.txt, CNAME, images, JS)
```

**Reach for `theme/templates/head.html` first.** It is empty by default and is injected last in
`<head>`, which covers most of what people actually want: web fonts, favicons, social meta, a
pre-paint theme script. The build already emits `<meta name="description">` and `og:description`
from the page's own `description` or first paragraph, so adding one here gives the page two.
Because it lands last, it wins over the built-in font links and stylesheet,
and you never take ownership of `base.html`.

Overriding `base.html` is the heavy option, and it makes you responsible for four things the rest of
the engine depends on. `overprint validate` refuses a `base.html` missing any of them:

- `{% block head_top %}` — the 404 page emits its `<base href>` here.
- `{% block title %}` and `{% block content %}` — or every page renders identical and empty.
- `{{ theme.rootStyle }}` — the `:root` block carrying `--accent`, `--paper`, `--display`.

The `theme` block in `overprint.yml` keeps working alongside an override. Those tokens are still
emitted, so custom CSS can consume them (`color: var(--accent)`) or ignore them entirely.

`theme/assets/**` lands in `dist/assets/`, so a stylesheet can use relative URLs. `static/**` lands
at the site root. A static file that would overwrite generated output (`index.html`, `feed.xml`,
`sitemap.xml`, `404.html`, a post's `<slug>.html`, `assets/style.css`) is a build error rather than a
silent overwrite in either direction.

A file in `theme/templates/` that is not one of the eight names above is an error, so a typo
announces itself instead of quietly doing nothing. Name your own partials with a leading underscore
(`_sidebar.html`) and `{% include %}` them yourself.

`dist/` is still deleted and rewritten on every build. Nothing here changes that.

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
