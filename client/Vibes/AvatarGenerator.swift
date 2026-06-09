import AppKit
import CoreGraphics
import Foundation
import ImagePlayground

// AvatarGenerator — on-device profile-icon generation via Apple Intelligence's
// programmatic ImageCreator (ImagePlayground). Generation runs on device only;
// it cannot run on the relay. The whole API is gated to macOS 15.4+ and degrades
// gracefully when the device is not Apple-Intelligence-capable or the models are
// still downloading — `isSupported` is the runtime probe the UI checks before
// offering the feature.
//
// Flow: compose `house.promptPrefix + userPrompt + house.promptSuffix`, pick the
// first of `house.styles` actually present in `creator.availableStyles` (else the
// first available), run the creator with a limit of 1, take the first CGImage,
// scale/center-crop to a square `house.imageSize`, and encode PNG via
// NSBitmapImageRep. All ImageCreator errors collapse to a small
// `AvatarGenerationError` so the UI shows one "couldn't generate" state.

// Single user-facing failure surface. Every ImageCreator error maps to one of
// these; callers show a "try a different prompt / try later" message.
enum AvatarGenerationError: LocalizedError, Equatable {
  case unavailable
  case cancelled
  case failed

  var errorDescription: String? {
    switch self {
    case .unavailable:
      "Profile-icon generation isn't available on this Mac right now."
    case .cancelled:
      "Generation was cancelled."
    case .failed:
      "Couldn't generate an icon. Try a different prompt or try again later."
    }
  }
}

// The PNG bytes plus the style the creator actually used. The chosen style may
// differ from `house.styles.first` (the generator falls back to whatever the
// device offers), so callers thread `style` through to the upload header/store.
struct GeneratedAvatar {
  let data: Data
  let style: String
}

@available(macOS 15.4, *)
struct AvatarGenerator {
  // Runtime capability probe: ImageCreator() throws when the device/model is
  // unusable, and an empty `availableStyles` means nothing to generate with.
  // Never crashes — used to gate the Settings feature on/off.
  static var isSupported: Bool {
    get async {
      do {
        let creator = try await ImageCreator()
        return !creator.availableStyles.isEmpty
      } catch {
        return false
      }
    }
  }

  // Cheap, synchronous capability gate. `ImagePlaygroundViewController.isAvailable`
  // reports eligibility (AI-capable HW + enabled + supported language) — NOT model
  // readiness, so it can be `true` while the model is still downloading and every
  // `images(...)` call still fails. We use it as a fast pre-check to decide whether
  // to offer the AI path at all; the real readiness signal is a failed generation.
  @MainActor
  static var isAvailableSync: Bool {
    ImagePlaygroundViewController.isAvailable
  }

  // Open the system Image Playground app, which surfaces the model download and
  // primes it. There is no URL scheme, so we resolve it by bundle id and launch.
  static func openImagePlayground() {
    let bundleID = "com.apple.GenerativePlaygroundApp"
    guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
      return
    }
    NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
  }

  // Generate a square PNG for `prompt` under the server `house` style. Returns
  // the raw PNG bytes (ready to POST to /api/avatar) plus the style id actually
  // chosen by the creator, which may differ from `house.styles.first`. Throws
  // AvatarGenerationError.
  func generate(prompt: String, house: HouseStyle) async throws -> GeneratedAvatar {
    let creator: ImageCreator
    do {
      creator = try await ImageCreator()
    } catch {
      throw AvatarGenerationError.unavailable
    }

    let available = creator.availableStyles
    guard let chosen = pickStyle(preferred: house.styles, available: available) else {
      throw AvatarGenerationError.unavailable
    }

    let full = house.promptPrefix + prompt + house.promptSuffix

    // The very first generation after a cold model often returns `.creationFailed`
    // as a warm-up transient. Retry once before surfacing the error so the common
    // case "just worked on the second try" doesn't reach the user.
    do {
      do {
        return try await attempt(creator: creator, prompt: full, style: chosen, size: house.imageSize)
      } catch let error as ImageCreator.Error where error == .creationFailed {
        return try await attempt(creator: creator, prompt: full, style: chosen, size: house.imageSize)
      }
    } catch let error as ImageCreator.Error {
      throw map(error)
    }
  }

  // One generation pass. Throws ImageCreator.Error verbatim (so the caller can see
  // `.creationFailed` for its retry) and maps everything else to the user-facing
  // AvatarGenerationError.
  private func attempt(
    creator: ImageCreator,
    prompt: String,
    style: ImagePlaygroundStyle,
    size: Int
  ) async throws -> GeneratedAvatar {
    do {
      let stream = creator.images(for: [.text(prompt)], style: style, limit: 1)
      for try await created in stream {
        let data = try encodeSquarePNG(created.cgImage, size: size)
        return GeneratedAvatar(data: data, style: style.id)
      }
      // Stream finished with no image.
      throw AvatarGenerationError.failed
    } catch let error as ImageCreator.Error {
      throw error
    } catch let error as AvatarGenerationError {
      throw error
    } catch is CancellationError {
      throw AvatarGenerationError.cancelled
    } catch {
      throw AvatarGenerationError.failed
    }
  }

  // Prefer the first server-listed style the creator actually offers; fall back
  // to the first available style. `ImagePlaygroundStyle.identifier` is the stable
  // string key we match the server's style names against.
  private func pickStyle(
    preferred: [String],
    available: [ImagePlaygroundStyle]
  ) -> ImagePlaygroundStyle? {
    for name in preferred {
      if let match = available.first(where: { $0.id == name }) {
        return match
      }
    }
    return available.first
  }

  // Map every ImageCreator error to the single user-facing enum. Cancellation is
  // distinct; everything else (notSupported/unavailable/faceInImageTooSmall/
  // unsupportedLanguage/unsupportedInputImage/backgroundCreationForbidden/
  // creationFailed/…) collapses to .unavailable or .failed.
  private func map(_ error: ImageCreator.Error) -> AvatarGenerationError {
    switch error {
    case .notSupported, .unavailable:
      return .unavailable
    case .creationCancelled:
      return .cancelled
    default:
      return .failed
    }
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
