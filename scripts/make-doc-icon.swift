#!/usr/bin/env swift
//
// make-doc-icon.swift — render the Finder document icon for `.md` files.
//
// Concept: the macOS document convention — a white page with a folded top-right
// corner — carrying the same M↓ mark as the app icon, so a Markdown file in
// Finder reads as "belongs to MacDown" at a glance.
//
// Usage:  swift scripts/make-doc-icon.swift [output.png]
//
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "/tmp/macdown-doc-icon.png"
let S: CGFloat = 1024

let image = NSImage(size: NSSize(width: S, height: S))
image.lockFocus()
guard let ctx = NSGraphicsContext.current?.cgContext else { fatalError("no context") }

// --- Page geometry. Documents are portrait and narrower than app icons, and
// sit inset from the canvas edges so Finder's grid spacing looks right.
let pageWidth = S * 0.62
let pageHeight = S * 0.80
let pageX = (S - pageWidth) / 2
let pageY = (S - pageHeight) / 2
let page = CGRect(x: pageX, y: pageY, width: pageWidth, height: pageHeight)
let cornerFold = pageWidth * 0.28
let radius = pageWidth * 0.04

/// The page outline: rounded rect with the top-right corner cut away.
func pagePath() -> NSBezierPath {
    let p = NSBezierPath()
    p.move(to: CGPoint(x: page.minX + radius, y: page.minY))
    p.line(to: CGPoint(x: page.maxX - radius, y: page.minY))
    p.appendArc(
        withCenter: CGPoint(x: page.maxX - radius, y: page.minY + radius),
        radius: radius, startAngle: -90, endAngle: 0
    )
    p.line(to: CGPoint(x: page.maxX, y: page.maxY - cornerFold))
    p.line(to: CGPoint(x: page.maxX - cornerFold, y: page.maxY))
    p.line(to: CGPoint(x: page.minX + radius, y: page.maxY))
    p.appendArc(
        withCenter: CGPoint(x: page.minX + radius, y: page.maxY - radius),
        radius: radius, startAngle: 90, endAngle: 180
    )
    p.line(to: CGPoint(x: page.minX, y: page.minY + radius))
    p.appendArc(
        withCenter: CGPoint(x: page.minX + radius, y: page.minY + radius),
        radius: radius, startAngle: 180, endAngle: 270
    )
    p.close()
    return p
}

// Soft drop shadow so the page lifts off dark Finder backgrounds.
ctx.saveGState()
ctx.setShadow(
    offset: CGSize(width: 0, height: -S * 0.008),
    blur: S * 0.022,
    color: NSColor(white: 0, alpha: 0.22).cgColor
)
NSColor.white.setFill()
pagePath().fill()
ctx.restoreGState()

// Hairline edge, so the page still has a boundary on a white background.
NSColor(white: 0.78, alpha: 1).setStroke()
let edge = pagePath()
edge.lineWidth = S * 0.004
edge.stroke()

// --- Folded corner: a triangle shaded slightly darker, as if the paper turned over.
let fold = NSBezierPath()
fold.move(to: CGPoint(x: page.maxX - cornerFold, y: page.maxY))
fold.line(to: CGPoint(x: page.maxX, y: page.maxY - cornerFold))
fold.line(to: CGPoint(x: page.maxX - cornerFold, y: page.maxY - cornerFold))
fold.close()
NSColor(white: 0.88, alpha: 1).setFill()
fold.fill()
NSColor(white: 0.72, alpha: 1).setStroke()
fold.lineWidth = S * 0.003
fold.stroke()

// --- The M↓ mark, matching the app icon, sitting in the lower half of the page
// where document icons conventionally carry their type badge.
let markHeight = pageHeight * 0.26
let markCenterY = page.minY + pageHeight * 0.30
let markBlue = NSColor(srgbRed: 0.12, green: 0.45, blue: 0.92, alpha: 1)
let swiftOrange = NSColor(srgbRed: 0.941, green: 0.318, blue: 0.220, alpha: 1) // #F05138

let mFont = NSFont.systemFont(ofSize: markHeight * 1.30, weight: .heavy)
let roundedM: NSFont = {
    if let d = mFont.fontDescriptor.withDesign(.rounded) {
        return NSFont(descriptor: d, size: mFont.pointSize) ?? mFont
    }
    return mFont
}()
let mStr = NSAttributedString(
    string: "M", attributes: [.font: roundedM, .foregroundColor: markBlue]
)
let mSize = mStr.size()

// Centre the "M" + arrow pair as a unit within the page.
let arrowGap = pageWidth * 0.10
let headSpan = markHeight * 0.42
let markTotalWidth = mSize.width + arrowGap + headSpan * 2
let mX = page.midX - markTotalWidth / 2
mStr.draw(in: CGRect(
    x: mX, y: markCenterY - mSize.height / 2,
    width: mSize.width, height: mSize.height
))

let arrowCenterX = mX + mSize.width + arrowGap + headSpan
let arrowCenterY = markCenterY + markHeight * 0.07
let stemTop = arrowCenterY + markHeight / 2
let stemBottom = arrowCenterY - markHeight / 2
let lineWidth = markHeight * 0.20

swiftOrange.setStroke()
let stem = NSBezierPath()
stem.lineWidth = lineWidth
stem.lineCapStyle = .round
stem.lineJoinStyle = .round
stem.move(to: CGPoint(x: arrowCenterX, y: stemTop))
stem.line(to: CGPoint(x: arrowCenterX, y: stemBottom))
stem.stroke()

let head = NSBezierPath()
head.lineWidth = lineWidth
head.lineCapStyle = .round
head.lineJoinStyle = .round
head.move(to: CGPoint(x: arrowCenterX - headSpan, y: stemBottom + headSpan))
head.line(to: CGPoint(x: arrowCenterX, y: stemBottom))
head.line(to: CGPoint(x: arrowCenterX + headSpan, y: stemBottom + headSpan))
head.stroke()

// --- Text lines above the mark, hinting "this is a document full of prose".
NSColor(white: 0.80, alpha: 1).setFill()
let lineHeight = pageHeight * 0.022
let lineSpacing = pageHeight * 0.050
let lineInset = pageWidth * 0.16
// Start below the folded corner so no line runs underneath it.
let lineTop = page.maxY - cornerFold - pageHeight * 0.06
let lineWidths: [CGFloat] = [1.0, 0.85, 0.95, 0.6]
for (index, factor) in lineWidths.enumerated() {
    let y = lineTop - CGFloat(index) * lineSpacing
    let width = (pageWidth - lineInset * 2) * factor
    let bar = NSBezierPath(
        roundedRect: CGRect(x: page.minX + lineInset, y: y, width: width, height: lineHeight),
        xRadius: lineHeight / 2, yRadius: lineHeight / 2
    )
    bar.fill()
}

image.unlockFocus()

// --- Write PNG
guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("failed to encode PNG")
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
