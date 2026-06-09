import SwiftUI

// FriendCard — an isolated, reusable presence card for one person (a friend or
// "you"). Pulls its visual language from the shared TE tokens in `VibeColor`
// (see client/Vibes/DESIGN.md): a raised `cardSurface` block on the chassis,
// hairline `cardBorder`, chunky `radiusCard`. The online dot is "lit"; offline
// is "at-rest". Commit count is surfaced prominently; repos and an optional
// manual status note fill out the body.
//
// Rendered in isolation here with previews for every state and both sizes.
// Wiring into the Home view happens in a later task (td-4ac06a).

// Shape / sizing constants documented in DESIGN.md. Colors live in VibeColor;
// these are the matching shape tokens, kept local to the card for now.
enum FriendCardSize {
  case comfortable
  case compact

  var padding: CGFloat { self == .comfortable ? 16 : 12 }
  var spacing: CGFloat { self == .comfortable ? 10 : 7 }
  var nameFont: Font {
    .system(size: self == .comfortable ? 16 : 14, weight: .medium)
  }
  var commitNumberFont: Font {
    .system(size: self == .comfortable ? 30 : 24, weight: .semibold, design: .rounded)
  }
  var commitLabelFont: Font {
    .system(size: self == .comfortable ? 11 : 10, weight: .medium)
  }
  var bodyFont: Font {
    .system(size: self == .comfortable ? 14 : 13)
  }
  var captionFont: Font {
    .system(size: self == .comfortable ? 12 : 11)
  }
  var dotSize: CGFloat { self == .comfortable ? 14 : 10 }
  var chipFont: Font {
    .system(size: self == .comfortable ? 11 : 10, weight: .medium)
  }
}

private enum FriendCardShape {
  static let radiusCard: CGFloat = 14
  static let radiusControl: CGFloat = 8
}

struct FriendCard: View {
  var status: MergedStatus
  var isYou: Bool = false
  var size: FriendCardSize = .comfortable

  var body: some View {
    VStack(alignment: .leading, spacing: size.spacing) {
      header
      commitFeature
      if !repoAliases.isEmpty {
        repoChips
      }
      if let note = manualNote {
        Text(note)
          .font(size.bodyFont)
          .foregroundStyle(VibeColor.foreground)
          .lineLimit(2)
          .fixedSize(horizontal: false, vertical: true)
      } else {
        Text(presenceText)
          .font(size.bodyFont)
          .foregroundStyle(VibeColor.muted)
      }
    }
    .padding(size.padding)
    .frame(maxWidth: .infinity, alignment: .leading)
    .background(VibeColor.cardSurface)
    .clipShape(RoundedRectangle(cornerRadius: FriendCardShape.radiusCard))
    .overlay(
      RoundedRectangle(cornerRadius: FriendCardShape.radiusCard)
        .stroke(VibeColor.cardBorder, lineWidth: 1)
    )
  }

  // MARK: - Sections

  private var header: some View {
    HStack(alignment: .firstTextBaseline, spacing: 8) {
      // Presence dot: "lit" green when online, "at-rest" neutral otherwise.
      Circle()
        .fill(isOnline ? VibeColor.online : VibeColor.controlAtRest)
        .frame(width: size.dotSize, height: size.dotSize)
        .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
      Text(isYou ? "you" : status.user.displayName)
        .font(size.nameFont)
        .foregroundStyle(VibeColor.foreground)
        .lineLimit(1)
      Spacer(minLength: 4)
      Text(lastSeen)
        .font(size.captionFont)
        .foregroundStyle(VibeColor.muted)
    }
  }

  // Commits-per-day, surfaced prominently — the focal stat of the card.
  private var commitFeature: some View {
    HStack(alignment: .firstTextBaseline, spacing: 6) {
      Text("\(commitCount)")
        .font(size.commitNumberFont)
        .foregroundStyle(commitCount > 0 ? VibeColor.accent : VibeColor.muted)
      Text(commitCount == 1 ? "commit today" : "commits today")
        .font(size.commitLabelFont)
        .foregroundStyle(VibeColor.muted)
        .textCase(.uppercase)
    }
  }

  // Repos worked on today as small at-rest chips.
  private var repoChips: some View {
    FlowChips(aliases: repoAliases, size: size)
  }

  // MARK: - Derived data

  private var isOnline: Bool { status.mode == .online }

  private var manualNote: String? {
    guard isOnline, let note = status.manualStatus, !note.isEmpty else { return nil }
    return note
  }

  private var gitStatsCard: StatusCard? {
    status.cards.first { $0.type == "git_stats" }
  }

  private var commitCount: Int {
    gitStatsCard?.data["commits"]?.intValue ?? 0
  }

  private var repoAliasCard: StatusCard? {
    status.cards.first { $0.type == "repo_aliases" }
  }

