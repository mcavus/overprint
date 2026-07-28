<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/logo-dark.png">
    <img src="docs/logo.png" alt="Overprint" width="380">
  </picture>
</p>

<p align="center">
  <strong>A native macOS blogging app you can talk to.</strong><br>
  Write in Markdown, build your site by describing it, and publish it to a domain you own.
</p>

<p align="center">
  Your posts are plain files in a folder. Hosting is free on GitHub Pages,<br>
  with your own domain and HTTPS, and no server to run.
</p>

<p align="center">
  <img src="docs/screenshot-hero.png" alt="Overprint with a post open: the mode rail, the posts list, the Markdown editor, and the live preview" width="900">
</p>

---

## See it live

Three sample blogs, built by Overprint and published to GitHub Pages. Each ships inside the app, so you can open the same folder and read the Markdown behind it.

| | | |
|---|---|---|
| **[Field Notes](https://mcavus.github.io/overprint/starter/)** | A personal writing blog | Posts, post settings, and how drafts behave |
| **[Release Notes](https://mcavus.github.io/overprint/changelog/)** | A developer changelog | Dark mode, monospaced, tags and tag pages |
| **[Studio Journal](https://mcavus.github.io/overprint/journal/)** | A studio journal on cream paper | Theming, standalone pages, and navigation |

The writing is invented. The sites are real output from the engine the app ships with.

There is also an [Overprint landing page](https://mcavus.github.io/overprint/).

---

## Describe your site, and it builds it

<p align="center">
  <img src="docs/screenshot-build.png" alt="Build mode: asking for a warm terracotta accent and a soft cream background, with the change applied and visible in the live preview" width="900">
</p>

Build mode is a chat that works in your site folder, editing the Markdown and config the way you would:

> *"A minimal personal blog with a dark editorial theme"* scaffolds the whole site
> *"Make the accent a warm terracotta and the page background a soft cream"* re-themes it
> *"Add an about page"* or *"rewrite my last post"* does exactly that

## Write, with an editor that can edit

<p align="center">
  <img src="docs/screenshot-write.png" alt="Write mode: the posts list, a Markdown editor, and a live preview, with the Ask Claude popover open over the current draft" width="900">
</p>

A Markdown editor beside a live preview of the real page. Drafts sit in the list with your published posts and stay out of the feed until you say so.

**Ask Claude** works on the draft in front of you. One click for *tighten the introduction*, *fix grammar and spelling*, or *add a conclusion*, or type your own.

### No API key, no extra bill

Both run through [Claude Code](https://claude.com/claude-code) on your own machine, on your existing Claude subscription. Nothing is metered and no key is stored. Without Claude Code installed they disable themselves, and the rest of the app works the same.

Pick the model (Opus, Sonnet, or Haiku) in Settings. If Claude Code needs a token for headless use, run `claude setup-token` and paste it into Settings; it goes to your Keychain.

---

## Publish for free, on your own domain

Overprint publishes to **GitHub Pages**. Connect a site to a repository once; every publish after that is one click.

- **No hosting bill, at any traffic level.** Static files served off GitHub's CDN.
- **Your own domain.** Point `blog.example.com` at it and Overprint writes the `CNAME` for you.
- **HTTPS included**, issued and renewed automatically.
- **Nothing to maintain.** No server and no runtime, so nothing to patch.
- **Your writing stays yours.** It is a folder of Markdown in your own git repository, and it still builds if Overprint goes away.

Commit saves your writing to `main`. Deploy builds with drafts excluded and publishes to `gh-pages`. Your source history accumulates; the generated site is replaced each time.

## How it works

Overprint builds your Markdown into a static site with its own Swift generator, and previews it on localhost while you write.

The folder on disk is the whole thing. Everything lives in `overprint.yml` and under `content/`, so you can edit a site in Overprint, a text editor, a script, or an agent, in any order, and nothing gets out of sync.

The engine (`OverprintKit`) is a library. The app, the `overprint` CLI, and anything else you point at a site folder are thin front-ends over the same operations.

## Installing

There is no download yet. Building it yourself needs macOS 14 or later and Xcode 16:

```sh
git clone https://github.com/mcavus/overprint.git
cd overprint
SKIP_NOTARIZE=1 Scripts/release.sh 0.1.0
```

That produces `.release/Overprint-0.1.0.dmg` with the `overprint` command line tool embedded. Open it and drag Overprint to Applications.

Once it is running, open **Settings > Command line tool** and click Install to link `overprint` onto your PATH.

## Using it

<p align="center">
  <img src="docs/screenshot-launch.png" alt="The launch window: create a new site or open an existing one, with recent sites and three bundled examples" width="700">
</p>

1. **Create a new site**, or open an example from the launch window to learn by reading one.
2. **Write** in the Markdown editor with a live preview.
3. **Connect** the site to a GitHub repository once, the first time you Deploy.
4. **Commit** to save your writing, and **Deploy** to publish the built site to GitHub Pages.

## Making it look like yours

The `theme` block in `overprint.yml` covers mode, accent, font and page color. When you need more
than that, a site can override the built-in theme one file at a time:

```
theme/
  templates/head.html    injected last in <head>: fonts, favicons, meta, a pre-paint script
  templates/*.html       override any built-in template (base, index, post, tag, page, nav, 404)
  assets/style.css       replace the stylesheet
  assets/**              anything your CSS points at
static/                  copied verbatim to the site root: favicons, robots.txt, CNAME
```

Overrides are per file: anything you leave out falls back to the built-in version, so changing the
`<head>` does not mean owning the other templates. Most sites only need `head.html`.

`overprint validate` reports what a site overrides, rejects a filename it would never render, and
refuses a vendored `base.html` missing a block the engine depends on. A `static/` file that would
overwrite generated output is a build error, not a silent overwrite.

## Site layout

```
my-site/
  overprint.yml            # site config
  AGENTS.md                # the contract, for agents and humans
  content/
    posts/
      2026-07-16-hello.md
    pages/                 # optional standalone pages
      about.md
  theme/                   # optional template and stylesheet overrides
  static/                  # optional passthrough files, copied to the site root
  dist/                    # generated output, never edit by hand
```

`overprint.yml`:

```yaml
title: My Blog
author: Your Name
description: A short line about the site.
url: https://blog.example.com
theme:
  mode: light        # light | dark
  accent: "#0A7AFF"
  font: serif        # serif | sans | mono
  background: null   # optional page color, overrides the mode default
nav:                 # optional header navigation
  - { label: Writing, url: index.html }
  - { label: About,   url: about.html }
```

Every field is optional with a sensible default. `url` is what makes the feed and sitemap use absolute links.

## What goes at the top of a post

Every post lives at `content/posts/YYYY-MM-DD-slug.md` and opens with a few lines of settings between two `---` fences. Everything below the second fence is the post itself:

```markdown
---
title: <string>
date: <YYYY-MM-DD>
tags: [<string>, ...]
slug: <string>
draft: <true|false>
---

The Markdown body starts here.
```

`title` and a valid `date` are required. `slug` falls back to the filename with the date prefix stripped, `tags` defaults to empty, and `draft` defaults to `false`. These five names will not change, so a script or an agent can count on them.

Standalone pages live at `content/pages/<slug>.md` with only a `title` (plus optional `slug` and `draft`). Pages have no date and no tags, so they never appear in the post list, the feed, or tag pages.

## Build output

`dist/` is flat, with relative links, so it opens over `file://` as well as a server:

- `index.html`, the post list
- `<slug>.html`, one page per post, and per standalone page
- `tag-<slug>.html`, one page per tag
- `assets/style.css`, generated from the `theme:` tokens
- `feed.xml` (RSS 2.0) and `sitemap.xml`

Drafts render in local preview but are excluded from everything on deploy. `dist/` is rebuilt from scratch on every build, so never edit it by hand.

## Building from source

Requires macOS 14+ and Xcode 16+ (Swift 6). `git` (from the Xcode command line tools) is needed for Commit and Deploy.

Engine and CLI:

```sh
swift build --package-path OverprintKit
swift test --package-path OverprintKit
swift run --package-path OverprintKit overprint <subcommand>
```

The app: open `Overprint/Overprint.xcodeproj` in Xcode and run the `Overprint` scheme, or `xcodebuild -project Overprint/Overprint.xcodeproj -scheme Overprint -destination 'platform=macOS' build`. It depends on the local `OverprintKit` package, so there is nothing else to fetch. The app runs unsandboxed (to launch the Claude Code CLI) and is not built for the Mac App Store.

### CLI reference

| Command | What it does |
| --- | --- |
| `overprint init [path] [--title <title>]` | Scaffold a new site. |
| `overprint new <title> [--site <path>]` | Create a new draft post. |
| `overprint build [path]` | Build the site into `dist/`. |
| `overprint serve [path] [--port <port>]` | Build, then serve `dist/` (default port 4321). |
| `overprint validate [path]` | Check `overprint.yml` and every post and page. Run before deploying. |

## License

Overprint is licensed under the **GNU General Public License v3.0 or later**. See [LICENSE](LICENSE).

Copyright (C) 2026 Mark Cavusoglu

You are free to use, study, modify, and redistribute it. A distributed modified version must also be GPL and ship its source, with the notices intact. It cannot be made closed-source.

**Name and logo.** In printing, overprinting is laying one ink over another so the colors combine, and the logo is two rings doing exactly that. The GPL covers the code, not the name "Overprint" or the tri-color mark and lockup under `overprint-logos/`, which are reserved (GPL section 7(e) permits this). A modified version must use a different name and its own icon.

### Third-party components

Overprint depends on these, which keep their own licenses:

| Component | License |
| --- | --- |
| [swift-markdown](https://github.com/swiftlang/swift-markdown) (and swift-cmark) | Apache-2.0, BSD-2-Clause |
| [swift-argument-parser](https://github.com/apple/swift-argument-parser) | Apache-2.0 |
| [Yams](https://github.com/jpsim/Yams) | MIT |
| [Stencil](https://github.com/stencilproject/Stencil) (and PathKit) | BSD-2-Clause |
| [Swifter](https://github.com/httpswift/swifter) | BSD-3-Clause |
| [Sparkle](https://github.com/sparkle-project/Sparkle) | MIT |
| [JetBrains Mono](https://github.com/JetBrains/JetBrainsMono) | SIL Open Font License 1.1 |

The bundled font's full OFL text is at [`Overprint/Overprint/Resources/Fonts/OFL.txt`](Overprint/Overprint/Resources/Fonts/OFL.txt). The Apache-2.0 components are provided under that license; you may obtain a copy at <http://www.apache.org/licenses/LICENSE-2.0>.
