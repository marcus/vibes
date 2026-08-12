import SwiftUI

// PulseView — the aggregate "network pulse" surfaces (design/mockups/network-pulse.html,
// concept A + panel C). Two views that share the same privacy-safe NetworkPulse data:
//
//   PulseCore     — a dim, slow-breathing neutral-slate "core" orb the real friend
//                   orbs drift around. No avatar, no identity. A churn ring shows
//                   today's network churn vs the network's typical day (lap badge
//                   when it laps), a 14-day sparkline rides across its empty center,
//                   and a caption sits below. Rendered behind the friend orbs in
//                   OrbitView so it fills an empty sky without faking people.
//   PulseHistory  — the 14-day bar chart pinned at the top of the list feed:
//                   weekend bars shaded, today highlighted, suppressed days empty.
//
// When the network is `statless` (< 3 contributors today) both fall back to a
// wordless "people are vibing today" sign of life — no numbers, no sparkline.

// MARK: - Number abbreviation

// 1,247 -> "1.2k", 128,400 -> "128.4k", 1,200,000 -> "1.2M". One decimal,
// trailing ".0" trimmed, sub-1k passed through whole.
func abbreviateCount(_ value: Int) -> String {
  let n = Double(abs(value))
  let sign = value < 0 ? "-" : ""
  func trim(_ x: Double) -> String {
    let s = String(format: "%.1f", x)
    return s.hasSuffix(".0") ? String(s.dropLast(2)) : s
  }
  if n >= 1_000_000 { return "\(sign)\(trim(n / 1_000_000))M" }
  if n >= 1_000 { return "\(sign)\(trim(n / 1_000))k" }
  return "\(sign)\(Int(n))"
}

// MARK: - Core gradient background

// The animated backdrop inside the pulse core: a "rainbow minus green" sheen
// (the Vibes palette), kept quiet so a sparkline reads cleanly on top.
// Sheen is baked once and rotated with Core Animation under a circular mask
// (see AmbientSheenDisk) so rotation stays cheap and clipped.
struct CoreGradientBackground: View {
  var allowsMotion: Bool = true

  @Environment(\.colorScheme) private var colorScheme

  static let restingAngle: Double = 210
  static let rotationPeriod: TimeInterval = 30
  static let darkBase = Color(red: 0.06, green: 0.07, blue: 0.11)
  static let lightBase = Color(red: 0.90, green: 0.95, blue: 1.0)

  var body: some View {
    let isDark = colorScheme == .dark
    let base = isDark ? Self.darkBase : Self.lightBase
    ZStack {
      base
      AmbientSheenDisk(
        isDark: isDark,
        enabled: allowsMotion,
        period: Self.rotationPeriod,
        startDegrees: Self.restingAngle
      )
      // Vignette stays fixed so the center remains the luminous reading area.
      RadialGradient(
        colors: [.clear, base.opacity(isDark ? 0.65 : 0.50)],
        center: .center, startRadius: 6, endRadius: 70
      )
    }
    .clipShape(Circle())
  }
}

// MARK: - Pulse core (orbit background layer)

// The neutral-slate core. Reuses the ChurnMeter/ChurnRing vocabulary from
// OrbitView for the today-vs-typical ring, but with no identity and a dim,
// breathing presence so it reads as ambient population rather than a person.
// Opacity breath is applied by the caller via ambientOpacityBreath.
struct PulseCore: View {
  var pulse: NetworkPulse
  var allowsMotion: Bool = true

  // Conservative so it never crowds the friend orbits' edge slots.
  private static let diameter: CGFloat = 120
  private static let glowColor = Color(red: 0.47, green: 0.55, blue: 0.85)

  var body: some View {
    VStack(spacing: 9) {
      ZStack {
        // Soft static halo (animated shadows are expensive).
        Circle()
          .fill(Self.glowColor.opacity(0.20 * 0.55))
          .frame(width: Self.diameter * 1.45, height: Self.diameter * 1.45)

        CoreGradientBackground(allowsMotion: allowsMotion)
          .frame(width: Self.diameter, height: Self.diameter)
          .clipShape(Circle())
          .overlay(Circle().strokeBorder(Color.white.opacity(0.10), lineWidth: 0.5))
          .shadow(color: Self.glowColor.opacity(0.18), radius: Self.diameter * 0.45)

        PulseCoreStaticForeground(pulse: pulse)
          .equatable()
        if pulse.statless {
          PulseCoreTwinkle()
        }
      }
      if !pulse.statless {
        PulseCoreCaption(pulse: pulse)
          .equatable()
      }
    }
    .accessibilityElement(children: .ignore)
    .accessibilityLabel(accessibilityLabel)
  }

