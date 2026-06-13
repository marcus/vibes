import AppKit
import Foundation
import SwiftUI

enum PresenceMode: String, Codable, CaseIterable, Identifiable {
  case online
  case offline

  var id: String { rawValue }

  var label: String {
    switch self {
    case .online: "Online"
    case .offline: "Offline"
    }
  }
}

struct IdentityConfig: Codable, Equatable {
  var handle: String
  var displayName: String
  var timezone: String?

  init(handle: String, displayName: String, timezone: String? = nil) {
    self.handle = handle
    self.displayName = displayName
    self.timezone = timezone
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    handle = try container.decode(String.self, forKey: .handle)
    displayName = try container.decode(String.self, forKey: .displayName)
    timezone = try container.decodeIfPresent(String.self, forKey: .timezone)
  }

  enum CodingKeys: String, CodingKey {
    case handle
    case displayName = "display_name"
    case timezone
  }
}

struct DeviceConfig: Codable, Equatable {
  var id: String
  var label: String

  init(id: String = "", label: String) {
    self.id = id
    self.label = label
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
    label = try container.decodeIfPresent(String.self, forKey: .label) ?? "Mac"
  }
}

struct ServerConfig: Codable, Equatable {
  var relayURL: URL

  enum CodingKeys: String, CodingKey {
    case relayURL = "relay_url"
  }
}

struct RepoConfig: Codable, Equatable, Identifiable {
  var id: UUID
  var path: String
  var alias: String
  var shareAlias: Bool

  init(id: UUID = UUID(), path: String, alias: String, shareAlias: Bool = true) {
    self.id = id
    self.path = path
    self.alias = alias
    self.shareAlias = shareAlias
  }

  enum CodingKeys: String, CodingKey {
    case id
    case path
    case alias
    case shareAlias = "share_alias"
  }
}

struct SharingCardsConfig: Codable, Equatable {
  var gitStats: Bool
  var repoAliases: Bool
  var music: Bool
  var weather: Bool

  static let defaults = SharingCardsConfig(
    gitStats: true,
    repoAliases: true,
    music: false,
    weather: false
  )

  init(
    gitStats: Bool,
    repoAliases: Bool,
    music: Bool,
    weather: Bool
  ) {
    self.gitStats = gitStats
    self.repoAliases = repoAliases
    self.music = music
    self.weather = weather
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    gitStats = try container.decodeIfPresent(Bool.self, forKey: .gitStats) ?? Self.defaults.gitStats
    repoAliases = try container.decodeIfPresent(Bool.self, forKey: .repoAliases) ?? Self.defaults.repoAliases
    // "music" covers Spotify and Apple Music; it supersedes the never-shipped
    // "spotify" key, which is still honored if an old config flipped it on.
    let legacy = try decoder.container(keyedBy: LegacyKeys.self)
    music = try container.decodeIfPresent(Bool.self, forKey: .music)
      ?? legacy.decodeIfPresent(Bool.self, forKey: .spotify)
      ?? Self.defaults.music
    weather = try container.decodeIfPresent(Bool.self, forKey: .weather) ?? Self.defaults.weather
  }

  enum CodingKeys: String, CodingKey {
    case gitStats = "git_stats"
    case repoAliases = "repo_aliases"
    case music
    case weather
  }

  private enum LegacyKeys: String, CodingKey {
    case spotify
  }
}

// Sender-side weather settings, separate from the on/off card toggle. An empty
// `manualCity` means "use Location Services"; a non-empty city is geocoded by
// WeatherProvider instead (no location permission needed). City name rides
// along in the shared card only when `shareCity` is on.
struct WeatherConfig: Codable, Equatable {
  var manualCity: String
  var shareCity: Bool

  static let defaults = WeatherConfig(manualCity: "", shareCity: false)

  init(manualCity: String, shareCity: Bool) {
    self.manualCity = manualCity
    self.shareCity = shareCity
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    manualCity = try container.decodeIfPresent(String.self, forKey: .manualCity) ?? Self.defaults.manualCity
    shareCity = try container.decodeIfPresent(Bool.self, forKey: .shareCity) ?? Self.defaults.shareCity
  }

