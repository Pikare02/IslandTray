#!/usr/bin/env swift
//
// Renders the app icon. Run from the repository root:
//
//     swift scripts/make-icon.swift
//
// Writes Resources/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png at
// 1024x1024, opaque and square -- iOS applies the corner mask itself, and an
// icon with alpha is rejected at submission.
//
// CoreGraphics only, no external tool or service, so the icon in the
// repository can always be reproduced from what is in the repository.

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let side: CGFloat = 1024

// The motif: the Dynamic Island's pill above an open tray, the app in one
// picture. Everything is sized so it survives the ~60pt the home screen
// actually draws -- two shapes, high contrast, no detail below ~40px.
let pillSize = CGSize(width: 300, height: 104)
let pillBottom: CGFloat = 636
let trayBottom: CGFloat = 300
let trayTop: CGFloat = 560
let trayBottomWidth: CGFloat = 470
let trayTopWidth: CGFloat = 700
let trayThickness: CGFloat = 66

func rgb(_ r: Int, _ g: Int, _ b: Int) -> CGColor {
    CGColor(red: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}

/// The tray, open at the top: down the left wall, across the floor, up the
/// right wall. Stroked rather than filled, so the wall thickness stays even
/// where the sides slant -- filling an outer shape and punching an inner one
/// does not, and a punch that overshoots the open top fills it back in.
func trayPath() -> CGPath {
    let mid = side / 2
    let path = CGMutablePath()
    path.move(to: CGPoint(x: mid - trayTopWidth / 2, y: trayTop))
    path.addLine(to: CGPoint(x: mid - trayBottomWidth / 2, y: trayBottom))
    path.addLine(to: CGPoint(x: mid + trayBottomWidth / 2, y: trayBottom))
    path.addLine(to: CGPoint(x: mid + trayTopWidth / 2, y: trayTop))
    return path
}

guard let context = CGContext(
    data: nil,
    width: Int(side),
    height: Int(side),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: CGColorSpaceCreateDeviceRGB(),
    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
) else { exit(1) }

// Background: graphite, lighter at the top, so the black pill reads as a
// cut-out rather than a smudge.
let space = CGColorSpaceCreateDeviceRGB()
if let gradient = CGGradient(
    colorsSpace: space,
    colors: [rgb(60, 66, 80), rgb(16, 18, 24)] as CFArray,
    locations: [0, 1]
) {
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: side),
        end: CGPoint(x: 0, y: 0),
        options: []
    )
}

context.addPath(trayPath())
context.setStrokeColor(CGColor(gray: 1, alpha: 1))
context.setLineWidth(trayThickness)
context.setLineJoin(.round)
context.setLineCap(.round)
context.strokePath()

// The pill, with a rim: a black shape on a dark background needs an edge to
// be a shape at all.
let pill = CGPath(
    roundedRect: CGRect(
        x: (side - pillSize.width) / 2,
        y: pillBottom,
        width: pillSize.width,
        height: pillSize.height
    ),
    cornerWidth: pillSize.height / 2,
    cornerHeight: pillSize.height / 2,
    transform: nil
)
context.addPath(pill)
context.setFillColor(CGColor(gray: 0, alpha: 1))
context.fillPath()
context.addPath(pill)
context.setStrokeColor(CGColor(gray: 1, alpha: 0.32))
context.setLineWidth(7)
context.strokePath()

let output = URL(fileURLWithPath: "Resources/App/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
guard let image = context.makeImage(),
      let destination = CGImageDestinationCreateWithURL(
          output as CFURL, UTType.png.identifier as CFString, 1, nil
      ) else { exit(1) }
CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else { exit(1) }
print("wrote \(output.path)")
