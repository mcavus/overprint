---
title: Welcome to Field Notes
date: 2026-06-08
tags: [writing, overprint, basics]
slug: welcome-to-field-notes
draft: false
---

This is the first entry in Field Notes, a small blog I keep about writing. It is also
the starting point of the Overprint tutorial, so it explains the one idea everything
else rests on.

## The folder is the site

Open the folder this post lives in and you can see the whole site at once:

```
overprint.yml
content/
  posts/
    2026-06-08-welcome-to-field-notes.md
  pages/
    about.md
```

That is it. `overprint.yml` holds the title, the author, the theme, and the navigation.
Everything under `content/posts` becomes an entry in the list you are reading. Everything
under `content/pages` becomes a standalone page like About.

There is no database behind this. There is no hidden app state, no sync service, no
export button you have to remember to press. The files on disk are the site. If a file
is there, it gets built. If you delete it, it stops existing. If you rename it, the
site changes.

## Why that matters

Two reasons, and both of them are about not losing your work.

The first is that you are never locked in. These are plain Markdown files with a few
lines of YAML at the top. You can open them in Overprint, in a text editor, in a
terminal, on a different machine ten years from now. Put the folder in a git repository
and you get version history for free. Put it in a synced folder and you can write on
either computer.

The second is that anything can edit them. Overprint is a comfortable place to write,
but it is not the only door into this folder. A script can add a post. A command line
tool can rename a file. You are not asking permission from an app to touch your own
prose.

## Running this site

From the folder, start the local preview:

```
overprint serve
```

That builds the site into `dist/` and serves it at `http://localhost:4321`. Leave it
running while you write. Edit a file, save, and the preview updates. If you want a
one-off build without the server, `overprint build` does that instead.

Never edit anything inside `dist/`. It is generated output, and the next build will
overwrite it. Your work belongs in `content/`.

## Where to go next

Read the next two posts in order. The first explains the block of YAML at the top of
every post and what each field controls. The second explains drafts, which is how you
keep something out of the public site while you are still figuring out what it says.

After that, delete these posts. They exist to be read once and thrown away, and the
folder is more useful to you empty.
