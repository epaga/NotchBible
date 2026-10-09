# Building and developing NotchBible

For downloading the DMG and using the app, see the [main README](../README.md).
This page covers building from source, bundling translations in a local build,
reference and search details, development, and signed releases.

[Build from source](#build-and-run-from-source) ·
[Add translations](#add-local-translations) ·
[Reference syntax](#references) ·
[Search syntax](#full-text-search) ·
[Development](#development) ·
[Release a DMG](#release-a-dmg)

## Build and run from source

Requires **macOS 14 or later** and **Swift 5.9 or later**, supplied by Xcode or
the Xcode Command Line Tools. Clone the repository first:

```sh
git clone https://github.com/epaga/NotchBible.git
cd NotchBible
```

Then build and open the app:

```sh
scripts/build-app.sh
open build/NotchBible.app
```

The built app is self-contained; it does not need this checkout. You can drag
`build/NotchBible.app` to Applications. Local builds are signed ad hoc, unless
you supply `SIGN_IDENTITY`. They are not notarized.

## Add local translations

The installed app also loads `.txt` files from
`~/Library/Application Support/NotchBible/Translations` at launch. Use **Open
Translations Folder…** in the menu bar icon's right-click menu to create and open
it. Files added there work with the signed download and survive app replacement;
see the [user instructions](../README.md#add-your-own-translations).
Restart after adding, changing, or removing files. Invalid user files and
duplicate names are skipped with a warning; bundled editions take precedence.

For a development build, you can also bundle additional texts:

**This repository includes NET only.** Additional translations can be supplied
locally for use under their own terms; their texts are ignored by Git. The resource
directory is ignored except for `NETBible.txt`, so new translations, archives,
and backup files stay out of ordinary commits too. NET is also copyrighted;
its permissions are described below and in [THIRD-PARTY-NOTICES.md](../THIRD-PARTY-NOTICES.md).

To add a local translation, place a UTF-8 `.txt` file in
`Sources/BibleCore/Resources` and rebuild with `scripts/build-app.sh`.
Quit any running copy of NotchBible, then open `build/NotchBible.app`. Enter a
reference or search and select your translation's tab below the results.
Every text file there is automatically bundled and discovered at launch; no
Swift code or translation list needs editing. The tab name is the filename
without `.txt` and a trailing `Bible`: `ExampleBible.txt` becomes `Example`.

Use one verse per line in canonical book/chapter/verse order:

```text
GEN 1:1 In the beginning...
GEN 1:2 ...
```

Use the same three-letter book codes as `NETBible.txt`; the complete list is in
[Books.swift](../Sources/BibleCore/Books.swift). Save plain UTF-8 text, keep verses
in Bible book/chapter/verse order, and avoid duplicate addresses or translation
names. Each translation has its own verse index, so differences in numbering and partial coverage are
preserved. A local translation can contain only some books or chapters;
unavailable passages show a message with the translation tabs still accessible.
All editions are indexed once locally, so switching does not read files or
access the network. Copied passages always identify the selected edition.

**Build shared apps from a clean checkout containing only NET.** Git's ignore
rules do not affect SwiftPM or the app build script: a build from a checkout
containing additional local `.txt` files includes those texts in the app.
Run `build/NotchBible.app/Contents/MacOS/NotchBible --check` to list the
available translations, including the user's Translations folder. Check
`build/NotchBible.app/Contents/Resources` to confirm which texts are actually
bundled before distributing it. Additional texts need their
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
edition-specific addressing, partial coverage, persistent selection, and merging
user translations while handling missing folders, invalid files, and duplicate
names. Search
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

## Release a DMG

Releases are built locally on a Mac with Xcode, a **Developer ID Application**
certificate and its private key, and notarization credentials. The DMG contains
a universal app for Apple silicon and Intel, plus an Applications shortcut.
The app and DMG are both notarized and have their tickets stapled for offline
verification. Signing uses the hardened runtime and a secure timestamp, as
required by [Apple's notarization workflow](https://developer.apple.com/documentation/security/customizing-the-notarization-workflow).

Store notarization credentials in Keychain once (the password is prompted securely):

```sh
xcrun notarytool store-credentials notchbible \
  --apple-id 'YOUR_APPLE_ID' --team-id 'YOUR_TEAM_ID'
```

An existing `notarytool` Keychain profile works too. For an App Store Connect
team API key, use `--key /path/to/AuthKey.p8 --key-id YOUR_KEY_ID --issuer YOUR_ISSUER_ID`
instead of the Apple ID and team ID options. Keep keys and passwords outside
this repository.

Update `CFBundleShortVersionString` and `CFBundleVersion` in `packaging/Info.plist`
for each release, commit the changes, and build from a checkout containing only
the committed NET text. The release script refuses additional local translations.
If your development checkout has extra texts, make a clean release worktree
after committing the release scripts and version changes:

```sh
git worktree add --detach ../NotchBible-release HEAD
cd ../NotchBible-release
```

```sh
SIGN_IDENTITY='Developer ID Application: John Goering (XAHCV8RVGN)' \
NOTARY_KEYCHAIN_PROFILE=notchbible scripts/release-dmg.sh
```

For version 1.0.0 this produces `build/NotchBible-1.0.0-universal.dmg` and a
matching `.dmg.sha256` checksum. Notarization responses and failure logs are
saved under `build/`. The script finishes only after Apple accepts both uploads
and signature, ticket, and Gatekeeper checks pass.

After checking the DMG, push the release commit and tag, then attach the files
to a [GitHub Release](https://cli.github.com/manual/gh_release_create):

```sh
git tag v1.0.0
git push origin main v1.0.0
gh release create v1.0.0 \
  build/NotchBible-1.0.0-universal.dmg \
  build/NotchBible-1.0.0-universal.dmg.sha256 \
  --verify-tag --title 'NotchBible 1.0.0' --generate-notes
```

Replace the version for later releases. For an existing release, use
`gh release upload v1.0.0 build/NotchBible-1.0.0-universal.dmg build/NotchBible-1.0.0-universal.dmg.sha256`.

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

The app code is [MIT licensed](../LICENSE). **Bible texts are excluded from that
license.** NET is copyrighted by Biblical Studies Press, L.L.C.; its publisher
permits free, noncommercial use of the Scripture text with the NET designation
and copyright acknowledgment under its [permissions](https://netbible.com/copyright/).
Commercial use requires separate licensing. Translators' notes are excluded.
Source acknowledgments and the required notice are preserved in
[THIRD-PARTY-NOTICES.md](../THIRD-PARTY-NOTICES.md) and [NET source notice](NET-source.html).
