import SwiftUI

// OrbitView — the ambient "sky" presence view (design/mockups/b-orbit.html).
//
// Everyone online floats as an orb. Three encodings, all glanceable:
//   orb size   — today's churn relative to the group's biggest day
//   churn ring — sweep is today vs THIS person's typical day (server-provided
//                median, `typical_churn`); the swept arc splits green/red by
//                their adds-vs-deletes ratio. Past 1× the ring laps and a
//                small "1.7×" badge appears.
//   repo moons — up to two repo-alias chips hanging off the orb
// Offline friends compress into the "drifting" dock along the bottom edge.
//
// The list view (FriendCard column) remains one switch away; see HomeView.

enum FeedViewMode: String, CaseIterable {
  case orbit
  case list
}

// Feed text scaling: macOS SwiftUI ignores `.dynamicTypeSize`, so the feed's
// text applies this multiplier to explicit base sizes that mirror the macOS
// text styles they replace (headline 13, subheadline 11, caption/caption2 10).
// Set from the user's FeedTextSize setting in HomeView; chrome never scales.
struct FeedTextScaleKey: EnvironmentKey {
  static let defaultValue: CGFloat = 1.0
}

extension EnvironmentValues {
  var feedTextScale: CGFloat {
    get { self[FeedTextScaleKey.self] }
    set { self[FeedTextScaleKey.self] = newValue }
  }
}

struct OrbitView: View {
  var you: MergedStatus
  var friends: [MergedStatus]

  var body: some View {
    VStack(spacing: 0) {
      GeometryReader { geo in
        ZStack {
          let members = skyMembers
          let biggest = maxChurn(of: members)
          ForEach(Array(members.enumerated()), id: \.element.id) { index, status in
            OrbView(
              status: status,
              isYou: status.user.handle == you.user.handle,
              rank: index,
              maxChurn: biggest
            )
            .position(slotPosition(index: index, count: members.count, in: geo.size))
          }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .bottom) {
          if friends.isEmpty {
            Text("Just you up here so far. Invite a friend to fill the sky.")
              .font(.callout)
              .foregroundStyle(Color.secondary)
              .multilineTextAlignment(.center)
              .padding(.bottom, 24)
          }
        }
      }
      if !drifters.isEmpty {
        DriftDock(drifters: drifters)
      }
    }
  }

  // "You" plus every online friend, biggest day first so the most active
  // people land in the most prominent slots. Handle tiebreak keeps the
  // ordering (and therefore positions) stable between refreshes.
  private var skyMembers: [MergedStatus] {
    let online = [you] + friends.filter { $0.mode == .online }
    return online.sorted { lhs, rhs in
      lhs.churn == rhs.churn ? lhs.user.handle < rhs.user.handle : lhs.churn > rhs.churn
    }
  }

  private var drifters: [MergedStatus] {
    friends.filter { $0.mode != .online }
  }

  private func maxChurn(of members: [MergedStatus]) -> Int {
    max(members.map(\.churn).max() ?? 0, 1)
  }

  // Hand-tuned constellation slots (unit coordinates) for small skies, echoing
  // the mockup's layout; larger groups fall back to a staggered grid. Slots are
  // ordered most→least prominent to match the churn-sorted members.
  private static let slots: [[CGPoint]] = [
    [CGPoint(x: 0.50, y: 0.44)],
    [CGPoint(x: 0.30, y: 0.32), CGPoint(x: 0.70, y: 0.60)],
    [CGPoint(x: 0.28, y: 0.26), CGPoint(x: 0.73, y: 0.36), CGPoint(x: 0.46, y: 0.70)],
    [
      CGPoint(x: 0.26, y: 0.24), CGPoint(x: 0.73, y: 0.28),
      CGPoint(x: 0.55, y: 0.62), CGPoint(x: 0.22, y: 0.72),
    ],
    [
      CGPoint(x: 0.26, y: 0.22), CGPoint(x: 0.73, y: 0.26), CGPoint(x: 0.50, y: 0.54),
      CGPoint(x: 0.22, y: 0.74), CGPoint(x: 0.77, y: 0.72),
    ],
    [
      CGPoint(x: 0.24, y: 0.20), CGPoint(x: 0.72, y: 0.22), CGPoint(x: 0.48, y: 0.48),
      CGPoint(x: 0.20, y: 0.62), CGPoint(x: 0.76, y: 0.62), CGPoint(x: 0.48, y: 0.82),
    ],
  ]