  private var accessibilityLabel: String {
    if pulse.statless {
      return "People are vibing on the network today"
    }
    guard let today = pulse.today else {
      return "Network pulse"
    }
    var parts = ["Across the network today"]
    parts.append("plus \(today.insertions), minus \(today.deletions) lines")
    parts.append("\(today.contributors) people vibing")
    if let lap = today.lap, lap > 1.0 {
      parts.append(String(format: "%.1f× the network's typical day", lap))
    }
    return parts.joined(separator: ", ")
  }
}

// Disk chrome that does not depend on the animation clock.
private struct PulseCoreStaticForeground: View, Equatable {
  var pulse: NetworkPulse

  @Environment(\.feedTextScale) private var textScale
  @Environment(\.colorScheme) private var colorScheme

  private static let diameter: CGFloat = 120

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.pulse == rhs.pulse
  }

  private var meter: ChurnMeter? {
    guard let today = pulse.today else { return nil }
    return ChurnMeter(
      insertions: today.insertions, deletions: today.deletions, typical: today.typicalChurn)
  }

  private var lapLabel: String? {
    guard let lap = pulse.today?.lap, lap > 1.0 else { return nil }
    return String(format: "%.1f×", lap)
  }

  var body: some View {
    let d = Self.diameter
    ZStack {
      if !pulse.statless, pulse.history.count >= 2 {
        ZStack {
          PulseSparkline(history: pulse.history)
            .frame(width: d, height: d * 0.34)
          Text("14 days")
            .font(.system(size: 9 * textScale, weight: .medium))
            .foregroundStyle(sparklineCaptionColor)
            .offset(y: d * 0.22)
        }
        .frame(width: d, height: d)
        .clipShape(Circle())
      }
    }
    .overlay {
      if let meter {
        ChurnRing(meter: meter)
          .frame(width: d + 13, height: d + 13)
          .opacity(0.7)
      }
    }
    .overlay(alignment: .topTrailing) {
      if let lapLabel {
        Text(lapLabel)
          .font(.system(size: 9.5 * textScale, weight: .bold).monospaced())
          .padding(.horizontal, 6)
          .padding(.vertical, 1.5)
          .background(.yellow.opacity(0.16), in: Capsule())
          .overlay(Capsule().strokeBorder(.yellow.opacity(0.45), lineWidth: 1))
          .foregroundStyle(.yellow)
          .offset(x: 14, y: -8)
      }
    }
  }

  private var sparklineCaptionColor: Color {
    colorScheme == .dark
      ? Color.white.opacity(0.6)
      : Color(red: 0.22, green: 0.31, blue: 0.45).opacity(0.82)
  }
}

// Sign-of-life dots when the network is too small for stats.
private struct PulseCoreTwinkle: View {
  var body: some View {
    HStack(spacing: 9) {
      ForEach(0..<3, id: \.self) { _ in
        Circle()
          .fill(Color(red: 0.49, green: 0.54, blue: 0.63).opacity(0.5))
          .frame(width: 11, height: 11)
      }
    }
  }
}

private struct PulseCoreCaption: View, Equatable {
  var pulse: NetworkPulse

  @Environment(\.feedTextScale) private var textScale

  static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.pulse == rhs.pulse
  }

  var body: some View {
    VStack(spacing: 2) {
      Text("across vibes · today")
        .font(.system(size: 9.5 * textScale, weight: .semibold))
        .tracking(1.4)
        .textCase(.uppercase)
        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
      if let today = pulse.today {
        HStack(spacing: 6) {
          Text("+\(abbreviateCount(today.insertions))")
            .foregroundStyle(Color(nsColor: .systemGreen))
          Text("\u{2212}\(abbreviateCount(today.deletions))")
            .foregroundStyle(Color(nsColor: .systemRed))
        }
        .font(.system(size: 13 * textScale, weight: .semibold).monospaced())
        Text("\(today.contributors) vibing")
          .font(.system(size: 10.5 * textScale))
          .foregroundStyle(Color.secondary)
      }
    }
  }
}

// The 14-day sparkline as a SwiftUI Path, normalized to its own min/max with a
// terminal dot on today. Suppressed (null-churn) days are interpolated over so
// the line stays continuous.
struct PulseSparkline: View {
  var history: [PulseDay]

  @Environment(\.colorScheme) private var colorScheme

  // Glow styling, tunable in one place.
  private var glow: Color {
    Color(red: 0.62, green: 0.80, blue: 1.0).opacity(colorScheme == .dark ? 0.9 : 0.5)
  }

