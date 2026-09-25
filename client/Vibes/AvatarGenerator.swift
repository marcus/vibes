import AppKit
import CoreGraphics
import Foundation
import ImagePlayground

// ImageCreator is unavailable on macOS 27. The system Image Playground sheet
// owns generation; this adapter builds its request and converts the chosen image
// into the same square PNG that the existing preview/upload flow expects.
enum AvatarGenerationError: LocalizedError, Equatable {
  case unavailable
  case failed

  var errorDescription: String? {
    switch self {
    case .unavailable:
      "Profile-icon generation isn't available on this Mac right now."
    case .failed:
      "Couldn't prepare that icon. Try generating another image."
    }
  }
}

struct GeneratedAvatar {
  let data: Data
  let style: String
}

struct AvatarGenerationRequest {
  let prompt: String
  let fullPrompt: String
  let style: ImagePlaygroundStyle
  let imageSize: Int
}

struct AvatarGenerator {
  // Do not probe ImageCreator: on macOS 27 it throws notSupported even on Macs
  // where the supported Image Playground UI is available. The sheet handles
  // model setup and generation readiness itself.
  @MainActor
  static var isAvailableSync: Bool {
    ImagePlaygroundViewController.isAvailable
  }

  // Restrict generation to Apple's on-device styles. `all` also contains Any
  // and external-provider styles on newer macOS versions; neither belongs in
  // Vibes' private, on-device avatar flow.
  static func request(prompt: String, house: HouseStyle) -> AvatarGenerationRequest {
    let allowed: [ImagePlaygroundStyle] = [.illustration, .animation, .sketch]
    let style = house.styles.compactMap { name in allowed.first { $0.id == name } }.first
      ?? .illustration
    return AvatarGenerationRequest(
      prompt: prompt,
      fullPrompt: house.promptPrefix + prompt + house.promptSuffix,
      style: style,
      imageSize: house.imageSize
    )
  }

  // Read the temporary system-provided file during the completion callback,
  // before it can be removed. No image or prompt is uploaded here.
  func prepareImage(at url: URL, request: AvatarGenerationRequest) throws -> GeneratedAvatar {
    guard let image = NSImage(contentsOf: url),
          let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil)
    else { throw AvatarGenerationError.failed }
    return GeneratedAvatar(
      data: try encodeSquarePNG(cgImage, size: request.imageSize),
      style: request.style.id
    )
  }

  // Center-crop the CGImage to a square, scale to `size`×`size`, encode PNG.
  private func encodeSquarePNG(_ image: CGImage, size: Int) throws -> Data {
    let side = min(image.width, image.height)
    let cropX = (image.width - side) / 2
    let cropY = (image.height - side) / 2
    let square = image.cropping(
      to: CGRect(x: cropX, y: cropY, width: side, height: side)
    ) ?? image

    let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
    guard
      let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
      )
    else {
      throw AvatarGenerationError.failed
    }
    context.interpolationQuality = .high
    context.draw(square, in: CGRect(x: 0, y: 0, width: size, height: size))

    guard
      let scaled = context.makeImage(),
      let png = pngData(from: scaled)
    else {
      throw AvatarGenerationError.failed
    }
    return png
  }

  private func pngData(from image: CGImage) -> Data? {
    let rep = NSBitmapImageRep(cgImage: image)
    return rep.representation(using: .png, properties: [:])
  }
}
