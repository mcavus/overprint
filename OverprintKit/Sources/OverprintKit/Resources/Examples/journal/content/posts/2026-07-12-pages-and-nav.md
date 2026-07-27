---
title: Pages, and what the nav is for
date: 2026-07-12
tags: [process, notes]
slug: pages-and-nav
draft: false
---

A woman emailed in June asking whether I take commissions, and I realized I had written forty
thousand words about dovetails without ever writing down who I am or where the shop is. Everything
on this site was a journal entry, which meant everything was dated, everything was in the feed, and
everything scrolled away.

Some writing is not an entry. "About" is not an entry. A colophon is not an entry. They do not
belong to a day, they should not turn up in the RSS feed, and they should not sit in a tag page
between two posts about finishing schedules. They are just there, permanently, waiting for someone
who wants them.

That is what standalone pages are for. They live in `content/pages/` rather than
`content/posts/`, one file per page, and their frontmatter is almost nothing:

```
---
title: About
---
```

No date, no tags, no slug line, no draft flag. The slug comes from the filename, so `about.md`
becomes `about.html`. A page is a title and a body, and it is the missing date that keeps it out of
the post list, out of the feed, and out of the tag pages.

Which raises the obvious question of how anyone finds them, since nothing links to a page
automatically. That is the nav's job. The nav is a list of labels and urls in `overprint.yml`, and
it is the one place where the site's structure is stated rather than inferred:

```yaml
nav:
  - { label: Journal, url: index.html }
  - { label: About, url: about.html }
  - { label: Colophon, url: colophon.html }
```

Three links, in the order I want them read. `index.html` is the journal itself. The other two are
the pages I just wrote. A nav entry can also point at a tag page if you want a section that is
really a filter, though I would be careful there, because a nav link to a tag with nothing in it is
a promise the site cannot keep.

I wrote both pages in an afternoon. The About is short and says where the shop is. The Colophon
turned out to be the more interesting one, because explaining why the page is cream and why the
type is a sans forced me to admit that I had reasons, and that they were mostly about not wanting
this to look finished.
