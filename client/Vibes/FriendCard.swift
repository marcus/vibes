import SwiftUI

// FriendCard — the Aurora II presence card for one person (a friend or "you").
// Design source: experiments/friend-list-mockups, design E ("Aurora II").
//
// Layout, top to bottom:
//   header  — ring avatar (breathing when online) · name + status line · updated-at
//   LOC bar — always full width; additions left, deletions right, numbers inside.
//             The split reflects this person's own add/remove ratio (absolute
//             scale isn't comparable between people).
//   legend  — commit count left, repo list right
//   extras  — optional spotify track / weather, faintest tier, only when shared
//
// "You" gets the identical treatment on a subtle accent-tinted wash. Offline
// friends don't use this card — they render as AwayFriendRow below.

enum FriendCardSize {
  case comfortable
  case compact
}

struct FriendCard: View {
  var status: MergedStatus
  var isYou: Bool = false
  @Environment(\.feedTextScale) private var textScale

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      header
      LocBar(added: status.insertions, removed: status.deletions)
      legend
      if status.nowPlayingLine != nil || status.weatherLine != nil {
        extras
      }
    }
    .padding(15)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(isYou ? AnyShapeStyle(.tint.opacity(0.12)) : AnyShapeStyle(.background.secondary))
    .clipShape(RoundedRectangle(cornerRadius: 16))
    .overlay(
      RoundedRectangle(cornerRadius: 16)
        .stroke(Color(nsColor: .separatorColor), lineWidth: 1)
    )
  }

  // MARK: - Sections

  private var header: some View {
    HStack(alignment: .center, spacing: 13) {
      AvatarView(status: status, size: .comfortable, isOnline: isOnline, breathes: isOnline)
      VStack(alignment: .leading, spacing: 2) {
        Text(isYou ? "you" : status.user.displayName)
          .font(.system(size: 13 * textScale, weight: .semibold))
          .foregroundStyle(Color.primary)
          .lineLimit(1)
        Text(statusLine)
          .font(.system(size: 11 * textScale))
          .foregroundStyle(Color.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 4)
      Text(lastSeen)
        .font(.system(size: 10 * textScale))
        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
        .frame(maxHeight: .infinity, alignment: .top)
        .padding(.top, 2)
    }
    .fixedSize(horizontal: false, vertical: true)
  }

  private var legend: some View {
    HStack(alignment: .firstTextBaseline) {
      HStack(alignment: .firstTextBaseline, spacing: 7) {
        Text("\(Text("\(status.commitCount)").fontWeight(.bold).foregroundColor(Color.primary))\(status.commitCount == 1 ? " commit today" : " commits today")")
          .font(.system(size: 10 * textScale))
          .foregroundStyle(Color.secondary)
          .monospacedDigit()
          .lineLimit(1)
        if let streak = status.commitStreakLine {
          Text(streak)
            .font(.system(size: 10 * textScale))
            .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
            .monospacedDigit()
            .lineLimit(1)
        }
      }
      .layoutPriority(1)

      Spacer(minLength: 8)

      if !status.repoAliases.isEmpty {
        Text(status.repoAliases.joined(separator: ", "))
          .font(.system(size: 10 * textScale, weight: .semibold))
          .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
          .lineLimit(1)
          .truncationMode(.tail)
      }
    }
  }

  // One quiet line: now-playing left, weather right. Either half drops out
  // when the friend isn't sharing it (or the track has gone stale — see
  // MergedStatus.nowPlayingLine); the row drops out when both are absent.
  private var extras: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      if let track = status.nowPlayingLine {
        Text("♪ \(track)")
          .font(.caption)
          .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
          .lineLimit(1)
          .truncationMode(.tail)
      }
      Spacer(minLength: 0)
      if let weather = status.weatherLine {
        Text(weather)
          .font(.caption)
          .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
          .monospacedDigit()
          .lineLimit(1)
          .help(status.weatherDetail ?? "")
      }
    }
  }

  // MARK: - Derived data

  private var isOnline: Bool { status.mode == .online }

  // Manual status when set; otherwise a quiet presence description.
  private var statusLine: String {
    if let note = status.manualStatus, !note.isEmpty { return note }
    if isOnline { return "online" }
    guard let updatedAt = status.updatedAt else { return "offline" }
    return "offline, synced \(updatedAt.formatted(.relative(presentation: .numeric)))"
  }

  private var lastSeen: String {
    guard let date = status.updatedAt else { return "" }
    return date.formatted(.relative(presentation: .named))
  }
}

