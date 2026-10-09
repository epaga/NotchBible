# NET Bible®

The complete, **noteless** NET Bible text in `Sources/BibleCore/Resources/NETBible.txt`
was downloaded from [eBible.org](https://ebible.org/find/show.php?id=engnet),
[verse-per-line archive](https://ebible.org/Scriptures/engnet_vpl.zip), on 2026-10-09.
The archive describes this text as copyright ©1996–2016 Biblical Studies Press,
L.L.C. Its original source notice is preserved in `docs/NET-source.html`.

Scripture quoted by permission. Quotations designated (NET) are from the NET Bible®
copyright ©1996, 2019 by Biblical Studies Press, L.L.C. https://netbible.com.
All rights reserved.

This app is a free, noncommercial use of the Scripture text. The NET text has its
own copyright and **is not covered by the app's MIT license**. Follow the
[publisher's permissions](https://netbible.com/copyright/) for any distribution
or commercial use. Translators' notes are not included. The display identifies
the translation as NET; copied passages include NET and the copyright notice.

Seventeen traditional verse addresses are blank in this edition. Their source
records are preserved as supplied; the app explicitly identifies these empty
addresses instead of substituting text from another translation.

# Additional local translations

This repository distributes **NET only**. Additional text files placed locally
in `Sources/BibleCore/Resources` are ignored by Git and retain their respective
copyrights. They are not covered by the app's MIT license, and the NET permissions
and attribution above apply to NET alone.

Both SwiftPM and `scripts/build-app.sh` bundle all local `.txt` files, including
ones ignored by Git. Build publicly distributed apps from a clean checkout
containing only NET. Including another translation requires its own redistribution
permission and attribution; the app adds no publisher notice for non-NET texts.
No additional translation texts are downloaded by the app.

# Tendedero

The native panel approach was inspired by
[Tendedero](https://github.com/alejandrobujan/tendedero), by Alejandro Buján:
AppKit NSPanel, SwiftUI NSHostingView, NSScreen geometry, NSEvent mouse monitors,
and Carbon hot keys. NotchBible's implementation, interface, name, and icon are
original; no Tendedero assets are included.
