import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Winnow: the wind blows the chaff away and the grain stays.
// A golden grain on a calm evening teal, with light chaff drifting off to the top right.
// Run from the repo root: `swift scripts/make-icon.swift`.

let size = 1024.0
let canvas = CGRect(x: 0, y: 0, width: size, height: size)
let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
let assets = URL(fileURLWithPath: "Resources/Assets.xcassets", isDirectory: true)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
}

/// An almond shape with pointed ends, centred on 0,0, pointing up.
func grainPath(length: CGFloat, width: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let half = length / 2
    path.move(to: CGPoint(x: 0, y: -half))
    path.addCurve(
        to: CGPoint(x: 0, y: half), control1: CGPoint(x: width * 0.66, y: -half * 0.55),
        control2: CGPoint(x: width * 0.72, y: half * 0.62))
    path.addCurve(
        to: CGPoint(x: 0, y: -half), control1: CGPoint(x: -width * 0.72, y: half * 0.62),
        control2: CGPoint(x: -width * 0.66, y: -half * 0.55))
    path.closeSubpath()
    return path
}

/// A plump grain kernel: rounder at the bottom, a little pointed at the top.
func kernelPath(length: CGFloat, width: CGFloat) -> CGPath {
    let path = CGMutablePath()
    let half = length / 2
    path.move(to: CGPoint(x: 0, y: -half))
    path.addCurve(
        to: CGPoint(x: 0, y: half), control1: CGPoint(x: width * 0.52, y: -half * 0.92),
        control2: CGPoint(x: width * 0.70, y: half * 0.98))
    path.addCurve(
        to: CGPoint(x: 0, y: -half), control1: CGPoint(x: -width * 0.70, y: half * 0.98),
        control2: CGPoint(x: -width * 0.52, y: -half * 0.92))
    path.closeSubpath()
    return path
}

func drawBackground(in context: CGContext, dark: Bool) {
    let colors = dark ? [color(0x0E2226), color(0x050C0E)] : [color(0x1D4A50), color(0x0C2326)]
    let gradient = CGGradient(colorsSpace: sRGB, colors: colors as CFArray, locations: [0, 1])!
    context.drawLinearGradient(
        gradient, start: CGPoint(x: 0, y: size), end: CGPoint(x: size, y: 0), options: [])
}

func drawMark(in context: CGContext) {
    // Top-left origin makes the numbers easier to read.
    context.saveGState()
    context.translateBy(x: 0, y: size)
    context.scaleBy(x: 1, y: -1)

    // A soft gust of wind behind the chaff.
    context.setLineCap(.round)
    context.setStrokeColor(color(0xF4E9D2, 0.10))
    context.setLineWidth(18)
    let gust = CGMutablePath()
    gust.move(to: CGPoint(x: 300, y: 300))
    gust.addCurve(
        to: CGPoint(x: 905, y: 170), control1: CGPoint(x: 500, y: 150), control2: CGPoint(x: 720, y: 120))
    context.addPath(gust)
    context.strokePath()

    drawChaff(in: context)
    drawGrain(in: context)
    context.restoreGState()
}

struct Chaff {
    let center: CGPoint
    let length: CGFloat
    let angle: CGFloat
    let alpha: CGFloat
}

/// Small, light pieces that fade as they fly away.
func drawChaff(in context: CGContext) {
    let pieces = [
        Chaff(center: CGPoint(x: 660, y: 292), length: 88, angle: 52, alpha: 0.92),
        Chaff(center: CGPoint(x: 728, y: 236), length: 70, angle: 74, alpha: 0.72),
        Chaff(center: CGPoint(x: 812, y: 300), length: 54, angle: 30, alpha: 0.55),
        Chaff(center: CGPoint(x: 856, y: 196), length: 42, angle: 96, alpha: 0.40),
        Chaff(center: CGPoint(x: 924, y: 262), length: 30, angle: 60, alpha: 0.26),
    ]
    for piece in pieces {
        context.saveGState()
        context.translateBy(x: piece.center.x, y: piece.center.y)
        context.rotate(by: piece.angle * .pi / 180)
        context.setFillColor(color(0xF4E9D2, piece.alpha))
        context.addPath(grainPath(length: piece.length, width: piece.length * 0.34))
        context.fillPath()
        context.restoreGState()
    }
}

func drawGrain(in context: CGContext) {
    context.saveGState()
    context.translateBy(x: 450, y: 600)
    context.rotate(by: 34 * .pi / 180)
    let grain = kernelPath(length: 600, width: 420)
    context.addPath(grain)
    context.clip()
    let gold = CGGradient(
        colorsSpace: sRGB, colors: [color(0xFAD679), color(0xF0B243), color(0xD98A24)] as CFArray,
        locations: [0, 0.55, 1])!
    context.drawLinearGradient(
        gold, start: CGPoint(x: -210, y: -300), end: CGPoint(x: 210, y: 300), options: [])
    // The groove along the grain.
    context.setStrokeColor(color(0xA8641A, 0.55))
    context.setLineWidth(16)
    let groove = CGMutablePath()
    groove.move(to: CGPoint(x: 0, y: -215))
    groove.addCurve(
        to: CGPoint(x: 0, y: 240), control1: CGPoint(x: 44, y: -80), control2: CGPoint(x: 44, y: 100))
    context.addPath(groove)
    context.strokePath()
    // A soft light on the upper side.
    context.setFillColor(color(0xFFFFFF, 0.18))
    context.fillEllipse(in: CGRect(x: -140, y: -210, width: 96, height: 250))
    context.restoreGState()
}

func render(filename: String, dark: Bool) {
    let context = CGContext(
        data: nil, width: Int(size), height: Int(size), bitsPerComponent: 8, bytesPerRow: 0, space: sRGB,
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
    drawBackground(in: context, dark: dark)
    drawMark(in: context)
    let url = assets.appendingPathComponent("AppIcon.appiconset/\(filename)")
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, context.makeImage()!, nil)
    precondition(CGImageDestinationFinalize(destination), "Could not write \(filename)")
}

try FileManager.default.createDirectory(
    at: assets.appendingPathComponent("AppIcon.appiconset"), withIntermediateDirectories: true)
render(filename: "AppIcon.png", dark: false)
render(filename: "AppIcon-Dark.png", dark: true)
print("Rendered AppIcon.png and AppIcon-Dark.png")
