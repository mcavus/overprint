---
title: v0.4.0, faster builds
date: 2026-07-15
tags: [release, performance, fixes, cli]
slug: v0-4-0-faster-builds
draft: false
---

The release I have wanted to ship since the project started. Splitting is now roughly four times faster on large files, and the command line interface finally behaves the way I always described it in the README.

## Faster splits

The split path used to make one syscall per chunk boundary and one allocation per chunk. On a file with a hundred thousand boundaries that adds up to real time spent doing nothing useful.

Three changes did most of the work. Reads now come through a memory mapped window rather than a buffered reader, boundary scanning uses a vectorized search instead of a byte at a time loop, and output pieces are written through a reusable buffer pool instead of a fresh allocation each time.

Splitting a 40 GB dump on 50000 line boundaries:

| version | wall time |
| --- | --- |
| v0.2.0 | 5m 02s |
| v0.3.0 | 4m 18s |
| v0.4.0 | 1m 07s |

Regular expression boundaries benefit less, around a 40 percent improvement, because the regex engine is the bottleneck there and I have not touched it.

## Command line changes

Two breaking changes, both of which I am sorry about and neither of which I regret.

`--out` is now `--output`, consistently across every subcommand. The short form `-o` still works. Previously `split` used `--out` and `join` used `--dest`, which was indefensible.

`shard verify` is now its own subcommand rather than a flag on `join`. Verifying a set of pieces without writing anything is a thing people do constantly in CI, and making them join into `/dev/null` to do it was silly.

Old invocations print a clear deprecation message and still work through v0.5.0.

## Fixes

- A manifest with a trailing blank line was rejected as malformed. It is now accepted.
- `shard join` on a read only output directory failed after reading every piece rather than before reading any of them. It now checks first.
- Piece filenames with more than four digits sorted lexically, so piece 10000 landed between 1 and 2. Padding is now computed from the piece count.
- The progress bar wrote escape codes when stdout was not a terminal, which made log files unreadable. It now detects a pipe and prints plain lines instead.

## About these notes

Last part of the tour, and the important one.

Before publishing anything, run:

```
overprint validate
```

That checks every post and page under `content/`. It confirms the config loads, that the frontmatter parses, that the required fields are present, that each post date is a real date in `YYYY-MM-DD` form, and that no two posts or pages claim the same slug.

That last one matters more than it sounds. A slug becomes `<slug>.html`, so two files claiming the same slug means one quietly overwrites the other in the output. Run validate before every deploy, without exception. A broken build is obvious and you fix it in a minute. A post that silently vanished is the kind of thing you discover six weeks later when someone emails to ask where it went.

So the whole loop, from nothing to a published entry, is five commands:

```
overprint init ./release-notes
overprint new "v0.4.0, faster builds"
overprint serve
overprint validate
overprint build
```

Everything else is writing.

## One more note on tags

This entry carries all four tags I use here, so it appears on `tag-release.html`, `tag-performance.html`, `tag-fixes.html`, and `tag-cli.html`. That is deliberate: it is a release, it contains speed work, it contains bug fixes, and it changes the command line interface. Someone who only follows the performance page should still see this one, because the thing they care about is in it.

The rule I have settled on after three releases is to tag for the reader who is filtering, not for the reader who is browsing. Browsing readers have the front page. Filtering readers have a specific question, and a tag is only useful if it answers that question the same way every time.
