import AppKit
import Combine
import Foundation

// MusicProvider — the sender side of the music ("now playing") card.
//
// Both desktop players broadcast track changes over the distributed
// notification center with the track metadata in userInfo, so the core flow
// needs no OAuth, no Apple Events consent, and no private MediaRemote API
// (blocked for unentitled apps since macOS 15.4):
//   Spotify      com.spotify.client.PlaybackStateChanged
//   Apple Music  com.apple.Music.playerInfo
//
// Notifications only fire on *change*, so enabling the card mid-song would
// show nothing until the next track. seedFromRunningPlayers() closes that gap
// with a one-shot AppleScript query — strictly guarded by a running-app check
// (a bare `tell application` would launch the player) and triggering the
// standard Automation consent prompt the first time. Declining just means the
// card populates at the next track change.

struct NowPlaying: Equatable {
  enum Source: String {
    case spotify
    case appleMusic = "apple_music"
  }

  var source: Source
  var track: String
  var artist: String
  var isPlaying: Bool
  var capturedAt: Date

  var summary: String {
    artist.isEmpty ? track : "\(track) · \(artist)"
  }

  var card: StatusCard {
    StatusCard(
      type: "music",
      enabled: true,
      summary: summary,
      data: [
        "source": .string(source.rawValue),
        "track": .string(track),
        "artist": .string(artist),
        "state": .string(isPlaying ? "playing" : "paused"),
        "captured_at": .string(ISO8601DateFormatter().string(from: capturedAt)),
      ]
    )
  }
}

final class MusicProvider: ObservableObject {
  // The latest report per player. When both players have reported, whichever
  // is actually playing wins; ties go to the most recent report.
  @Published private(set) var current: NowPlaying?

  // Fired (debounced upstream) so a track change can publish without waiting
  // up to three minutes for the next loop tick.
  var onChange: (() -> Void)?

  private var bySource: [NowPlaying.Source: NowPlaying] = [:]
  private var observers: [NSObjectProtocol] = []
  private var workspaceObserver: NSObjectProtocol?
  private var hasSeeded = false

  private static let spotifyBundleID = "com.spotify.client"
  private static let musicBundleID = "com.apple.Music"

  func start() {
    guard observers.isEmpty else { return }
    let center = DistributedNotificationCenter.default()
    observers.append(
      center.addObserver(
        forName: Notification.Name("com.spotify.client.PlaybackStateChanged"),
        object: nil, queue: .main
      ) { [weak self] note in
        MainActor.assumeIsolated { self?.ingest(note, source: .spotify) }
      })
    observers.append(
      center.addObserver(
        forName: Notification.Name("com.apple.Music.playerInfo"),
        object: nil, queue: .main
      ) { [weak self] note in
        MainActor.assumeIsolated { self?.ingest(note, source: .appleMusic) }
      })

    // A quit player can't say "stopped" — drop its report when it exits.
    workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.didTerminateApplicationNotification,
      object: nil, queue: .main
    ) { [weak self] note in
      MainActor.assumeIsolated {
        guard
          let bundleID = (note.userInfo?[NSWorkspace.applicationUserInfoKey]
            as? NSRunningApplication)?.bundleIdentifier
        else { return }
        if bundleID == Self.spotifyBundleID { self?.clear(.spotify) }
        if bundleID == Self.musicBundleID { self?.clear(.appleMusic) }
      }
    }
  }

  func stop() {
    let center = DistributedNotificationCenter.default()
    observers.forEach { center.removeObserver($0) }
    observers = []
    if let workspaceObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
      self.workspaceObserver = nil
    }
    bySource = [:]
    current = nil
    hasSeeded = false
  }

  // One-shot AppleScript query of any player that is already running, used
  // when the card is first enabled (and once per provider start). Runs off
  // the main actor — a consent prompt or a busy player can block the
  // AppleEvent round-trip.
  func seedFromRunningPlayers() {
    guard !hasSeeded else { return }
    hasSeeded = true
    let running = Set(
      NSWorkspace.shared.runningApplications.compactMap(\.bundleIdentifier)
    )
    for (bundleID, source, appName) in [
      (Self.spotifyBundleID, NowPlaying.Source.spotify, "Spotify"),
      (Self.musicBundleID, .appleMusic, "Music"),
    ] where running.contains(bundleID) {
      Task.detached(priority: .utility) {
        guard let seeded = Self.queryPlayer(appName: appName, source: source) else { return }
        await MainActor.run { [weak self] in
          guard let self else { return }
          // Live notifications beat the seed — don't overwrite one that
          // arrived while the AppleScript round-trip was in flight.
          if self.bySource[source] == nil {
            self.bySource[source] = seeded
            self.recomputeCurrent(notify: true)
          }
        }
      }
    }
  }

  // MARK: - Ingest

  private func ingest(_ note: Notification, source: NowPlaying.Source) {
    guard let info = note.userInfo else { return }
    let state = (info["Player State"] as? String ?? "").lowercased()
    let track = (info["Name"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
    let artist = (info["Artist"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

    if state == "stopped" || track.isEmpty {
      clear(source)
      return
    }
    bySource[source] = NowPlaying(
      source: source,
      track: track,
      artist: artist,
      isPlaying: state == "playing",
      capturedAt: Date()
    )
    recomputeCurrent(notify: true)
  }

  private func clear(_ source: NowPlaying.Source) {
    guard bySource[source] != nil else { return }
    bySource[source] = nil
    recomputeCurrent(notify: true)
  }

  private func recomputeCurrent(notify: Bool) {
    let next = bySource.values.sorted { lhs, rhs in
      lhs.isPlaying == rhs.isPlaying
        ? lhs.capturedAt > rhs.capturedAt
        : lhs.isPlaying && !rhs.isPlaying
    }.first
    guard next != current else { return }
    current = next
    if notify { onChange?() }
  }

  // MARK: - AppleScript seed

  nonisolated private static func queryPlayer(
    appName: String, source: NowPlaying.Source
  ) -> NowPlaying? {
    // Tab-joined single result keeps the parse trivial; "missing value"
    // artists (podcasts, local files) come back as empty.
    let script = """
      tell application "\(appName)"
        if player state is playing or player state is paused then
          set t to name of current track
          set a to artist of current track
          if a is missing value then set a to ""
          set s to (player state is playing)
          return t & tab & a & tab & s
        end if
        return ""
      end tell
      """
    var errorInfo: NSDictionary?
    guard
      let result = NSAppleScript(source: script)?.executeAndReturnError(&errorInfo).stringValue,
      !result.isEmpty
    else { return nil }
    let parts = result.components(separatedBy: "\t")
    guard parts.count >= 3, !parts[0].isEmpty else { return nil }
    return NowPlaying(
      source: source,
      track: parts[0],
      artist: parts[1],
      isPlaying: parts[2] == "true",
      capturedAt: Date()
    )
  }
}