// The full-width added/removed bar. Additions fill from the left, deletions from
// the right; each half keeps a minimum width so small numbers stay readable, and
// a zero day splits the bar evenly.
private struct LocBar: View {
  var added: Int
  var removed: Int
  @Environment(\.feedTextScale) private var textScale

  private let height: CGFloat = 22
  private let minHalf: CGFloat = 64

  var body: some View {
    GeometryReader { geo in
      let addWidth = addedWidth(in: geo.size.width)
      HStack(spacing: 0) {
        Text("+\(added)")
          .foregroundStyle(Color(nsColor: .systemGreen))
          .padding(.leading, 12)
          .frame(width: addWidth, height: height, alignment: .leading)
          .background(Color(nsColor: .systemGreen).opacity(0.15))
        Text("\u{2212}\(removed)")
          .foregroundStyle(Color(nsColor: .systemRed))
          .padding(.trailing, 12)
          .frame(width: geo.size.width - addWidth, height: height, alignment: .trailing)
          .background(Color(nsColor: .systemRed).opacity(0.12))
      }
      // Base size 11 must fit inside the fixed-height (22pt) capsule with the
      // per-half minimum width; even at the largest feed scale (1.3 → ~14pt)
      // it stays inside. Monospaced digits keep the +/− counts aligned.
      .font(.system(size: 11 * textScale, weight: .bold))
      .monospacedDigit()
      .clipShape(Capsule())
    }
    .frame(height: height)
  }

  private func addedWidth(in total: CGFloat) -> CGFloat {
    guard total > 2 * minHalf else { return total / 2 }
    let sum = added + removed
    guard sum > 0 else { return total / 2 }
    let proportional = total * CGFloat(added) / CGFloat(sum)
    return min(max(proportional, minHalf), total - minHalf)
  }
}

// MARK: - Away list

// Compact one-line row for an offline friend: small at-rest avatar, name, the
// last-known activity, and recency. Quiet by design — these sit below the
// "away" divider and shouldn't compete with the online cards.
struct AwayFriendRow: View {
  var status: MergedStatus
  @Environment(\.feedTextScale) private var textScale

  var body: some View {
    HStack(spacing: 10) {
      AvatarView(status: status, size: .compact, isOnline: false)
        .saturation(0.3)
        .opacity(0.8)
      Text(status.user.displayName)
        .font(.system(size: 11 * textScale, weight: .semibold))
        .foregroundStyle(Color.secondary)
        .lineLimit(1)
      Text(recentSummary)
        .font(.system(size: 10 * textScale))
        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
        .lineLimit(1)
        .truncationMode(.tail)
      Spacer(minLength: 8)
      Text(lastSeen)
        .font(.system(size: 10 * textScale))
        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
    }
    .padding(.vertical, 7)
    .padding(.horizontal, 10)
    .background(Color(nsColor: .quaternarySystemFill))
    .clipShape(RoundedRectangle(cornerRadius: 11))
  }

  private var recentSummary: String {
    let commits = status.commitCount
    guard commits > 0 else { return "quiet today" }
    var parts = ["\(commits) commit\(commits == 1 ? "" : "s")"]
    let aliases = status.repoAliases
    if !aliases.isEmpty { parts.append(aliases.joined(separator: ", ")) }
    return parts.joined(separator: " · ")
  }

  private var lastSeen: String {
    guard let date = status.updatedAt else { return "" }
    return date.formatted(.relative(presentation: .named))
  }
}

