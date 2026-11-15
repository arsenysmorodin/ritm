import AppKit
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                    space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [r, g, b, a])!
}
let background = CGGradient(colorsSpace: space, colors: [color(0.09, 0.07, 0.14), color(0.21, 0.14, 0.34)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(background, start: .zero, end: CGPoint(x: size, y: size), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
ctx.setStrokeColor(color(0.851, 0.799, 1, 0.09))
ctx.setLineWidth(2)
for index in 0...10 {
    let v = CGFloat(152 + index * 72)
    ctx.move(to: CGPoint(x: v, y: 150)); ctx.addLine(to: CGPoint(x: v, y: 874))
    ctx.move(to: CGPoint(x: 150, y: v)); ctx.addLine(to: CGPoint(x: 874, y: v))
}
ctx.strokePath()
ctx.setStrokeColor(color(0.851, 0.799, 1, 0.21))
ctx.setLineWidth(3)
ctx.strokeEllipse(in: CGRect(x: 194, y: 194, width: 636, height: 636))
ctx.strokeEllipse(in: CGRect(x: 242, y: 242, width: 540, height: 540))
ctx.saveGState()
ctx.translateBy(x: 512, y: 512)
ctx.rotate(by: .pi / 5)
func fill(_ rect: CGRect, radius: CGFloat, _ color: CGColor) {
    ctx.setFillColor(color)
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)); ctx.fillPath()
}
let lavender = color(0.851, 0.799, 1)
let violet = color(0.64, 0.49, 0.91)
let peach = color(1, 0.766, 0.660)
fill(CGRect(x: -277, y: -29, width: 554, height: 58), radius: 28, peach)
for side: CGFloat in [-1, 1] {
    fill(CGRect(x: side * 214 - 26, y: -100, width: 52, height: 200), radius: 26, violet)
    fill(CGRect(x: side * 149 - 28, y: -156, width: 56, height: 312), radius: 28, lavender)
}
ctx.restoreGState()
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, ctx.makeImage()!, nil)
precondition(CGImageDestinationFinalize(destination))
