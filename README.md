# MacDown (Swift)

A modern, native **Swift / SwiftUI rewrite** of [MacDown](https://github.com/MacDownApp/macdown), the open-source Markdown editor for macOS.

> **Credit where it's due.** MacDown was created by **[Tzu-ping Chung](https://github.com/uranusjr)** and contributors, who in turn took inspiration from [Chen Luo](https://twitter.com/chenluois)'s [Mou](http://mouapp.com). This project is an independent, affectionate rewrite — the original hasn't been updated in years, and Apple is winding down support for Intel-only apps. All original copyrights and the MIT License are preserved. This is *their* idea, rebuilt for the next decade of the Mac.

## Why a rewrite?

The original MacDown is Objective-C built on Hoedown, CocoaPods, and an AppKit codebase that predates Apple Silicon. This version is:

- **Pure Swift + SwiftUI**, cross-platform core (macOS and iOS share `MacDownCore`)
- **Apple Silicon native**, no Intel-era dependencies
- **Built with Swift Package Manager** — no CocoaPods, no submodules
- **GitHub-Flavored Markdown** via Apple's [`swift-cmark`](https://github.com/apple/swift-cmark) (tables, task lists, strikethrough, autolinks, footnotes)
- Live preview with editor↔preview scroll sync, Prism syntax highlighting, MathJax, and Mermaid

It is a deliberately *modern* take rather than a 1:1 port — some legacy features (plug-ins, Homebrew subprocess integration, the older preference surface) are intentionally dropped.

## Features

**Reading first.** A file you already have opens in preview, so you can just read
it. New documents open in the editor. Either way, MacDown remembers how you last
viewed each individual file and restores it next time.

**Writing.** Lists continue themselves — bullets keep their marker, numbered
items increment, task items carry on unchecked, and Return on an empty item ends
the list. Brackets and quotes close themselves, wrap a selection when you have
one, and let you type straight through the closing character. Tab indents (or
outdents a whole selected block). Focus mode dims everything but the paragraph
you're in; typewriter mode keeps the cursor centred.

**Getting around.** A command palette on <kbd>⌘K</kbd> fuzzy-searches every
command. A sidebar on <kbd>⌥⌘S</kbd> shows the document outline — click a heading
to jump both panes — alongside the other markdown files in the folder. Find and
replace is on <kbd>⌘F</kbd> / <kbd>⌥⌘F</kbd>.

**Formatting.** Bold, italic, strikethrough, code, headings, lists, task items,
blockquotes, links, images, tables, and rules, from the toolbar, the Format menu,
or the palette. Applying a style twice removes it, and an empty selection gets a
placeholder that's left selected so you can type straight over it.

**Images.** Paste or drag an image in and it's saved to a `<document>.assets`
folder beside the file, with a relative link inserted — so the document stays
portable.

**Sharing.** Export to PDF, HTML, or Word, print, or copy the document as HTML or
rich text straight into Mail or Pages. Export renders offscreen, so it works even
from editor-only mode and lays out to the page rather than the window.

**Appearance.** The preview follows the system light/dark setting (or pin it),
and the editor's syntax theme follows along so the two panes always agree. Drop
your own `.css` into *Application Support/MacDown/Styles* to add a preview theme.

## Install

Download the latest release from the [Releases page](https://github.com/mfbergmann/macdown-swift/releases) — either the `.dmg`
(drag to Applications) or `MacDown.app.zip`.

Released builds are signed with an Apple Developer ID and notarized by Apple, so they open without Gatekeeper warnings.

MacDown checks for new versions itself: **MacDown → Check for Updates…**

## Build from source

Requirements: macOS 15+ and a recent Xcode / Swift 6 toolchain.

```sh
git clone https://github.com/mfbergmann/macdown-swift.git
cd macdown-swift

swift build          # build the package
swift test           # run the test suite
swift run MacDownSwift   # launch the macOS app

./scripts/build-app.sh   # produce dist/MacDown.app
./scripts/build-dmg.sh   # produce dist/MacDown-<version>.dmg
```

See [RELEASING.md](RELEASING.md) for signing, notarization, and cutting a release.

## Project layout

```
Shared/        MacDownCore — cross-platform core
  Editor/        text view, formatter, typing behaviours, image insertion
  Export/        PDF, HTML, Word, print, clipboard
  Models/        document, preferences, view mode, outline, folder listing
  Preview/       WKWebView preview and scroll sync
  Rendering/     cmark-gfm renderer and HTML composition
  Support/       notifications, update check, command palette, about, first run
  Views/         split view, sidebar, command palette, settings
macOS/         macOS app target (DocumentGroup, menus, Settings)
iOS/           iOS app target
Tests/         Swift Testing test suite
scripts/       build-app.sh, build-dmg.sh, icon generators
```

The design rule throughout: anything with interesting logic — the formatter, the
typing behaviours, the outline parser, version comparison, fuzzy matching — is a
pure transform over values, so it can be tested without a running UI. The AppKit
and SwiftUI layers stay thin glue over those.

## License

Released under the **MIT License**, the same as the original MacDown. The original
copyright — `Copyright (c) 2014 Tzu-ping Chung` — is preserved in
`LICENSE/macdown.txt`, alongside the full license texts for every third-party
component this app actually ships, in the `LICENSE/` directory.

The following editor themes and preview stylesheets come from [Mou](http://mouapp.com), courtesy of Chen Luo:

* Mou Fresh Air / Fresh Air+
* Mou Night / Night+
* Mou Paper / Paper+
* Tomorrow / Tomorrow Blue / Tomorrow+
* Writer / Writer+
* Clearness / Clearness Dark
* GitHub / GitHub2

`GitHub Dark` is original to this project.

## Acknowledgements

- **Tzu-ping Chung** and the MacDown contributors — for the original app this is built on.
- **Chen Luo** — for Mou, and the themes used here.
- [swift-cmark](https://github.com/apple/swift-cmark), [Highlightr](https://github.com/raspu/Highlightr), [Prism](https://prismjs.com), [MathJax](https://www.mathjax.org), and [Mermaid](https://mermaid.js.org).
