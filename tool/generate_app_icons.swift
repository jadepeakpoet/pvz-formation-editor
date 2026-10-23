import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

// Run from the repository root. Preserve approved artwork; only resize/package.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let sourceURL = root.appendingPathComponent("assets/branding/app-logo.png")
guard let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
      image.width == image.height else {
  fatalError("Expected square assets/branding/app-logo.png")
}
let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)!
func png(_ size: Int, opaque: Bool = false) throws -> Data {
  let alpha: CGImageAlphaInfo = opaque ? .noneSkipLast : .premultipliedLast
  guard let context = CGContext(data: nil, width: size, height: size,
      bitsPerComponent: 8, bytesPerRow: size * 4, space: colorSpace,
      bitmapInfo: alpha.rawValue) else { fatalError("Cannot create icon context") }
  if opaque {
    // iOS requires opaque source icons and applies its own rounded mask.
    context.setFillColor(CGColor(red: 0.02, green: 0.25, blue: 0.16, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: size, height: size))
  }
  context.interpolationQuality = .high
  context.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size))
  let data = NSMutableData()
  let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil)!
  CGImageDestinationAddImage(destination, context.makeImage()!, nil)
  guard CGImageDestinationFinalize(destination) else { fatalError("PNG export failed") }
  return data as Data
}
let macFolder = root.appendingPathComponent("macos/Runner/Assets.xcassets/AppIcon.appiconset")
for size in [16, 32, 64, 128, 256, 512, 1024] {
  try png(size).write(to: macFolder.appendingPathComponent("app_icon_\(size).png"))
}
for (density, size) in [("mdpi", 48), ("hdpi", 72), ("xhdpi", 96), ("xxhdpi", 144), ("xxxhdpi", 192)] {
  try png(size).write(to: root.appendingPathComponent(
      "android/app/src/main/res/mipmap-\(density)/ic_launcher.png"))
}
let iosFolder = root.appendingPathComponent("ios/Runner/Assets.xcassets/AppIcon.appiconset")
let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf:
    iosFolder.appendingPathComponent("Contents.json"))) as! [String: Any]
var written = Set<String>()
for entry in manifest["images"] as! [[String: String]] {
  guard let name = entry["filename"], written.insert(name).inserted else { continue }
  let points = Double(entry["size"]!.components(separatedBy: "x")[0])!
  let scale = Double(entry["scale"]!.replacingOccurrences(of: "x", with: ""))!
  try png(Int((points * scale).rounded()), opaque: true)
      .write(to: iosFolder.appendingPathComponent(name))
}
func u16(_ value: Int) -> Data {
  var little = UInt16(value).littleEndian
  return withUnsafeBytes(of: &little) { Data($0) }
}
func u32(_ value: Int) -> Data {
  var little = UInt32(value).littleEndian
  return withUnsafeBytes(of: &little) { Data($0) }
}
let sizes = [16, 24, 32, 48, 64, 128, 256]
let images = try sizes.map { try png($0) }
var ico = u16(0) + u16(1) + u16(sizes.count)
var offset = 6 + 16 * sizes.count
for (size, data) in zip(sizes, images) {
  ico.append(contentsOf: [UInt8(size == 256 ? 0 : size), UInt8(size == 256 ? 0 : size), 0, 0])
  ico.append(u16(1)); ico.append(u16(32)); ico.append(u32(data.count)); ico.append(u32(offset))
  offset += data.count
}
for data in images { ico.append(data) }
try ico.write(to: root.appendingPathComponent("windows/runner/resources/app_icon.ico"))
print("Generated macOS, iOS, Android and Windows icons from approved logo")