  private func slotPosition(index: Int, count: Int, in size: CGSize) -> CGPoint {
    let unit: CGPoint
    if count <= Self.slots.count {
      unit = Self.slots[count - 1][index]
    } else {
      // Staggered grid for big skies: 3 columns, odd rows offset half a cell.
      let columns = 3
      let rows = (count + columns - 1) / columns
      let row = index / columns
      let column = index % columns
      let xStep = 1.0 / Double(columns + 1)
      let yStep = 0.84 / Double(max(rows, 1))
      let stagger = row.isMultiple(of: 2) ? 0.0 : xStep * 0.4
      unit = CGPoint(
        x: min(0.84, xStep * Double(column + 1) + stagger),
        y: 0.12 + yStep * (Double(row) + 0.5)
      )
    }
    return CGPoint(x: unit.x * size.width, y: unit.y * size.height)
  }
}

// MARK: - Churn meter

// The ring math, kept as a pure value so it is previewable and testable.
struct ChurnMeter {
  var insertions: Int
  var deletions: Int
  var typical: Int?

  init(status: MergedStatus) {
    insertions = status.insertions
    deletions = status.deletions
    typical = status.typicalChurn
  }

  init(insertions: Int, deletions: Int, typical: Int?) {
    self.insertions = insertions
    self.deletions = deletions
    self.typical = typical
  }

  var churn: Int { insertions + deletions }

  // Fraction of the ring swept (0...1). With a baseline: linear progress
  // toward this person's typical day, capped at one lap. Without one (new
  // user, server too old): log scale against a fixed 2,000-line "full day" so
  // brand-new users still see life in the ring. Any activity at all keeps a
  // minimum visible sliver.
  var sweep: Double {
    guard churn > 0 else { return 0 }
    let raw: Double
    if let typical, typical > 0 {
      raw = min(1.0, Double(churn) / Double(typical))
    } else {
      raw = min(1.0, log10(Double(churn) + 1) / log10(2000.0))
    }
    return max(raw, 0.03)
  }

  // How much of the swept arc is green (adds) vs red (deletes).
  var greenFraction: Double {
    guard churn > 0 else { return 0.5 }
    return Double(insertions) / Double(churn)
  }

  // "1.7×" once past the typical day; nil before that or without a baseline.
  var lapLabel: String? {
    guard let typical, typical > 0, churn > typical else { return nil }
    return String(format: "%.1f×", Double(churn) / Double(typical))
  }
}

// The churn ring: a faint full-circle track, then green and red arcs from the
// twelve-o'clock position. LOC semantics reuse the system green/red pair.
struct ChurnRing: View {
  var meter: ChurnMeter
  var lineWidth: CGFloat = 3

  var body: some View {
    let split = meter.sweep * meter.greenFraction
    ZStack {
      Circle()
        .stroke(Color(nsColor: .quaternaryLabelColor), lineWidth: lineWidth)
      Circle()
        .trim(from: 0, to: split)
        .stroke(
          Color(nsColor: .systemGreen),
          style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )
      Circle()
        .trim(from: split, to: meter.sweep)
        .stroke(
          Color(nsColor: .systemRed),
          style: StrokeStyle(lineWidth: lineWidth, lineCap: .round)
        )
    }
    .rotationEffect(.degrees(-90))
    .animation(.easeInOut(duration: 0.8), value: meter.sweep)
  }
}

// MARK: - Orb

private struct OrbView: View {
  var status: MergedStatus
  var isYou: Bool
  var rank: Int
  var maxChurn: Int

