import SwiftUI

// AvatarView — a reusable circular profile icon whose surrounding ring IS the
// presence indicator (replacing the old standalone dot in FriendCard.header).
// The AI-generated PNG (or initials fallback) fills a Circle; a stroked ring sits
// just outside it with a small gap. Ring color is the presence state:
//   online  → VibeColor.online        ("lit")
//   offline → VibeColor.controlAtRest ("at-rest")
// All dimensions scale with the FriendCard size enum and all colors are pure
// VibeColor tokens (see client/Vibes/DESIGN.md).
struct AvatarView: View {
  var status: MergedStatus
  var size: FriendCardSize
  var isOnline: Bool
  // Aurora II: online avatars get a slow "breathing" ring (scale + fade, ~3.4s).
  // Off by default so static contexts (settings preview, away rows) stay still.
  var breathes: Bool

  @State private var isBreathing = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  init(status: MergedStatus, size: FriendCardSize = .comfortable, isOnline: Bool, breathes: Bool = false) {
    self.status = status
    self.size = size
    self.isOnline = isOnline
    self.breathes = breathes
  }

  // The full outer diameter (image + gap + ring on every side) for a given size.
  // Exposed so callers that scale a rendered AvatarView (e.g. the Settings
  // preview) can match the real geometry instead of hardcoding a magic number.
  static func outerDiameter(for size: FriendCardSize) -> CGFloat {
    let metrics = AvatarMetrics(size: size)
    return metrics.diameter + 2 * (metrics.gap + metrics.ringWidth)
  }

  var body: some View {
    // The ring lives outside the image with a gap, so the overall frame is the
    // image diameter plus the gap and ring on every side.
    let outer = AvatarView.outerDiameter(for: size)

    ZStack {
      avatarFill
        .frame(width: metrics.diameter, height: metrics.diameter)
        .clipShape(Circle())

      Circle()
        .strokeBorder(ringColor, lineWidth: metrics.ringWidth)
        .frame(width: outer, height: outer)
        .scaleEffect(isBreathing ? 1.07 : 1.0)
        .opacity(isBreathing ? 0.45 : 1.0)
    }
    .frame(width: outer, height: outer)
    .onAppear {
      guard breathes, isOnline, !reduceMotion else { return }
      withAnimation(.easeInOut(duration: 3.4).repeatForever(autoreverses: true)) {
        isBreathing = true
      }
    }
    .accessibilityElement()
    .accessibilityLabel(isOnline ? "\(status.user.displayName), online" : "\(status.user.displayName), offline")
  }

  // Choose the representation by the user's explicit `avatarKind`:
  //   "image"    → AI-generated PNG (AsyncImage, initials on empty/failure)
  //   "gradient" → a two-color LinearGradient (topLeading → bottomTrailing)
  //   else       → initials on a neutral VibeColor fill
  // The presence ring is applied once in `body` and is identical in every case.
  @ViewBuilder
  private var avatarFill: some View {
    switch status.user.avatarKind {
    case "image" where avatarURL != nil:
      AsyncImage(url: avatarURL!) { phase in
        switch phase {
        case .success(let image):
          image.resizable().scaledToFill()
        case .empty, .failure:
          initials
        @unknown default:
          initials
        }
      }
    case "gradient" where gradientColors != nil:
      ZStack {
        LinearGradient(
          colors: gradientColors!,
          startPoint: .topLeading,
          endPoint: .bottomTrailing
        )
        Text(handleInitial)
          .font(.system(size: metrics.initialsFontSize, weight: .medium, design: .rounded))
          .foregroundStyle(.white.opacity(0.9))
          .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
      }
    default:
      initials
    }
  }

  // The first letter of the handle, shown over the gradient fill.
  private var handleInitial: String {
    (status.user.handle.first.map(String.init) ?? "?").uppercased()
  }

  private var initials: some View {
    ZStack {
      VibeColor.controlAtRest
      Text(initialsText)
        .font(.system(size: metrics.initialsFontSize, weight: .medium, design: .rounded))
        .foregroundStyle(VibeColor.controlAtRestForeground)
    }
  }

  // MARK: - Derived

  private var avatarURL: URL? {
    guard let raw = status.user.avatarUrl, !raw.isEmpty else { return nil }
    return URL(string: raw)
  }

  // The gradient's two ends as SwiftUI Colors, or nil if absent/unparseable (the
  // switch then falls back to initials).
  private var gradientColors: [Color]? {
    guard
      let gradient = status.user.avatarGradient,
      let start = Color(hex: gradient.start),
      let end = Color(hex: gradient.end)
    else { return nil }
    return [start, end]
  }

  // First letters of up to the first two words of the display name, uppercased.
  private var initialsText: String {
    let words = status.user.displayName
      .split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
      .prefix(2)
    let letters = words.compactMap { $0.first }.map(String.init).joined()
    return letters.isEmpty ? "?" : letters.uppercased()
  }

  private var ringColor: Color {
    isOnline ? VibeColor.online : VibeColor.controlAtRest
  }

  private var metrics: AvatarMetrics { AvatarMetrics(size: size) }
}

// Size-driven avatar dimensions, mirroring the FriendCard size enum scale.
private struct AvatarMetrics {
  let diameter: CGFloat
  let ringWidth: CGFloat
  let gap: CGFloat
  let initialsFontSize: CGFloat

  init(size: FriendCardSize) {
    switch size {
    case .comfortable:
      diameter = 40
      ringWidth = 2
      gap = 2.5
      initialsFontSize = 16
    case .compact:
      diameter = 26
      ringWidth = 2
      gap = 1.5
      initialsFontSize = 11
    }
  }
}

// MARK: - Preview

#Preview("Avatar — states") {
  func sample(_ name: String, online: Bool, url: String? = nil) -> MergedStatus {
    var user = UserSummary(id: name, handle: name, displayName: name, timezone: nil)
    user.avatarUrl = url
    return MergedStatus(
      user: user,
      mode: online ? .online : .offline,
      manualStatus: nil,
      day: nil,
      updatedAt: Date(),
      cards: []
    )
  }

  return VStack(spacing: 20) {
    HStack(spacing: 20) {
      AvatarView(status: sample("Lin Wei", online: true), size: .comfortable, isOnline: true)
      AvatarView(status: sample("Sam Ortiz", online: false), size: .comfortable, isOnline: false)
      AvatarView(status: sample("Kai Mensah", online: true), size: .compact, isOnline: true)
    }
  }
  .padding(40)
  .background(VibeColor.chassis)
}
