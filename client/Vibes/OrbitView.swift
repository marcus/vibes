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
  // The network pulse "core" — drawn dim and centered behind the friend orbs.
  // nil (old server, or feature off) => no core layer at all.
  var pulse: NetworkPulse?

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var windowAllowsAnimation = false

  private static let animationInterval = 1.0 / 12.0

  var body: some View {
    TimelineView(
      .animation(
        minimumInterval: Self.animationInterval,
        paused: reduceMotion || !windowAllowsAnimation
      )
    ) { context in
      VStack(spacing: 0) {
        GeometryReader { geo in
          ZStack {
            let members = skyMembers
            let biggest = maxChurn(of: members)
            // The pulse core is laid out as one more body in the same slot system
            // as the orbs: the slots are sized for everyone at once, the core takes
            // the most central one, and the churn-sorted members fill the rest. The
            // sky self-arranges around it, so the core no longer overlaps anyone.
            let layout = skyLayout(memberCount: members.count, hasCore: pulse != nil)
            if let pulse, let coreUnit = layout.core {
              PulseCore(pulse: pulse, animationDate: context.date)
                .position(point(coreUnit, in: geo.size))
                .allowsHitTesting(false)
            }
            ForEach(Array(members.enumerated()), id: \.element.id) { index, status in
              OrbView(
                status: status,
                isYou: status.user.handle == you.user.handle,
                rank: index,
                maxChurn: biggest,
                animationDate: context.date
              )
              .position(point(layout.members[index], in: geo.size))
            }
          }
          .frame(maxWidth: .infinity, maxHeight: .infinity)
          .overlay(alignment: .bottom) {
            if friends.isEmpty {
              // With the pulse core filling the sky the nudge softens to a quiet
              // invite line rather than a lonely "empty sky" message.
              Text(
                pulse != nil
                  ? "Invite a friend to share your orbit."
                  : "Just you up here so far. Invite a friend to fill the sky."
              )
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
    .background {
      WindowAnimationVisibilityReader(allowsAnimation: $windowAllowsAnimation)
        .frame(width: 0, height: 0)
    }
  }

  // Reports whether drawing another animation frame could produce a visible
  // result. AppKit's occlusion state covers a fully covered window, while the
  // other flags cover close/hide and minimization explicitly.
  private struct WindowAnimationVisibilityReader: NSViewRepresentable {
    @Binding var allowsAnimation: Bool

    func makeNSView(context: Context) -> VisibilityNSView {
      VisibilityNSView { value in
        DispatchQueue.main.async {
          if allowsAnimation != value {
            allowsAnimation = value
          }
        }
      }
    }

    func updateNSView(_ nsView: VisibilityNSView, context: Context) {
      nsView.report = { value in
        DispatchQueue.main.async {
          if allowsAnimation != value {
            allowsAnimation = value
          }
        }
      }
      nsView.refresh()
    }

    final class VisibilityNSView: NSView {
      var report: (Bool) -> Void
      private var observations: [NSObjectProtocol] = []

      init(report: @escaping (Bool) -> Void) {
        self.report = report
        super.init(frame: .zero)
      }

      @available(*, unavailable)
      required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
      }

      deinit {
        observations.forEach(NotificationCenter.default.removeObserver)
      }

      override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        observeWindow()
        refresh()
      }

      func refresh() {
        guard let window else {
          report(false)
          return
        }
        report(
          window.isVisible
            && !window.isMiniaturized
            && window.occlusionState.contains(.visible)
        )
      }

      private func observeWindow() {
        observations.forEach(NotificationCenter.default.removeObserver)
        observations.removeAll()
        guard let window else { return }

        let names: [Notification.Name] = [
          NSWindow.didChangeOcclusionStateNotification,
          NSWindow.didMiniaturizeNotification,
          NSWindow.didDeminiaturizeNotification,
          NSWindow.willCloseNotification,
        ]
        observations = names.map { name in
          NotificationCenter.default.addObserver(
            forName: name,
            object: window,
            queue: .main
          ) { [weak self] _ in
            self?.refresh()
          }
        }
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

  // Unit-coordinate positions for `count` bodies — the hand-tuned constellation
  // for small skies, a staggered grid beyond that.
  private func slotUnits(count: Int) -> [CGPoint] {
    guard count > 0 else { return [] }
    if count <= Self.slots.count {
      return Self.slots[count - 1]
    }
    // Staggered grid for big skies: 3 columns, odd rows offset half a cell.
    let columns = 3
    let rows = (count + columns - 1) / columns
    return (0..<count).map { index in
      let row = index / columns
      let column = index % columns
      let xStep = 1.0 / Double(columns + 1)
      let yStep = 0.84 / Double(max(rows, 1))
      let stagger = row.isMultiple(of: 2) ? 0.0 : xStep * 0.4
      return CGPoint(
        x: min(0.84, xStep * Double(column + 1) + stagger),
        y: 0.12 + yStep * (Double(row) + 0.5)
      )
    }
  }

  // Place the orbs and (optionally) the pulse core in one shared layout. The
  // core counts as an extra body, so the slots are spaced for everyone; it then
  // claims the most central slot — pinned to true center — while the churn-sorted
  // members take the remaining outer slots. Centered when it can be, but always a
  // slot the others arranged around, so nothing overlaps.
  private func skyLayout(memberCount: Int, hasCore: Bool) -> (core: CGPoint?, members: [CGPoint]) {
    guard hasCore else { return (nil, slotUnits(count: memberCount)) }
    var units = slotUnits(count: memberCount + 1)
    guard !units.isEmpty else { return (Self.skyCenter, []) }
    units.remove(at: indexClosestToCenter(units))
    return (Self.skyCenter, units)
  }

  private static let skyCenter = CGPoint(x: 0.5, y: 0.46)

  private func indexClosestToCenter(_ units: [CGPoint]) -> Int {
    units.indices.min { distanceToCenter(units[$0]) < distanceToCenter(units[$1]) } ?? 0
  }

  private func distanceToCenter(_ unit: CGPoint) -> CGFloat {
    hypot(unit.x - Self.skyCenter.x, unit.y - Self.skyCenter.y)
  }

  private func point(_ unit: CGPoint, in size: CGSize) -> CGPoint {
    CGPoint(x: unit.x * size.width, y: unit.y * size.height)
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
  var animationDate: Date

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.feedTextScale) private var textScale
  @State private var musicHovered = false

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
    .offset(y: floatOffset(at: animationDate))
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilitySummary)
  }

  // Gentle bob, period and phase staggered by rank so the orbs don't move in
  // lockstep. Driven by TimelineView (a committed offset each frame) rather
  // than a repeatForever animation: the avatar PNG loads async, and content
  // inserted under an in-flight persistent animation can end up out of phase
  // with its clip circle, showing the bitmap's cropped edges as the orb floats.
  private func floatOffset(at date: Date) -> CGFloat {
    guard !reduceMotion else { return 0 }
    let period = 12.0 + Double(rank % 3) * 2.6
    let phase = Double(rank) * 0.9
    return CGFloat(sin(date.timeIntervalSinceReferenceDate * 2 * .pi / period + phase) * 5)
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
      .overlay(alignment: .bottomTrailing) {
        // Mirrors the second repo moon's perch on the opposite arc, so the
        // expanded track line rides across the orb instead of the name label.
        if let track = status.nowPlayingLine {
          musicChip(track).offset(x: diameter * 0.46, y: -diameter * 0.10)
        }
      }
  }

  private var labels: some View {
    VStack(spacing: 1) {
      HStack(spacing: 5) {
        Text(isYou ? "you" : status.user.displayName)
          .font(.system(size: 11 * textScale, weight: .semibold))
          .lineLimit(1)
        if let weather = status.weatherLine {
          Text(weather)
            .font(.system(size: 10 * textScale))
            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            .monospacedDigit()
            .lineLimit(1)
            .help(status.weatherDetail ?? "")
        }
      }
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

  // The now-playing chip: a lone ♪ at rest so the sky stays quiet, expanding
  // on hover to the track line. Same capsule family as the repo moons.
  private func musicChip(_ track: String) -> some View {
    HStack(spacing: 4) {
      Text("♪")
        .font(.system(size: 10 * textScale, weight: .semibold))
        .foregroundStyle(Color.secondary)
      if musicHovered {
        Text(track)
          .font(.system(size: 10 * textScale))
          .foregroundStyle(Color.secondary)
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(maxWidth: 150)
          .transition(.opacity.combined(with: .move(edge: .leading)))
      }
    }
    .padding(.horizontal, 7)
    .padding(.vertical, 2.5)
    // At rest it's a moon-family chip; expanded it floats over whatever it
    // crosses (the orb, the far repo moon), so it switches to an opaque
    // material and reads as a tooltip.
    .background(
      musicHovered
        ? AnyShapeStyle(.regularMaterial)
        : AnyShapeStyle(Color(nsColor: .quaternarySystemFill)),
      in: Capsule()
    )
    .fixedSize()
    .onHover { hovering in
      withAnimation(.snappy(duration: 0.18)) { musicHovered = hovering }
    }
    .help(track)
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
    if let track = status.nowPlayingLine {
      parts.append("listening to \(track)")
    }
    if let weather = status.weatherDetail ?? status.weatherLine {
      parts.append("weather \(weather)")
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
    gradient: (String, String)? = nil, agoHours: Double = 0,
    music: String? = nil, weather: (String, Int)? = nil
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
    if let music {
      cards.append(StatusCard(
        type: "music", enabled: true, summary: music,
        data: [
          "source": .string("spotify"),
          "state": .string("playing"),
          "captured_at": .string(ISO8601DateFormatter().string(from: Date())),
        ]
      ))
    }
    if let weather {
      cards.append(StatusCard(
        type: "weather", enabled: true, summary: "\(weather.0) \(weather.1)°",
        data: [
          "emoji": .string(weather.0),
          "condition": .string("Partly cloudy"),
          "temp_f": .int(weather.1),
          "temp_c": .int(Int((Double(weather.1) - 32) * 5 / 9)),
          "city": .string("Seattle"),
        ]
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
      repos: ["vibes", "td-watch"], gradient: ("#4F8CFF", "#9B5CFF"),
      music: "Pink Pony Club · Chappell Roan", weather: ("⛅️", 61)
    ),
    friends: [
      sample(
        "dana", "Dana", mode: .online, manual: "deep in the parser mines",
        insertions: 1204, deletions: 688, commits: 14, typical: 1100,
        repos: ["perch", "perch-docs"], gradient: ("#FF7847", "#FF4787"),
        music: "Starburster · Fontaines D.C.", weather: ("🌧", 54)
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
    ],
    pulse: {
      let f = DateFormatter()
      f.locale = Locale(identifier: "en_US_POSIX")
      f.dateFormat = "yyyy-MM-dd"
      let churns = [90_000, 96_000, 42_000, 38_000, 110_000, 118_000, 132_000,
                    100_000, 108_000, 48_000, 36_000, 124_000, 140_000, 162_600]
      let start = Calendar.current.date(byAdding: .day, value: -(churns.count - 1), to: Date())!
      let history = churns.enumerated().map { i, c -> PulseDay in
        let date = Calendar.current.date(byAdding: .day, value: i, to: start)!
        let ins = Int(Double(c) * 0.79)
        return PulseDay(day: f.string(from: date), churn: c, contributors: 30 + i,
          insertions: ins, deletions: c - ins)
      }
      return NetworkPulse(
        statless: false,
        today: PulseToday(insertions: 128_400, deletions: 34_200, churn: 162_600,
          contributors: 47, typicalChurn: 125_000, lap: 1.3),
        history: history)
    }()
  )
  .frame(width: 480, height: 600)
}
