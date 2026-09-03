#!/usr/bin/env swift

import AppKit
import Foundation

let fileManager = FileManager.default
let projectDirectory = URL(fileURLWithPath: fileManager.currentDirectoryPath, isDirectory: true)
let resourcesDirectory = projectDirectory.appendingPathComponent("Resources", isDirectory: true)
let designDirectory = projectDirectory.appendingPathComponent("Design", isDirectory: true)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
  NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
}

func renderIcon(size: Int) throws -> Data {
  guard
    let bitmap = NSBitmapImageRep(
      bitmapDataPlanes: nil,
      pixelsWide: size,
      pixelsHigh: size,
      bitsPerSample: 8,
      samplesPerPixel: 4,
      hasAlpha: true,
      isPlanar: false,
      colorSpaceName: .deviceRGB,
      bytesPerRow: 0,
      bitsPerPixel: 0
    ),
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
  else {
    throw NSError(domain: "CodexVoiceIcon", code: 1)
  }

  let scale = CGFloat(size) / 1024
  func value(_ number: CGFloat) -> CGFloat { number * scale }
  func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> NSRect {
    NSRect(x: value(x), y: value(y), width: value(width), height: value(height))
  }

  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context
  context.imageInterpolation = .high
  NSColor.clear.setFill()
  NSRect(x: 0, y: 0, width: size, height: size).fill()

  let tileRect = rect(64, 64, 896, 896)
  let tile = NSBezierPath(
    roundedRect: tileRect,
    xRadius: value(218),
    yRadius: value(218)
  )
  tile.addClip()
  NSGradient(
    starting: color(0.025, 0.055, 0.105),
    ending: color(0.015, 0.02, 0.055)
  )!.draw(in: tileRect, angle: -72)

  let sheen = NSBezierPath(ovalIn: rect(65, 470, 894, 650))
  color(0.13, 0.49, 1, 0.10).setFill()
  sheen.fill()

  for (diameter, alpha) in [(690.0, 0.035), (630.0, 0.055), (580.0, 0.08)] {
    let d = CGFloat(diameter)
    let halo = NSBezierPath(ovalIn: rect((1024 - d) / 2, (1024 - d) / 2, d, d))
    color(0.13, 0.49, 1, CGFloat(alpha)).setFill()
    halo.fill()
  }

  let orbRect = rect(247, 247, 530, 530)
  let orb = NSBezierPath(ovalIn: orbRect)
  orb.addClip()
  NSGradient(colors: [
    color(0.24, 0.67, 1),
    color(0.06, 0.39, 0.96),
    color(0.025, 0.16, 0.57),
  ])!.draw(in: orbRect, angle: -62)

  let highlight = NSBezierPath(ovalIn: rect(318, 535, 355, 164))
  color(1, 1, 1, 0.13).setFill()
  highlight.fill()

  NSGraphicsContext.restoreGraphicsState()
  NSGraphicsContext.saveGraphicsState()
  NSGraphicsContext.current = context

  color(1, 1, 1, 0.97).setFill()
  let speakerBody = NSBezierPath(
    roundedRect: rect(300, 432, 116, 160),
    xRadius: value(28),
    yRadius: value(28)
  )
  speakerBody.fill()

  let speakerCone = NSBezierPath()
  speakerCone.move(to: NSPoint(x: value(390), y: value(438)))
  speakerCone.line(to: NSPoint(x: value(548), y: value(326)))
  speakerCone.curve(
    to: NSPoint(x: value(586), y: value(360)),
    controlPoint1: NSPoint(x: value(565), y: value(314)),
    controlPoint2: NSPoint(x: value(586), y: value(329))
  )
  speakerCone.line(to: NSPoint(x: value(586), y: value(664)))
  speakerCone.curve(
    to: NSPoint(x: value(548), y: value(698)),
    controlPoint1: NSPoint(x: value(586), y: value(695)),
    controlPoint2: NSPoint(x: value(565), y: value(710))
  )
  speakerCone.line(to: NSPoint(x: value(390), y: value(586)))
  speakerCone.close()
  speakerCone.fill()

  color(1, 1, 1, 0.97).setStroke()
  for (radius, width) in [(130.0, 29.0), (205.0, 31.0)] {
    let wave = NSBezierPath()
    wave.lineWidth = value(CGFloat(width))
    wave.lineCapStyle = .round
    wave.appendArc(
      withCenter: NSPoint(x: value(532), y: value(512)),
      radius: value(CGFloat(radius)),
      startAngle: -49,
      endAngle: 49
    )
    wave.stroke()
  }

  NSGraphicsContext.restoreGraphicsState()
  guard let png = bitmap.representation(using: .png, properties: [:]) else {
    throw NSError(domain: "CodexVoiceIcon", code: 2)
  }
  return png
}

func bigEndianData(_ value: UInt32) -> Data {
  var encoded = value.bigEndian
  return Data(bytes: &encoded, count: MemoryLayout<UInt32>.size)
}

try fileManager.createDirectory(at: designDirectory, withIntermediateDirectories: true)
let masterIcon = try renderIcon(size: 1024)
try masterIcon.write(
  to: designDirectory.appendingPathComponent("CodexVoice3-AppIcon.png")
)

let iconRepresentations: [(type: String, pixels: Int)] = [
  ("icp4", 16),
  ("icp5", 32),
  ("icp6", 64),
  ("ic07", 128),
  ("ic08", 256),
  ("ic09", 512),
  ("ic10", 1024),
]

var iconBody = Data()
for representation in iconRepresentations {
  let png = representation.pixels == 1024 ? masterIcon : try renderIcon(size: representation.pixels)
  iconBody.append(Data(representation.type.utf8))
  iconBody.append(bigEndianData(UInt32(png.count + 8)))
  iconBody.append(png)
}

var iconFile = Data("icns".utf8)
iconFile.append(bigEndianData(UInt32(iconBody.count + 8)))
iconFile.append(iconBody)
try iconFile.write(to: resourcesDirectory.appendingPathComponent("CodexVoice3.icns"))

print("Design/CodexVoice3-AppIcon.png")
print("Resources/CodexVoice3.icns")