  @State private var floating = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.feedTextScale) private var textScale

  private static let minDiameter: CGFloat = 44
  private static let maxDiameter: CGFloat = 84

  private var meter: ChurnMeter { ChurnMeter(status: status) }

  // sqrt so area (not radius) tracks churn — doubling output shouldn't double
  // the orb's footprint.
  private var diameter: CGFloat {
    let share = sqrt(Double(status.churn) / Double(maxChurn))
    return Self.minDiameter + (Self.maxDiameter - Self.minDiameter) * CGFloat(share)
  }

  var body: some View {
    VStack(spacing: 7) {
      globe
      labels
    }
    .frame(width: 168)
    .offset(y: floating ? -5 : 5)
    .onAppear {
      guard !reduceMotion else { return }
      // Stagger durations by rank so the orbs don't bob in lockstep.
      withAnimation(
        .easeInOut(duration: 6.0 + Double(rank % 3) * 1.3).repeatForever(autoreverses: true)
      ) {
        floating = true
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilitySummary)
  }

  private var globe: some View {
    AvatarFill(user: status.user, diameter: diameter)
      // The glow is the avatar's own gradient color — the sanctioned
      // user-chosen-color exception, used as light rather than chrome.
      .shadow(color: glowColor.opacity(0.45), radius: diameter * 0.22)
      .overlay(
        ChurnRing(meter: meter)
          .frame(width: diameter + 13, height: diameter + 13)
      )
      .overlay(alignment: .topTrailing) {
        if let lap = meter.lapLabel {
          Text(lap)
            .font(.caption2.weight(.bold).monospaced())
            .padding(.horizontal, 6)
            .padding(.vertical, 1.5)
            .background(.yellow.opacity(0.18), in: Capsule())
            .overlay(Capsule().strokeBorder(.yellow.opacity(0.5), lineWidth: 1))
            .foregroundStyle(.yellow)
            .offset(x: 16, y: -10)
        }
      }
      .overlay(alignment: .topTrailing) {
        if let alias = status.repoAliases.first {
          moon(alias).offset(x: diameter * 0.42, y: -diameter * 0.34)
        }
      }
      .overlay(alignment: .bottomLeading) {
        if status.repoAliases.count > 1 {
          moon(status.repoAliases[1]).offset(x: -diameter * 0.46, y: -diameter * 0.10)
        }
      }
  }

  private var labels: some View {
    VStack(spacing: 1) {
      Text(isYou ? "you" : status.user.displayName)
        .font(.system(size: 11 * textScale, weight: .semibold))
        .lineLimit(1)
      if let note = status.manualStatus, !note.isEmpty {
        Text(note)
          .font(.system(size: 10 * textScale))
          .foregroundStyle(Color.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
      }
      locLine
    }
  }

  @ViewBuilder
  private var locLine: some View {
    if status.churn > 0 || status.commitCount > 0 {
      HStack(spacing: 5) {
        Text("+\(status.insertions)")
          .foregroundStyle(Color(nsColor: .systemGreen))
        Text("\u{2212}\(status.deletions)")
          .foregroundStyle(Color(nsColor: .systemRed))
        Text("· \(status.commitCount)c")
          .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
      }
      .font(.system(size: 10 * textScale, weight: .semibold).monospaced())
    } else {
      Text("quiet so far")
        .font(.system(size: 10 * textScale))
        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
    }
  }

  // A repo "moon": small capsule chip with a per-repo identity dot. The dot
  // hue is derived deterministically from the alias so a repo keeps its color
  // across refreshes, launches, and friends' machines.
  private func moon(_ alias: String) -> some View {
    HStack(spacing: 4) {
      Circle()
        .fill(Color(hue: stableHue(alias), saturation: 0.55, brightness: 0.9))
        .frame(width: 5, height: 5)
      Text(alias)
        .font(.system(size: 10 * textScale))
        .foregroundStyle(Color.secondary)
        .lineLimit(1)
    }
    .padding(.horizontal, 7)
    .padding(.vertical, 2.5)
    .background(Color(nsColor: .quaternarySystemFill), in: Capsule())
    .fixedSize()
  }

  // djb2 over unicode scalars: stable across launches (unlike hashValue, which
  // is seeded per process).
  private func stableHue(_ text: String) -> Double {
    var hash: UInt32 = 5381
    for scalar in text.unicodeScalars {
      hash = hash &* 33 &+ scalar.value
    }
    return Double(hash % 360) / 360.0
  }

  private var glowColor: Color {
    if let gradient = status.user.avatarGradient, let start = Color(hex: gradient.start) {
      return start
    }
    return .accentColor
  }

  private var accessibilitySummary: String {
    let name = isYou ? "You" : status.user.displayName
    var parts = ["\(name), online"]
    if status.churn > 0 {
      parts.append("plus \(status.insertions), minus \(status.deletions) lines today")
    }
    if let lap = meter.lapLabel {
      parts.append("\(lap) their typical day")
    }
    if !status.repoAliases.isEmpty {
      parts.append("in \(status.repoAliases.joined(separator: ", "))")
    }
    return parts.joined(separator: ", ")
  }
}

// MARK: - Drift dock

// Offline friends, compressed into one quiet band under the sky (mockup:
// "DRIFTING · sam 2h · +210 −95 in kiln · kei 1d").
private struct DriftDock: View {
  var drifters: [MergedStatus]

  var body: some View {
    VStack(spacing: 0) {
      Divider()
      ScrollView(.horizontal, showsIndicators: false) {
        HStack(spacing: 18) {
          Text("DRIFTING")
            .font(.caption2.weight(.bold))
            .tracking(1.2)
            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
          ForEach(drifters) { status in
            DrifterItem(status: status)
          }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 11)
      }
    }
    .background(Color(nsColor: .quaternarySystemFill).opacity(0.55))
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }
}

private struct DrifterItem: View {
  var status: MergedStatus
  @Environment(\.feedTextScale) private var textScale

  var body: some View {
    HStack(spacing: 7) {
      AvatarFill(user: status.user, diameter: 20)
        .saturation(0.3)
        .opacity(0.8)
      Text(status.user.displayName)
        .font(.system(size: 10 * textScale, weight: .semibold))
        .foregroundStyle(Color.secondary)
      detail
        .font(.system(size: 10 * textScale))
        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
        .monospacedDigit()
        .lineLimit(1)
    }
    .accessibilityElement(children: .combine)
  }

  // "2h · +210 −95 in kiln" — recency first, then the day's residue when the
  // friend left one behind. Quiet days are just the recency.
  private var detail: Text {
    var text = Text(compactRecency)
    if status.churn > 0 {
      text = text + Text(" · ")
        + Text("+\(status.insertions)").foregroundColor(Color(nsColor: .systemGreen))
        + Text(" \u{2212}\(status.deletions)").foregroundColor(Color(nsColor: .systemRed))
      if let repo = status.repoAliases.first {
        text = text + Text(" in \(repo)")
      }
    }
    return text
  }

  // Tight relative stamp for the dock ("2h", "1d") — the full relative
  // phrasing the list rows use reads too long at this density.
  private var compactRecency: String {
    guard let date = status.updatedAt else { return "" }
    let seconds = max(0, Date().timeIntervalSince(date))
    if seconds < 3600 { return "\(max(1, Int(seconds / 60)))m" }
    if seconds < 86_400 { return "\(Int(seconds / 3600))h" }
    return "\(Int(seconds / 86_400))d"
  }
}

// MARK: - Preview

#Preview("Orbit — four online, three drifting") {
  func sample(
    _ handle: String, _ name: String, mode: PresenceMode,
    manual: String? = nil, insertions: Int = 0, deletions: Int = 0,
    commits: Int = 0, typical: Int? = nil, repos: [String] = [],
    gradient: (String, String)? = nil, agoHours: Double = 0
  ) -> MergedStatus {
    var user = UserSummary(id: handle, handle: handle, displayName: name, timezone: nil)
    if let gradient {
      user.avatarKind = "gradient"
      user.avatarGradient = AvatarGradient(start: gradient.0, end: gradient.1)
    }
    var cards: [StatusCard] = [
      StatusCard(
        type: "git_stats", enabled: true, summary: nil,
        data: [
          "commits": .int(commits), "insertions": .int(insertions),
          "deletions": .int(deletions),
        ]
      )
    ]
    if !repos.isEmpty {
      cards.append(StatusCard(
        type: "repo_aliases", enabled: true,
        summary: repos.joined(separator: ", "),
        data: ["aliases": .array(repos.map { .string($0) })]
      ))
    }
    return MergedStatus(
      user: user, mode: mode, manualStatus: manual, day: nil,
      updatedAt: Date().addingTimeInterval(-agoHours * 3600),
      cards: cards, typicalChurn: typical
    )
  }

  return OrbitView(
    you: sample(
      "marcus", "Marcus", mode: .online, manual: "shipping the new titlebar ✨",
      insertions: 482, deletions: 127, commits: 9, typical: 800,
      repos: ["vibes", "td-watch"], gradient: ("#4F8CFF", "#9B5CFF")
    ),
    friends: [
      sample(
        "dana", "Dana", mode: .online, manual: "deep in the parser mines",
        insertions: 1204, deletions: 688, commits: 14, typical: 1100,
        repos: ["perch", "perch-docs"], gradient: ("#FF7847", "#FF4787")
      ),
      sample(
        "priya", "Priya", mode: .online, manual: "refactor friday!!",
        insertions: 356, deletions: 1892, commits: 7, typical: 2600,
        repos: ["atlas"], gradient: ("#27D3A2", "#1F9BFF")
      ),
      sample(
        "theo", "Theo", mode: .online, manual: "coffee #2, warming up",
        insertions: 23, deletions: 4, commits: 1, typical: 400,
        repos: ["dotfiles"], gradient: ("#FFD24F", "#FF8C3B")
      ),
      sample("sam", "Sam", mode: .offline, insertions: 210, deletions: 95, commits: 4, agoHours: 2),
      sample("kei", "Kei", mode: .offline, agoHours: 26),
    ]
  )
  .frame(width: 480, height: 600)
}