  private var lineColors: [Color] {
    if colorScheme == .dark {
      return [
        Color(red: 0.80, green: 0.92, blue: 1.0),
        Color.white,
        Color(red: 1.0, green: 0.90, blue: 0.82),
      ]
    }
    return [
      Color(red: 0.22, green: 0.47, blue: 0.74),
      Color(red: 0.42, green: 0.66, blue: 0.94),
      Color(red: 0.72, green: 0.47, blue: 0.72),
    ]
  }

  private var endpointFill: Color {
    colorScheme == .dark ? .white : Color(red: 0.27, green: 0.52, blue: 0.86)
  }

  var body: some View {
    GeometryReader { geo in
      let points = normalizedPoints(in: geo.size)
      ZStack {
        if points.count >= 2 {
          let line = Path { path in
            path.move(to: points[0])
            for p in points.dropFirst() { path.addLine(to: p) }
          }
          // Soft wide halo under a bright near-white stroke = a glowing line.
          line.stroke(glow,
            style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            .blur(radius: 4)
          line.stroke(
            LinearGradient(colors: lineColors, startPoint: .leading, endPoint: .trailing),
            style: StrokeStyle(lineWidth: 1.8, lineCap: .round, lineJoin: .round)
          )
          .shadow(color: glow, radius: 2.5)
        }
        if let last = points.last {
          Circle()
            .fill(endpointFill)
            .frame(width: 4.6, height: 4.6)
            .shadow(color: glow, radius: 4)
            .position(last)
        }
      }
    }
  }

  // Churn series with suppressed days filled from their neighbors so a gap
  // doesn't drop the line to zero. Two-pass (forward then backward): the forward
  // pass carries each known value over later gaps; the backward pass fills any
  // LEADING run of suppressed days from the first known value, so a leading gap
  // doesn't render a misleading flat segment that then jumps.
  private func churnSeries() -> [Double] {
    var series = history.map { $0.churn.map(Double.init) }
    var last: Double?
    for i in series.indices {
      if let value = series[i] { last = value } else { series[i] = last }
    }
    var next: Double?
    for i in series.indices.reversed() {
      if let value = series[i] { next = value } else { series[i] = next }
    }
    return series.map { $0 ?? 0 }
  }

  private func normalizedPoints(in size: CGSize) -> [CGPoint] {
    let series = churnSeries()
    guard series.count >= 2 else { return [] }
    let lo = series.min() ?? 0
    let hi = series.max() ?? 1
    let span = max(hi - lo, 1)
    // Full-bleed horizontally (the circle clips the ends); a little vertical
    // inset so peaks and troughs keep clear of the glow's blur radius.
    let vInset: CGFloat = 4
    let w = size.width
    let h = size.height - vInset * 2
    return series.enumerated().map { index, value in
      let x = w * CGFloat(index) / CGFloat(series.count - 1)
      let y = vInset + h * (1 - CGFloat((value - lo) / span))
      return CGPoint(x: x, y: y)
    }
  }
}

// MARK: - Pulse history (list top, panel C)

// The 14-day bar chart: weekend bars shaded, today highlighted, suppressed days
// drawn as a minimal empty stub. A summary line sits below. Statless => the
// "people are vibing today" fallback instead of the chart.
struct PulseHistory: View {
  var pulse: NetworkPulse

  @Environment(\.feedTextScale) private var textScale

  private var maxChurn: Int {
    max(pulse.history.compactMap { $0.churn }.max() ?? 1, 1)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("the pulse · last \(pulse.windowDays) days")
        .font(.system(size: 9.5 * textScale, weight: .semibold))
        .tracking(1.4)
        .textCase(.uppercase)
        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
        .padding(.bottom, 12)

      if pulse.statless {
        statlessFallback
      } else {
        chart
        // Divider + summary only when there's a `today` to summarize, so a
        // malformed response (chart but null today) doesn't leave an orphan rule.
        if pulse.today != nil {
          summary
            .padding(.top, 12)
            .overlay(alignment: .top) { Divider() }
        }
      }
    }
    .padding(18)
    .background(Color(nsColor: .quaternarySystemFill).opacity(0.6))
    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
  }

  // MARK: chart

