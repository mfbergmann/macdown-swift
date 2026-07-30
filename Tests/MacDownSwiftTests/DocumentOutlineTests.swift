import Foundation
import Testing
@testable import MacDownCore

private func titles(_ markdown: String) -> [String] {
    DocumentOutline.parse(markdown).headings.map(\.title)
}

private func levels(_ markdown: String) -> [Int] {
    DocumentOutline.parse(markdown).headings.map(\.level)
}

@Suite("Document outline")
struct DocumentOutlineTests {

    @Test("Finds ATX headings at every level")
    func atxLevels() {
        let md = "# One\n## Two\n### Three\n#### Four\n##### Five\n###### Six"
        #expect(levels(md) == [1, 2, 3, 4, 5, 6])
        #expect(titles(md) == ["One", "Two", "Three", "Four", "Five", "Six"])
    }

    @Test("Seven hashes is not a heading")
    func tooManyHashes() {
        #expect(titles("####### Seven").isEmpty)
    }

    @Test("A hash with no space is not a heading")
    func hashWithoutSpace() {
        #expect(titles("#NotAHeading").isEmpty)
        #expect(titles("#hashtag mid sentence").isEmpty)
    }

    @Test("Closing hashes are decoration, not title text")
    func closingHashes() {
        #expect(titles("## Title ##") == ["Title"])
    }

    @Test("Ignores headings inside fenced code blocks")
    func skipsFencedCode() {
        let md = """
        # Real Heading

        ```sh
        # this is a shell comment
        echo hi
        ```

        ## Another Real One
        """
        #expect(titles(md) == ["Real Heading", "Another Real One"])
    }

    @Test("Handles tilde fences too")
    func skipsTildeFence() {
        let md = "# Real\n\n~~~\n# not a heading\n~~~\n"
        #expect(titles(md) == ["Real"])
    }

    @Test("Skips YAML front matter")
    func skipsFrontMatter() {
        let md = """
        ---
        title: Something
        tags: [a, b]
        ---

        # Actual Heading
        """
        #expect(titles(md) == ["Actual Heading"])
    }

    @Test("Recognises setext headings")
    func setext() {
        let md = "Title\n=====\n\nSubtitle\n--------\n"
        #expect(titles(md) == ["Title", "Subtitle"])
        #expect(levels(md) == [1, 2])
    }

    @Test("Strips inline markdown from titles")
    func stripsInlineMarkup() {
        #expect(titles("# A **bold** heading") == ["A bold heading"])
        #expect(titles("# With `code`") == ["With code"])
        #expect(titles("# A [link](https://example.com) here") == ["A link here"])
    }

    @Test("Indented four spaces is a code block, not a heading")
    func indentedCodeBlock() {
        #expect(titles("    # indented") .isEmpty)
        #expect(titles("   # three spaces is fine") == ["three spaces is fine"])
    }

    @Test("Ranges point at the heading line in the source")
    func ranges() {
        let md = "intro\n\n# Target\n\nbody"
        let outline = DocumentOutline.parse(md)
        let heading = try! #require(outline.headings.first)
        let text = (md as NSString).substring(with: heading.range)
        #expect(text == "# Target")
    }

    @Test("Indexes run in document order from zero")
    func indexes() {
        let outline = DocumentOutline.parse("# A\n## B\n### C")
        #expect(outline.headings.map(\.index) == [0, 1, 2])
    }

    @Test("Finds the heading enclosing a caret position")
    func enclosingHeading() {
        let md = "# First\n\nbody\n\n# Second\n\nmore"
        let outline = DocumentOutline.parse(md)
        let location = (md as NSString).range(of: "more").location
        #expect(outline.heading(enclosing: location)?.title == "Second")
    }

    @Test("An empty document has an empty outline")
    func empty() {
        #expect(DocumentOutline.parse("").isEmpty)
        #expect(DocumentOutline.parse("just a paragraph").isEmpty)
    }
}

@Suite("Heading slugs")
struct HeadingSlugTests {

    @Test("Lowercases and hyphenates")
    func basicSlug() {
        #expect(DocumentOutline.Slugger.baseSlug(for: "Hello World") == "hello-world")
    }

    @Test("Drops punctuation")
    func dropsPunctuation() {
        #expect(DocumentOutline.Slugger.baseSlug(for: "What's New?") == "whats-new")
        #expect(DocumentOutline.Slugger.baseSlug(for: "A, B & C") == "a-b-c")
    }

    @Test("Collapses runs of hyphens")
    func collapsesHyphens() {
        #expect(DocumentOutline.Slugger.baseSlug(for: "a   b") == "a-b")
    }

    @Test("Duplicate headings get numbered slugs")
    func duplicates() {
        let outline = DocumentOutline.parse("# Setup\n## Setup\n### Setup")
        #expect(outline.headings.map(\.slug) == ["setup", "setup-1", "setup-2"])
    }

    @Test("A heading of only punctuation still gets a usable slug")
    func punctuationOnly() {
        let outline = DocumentOutline.parse("# ???")
        #expect(outline.headings.first?.slug == "section")
    }
}

@Suite("Rendered heading anchors")
struct HeadingAnchorTests {

    let renderer = MarkdownRenderer()

    @Test("Every heading gets an id and an index")
    func anchorsPresent() {
        let html = renderer.render("# One\n## Two").html
        #expect(html.contains("<h1 id=\"one\" data-heading-index=\"0\">"))
        #expect(html.contains("<h2 id=\"two\" data-heading-index=\"1\">"))
    }

    @Test("Anchor slugs match the outline's slugs")
    func anchorsMatchOutline() {
        let md = "# Getting Started\n## What's New?\n## What's New?"
        let outline = DocumentOutline.parse(md)
        let html = renderer.render(md).html

        for heading in outline.headings {
            #expect(
                html.contains("id=\"\(heading.slug)\""),
                "rendered HTML is missing the outline's slug \(heading.slug)"
            )
        }
    }

    @Test("Heading indexes line up with the outline's order")
    func indexesMatchOutline() {
        // A code fence between headings is the case most likely to desync the
        // source parser from cmark.
        let md = """
        # First

        ```
        # not a heading
        ```

        ## Second
        """
        let outline = DocumentOutline.parse(md)
        let html = renderer.render(md).html

        #expect(outline.headings.count == 2)
        for heading in outline.headings {
            #expect(html.contains("data-heading-index=\"\(heading.index)\""))
        }
        // The fence content must not have produced a third heading.
        #expect(!html.contains("data-heading-index=\"2\""))
    }

    @Test("Heading text is preserved")
    func textPreserved() {
        let html = renderer.render("# A **bold** heading").html
        #expect(html.contains("<strong>bold</strong>"))
    }
}