  private var repoAliases: [String] {
    if case let .array(items)? = repoAliasCard?.data["aliases"] {
      return items.compactMap { if case let .string(s) = $0 { return s } else { return nil } }
    }
    // Fall back to the comma-joined summary if structured data is absent.
    if let summary = repoAliasCard?.summary, !summary.isEmpty {
      return summary.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    return []
  }

  // Reused from StatusRow.presenceText:
  // online → "online"; offline-but-recent → "online {relative} ago";
  // offline-no-timestamp → "offline".
  private var presenceText: String {
    if isOnline { return "online" }
    guard let updatedAt = status.updatedAt else { return "offline" }
    return "online \(updatedAt.formatted(.relative(presentation: .numeric)))"
  }

  private var lastSeen: String {
    guard let date = status.updatedAt else { return "" }
    return date.formatted(.relative(presentation: .named))
  }
}

// Small wrapping row of repo-alias chips. At-rest neutral blocks per DESIGN.md.
private struct FlowChips: View {
  var aliases: [String]
  var size: FriendCardSize

  var body: some View {
    // A simple horizontal run; the card is narrow so we cap visible chips and
    // summarize the remainder. Avoids a custom flow layout dependency.
    HStack(spacing: 6) {
      ForEach(Array(visible.enumerated()), id: \.offset) { _, alias in
        Text(alias)
          .font(size.chipFont)
          .padding(.horizontal, 8)
          .padding(.vertical, 3)
          .foregroundStyle(VibeColor.controlAtRestForeground)
          .background(VibeColor.controlAtRest)
          .clipShape(RoundedRectangle(cornerRadius: 8))
          .lineLimit(1)
      }
      if overflow > 0 {
        Text("+\(overflow)")
          .font(size.chipFont)
          .foregroundStyle(VibeColor.muted)
      }
    }
  }

  private var maxVisible: Int { size == .comfortable ? 3 : 2 }
  private var visible: [String] { Array(aliases.prefix(maxVisible)) }
  private var overflow: Int { max(0, aliases.count - maxVisible) }
}

// MARK: - Preview sample data

private func sampleStatus(
  handle: String,
  name: String,
  mode: PresenceMode,
  manual: String? = nil,
  updatedAt: Date? = Date(),
  commits: Int? = 7,
  repos: [String] = ["vibes", "relay", "dotfiles"]
) -> MergedStatus {
  var cards: [StatusCard] = []
  if let commits {
    cards.append(StatusCard(
      type: "git_stats",
      enabled: true,
      summary: "\(repos.count) repos touched - \(commits) commits",
      data: ["commits": .int(commits), "repos_touched": .int(repos.count)]
    ))
  }
  if !repos.isEmpty {
    cards.append(StatusCard(
      type: "repo_aliases",
      enabled: true,
      summary: repos.joined(separator: ", "),
      data: ["aliases": .array(repos.map { .string($0) })]
    ))
  }
  return MergedStatus(
    user: UserSummary(id: handle, handle: handle, displayName: name, timezone: nil),
    mode: mode,
    manualStatus: manual,
    day: nil,
    updatedAt: updatedAt,
    cards: cards
  )
}

#Preview("Online") {
  FriendCard(status: sampleStatus(
    handle: "lin",
    name: "Lin Wei",
    mode: .online,
    manual: "deep in the parser rewrite",
    commits: 12
  ))
  .padding()
  .frame(width: 300)
  .background(VibeColor.chassis)
}

#Preview("Offline — recent") {
  FriendCard(status: sampleStatus(
    handle: "sam",
    name: "Sam Ortiz",
    mode: .offline,
    updatedAt: Date().addingTimeInterval(-3600),
    commits: 4,
    repos: ["api", "web"]
  ))
  .padding()
  .frame(width: 300)
  .background(VibeColor.chassis)
}

#Preview("Offline — hidden") {
  FriendCard(status: sampleStatus(
    handle: "kai",
    name: "Kai Mensah",
    mode: .offline,
    updatedAt: nil,
    commits: nil,
    repos: []
  ))
  .padding()
  .frame(width: 300)
  .background(VibeColor.chassis)
}

#Preview("You") {
  FriendCard(
    status: sampleStatus(
      handle: "me",
      name: "Marcus",
      mode: .online,
      manual: "shipping the UI rework",
      commits: 23,
      repos: ["vibes", "relay", "td", "dotfiles"]
    ),
    isYou: true
  )
  .padding()
  .frame(width: 300)
  .background(VibeColor.chassis)
}

#Preview("Empty / loading") {
  FriendCard(status: sampleStatus(
    handle: "new",
    name: "Pat",
    mode: .offline,
    updatedAt: nil,
    commits: 0,
    repos: []
  ))
  .padding()
  .frame(width: 300)
  .background(VibeColor.chassis)
}

#Preview("Sizes — comfortable vs compact") {
  VStack(spacing: 12) {
    FriendCard(
      status: sampleStatus(handle: "lin", name: "Lin Wei", mode: .online, commits: 12),
      size: .comfortable
    )
    FriendCard(
      status: sampleStatus(handle: "lin", name: "Lin Wei", mode: .online, commits: 12),
      size: .compact
    )
  }
  .padding()
  .frame(width: 280)
  .background(VibeColor.chassis)
}
