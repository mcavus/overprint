---
title: About
---

**shard** is a small command line tool for splitting large text files into addressable chunks and putting them back together again without losing a byte. It started as a fifty line script for chopping up database dumps that were too big to move over a flaky connection, and it grew into something a few thousand people now depend on.

It splits a file on a boundary you choose (line count, byte size, or a regular expression), records what it did in a manifest with a checksum for every piece, and puts the pieces back from that manifest, complaining loudly if anything is missing or corrupt.

Nothing beyond that. shard will not compress your files, encrypt them, upload them, or watch a directory for changes. Other tools do those jobs well and I would rather compose with them than reimplement them badly.

## Where to find it

The source lives at `github.com/example/shard`. It is MIT licensed. Releases are published as static binaries for macOS and Linux, and the whole thing builds from source with a single command if you would rather do that.

Bug reports are welcome. Feature requests are welcome too, though I will usually say no, and the reason is almost always that the feature belongs in a different tool.

## About this site

These release notes are built with Overprint, a static site generator that turns a folder of Markdown into a site. Every post here carries tags, and each tag gets its own listing page, which is how the navigation above works. If you want to read only the performance work, or only the bug fixes, the tag pages are the fastest way in.

## Who writes this

I am Dagny Halvorsen. I work on backend infrastructure during the day and maintain shard in the evenings. I live in Trondheim. If you need to reach me, the issue tracker is the best place, since email tends to sink into a pile I only dredge every few weeks.
