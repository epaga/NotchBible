# NotchBible

A free macOS menu bar app for looking up and searching Bible verses from your notch.
Click the notch, type a reference or a few words, and read or copy the results.
The complete NET Bible is included, so everything works offline.

![NotchBible's reference field below the Mac notch](docs/preview.png)

## Download and install

**[Download the DMG from GitHub Releases](https://github.com/epaga/NotchBible/releases).**
Requires **macOS 14 or later**; the universal app runs on Apple silicon and Intel Macs.
The release app is signed by its developer and notarized by Apple.

1. Download the `NotchBible-…-universal.dmg` file and open it.
2. Drag **NotchBible** onto the **Applications** shortcut.
3. Eject the disk image and open **NotchBible** from Applications.
4. Click your notch or the book icon in the menu bar, or press **Control–Option–B**.

You do not need Xcode or any developer tools to use the download.

## Features

- **Offline Bible lookup:** the complete NET Bible text is included, without translators' notes.
- **Flexible references:** full book names, abbreviations, verse ranges, whole chapters,
  and multiple passages. Common shorthand and small spelling mistakes are accepted.
- **Full-text search:** find words and phrases, use wildcards, exclude terms, and filter
  by book or testament. Results update as you type and stay in Bible order.
- **Copy complete results:** copy an entire passage or every search match, including
  references and the translation name.
- **Works with any Mac display:** use the notch, menu bar icon, or keyboard shortcut.
- **A panel that fits:** it grows with the passage, can be resized, and remembers its size.
- **Optional translations:** add your own text files to a [local folder](#add-your-own-translations)
  and switch between them with tabs. Your last selection is remembered.

No accounts, analytics, or network requests. Your lookups and searches stay on your Mac.

## Use

| Action | Control |
| --- | --- |
| Open or close | Click the notch or menu bar book, or press **Control–Option–B** |
| Look up or search | Type in the field; results update on each edit |
| Copy a complete result | Click the copy icon, press **Return**, or press **Shift–Command–C** |
| Dismiss | Press **Escape** or click outside the panel |
| Add translation files | Right-click the menu bar book → **Open Translations Folder…** |
| About or Quit | Right-click the menu bar book |

Opening the panel selects your previous input so you can replace it immediately.
On displays without a notch, the panel opens at the top center of the display.
Drag the bottom-right grip to resize it; the app remembers your width and height.

When an abbreviation matches several books, choose one with **↑/↓** and
**Return/Tab**, or click it. In that situation, **Return** selects the book.
For a completed passage or search, **Return** copies the result.

### Look up a passage

| Type | Result |
| --- | --- |
| `John 3:16` or `jn3.16` | A single verse |
| `John 3:16-18` | A verse range |
| `John 3:16,18,20` | Selected verses |
| `Psalm 23` or `Ps23` | A whole chapter |
| `Gen1-3` | Several chapters |
| `Gen1:1;John3:16` | Passages from different books |

Book names are case insensitive. Unfinished references preview what you have
entered so far; copying becomes available once the reference is complete.
See the [full reference guide](docs/DEVELOPMENT.md#references) for more shorthand and examples.

### Search for words

| Type | Result |
| --- | --- |
| `created God` | Verses containing both words, in any order |
| `"for God"` | An exact phrase, ignoring punctuation |
| `love -world` | Verses containing love but excluding world |
| `love*` | Words beginning with love |
| `*love*` | Words containing love |
| `book:gen created God` | Search only Genesis |
| `in:nt love` | Search only the New Testament |

Search matches whole words unless you use `*`. The panel shows 100 matches per
page; use the arrows to browse. **Copy includes all matches**, even across pages.
Click a result's chapter number to open that chapter, or its verse number to
open that verse. See the [full search guide](docs/DEVELOPMENT.md#full-text-search)
for more filters and combinations.

## Add your own translations

**The download includes NET only.** You can add other translations without rebuilding
the app. Right-click the book icon in the menu bar and choose **Open Translations
Folder…**. This creates and opens:

```text
~/Library/Application Support/NotchBible/Translations
```

To add a translation:

1. Obtain a Bible text you have permission to use and save it as a plain **UTF-8 `.txt`** file.
2. Give it a distinct name, such as `MyTranslationBible.txt`. Its tab will be called
   **MyTranslation**: `.txt` and a trailing `Bible` are removed from the filename.
3. Put one verse on each line, in Bible book order, then chapter and verse order:

   ```text
   GEN 1:1 Your translation's text for Genesis 1:1.
   GEN 1:2 Your translation's text for Genesis 1:2.
   ```

4. Use the [supported book codes](Sources/BibleCore/Books.swift), such as `GEN`, `PSA`,
   and `JOH`, and avoid duplicate verse addresses. A file may contain just some
   books or chapters; missing passages are shown as unavailable.
5. Copy the `.txt` file into the Translations folder, then **quit and reopen
   NotchBible**. Enter a reference or search to see its tab below the results.

Select a translation's tab below the results to switch editions. Switching keeps
your current reference or search, and the app remembers your selection.
Each edition uses its own verse numbering. Copied passages identify the selected
translation; NET copies also include its copyright acknowledgment.

To update or remove a translation, replace or remove its file and restart the app.
Files in this folder stay in place when you update NotchBible. Keep your own backups.
Invalid files or duplicate translation names are skipped with a warning; a user
file cannot replace a bundled edition such as NET. Bible texts retain their own
copyrights and permissions.

## Credits and source

The bundled noteless NET Bible edition ©1996–2016 comes from
[eBible.org](https://ebible.org/find/show.php?id=engnet). Bible texts are excluded
from the app code's [MIT license](LICENSE); see the
[text notices and permissions](THIRD-PARTY-NOTICES.md).

The app uses native macOS controls and panels. Its panel architecture is inspired
by [Alejandro Buján's Tendedero](https://github.com/alejandrobujan/tendedero).
NotchBible's interface and icon are original.

For source builds, bundled translations, tests, implementation details, and
release packaging, see [Building and developing NotchBible](docs/DEVELOPMENT.md).
