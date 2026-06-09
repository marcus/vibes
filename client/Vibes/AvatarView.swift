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

  init(status: MergedStatus, size: FriendCardSize = .comfortable, isOnline: Bool) {
    self.status = status
    self.size = size
    self.isOnline = isOnline
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
    }
    .frame(width: outer, height: outer)
    .accessibilityElement()
    .accessibilityLabel(isOnline ? "\(status.user.displayName), online" : "\(status.user.displayName), offline")
  }

  // The image when present, otherwise initials on a neutral VibeColor fill. The
  // initials view is also the AsyncImage placeholder/error state.
  @ViewBuilder
  private var avatarFill: some View {
    if let url = avatarURL {
      AsyncImage(url: url) { phase in
        switch phase {
        case .success(let image):
          image.resizable().scaledToFill()
        case .empty, .failure:
          initials
        @unknown default:
          initials
        }
      }
    } else {
      initials
    }
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
      diameter = 34
      ringWidth = 2.5
      gap = 2
      initialsFontSize = 14
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