  private var chart: some View {
    GeometryReader { geo in
      let bars = pulse.history
      let count = max(bars.count, 1)
      let gap: CGFloat = 4
      let barWidth = max((geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count), 1)
      let maxC = CGFloat(maxChurn)
      HStack(alignment: .bottom, spacing: gap) {
        ForEach(bars) { day in
          // Highlight by actual calendar date, not list position, so it stays
          // correct even if the server ever emits today mid-window.
          let isToday = Calendar.current.isDateInToday(day.date ?? .distantPast)
          let h = barHeight(for: day, maxC: maxC, available: geo.size.height)
          ZStack(alignment: .bottom) {
            // Weekend shading behind the bar column.
            if day.isWeekend {
              Rectangle()
                .fill(Color.white.opacity(0.025))
            }
            RoundedRectangle(cornerRadius: 2, style: .continuous)
              .fill(barFill(isToday: isToday, suppressed: day.isSuppressed))
              .frame(height: h)
          }
          .frame(width: barWidth)
        }
      }
    }
    .frame(height: 96)
  }

  private func barHeight(for day: PulseDay, maxC: CGFloat, available: CGFloat) -> CGFloat {
    guard let churn = day.churn, churn > 0 else { return 2 }  // suppressed/empty stub
    let frac = CGFloat(churn) / maxC
    return max(available * frac, 3)
  }

  private func barFill(isToday: Bool, suppressed: Bool) -> Color {
    if suppressed { return Color.white.opacity(0.06) }
    if isToday { return Color(red: 0.59, green: 0.71, blue: 0.88).opacity(0.85) }
    return Color(red: 0.49, green: 0.63, blue: 0.82).opacity(0.5)
  }

  // MARK: summary

  private var summary: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      if let today = pulse.today {
        HStack(spacing: 6) {
          Text("+\(abbreviateCount(today.insertions))")
            .foregroundStyle(Color(nsColor: .systemGreen))
          Text("\u{2212}\(abbreviateCount(today.deletions))")
            .foregroundStyle(Color(nsColor: .systemRed))
        }
        .font(.system(size: 15 * textScale, weight: .semibold).monospaced())
        Text("· \(today.contributors) vibing today")
          .font(.system(size: 11 * textScale))
          .foregroundStyle(Color.secondary)
      }
    }
  }

  private var statlessFallback: some View {
    VStack(spacing: 6) {
      HStack(spacing: 9) {
        ForEach(0..<3, id: \.self) { _ in
          Circle()
            .fill(Color(red: 0.49, green: 0.54, blue: 0.63).opacity(0.4))
            .frame(width: 12, height: 12)
        }
      }
      Text("people are vibing today")
        .font(.system(size: 12 * textScale))
        .foregroundStyle(Color.secondary)
      Text("numbers appear once 3+ have committed")
        .font(.system(size: 10.5 * textScale))
        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 8)
  }
}

// MARK: - Previews

private func previewPulse(
  statless: Bool = false, lap: Double? = 1.3, typical: Int? = 125_000
) -> NetworkPulse {
  let days = [90_000, 96_000, 42_000, 38_000, 110_000, 118_000, 132_000,
              100_000, 108_000, 48_000, 36_000, 124_000, 140_000, 162_600]
  let start = Calendar.current.date(byAdding: .day, value: -(days.count - 1), to: Date())!
  let f = DateFormatter()
  f.locale = Locale(identifier: "en_US_POSIX")
  f.dateFormat = "yyyy-MM-dd"
  let history = days.enumerated().map { index, churn -> PulseDay in
    let date = Calendar.current.date(byAdding: .day, value: index, to: start)!
    // Sprinkle a suppressed day to exercise the empty-bar path.
    if index == 4 {
      return PulseDay(day: f.string(from: date), churn: nil, contributors: nil,
        insertions: nil, deletions: nil)
    }
    let ins = Int(Double(churn) * 0.79)
    return PulseDay(day: f.string(from: date), churn: churn, contributors: 30 + index,
      insertions: ins, deletions: churn - ins)
  }
  let today = statless ? nil : PulseToday(
    insertions: 128_400, deletions: 34_200, churn: 162_600, contributors: 47,
    typicalChurn: typical, lap: lap)
  return NetworkPulse(statless: statless, today: today, history: history)
}

#Preview("PulseCore — lapped") {
  PulseCore(pulse: previewPulse())
    .frame(width: 280, height: 280)
    .background(Color.black)
}

#Preview("PulseCore — statless") {
  PulseCore(pulse: previewPulse(statless: true))
    .frame(width: 280, height: 280)
    .background(Color.black)
}

#Preview("PulseHistory — 14 days") {
  PulseHistory(pulse: previewPulse())
    .frame(width: 440)
    .padding()
    .background(Color.black)
}

#Preview("PulseHistory — statless") {
  PulseHistory(pulse: previewPulse(statless: true))
    .frame(width: 440)
    .padding()
    .background(Color.black)
}
