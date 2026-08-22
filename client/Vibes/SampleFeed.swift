#if DEBUG
import Foundation

// DEBUG-only sample data for SwiftUI previews and demo mode
// (VIBES_DEMO_FEED=1). Strip-out point: delete this file plus the
// `isDemoFeed` blocks marked "DEMO MODE" in AppModel.swift and VibesApp.swift.
// Release builds compile none of it.
//
// Single source of truth for the sample cast: OrbitView's #Preview renders
// exactly this data, and demo mode seeds AppModel.feed with the same set, so
// screenshots match previews by construction.

/// Sample feed data for previews and demo mode.
enum SampleFeed {
  /// One sample member carrying whatever cards it was given.
  static func status(
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

  /// The network pulse core shown behind the orbs.
  static var pulse: NetworkPulse {
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
  }

  /// The signed-in member of the sample cast.
  static let you = status(
    "marcus", "Marcus", mode: .online, manual: "shipping the new titlebar ✨",
    insertions: 482, deletions: 127, commits: 9, typical: 800,
    repos: ["vibes", "td-watch"], gradient: ("#4F8CFF", "#9B5CFF"),
    music: "Pink Pony Club · Chappell Roan", weather: ("⛅️", 61)
  )

  /// Four online friends and two drifting, matching the orbit mockup.
  static let friends: [MergedStatus] = [
    status(
      "dana", "Dana", mode: .online, manual: "deep in the parser mines",
      insertions: 1204, deletions: 688, commits: 14, typical: 1100,
      repos: ["perch", "perch-docs"], gradient: ("#FF7847", "#FF4787"),
      music: "Starburster · Fontaines D.C.", weather: ("🌧", 54)
    ),
    status(
      "priya", "Priya", mode: .online, manual: "refactor friday!!",
      insertions: 356, deletions: 1892, commits: 7, typical: 2600,
      repos: ["atlas"], gradient: ("#27D3A2", "#1F9BFF")
    ),
    status(
      "theo", "Theo", mode: .online, manual: "coffee #2, warming up",
      insertions: 23, deletions: 4, commits: 1, typical: 400,
      repos: ["dotfiles"], gradient: ("#FFD24F", "#FF8C3B")
    ),
    status("sam", "Sam", mode: .offline, insertions: 210, deletions: 95, commits: 4, agoHours: 2),
    status("kei", "Kei", mode: .offline, agoHours: 26),
  ]

  /// A complete feed for seeding a demo-mode AppModel.
  static func feedResponse() -> FeedResponse {
    FeedResponse(you: you, friends: friends, pulse: pulse)
  }
}
#endif