  enum CodingKeys: String, CodingKey {
    case manualCity = "manual_city"
    case shareCity = "share_city"
  }
}

struct SharingRedactionsConfig: Codable, Equatable {
  var repoPaths: Bool
  var branchNames: Bool
  var commitMessages: Bool
  var fileNames: Bool
  var editorActivity: Bool
  var assistantAttribution: Bool

  static let defaults = SharingRedactionsConfig(
    repoPaths: true,
    branchNames: true,
    commitMessages: true,
    fileNames: true,
    editorActivity: true,
    assistantAttribution: true
  )

  init(
    repoPaths: Bool,
    branchNames: Bool,
    commitMessages: Bool,
    fileNames: Bool,
    editorActivity: Bool,
    assistantAttribution: Bool
  ) {
    self.repoPaths = repoPaths
    self.branchNames = branchNames
    self.commitMessages = commitMessages
    self.fileNames = fileNames
    self.editorActivity = editorActivity
    self.assistantAttribution = assistantAttribution
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    repoPaths = try container.decodeIfPresent(Bool.self, forKey: .repoPaths) ?? Self.defaults.repoPaths
    branchNames = try container.decodeIfPresent(Bool.self, forKey: .branchNames) ?? Self.defaults.branchNames
    commitMessages = try container.decodeIfPresent(Bool.self, forKey: .commitMessages) ?? Self.defaults.commitMessages
    fileNames = try container.decodeIfPresent(Bool.self, forKey: .fileNames) ?? Self.defaults.fileNames
    editorActivity = try container.decodeIfPresent(Bool.self, forKey: .editorActivity) ?? Self.defaults.editorActivity
    assistantAttribution = try container.decodeIfPresent(Bool.self, forKey: .assistantAttribution) ?? Self.defaults.assistantAttribution
  }

  enum CodingKeys: String, CodingKey {
    case repoPaths = "repo_paths"
    case branchNames = "branch_names"
    case commitMessages = "commit_messages"
    case fileNames = "file_names"
    case editorActivity = "editor_activity"
    case assistantAttribution = "assistant_attribution"
  }
}

struct SharingConfig: Codable, Equatable {
  var cards: SharingCardsConfig
  var redactions: SharingRedactionsConfig
  var weather: WeatherConfig

  static let defaults = SharingConfig(cards: .defaults, redactions: .defaults, weather: .defaults)

  init(
    cards: SharingCardsConfig,
    redactions: SharingRedactionsConfig = .defaults,
    weather: WeatherConfig = .defaults
  ) {
    self.cards = cards
    self.redactions = redactions
    self.weather = weather
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    cards = try container.decodeIfPresent(SharingCardsConfig.self, forKey: .cards) ?? .defaults
    redactions = try container.decodeIfPresent(SharingRedactionsConfig.self, forKey: .redactions) ?? .defaults
    weather = try container.decodeIfPresent(WeatherConfig.self, forKey: .weather) ?? .defaults
  }

  enum CodingKeys: String, CodingKey {
    case cards
    case redactions
    case weather
  }
}

struct PresenceConfig: Codable, Equatable {
  var mode: PresenceMode
  var manualStatus: String

  static let defaults = PresenceConfig(mode: .online, manualStatus: "")

  enum CodingKeys: String, CodingKey {
    case mode
    case manualStatus = "manual_status"
  }
}

struct VibesConfig: Codable, Equatable {
  var identity: IdentityConfig
  var device: DeviceConfig
  var server: ServerConfig
  var repos: [RepoConfig]
  var sharing: SharingConfig
  var presence: PresenceConfig

  static func firstLaunch(
    relayURL: URL,
    handle: String,
    displayName: String,
    deviceLabel: String,
    timezone: String = TimeZone.current.identifier
  ) -> VibesConfig {
    VibesConfig(
      identity: IdentityConfig(handle: handle, displayName: displayName, timezone: timezone),
      device: DeviceConfig(id: UUID().uuidString.lowercased(), label: deviceLabel),
      server: ServerConfig(relayURL: relayURL),
      repos: [],
      sharing: .defaults,
      presence: .defaults
    )
  }
}

