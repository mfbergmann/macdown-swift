# MacDown (Swift) — Roadmap

**North star:** be the *default* app people reach for to open and edit `.md`
files on macOS — clean, fast, and native. We take inspiration from Typora,
iA Writer, Bear, and the original MacDown, but we stay minimal: speed and
clarity over feature sprawl.

Status legend: `[ ]` planned · `[~]` partial/started · `[x]` done

---

## ✅ Shipped (v0.1.0)
- [x] Swift/SwiftUI rewrite, Apple Silicon native, macOS + iOS core
- [x] GFM rendering (tables, task lists, strikethrough, autolinks, footnotes), MathJax, Mermaid
- [x] Live editor syntax highlighting + coordinated editor/preview themes
- [x] Split / editor / preview modes with scroll sync
- [x] Signed + notarized `.app`, GitHub release pipeline, fresh icon

---

## 1. Next up (high value, aligned with the north star)

### Reading-first behavior (do this first — highest value per line of code)
- [x] **Preview-first defaults** — an *existing* file opens in preview mode so you can just read it; a *new* document opens in the editor
- [x] **Per-file view mode memory** — remember how each file was last viewed and restore it on open (LRU-capped at 200 files; "Forget All" in Settings)
- [x] Persist the current view mode across launches (today `viewMode` in `SplitEditorView` resets every time)

### Export (the big one)
- [x] **Export to PDF** — paginated PDF via `WKWebView.pdf(configuration:)` with page size/margins and a print stylesheet
- [x] **Export to HTML** — self-contained document; all CSS/JS inlined
- [x] **Export to DOCX** — rendered HTML → `NSAttributedString` → `.officeOpenXML`
- [x] **Print** support (`NSPrintOperation` via the web view, honouring the user's page setup)
- [x] **Copy as HTML** / **Copy as Rich Text** to clipboard

Export renders in an *offscreen* web view rather than the visible preview, so it
works from editor-only mode and lays out to the page rather than the window.

### Formatting toolbar
- [x] Toolbar + menu actions for: bold, italic, strikethrough, inline code, code block, H1–H3, bullet/numbered list, task item, blockquote, link, image, horizontal rule, table
- [x] Smart toggling (apply/remove around selection; wrap empty selection with placeholder)
- [x] Reuse/extend the existing `insertMarkdownFormatting` notification path; add the missing actions

### "Default `.md` editor" system integration
- [x] Verify/strengthen UTI + document-type registration so macOS offers MacDown as a handler and it can be **Set as Default** for `.md`/`.markdown`/`.mdown`/`.mkd`
- [x] A **document icon** for `.md` files in Finder (`scripts/make-doc-icon.swift`)
- [~] Restore last session / recent documents; sensible new-doc behavior — Open Recent and window restoration come free from `DocumentGroup`; new-doc behavior done
- [ ] (Stretch) Quick Look preview extension for Markdown files

---

## 2. Editing quality (fast, frictionless)
- [x] Find & Replace — Find menu wired to the editor's native find bar (⌘F, ⌥⌘F, ⌘G, ⇧⌘G, ⌘E)
- [x] Auto-continue lists + smart renumbering — bullets, numbered (incrementing), task items (always unchecked), blockquotes; Return on an empty item ends the list
- [x] Auto-pair brackets/quotes; wrap selection with pairs; type over a closing character
- [x] Tab/indent handling, convert tabs→spaces; block indent/outdent across a multi-line selection
- [ ] Paste/drag-drop images → save to a sidecar folder and insert a link
- [ ] **Sidebar**: document **outline / TOC** navigator (jump to headings) *and* a folder file browser for the current document's directory
- [ ] Optional focus/typewriter mode (iA Writer-style), distraction-free toggle
- [ ] Command palette (fuzzy search over all commands)

> Explicitly **not** doing: prose linting / weasel-word / filler-word highlighting.
> Interesting, but it's the feature sprawl the north star warns against.

---

## 3. Preview & theming polish
- [x] Dark-mode preview that follows system appearance (and a manual toggle) — ships a **GitHub Dark** stylesheet paired with GitHub2; the editor highlight theme follows the same setting so both panes always match; print/PDF stays on white paper
- [ ] Tighten scroll-sync accuracy on long/uneven documents
- [ ] Preview style picker polish; allow user custom CSS
- [ ] Per-document front-matter driven options where sensible

---

## 4. App polish
- [ ] **Icon refinement** (cleanup of the current M↓ / Swift-arrow mark)
- [ ] About panel with credits (Tzu-ping Chung, Mou) and bundled third-party licenses
- [ ] First-run sample document / light onboarding
- [ ] Settings screen polish and grouping pass

---

## 5. Distribution & ops
- [ ] Add GitHub Actions signing secrets so CI cuts signed+notarized releases on tag push (see `RELEASING.md`)
- [ ] **In-app update check against the GitHub Releases API** — poll `/releases/latest`, compare versions, offer the download. No Sparkle: less machinery, and it matches how we already ship.
- [ ] **Ship a `.dmg`** installer alongside the current `.zip`
- [ ] (Deferred) Mac App Store: requires a sandboxed second build flavor — revisit later
- [ ] Homebrew Cask once releases are automated

---

## 6. iOS / iPadKit
- [ ] iPad-class layout, document browser, keyboard shortcuts
- [ ] Share-sheet import/export

---

### Performance guardrails (apply throughout)
- Keep launch instant and typing latency invisible.
- Incremental/debounced rendering for large files.
- No feature ships if it makes the editor feel heavier.
