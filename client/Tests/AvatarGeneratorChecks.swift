import AppKit
import ImagePlayground

// Minimal relay DTO fixture for compiling the avatar adapter independently of
// the rest of the app. Fields match Models.swift; no Apple model download or
// relay credentials are needed for these conversion/selection checks.
struct HouseStyle {
  var promptPrefix: String
  var promptSuffix: String
  var styles: [String]
  var imageSize: Int
}

@main struct AvatarChecks {
  @MainActor static func main() throws {
    var house = HouseStyle(promptPrefix: "A friendly icon of ", promptSuffix: ", soft palette", styles: ["z_external_provider", "any", "sketch"], imageSize: 512)
    let request = AvatarGenerator.request(prompt: "a fox", house: house)
    precondition(request.style == .sketch, "skip external and any styles")
    precondition(request.fullPrompt == "A friendly icon of a fox, soft palette")
    house.styles = ["z_external_provider", "any", "unknown"]
    precondition(AvatarGenerator.request(prompt: "fox", house: house).style == .illustration)
    let context = CGContext(data: nil, width: 100, height: 50, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    context.setFillColor(NSColor.red.cgColor)
    context.fill(CGRect(x: 0, y: 0, width: 100, height: 50))
    context.setFillColor(NSColor.blue.cgColor)
    context.fill(CGRect(x: 25, y: 0, width: 50, height: 50))
    let rep = NSBitmapImageRep(cgImage: context.makeImage()!)
    let file = FileManager.default.temporaryDirectory.appendingPathComponent("vibes-avatar-check-\(UUID().uuidString).png")
    try rep.representation(using: .png, properties: [:])!.write(to: file)
    defer { try? FileManager.default.removeItem(at: file) }
    let output = try AvatarGenerator().prepareImage(at: file, request: request)
    let result = NSBitmapImageRep(data: output.data)!
    precondition(result.pixelsWide == 512 && result.pixelsHigh == 512)
    precondition(output.style == "sketch")
    let corner = result.colorAt(x: 0, y: 0)!.usingColorSpace(.deviceRGB)!
    precondition(corner.blueComponent > 0.9 && corner.redComponent < 0.1, "center crop must remove red outside square")
    do {
      _ = try AvatarGenerator().prepareImage(at: file.appendingPathExtension("missing"), request: request)
      fatalError("invalid file unexpectedly succeeded")
    } catch AvatarGenerationError.failed {}
    print("PASS: available=\(AvatarGenerator.isAvailableSync), house style selection, external-provider exclusion, prompt composition, 512px center-cropped PNG, invalid image handling")
  }
}
