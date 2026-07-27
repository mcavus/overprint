---
title: v0.2.0, manifests and checksums
date: 2026-02-09
tags: [release, cli, fixes]
slug: v0-2-0-manifests-and-checksums
draft: false
---

First release of the year, and the first one where I feel comfortable telling people to use shard on data they care about.

## Manifests

Splitting a file was never the hard part. The hard part was proving that the pieces you carried across the network are the same pieces that came out the other end. Until now shard wrote nothing but the chunks themselves, and reassembly was a `cat` with your fingers crossed.

Every split now writes `shard.manifest` alongside the pieces:

```
shard split dump.sql --lines 50000
```

The manifest records the source name, the total byte count, the split rule that produced the pieces, and a BLAKE3 checksum for each one. `shard join` reads the manifest, refuses to run if a piece is missing, and refuses to write output if any checksum fails. There is no flag to skip the check. If you want a tool that will happily hand you a corrupt file, you already have `cat`.

## Fixes

- Splitting on a regular expression boundary dropped the final chunk when the file did not end in a newline. This was the oldest open issue in the tracker and it deserved to be closed a year ago.
- `shard split --bytes` rounded down instead of up, so a 100 byte file split at 30 bytes produced three pieces and silently lost the last ten. Now it produces four.
- Error messages that used to say `error: failed` now say what failed and which path it failed on.
- Exit codes are consistent: 0 for success, 1 for a usage problem, 2 for a data integrity problem. Scripts can finally tell the difference.

## About these notes

The release notes you are reading are a static site built with Overprint, and since a few people asked how it is wired up, I will explain a bit of it in each entry.

The whole site is a folder of Markdown files. To start one from nothing:

```
overprint init ./release-notes
```

That writes `overprint.yml`, an empty `content/posts` directory, and a `content/pages` directory. The config file holds the site title, the author, the theme, and the navigation. Nothing else is hidden anywhere. There is no database and no lock file, so the folder is the entire state of the site.

A new entry is one command:

```
overprint new "v0.2.0, manifests and checksums"
```

That creates `content/posts/2026-02-09-v0-2-0-manifests-and-checksums.md` with the frontmatter filled in, marked as a draft, and then you write the body. The date in the filename and the date in the frontmatter always agree, which matters more than it sounds like it does.

## Tags

Notice the `tags` line at the top of this entry. Overprint treats tags as a first class thing rather than decoration. Every unique tag across all published posts generates its own listing page at `tag-<slug>.html`, so `release` becomes `tag-release.html` and `performance` becomes `tag-performance.html`. The slug is the tag lowercased with anything that is not a letter or a number turned into a hyphen.

I am keeping the tag vocabulary here deliberately small: `release`, `fixes`, `performance`, and `cli`. Four tags means four useful pages. Forty tags would mean forty pages with one entry each, which helps nobody. If you only care about the speed work, the performance page is the whole story with none of the bug lists in between.
