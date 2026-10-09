# NotchBible

A free macOS menu bar app for looking up and searching Bible verses from your notch.

Click the notch and type a reference like `John 3:16` or a search like `created God`.
The complete NET Bible is bundled locally, so lookup and search work offline.
The panel grows for the passage and stays small when empty. Macs without a notch
can use the menu bar icon or keyboard shortcut. No accounts, third-party
dependencies, runtime downloads, analytics, or network requests.

![NotchBible's reference field below the Mac notch](docs/preview.png)

## Build and run

Requires **macOS 14 or later** and **Swift 5.9 or later**, supplied by Xcode or
the Xcode Command Line Tools. Run these commands from the repository directory:

```sh
scripts/build-app.sh
open build/NotchBible.app
```

The built app is self-contained; it does not need this checkout. You can drag
`build/NotchBible.app` to Applications. Local builds are signed ad hoc, unless
you supply `SIGN_IDENTITY`. They are not notarized.

## Use

| Action | Control |
| --- | --- |
| Open or close | Click the notch or menu bar book, or press **Control–Option–B** |
| Look up or search | Type in the field; results update on each edit |
| Copy a complete result | Click the copy icon, press **Return**, or press **Shift–Command–C** |
| Dismiss | Press **Escape** or click outside the panel |
| About or Quit | Right-click the menu bar book |

Opening the panel focuses the field and selects the previous input for replacement.
On displays without a notch, the panel opens at the top center of the display.
Copy includes the complete passage or **all search matches**, their references,
and the selected translation. NET copies also include the required copyright
acknowledgment. When book choices are shown, **Return** selects a choice instead.

Small translation tabs stay at the bottom of the results while the passage
scrolls. The selected tab is brighter and underlined. Switching keeps your
reference or search, and the app remembers the last translation across launches.

Drag the bottom-right grip to resize the panel. Horizontal resizing keeps it
centered under the notch, and the top stays in place. Your chosen width and
height are remembered across launches and fitted to the current display.

## Local translations

**This repository includes NET only.** Additional translations can be supplied
locally for use under their own terms; their texts are ignored by Git. The resource
directory is ignored except for `NETBible.txt`, so new translations, archives,
and backup files stay out of ordinary commits too. NET is also copyrighted;
its permissions are described below and in [THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).

To add a local translation, place a UTF-8 `.txt` file in
`Sources/BibleCore/Resources` and rebuild with `scripts/build-app.sh`.
Every text file there is automatically bundled and discovered at launch; no
Swift code or translation list needs editing. The tab name is the filename
without `.txt` and a trailing `Bible`: `ExampleBible.txt` becomes `Example`.

Use one verse per line in canonical book/chapter/verse order:

```text
GEN 1:1 In the beginning...
GEN 1:2 ...
```

Use the same three-letter book codes as `NETBible.txt`. Each translation
has its own verse index, so differences in numbering and partial coverage are
preserved. A local translation can contain only some books or chapters;
unavailable passages show a message with the translation tabs still accessible.
All editions are indexed once locally, so switching does not read files or
access the network. Copied passages always identify the selected edition.

**Build shared apps from a clean checkout containing only NET.** Git's ignore
rules do not affect SwiftPM or the app build script: a build from a checkout
containing additional local `.txt` files includes those texts in the app.
Run `build/NotchBible.app/Contents/MacOS/NotchBible --check` to list the
translations in a built app before distributing it. Additional texts need their
own redistribution permission and attribution.

## References

Book names are case insensitive. Full names, prefixes, common abbreviations,
small spelling mistakes, Arabic/roman/word ordinals, and Unicode punctuation
are accepted. Ambiguous abbreviations offer a book choice instead of silently
choosing the wrong book. Use **↑/↓** and **Return/Tab**, or click a choice.

| Input | Passage |
| --- | --- |
| `gen1,1`, `Gen1.1`, `gen1/1`, `Gen. 1:1`, `Genesis 1 1` | Genesis 1:1 |
| `genes 1:1-2:3`, `gen1.1-2.3`, `gen1:1-2:3` | Genesis 1:1–2:3 |
| `gen1.1;4:4-5` | Genesis 1:1; 4:4–5 |
| `Gen 1,31-2,3` | Genesis 1:31–2:3 |
| `John3:16,18-20,22` | John 3:16; 18–20; 22 |
| `Ps23`, `Psalm 119`, `Gen1-3` | Whole chapters or chapter ranges |
| `1John1:1`, `1. Jn 1.1`, `I John 1:1`, `First John 1:1` | 1 John 1:1 |
| `IIIJohn4`, `Jude5-7`, `Phm4` | Verse shorthand for single-chapter books |
| `Gen chapter 1 verse 1`, `Gen ch.1 v.1`, `gen1v1` | Genesis 1:1 |
| `Gen1:1 through 3`, `Gen1:1 to 3` | Genesis 1:1–3 |
| `Gen1:1;John3:16`, `Gen1:1 & John3:16` | Multiple books/passages |
| `genisis1:1`, `genseis1:1` | Genesis 1:1, with typo correction |

A semicolon starts another chapter/reference within the current book. A comma
after a chapter/verse pair lists more verses in that chapter. A plus does the
same: `heb13.7+13` selects Hebrews 13:7 and 13. The first comma
between two numbers is a chapter/verse delimiter, so `gen1,1` works.
For whole-chapter lists, write `Gen1;3;5`. Invalid addresses are explained;
unfinished input previews the known portion and disables copying until complete.

## Full-text search

When the input is not a recognized reference, it searches the selected translation
locally and case insensitively. Each word must occur in the same verse. Words match
whole words; use `*` for part of a word. Results stay in Bible order.

| Input | Search |
| --- | --- |
| `created God` | Both words, in any order |
| `"for God"` | Consecutive words in this order |
| `love -world` | Love, excluding verses containing world |
| `God -"for God"` | God, excluding the phrase |
| `love*`, `*love*` | Words beginning with love, or containing love |
| `book:gen book:ps created God` | Both words in Genesis OR Psalms |
| `in:ot love`, `in:nt love` | Old Testament, or New Testament |
| `book:gen book:john in:nt love` | John only: different filters are ANDed |
| `in:ot in:nt love` | Either testament: repeated filters are ORed |
| `book:"1 John" love`, `love -book:ps` | A full book name, or an excluded book |

Book filters accept the same names and abbreviations as references. Phrases ignore
punctuation between consecutive words. Quote a book name to search for that word
(e.g. `"Job"`), since bare book names offer reference suggestions. An unfinished
quote or filter previews the completed part of the query and disables copying.

The panel shows 100 matches per page and the total count; use the arrow buttons
to browse all matches. Click a result's chapter number to open that chapter, or
its verse number to open that verse. **Copy includes every matching verse** and
its reference, the translation label, and NET's copyright acknowledgment when
using NET. No matches and invalid filters show a message while keeping
translation tabs accessible.

## NET Bible text and permissions

The complete **noteless NET Bible edition ©1996–2016** comes from
[eBible.org's verse-per-line archive](https://ebible.org/find/show.php?id=engnet).
There are 66 books, 1,189 chapters, and 31,102 verse addresses. Seventeen
traditional verse numbers have no text in this edition; those are identified
explicitly. Translators' notes are not bundled.

Source downloaded 2026-10-09, archive dated 2026-10-08. Text SHA-256:
`e1ce3c0be1e4573d4a681d32ccdf7881179432b3ea8753bc4e9da9ae91267c11`.
`python3 scripts/download-net.py` downloads the current archive and replaces the
resource and its source notice. This development command requires internet access;
building and running the app use the committed text. If the upstream archive
changes, review the replacement and update the recorded hash and source details.

The app code is [MIT licensed](LICENSE). **Bible texts are excluded from that
license.** NET is copyrighted by Biblical Studies Press, L.L.C.; its publisher
permits free, noncommercial use of the Scripture text with the NET designation
and copyright acknowledgment under its [permissions](https://netbible.com/copyright/).
Commercial use requires separate licensing. Translators' notes are excluded.
Source acknowledgments and the required notice are preserved in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md) and [docs/NET-source.html](docs/NET-source.html).

## Development

```sh
swift test
scripts/build-app.sh debug
scripts/build-app.sh release --universal  # Apple silicon + Intel
build/NotchBible.app/Contents/MacOS/NotchBible --check
build/NotchBible.app/Contents/MacOS/NotchBible --benchmark
build/NotchBible.app/Contents/MacOS/NotchBible --lookup 'gen1.1;4:4-5'
build/NotchBible.app/Contents/MacOS/NotchBible --lookup 'book:gen book:ps created God'
build/NotchBible.app/Contents/MacOS/NotchBible --translation NET --lookup 'heb13.7+13'
```

Tests cover reference examples, shorthand, punctuation, ranges, lists,
ambiguity, typos, incomplete/invalid input, copy attribution, corrupted data,
and a round trip of **every NET verse address**, plus translation discovery,
edition-specific addressing, partial coverage, and persistent selection. Search
tests cover AND, phrases, exclusions, wildcards, filter grouping, Unicode casing,
reference fallback, translation switching, complete copying, and comparisons
against an independent text scan of every bundled translation. `--benchmark`
reports reference and search timings separately, including broad wildcard queries.

The text is loaded once into an immutable canonical verse array, a dictionary of
verse-address offsets, and chapter ranges. Each translation also has an inverted
word index, compact word positions for phrases, and book/testament postings.
Searches intersect or subtract sorted verse IDs; wildcards expand the word
vocabulary rather than scanning verse text. Book names and aliases have
precomputed exact/prefix indexes. Reference lookup slices the verse array.

Native SwiftUI + AppKit. The notch uses `NSScreen.safeAreaInsets` and
`auxiliaryTopLeftArea`/`auxiliaryTopRightArea`, a narrow nonactivating `NSPanel`,
and mouse event monitors. A separate keyboard-ready panel holds the field and
passage. The Carbon global shortcut needs no Accessibility permission.
Display changes reposition the panel and recreate notch targets.
This native panel architecture is inspired by
[Alejandro Buján's Tendedero](https://github.com/alejandrobujan/tendedero).

The interface and icon are original. No Tendedero artwork or branding is used.
