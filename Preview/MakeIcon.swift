import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                        space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
let dark = CommandLine.arguments.dropFirst(2).first == "dark"

func color(_ hex: UInt32, alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [
        CGFloat((hex >> 16) & 255) / 255, CGFloat((hex >> 8) & 255) / 255,
        CGFloat(hex & 255) / 255, alpha
    ])!
}

func fill(_ rect: CGRect, radius: CGFloat, with color: CGColor) {
    context.setFillColor(color)
    context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
    context.fillPath()
}

let field = color(dark ? 0x0D1014 : 0xF7F8FA)
let surface = color(dark ? 0x202730 : 0xEDF1F5)
let border = color(dark ? 0x313B48 : 0xD6DCE4)
let accent = color(dark ? 0xB9E76B : 0x436E16)
let gradient = CGGradient(colorsSpace: space, colors: [surface, field] as CFArray, locations: [0, 1])!
let center = CGPoint(x: 512, y: 512)
context.setFillColor(field)
context.fill(CGRect(x: 0, y: 0, width: size, height: size))
context.drawRadialGradient(gradient, startCenter: center, startRadius: 110, endCenter: center,
                           endRadius: 650, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

context.translateBy(x: center.x, y: center.y)
context.setLineWidth(7)
context.setStrokeColor(border)
context.strokeEllipse(in: CGRect(x: -333, y: -333, width: 666, height: 666))
context.setLineCap(.round)
context.setLineWidth(10)
for angle in [0.0, .pi / 2, .pi, 3 * .pi / 2] {
    context.move(to: CGPoint(x: cos(angle) * 322, y: sin(angle) * 322))
    context.addLine(to: CGPoint(x: cos(angle) * 344, y: sin(angle) * 344))
}
context.strokePath()

context.rotate(by: .pi / 6)
fill(CGRect(x: -254, y: -27, width: 508, height: 54), radius: 22, with: accent)
for side: CGFloat in [-1, 1] {
    fill(CGRect(x: side * 156 - 38, y: -128, width: 76, height: 256), radius: 24, with: accent)
    fill(CGRect(x: side * 225 - 22, y: -91, width: 44, height: 182), radius: 15, with: accent)
}

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination))