// "AWAY ────────" — the divider between online cards and the away list.
struct AwaySectionHeader: View {
  var body: some View {
    HStack(spacing: 10) {
      Text("AWAY")
        .font(.caption2.weight(.bold))
        .tracking(1.2)
        .foregroundStyle(Color(nsColor: .tertiaryLabelColor))
      Rectangle()
        .fill(Color(nsColor: .separatorColor))
        .frame(height: 1)
    }
    .padding(.horizontal, 2)
  }
}

// MARK: - Preview sample data

private func sampleStatus(
  handle: String,
  name: String,
  mode: PresenceMode,
  manual: String? = nil,
  updatedAt: Date? = Date(),
  commits: Int = 7,
  insertions: Int = 412,
  deletions: Int = 96,
  repos: [String] = ["vibes", "relay"],
  spotify: String? = nil,
  weather: String? = nil,
  streakDays: Int? = nil,
  streakThroughDay: String = "2026-06-15"
) -> MergedStatus {
  var cards: [StatusCard] = [
    StatusCard(
      type: "git_stats",
      enabled: true,
      summary: nil,
      data: [
        "commits": .int(commits),
        "insertions": .int(insertions),
        "deletions": .int(deletions),
      ]
    )
  ]
  if !repos.isEmpty {
    cards.append(StatusCard(
      type: "repo_aliases",
      enabled: true,
      summary: repos.joined(separator: ", "),
      data: ["aliases": .array(repos.map { .string($0) })]
    ))
  }
  if let spotify {
    cards.append(StatusCard(
      type: "music",
      enabled: true,
      summary: spotify,
      data: [
        "source": .string("spotify"),
        "state": .string("playing"),
        "captured_at": .string(ISO8601DateFormatter().string(from: Date())),
      ]
    ))
  }
  if let weather {
    cards.append(StatusCard(type: "weather", enabled: true, summary: weather, data: [:]))
  }
  return MergedStatus(
    user: UserSummary(id: handle, handle: handle, displayName: name, timezone: nil),
    mode: mode,
    manualStatus: manual,
    day: nil,
    updatedAt: updatedAt,
    cards: cards,
    commitStreak: streakDays.map { CommitStreak(days: $0, throughDay: streakThroughDay) }
  )
}

#Preview("Aurora II — column") {
  VStack(alignment: .leading, spacing: 12) {
    FriendCard(
      status: sampleStatus(
        handle: "me", name: "Marcus", mode: .online, manual: "VIBES",
        commits: 3, insertions: 777, deletions: 34, repos: ["braid"],
        spotify: "Pink Pony Club · Chappell Roan", weather: "⛅️ 61°",
        streakDays: 4
      ),
      isYou: true
    )
    FriendCard(status: sampleStatus(
      handle: "ana", name: "Ana", mode: .online, manual: "rewriting the parser, again",
      commits: 7, insertions: 412, deletions: 96, repos: ["lexer", "docs"],
      spotify: "Starburster · Fontaines D.C.", weather: "☀️ 72°",
      streakDays: 1
    ))
    FriendCard(status: sampleStatus(
      handle: "theo", name: "Theo", mode: .online, manual: "shipping the billing fix 🤞",
      commits: 4, insertions: 188, deletions: 240, repos: ["billing"],
      weather: "🌧 54°"
    ))
    AwaySectionHeader()
      .padding(.top, 4)
    AwayFriendRow(status: sampleStatus(
      handle: "priya", name: "Priya", mode: .offline,
      updatedAt: Date().addingTimeInterval(-3 * 3600),
      commits: 5, insertions: 301, deletions: 77, repos: ["api"]
    ))
    AwayFriendRow(status: sampleStatus(
      handle: "sam", name: "Sam", mode: .offline,
      updatedAt: Date().addingTimeInterval(-26 * 3600),
      commits: 0, insertions: 0, deletions: 0, repos: []
    ))
  }
  .padding(16)
  .frame(width: 420)
}

#Preview("Zero day") {
  FriendCard(status: sampleStatus(
    handle: "new", name: "Pat", mode: .online,
    commits: 0, insertions: 0, deletions: 0, repos: []
  ))
  .padding()
  .frame(width: 420)
}