struct DailyGitStats: Codable, Equatable {
  var commits: Int = 0
  var filesChanged: Int = 0
  var insertions: Int = 0
  var deletions: Int = 0
  var reposTouched: Int = 0
  var latestActivity: Date?
  var repoAliases: [String] = []

  // Committed activity only — see GitScanner.scanRepo for why uncommitted
  // diffs are excluded.
  var hasActivity: Bool {
    commits > 0 || insertions > 0 || deletions > 0
  }

  var summary: String {
    "\(reposTouched) repos touched - \(commits) commits - +\(insertions) / -\(deletions) LOC"
  }
}

enum JSONValue: Codable, Equatable {
  case string(String)
  case int(Int)
  case double(Double)
  case bool(Bool)
  case object([String: JSONValue])
  case array([JSONValue])
  case null

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode(Int.self) {
      self = .int(value)
    } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
    } else {
      self = .array(try container.decode([JSONValue].self))
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value): try container.encode(value)
    case .int(let value): try container.encode(value)
    case .double(let value): try container.encode(value)
    case .bool(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .null: try container.encodeNil()
    }
  }

  var intValue: Int? {
    switch self {
    case .int(let value): value
    case .double(let value): Int(value)
    default: nil
    }
  }

  var stringValue: String? {
    if case .string(let value) = self { value } else { nil }
  }

  var objectValue: [String: JSONValue]? {
    if case .object(let value) = self { value } else { nil }
  }

  // ISO-8601 timestamp parsing for date fields that ride inside card `data`
  // (the card payload is opaque JSON, so dates travel as strings). Tolerates
  // both plain and fractional-second forms.
  var dateValue: Date? {
    guard case .string(let value) = self else { return nil }
    if let date = JSONValue.isoFormatter.date(from: value) { return date }
    return JSONValue.isoFractionalFormatter.date(from: value)
  }

  private static let isoFormatter = ISO8601DateFormatter()
  private static let isoFractionalFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()
}

struct StatusCard: Codable, Equatable, Identifiable {
  var id: String { type }
  var type: String
  var enabled: Bool
  var summary: String?
  var data: [String: JSONValue]
}

// A two-color gradient profile icon, rendered client-side (no PNG asset). Synced
// to all the user's devices and to friends via the feed. Both ends are
// "#RRGGBB" hex strings (server-validated `^#[0-9a-fA-F]{6}$`).
struct AvatarGradient: Codable, Equatable {
  var start: String
  var end: String
}

struct UserSummary: Codable, Equatable, Identifiable {
  var id: String?
  var handle: String
  var displayName: String
  var timezone: String?
  var avatarUrl: String?
  // Explicit selector for which avatar representation to render:
  //   "image"    → AI-generated PNG at `avatarUrl`
  //   "gradient" → the two-color `avatarGradient`
  //   nil        → initials fallback
  var avatarKind: String?
  var avatarGradient: AvatarGradient?

  enum CodingKeys: String, CodingKey {
    case id
    case handle
    case displayName = "display_name"
    case timezone
    case avatarUrl = "avatar_url"
    case avatarKind = "avatar_kind"
    case avatarGradient = "avatar_gradient"
  }
}

// Server-owned art-direction template for AI profile-icon generation, fetched as
// part of `/api/me` (`house_style`). The client composes
// `promptPrefix + userPrompt + promptSuffix`, picks the first `styles` entry that
// the on-device ImageCreator actually offers, and renders a square
// `imageSize`×`imageSize` PNG. Tunable server-side without an app release.
struct HouseStyle: Codable, Equatable {
  var promptPrefix: String
  var promptSuffix: String
  var styles: [String]
  var imageSize: Int

  enum CodingKeys: String, CodingKey {
    case promptPrefix = "prompt_prefix"
    case promptSuffix = "prompt_suffix"
    case styles
    case imageSize = "image_size"
  }
}

struct RegisterRequest: Codable, Equatable {
  var displayName: String
  var deviceLabel: String
  var timezone: String

