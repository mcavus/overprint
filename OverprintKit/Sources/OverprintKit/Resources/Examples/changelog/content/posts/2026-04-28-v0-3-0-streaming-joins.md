---
title: v0.3.0, streaming joins
date: 2026-04-28
tags: [release, performance, cli]
slug: v0-3-0-streaming-joins
draft: false
---

Two and a half months of work, most of it spent deleting things.

## Joins no longer buffer

The old `shard join` read every piece into memory, verified the checksums, concatenated the buffers, and wrote the result. That is fine for a 200 MB dump on a laptop with 32 GB of memory. It is not fine for a 40 GB dump on a build agent with 4 GB, which is where three separate people hit it and filed three separate issues that were all the same issue.

Joins are now fully streaming. shard reads each piece in 1 MB frames, updates the running checksum as it goes, and writes straight through to the output. Peak memory during a join is now flat at roughly 4 MB regardless of input size.

The numbers on my machine, joining a 40 GB set of 800 pieces:

| version | wall time | peak memory |
| --- | --- | --- |
| v0.2.0 | out of memory | out of memory |
| v0.3.0 | 3m 41s | 4.1 MB |

Splitting got faster too, though less dramatically. Reusing a single output buffer instead of allocating per chunk cut split time on the same file from 5m 02s to 4m 18s. Not glamorous, but free.

## Parallel checksums

If you pass `--jobs N`, verification now runs across N threads. Checksums are the dominant cost on a fast disk, so this scales close to linearly up to about six threads before the disk becomes the ceiling again. The default is one job, because a tool that saturates every core by surprise is a rude tool.

## Smaller binary

Dropping two dependencies that each existed to provide one function took the release binary from 8.9 MB to 3.2 MB. Both functions were about twenty lines. I should have written them myself two years ago.

## About these notes

Continuing the tour of how this site is built.

Writing an entry is just editing Markdown, but you want to see it before anyone else does:

```
overprint serve
```

That builds the site and serves it on localhost with live reload, so saving the file refreshes the page. Drafts are included when you serve, which is the point, since you are usually looking at the thing you have not published yet.

When you want the real output on disk:

```
overprint build
```

That writes `dist/`, and it leaves drafts out. A post with `draft: true` in its frontmatter exists on your disk and nowhere else. It does not appear in the index, it does not appear on any tag page, and it does not appear in the RSS feed. There is no separate staging site to manage. Flipping the flag to `false` and rebuilding is the entire publishing step.

## More on tags

This entry is tagged `release`, `performance`, and `cli`, so it will show up on three different listing pages. Tag pages are generated from what the posts actually say, not from a list you maintain by hand, which means a tag page cannot go stale and cannot point at nothing.

That does create one sharp edge worth knowing about. If you link to a tag page from your navigation, and later you remove the last post carrying that tag, the page stops being generated and your navigation link goes to a 404. This is why I keep the vocabulary small and only link `tag-release.html` from the nav bar: every release entry carries `release`, so that page will exist for as long as this site does.
