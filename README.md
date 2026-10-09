# NotchBible

A reference field, a passage, a copy button. In your Mac's notch.

Click the notch and start typing. The complete NET Bible is bundled locally,
so verses appear immediately—even offline. The panel grows for the passage
and stays small when empty. No accounts, dependencies, runtime downloads,
analytics, or network requests.

![NotchBible](docs/preview.png)

## Run

Requires macOS 14 or later and the Swift toolchain (Xcode or Command Line Tools).

```sh
scripts/build-app.sh
open build/NotchBible.app
```

The built app is self-contained; it does not need this checkout. You can drag
`build/NotchBible.app` to Applications. Local builds are signed ad hoc, unless
you supply `SIGN_IDENTITY`. They are not notarized.

Click the notch, click the menu bar book, or press **Control–Option–B**.
The field is focused and the previous reference is selected for replacement.
Type; results update on each edit, without a debounce. Click the copy icon or
press **Return** to copy the complete passage with its reference and NET
attribution. **Shift–Command–C** also copies the passage. **Escape**, a click
outside, or another click on the notch closes it. Right-click the menu bar
book for About and Quit. On displays without a notch, use the menu bar or
shortcut; the panel opens at the top center of that display.

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

## Local text and index

The complete **noteless NET Bible edition ©1996–2016** comes from
[eBible.org's verse-per-line archive](https://ebible.org/find/show.php?id=engnet).
There are 66 books, 1,189 chapters, and 31,102 verse addresses. Seventeen
traditional verse numbers have no text in this edition; those are identified
explicitly. Translators' notes are not bundled.

The unmodified text is loaded once into an immutable canonical verse array,
a dictionary of verse-address offsets, and chapter ranges. Book names and
aliases have precomputed exact/prefix indexes. Lookup slices the array rather
than searching the full text. Only visible verse rows are rendered for long
passages; Copy always includes the entire selection.

Source downloaded 2026-10-09, archive dated 2026-10-08. Text SHA-256:
`e1ce3c0be1e4573d4a681d32ccdf7881179432b3ea8753bc4e9da9ae91267c11`.
To reproduce the resource, run `python3 scripts/download-net.py`.
Source acknowledgments and permissions are in
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md).
The app code is MIT licensed; the NET Bible text has its own copyright and
is supplied for free, noncommercial use under the publisher's terms.

## Development

```sh
swift test
scripts/build-app.sh debug
scripts/build-app.sh release --universal  # Apple silicon + Intel
build/NotchBible.app/Contents/MacOS/NotchBible --check
build/NotchBible.app/Contents/MacOS/NotchBible --benchmark
build/NotchBible.app/Contents/MacOS/NotchBible --lookup 'gen1.1;4:4-5'
```

Tests cover the requested examples, shorthand, punctuation, ranges, lists,
ambiguity, typos, incomplete/invalid input, copy attribution, corrupted data,
and a round trip of **every verse address**.

Native SwiftUI + AppKit. The notch uses `NSScreen.safeAreaInsets` and
`auxiliaryTopLeftArea`/`auxiliaryTopRightArea`, a narrow nonactivating `NSPanel`,
and mouse event monitors. A separate keyboard-ready panel holds the field and
passage. The Carbon global shortcut needs no Accessibility permission.
Display changes reposition the panel and recreate notch targets.
This native panel architecture is inspired by
[Alejandro Buján's Tendedero](https://github.com/alejandrobujan/tendedero).

The interface and icon are original. No Tendedero artwork or branding is used.