  enum CodingKeys: String, CodingKey {
    case displayName = "display_name"
    case deviceLabel = "device_label"
    case timezone
  }
}

struct RegisteredIdentity: Codable, Equatable {
  var user: UserSummary
  var token: String
}

// A short-lived pairing code minted on a signed-in Mac so a new Mac can join
// the same account ("Link this Mac"). The raw code is shown once; the server
// keeps only its hash.
struct DeviceLinkCode: Codable, Equatable {
  var id: String
  var code: String
  var expiresAt: Date

  enum CodingKeys: String, CodingKey {
    case id
    case code
    case expiresAt = "expires_at"
  }
}

struct ClaimLinkCodeRequest: Codable, Equatable {
  var code: String
  var deviceLabel: String

  enum CodingKeys: String, CodingKey {
    case code
    case deviceLabel = "device_label"
  }
}

// One row in Settings → General → Devices. A "device" is an active auth
// token: tokens are minted one per Mac and labeled with the device name, and
// last_used_at is touched on every authenticated call (device last-seen).
struct DeviceSummary: Codable, Equatable, Identifiable {
  var id: String { tokenId }
  var tokenId: String
  var label: String?
  var createdAt: Date
  var lastUsedAt: Date?
  // True when this row is the token making the request — "This Mac".
  var current: Bool

  enum CodingKeys: String, CodingKey {
    case tokenId = "token_id"
    case label
    case createdAt = "created_at"
    case lastUsedAt = "last_used_at"
    case current
  }
}

struct DeviceListResponse: Codable, Equatable {
  var devices: [DeviceSummary]
}

struct MintTokenRequest: Codable, Equatable {
  var label: String
}

struct RevokeTokenRequest: Codable, Equatable {
  var tokenId: String

  enum CodingKeys: String, CodingKey {
    case tokenId = "token_id"
  }
}

struct AcceptInviteResult: Codable, Equatable {
  var inviter: UserSummary
  var friend: UserSummary
}

struct PendingInvite: Equatable, Identifiable {
  var code: String
  // Looked up after the deep link arrives (GET /api/invites/<code>) so the
  // sheet can say who sent it; nil until the lookup lands or if it fails.
  var inviterName: String?

  var id: String { code }
}

// GET /api/invites/<code> — the code itself is the capability, mirroring the
// /invite/<code> web landing page.
struct InviteLookup: Codable, Equatable {
  var state: String
  var inviter: String?
}

struct MergedStatus: Codable, Equatable, Identifiable {
  var id: String { user.handle }
  var user: UserSummary
  var mode: PresenceMode
  var manualStatus: String?
  var day: String?
  var updatedAt: Date?
  var cards: [StatusCard]
  // Median daily churn (insertions + deletions) over this user's recent active
  // days, computed by the relay. nil until they have enough history — the
  // orbit ring then falls back to a fixed cold-start scale (see ChurnMeter).
  var typicalChurn: Int?

  enum CodingKeys: String, CodingKey {
    case user
    case mode
    case manualStatus = "manual_status"
    case day
    case updatedAt = "updated_at"
    case cards
    case typicalChurn = "typical_churn"
  }
}

// Shared accessors for the structured card data every presence view reads
// (FriendCard, AwayFriendRow, OrbitView). One parsing path, one fallback story.
extension MergedStatus {
  var gitStatsCard: StatusCard? {
    cards.first { $0.type == "git_stats" }
  }

  var commitCount: Int { gitStatsCard?.data["commits"]?.intValue ?? 0 }
  var insertions: Int { gitStatsCard?.data["insertions"]?.intValue ?? 0 }
  var deletions: Int { gitStatsCard?.data["deletions"]?.intValue ?? 0 }

  // Total lines touched today — the orbit ring's progress quantity.
  var churn: Int { insertions + deletions }

  var repoAliases: [String] {
    let card = cards.first { $0.type == "repo_aliases" }
    if case let .array(items)? = card?.data["aliases"] {
      return items.compactMap { if case let .string(s) = $0 { return s } else { return nil } }
    }
    // Fall back to the comma-joined summary if structured data is absent.
    if let summary = card?.summary, !summary.isEmpty {
      return summary.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }
    return []
  }

  var musicCard: StatusCard? {
    cards.first { $0.type == "music" && $0.enabled }
  }

  var weatherCard: StatusCard? {
    cards.first { $0.type == "weather" && $0.enabled }
  }

  // "Track · Artist" while the friend is actually listening. Gated on the
  // sender-stamped player state and capture time so a track from hours ago
  // never renders as now-playing (offline snapshots re-send old cards, and a
  // device can go quiet without un-publishing). Missing fields stay lenient.
  var nowPlayingLine: String? {
    guard let card = musicCard, let summary = card.summary, !summary.isEmpty else { return nil }
    if let state = card.data["state"]?.stringValue, state != "playing" { return nil }
    if let captured = card.data["captured_at"]?.dateValue,
      Date().timeIntervalSince(captured) > 20 * 60
    {
      return nil
    }
    return summary
  }

  // "⛅️ 61°", rendered in the viewer's units from the structured payload;
  // falls back to the sender-rendered summary for older payloads.
  var weatherLine: String? {
    guard let card = weatherCard else { return nil }
    if let emoji = card.data["emoji"]?.stringValue,
      let temp = card.data[Self.viewerUsesFahrenheit ? "temp_f" : "temp_c"]?.intValue
    {
      return "\(emoji) \(temp)°"
    }
    if let summary = card.summary, !summary.isEmpty { return summary }
    return nil
  }

  // Hover/tooltip detail: "Light rain · Seattle". City only when the friend
  // shares it.
  var weatherDetail: String? {
    guard let card = weatherCard else { return nil }
    var parts: [String] = []
    if let condition = card.data["condition"]?.stringValue, !condition.isEmpty {
      parts.append(condition)
    }
    if let city = card.data["city"]?.stringValue, !city.isEmpty {
      parts.append(city)
    }
    return parts.isEmpty ? nil : parts.joined(separator: " · ")
  }

  private static var viewerUsesFahrenheit: Bool {
    Locale.current.measurementSystem == .us
  }
}

struct FeedResponse: Codable, Equatable {
  var you: MergedStatus
  var friends: [MergedStatus]
}

// Color <-> "#RRGGBB" hex bridging via NSColor (so SwiftUI ColorPicker selections
// round-trip to the server's stored hex). Parsing tolerates a leading "#" and is
// case-insensitive; emission is always 6-digit uppercase with a leading "#",
// matching the server's `^#[0-9a-fA-F]{6}$` validation.
extension Color {
  init?(hex: String) {
    var s = hex.trimmingCharacters(in: .whitespacesAndNewlines)
    if s.hasPrefix("#") { s.removeFirst() }
    guard s.count == 6, let value = UInt64(s, radix: 16) else { return nil }
    let r = Double((value >> 16) & 0xFF) / 255.0
    let g = Double((value >> 8) & 0xFF) / 255.0
    let b = Double(value & 0xFF) / 255.0
    self = Color(.sRGB, red: r, green: g, blue: b, opacity: 1)
  }

  // "#RRGGBB" uppercase. Converts through NSColor's sRGB space so display-P3 or
  // named colors clamp to a representable 8-bit-per-channel value.
  var hexRGB: String {
    let ns = NSColor(self).usingColorSpace(.sRGB) ?? NSColor(self)
    let r = Int((ns.redComponent * 255).rounded())
    let g = Int((ns.greenComponent * 255).rounded())
    let b = Int((ns.blueComponent * 255).rounded())
    let clamp = { (v: Int) in max(0, min(255, v)) }
    return String(format: "#%02X%02X%02X", clamp(r), clamp(g), clamp(b))
  }
}

struct InviteSummary: Codable, Equatable, Identifiable {
  var id: String
  var inviteURL: URL?
  var state: String
  var createdAt: Date
  var expiresAt: Date?
  var acceptedBy: String?

  enum CodingKeys: String, CodingKey {
    case id
    case inviteURL = "invite_url"
    case state
    case createdAt = "created_at"
    case expiresAt = "expires_at"
    case acceptedBy = "accepted_by"
  }
}
