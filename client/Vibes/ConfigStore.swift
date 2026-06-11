import Foundation
import Security
import UniformTypeIdentifiers

struct ConfigStore {
  let configURL: URL

  init() {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    configURL = base.appendingPathComponent("Vibes", isDirectory: true).appendingPathComponent("config.json")
  }

  func load() throws -> VibesConfig? {
    guard FileManager.default.fileExists(atPath: configURL.path) else { return nil }
    let data = try Data(contentsOf: configURL)
    return try JSONCoding.decoder.decode(VibesConfig.self, from: data)
  }

  func save(_ config: VibesConfig) throws {
    try FileManager.default.createDirectory(
      at: configURL.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    let data = try JSONCoding.encoder.encode(config)
    try data.write(to: configURL, options: [.atomic])
  }

  func importConfig(from url: URL) throws -> ImportedConfig {
    let data = try Data(contentsOf: url)
    let imported = try JSONCoding.decoder.decode(ImportedConfig.self, from: data)
    var config = imported.config
    if config.device.id.isEmpty {
      config.device.id = UUID().uuidString.lowercased()
    }
    if config.device.label.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      config.device.label = Host.current().localizedName ?? "Mac"
    }
    return ImportedConfig(config: config, token: imported.token)
  }
}

struct ImportedConfig: Codable {
  var config: VibesConfig
  var token: String?

  init(config: VibesConfig, token: String?) {
    self.config = config
    self.token = token
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: DynamicKey.self)
    token = try container.decodeIfPresent(String.self, forKey: DynamicKey("token"))
    if let nested = try container.decodeIfPresent(VibesConfig.self, forKey: DynamicKey("config")) {
      config = nested
      return
    }

    let identity = try container.decode(IdentityConfig.self, forKey: DynamicKey("identity"))
    var device = try container.decodeIfPresent(DeviceConfig.self, forKey: DynamicKey("device"))
      ?? DeviceConfig(id: UUID().uuidString.lowercased(), label: Host.current().localizedName ?? "Mac")
    if device.id.isEmpty {
      device.id = UUID().uuidString.lowercased()
    }
    let server = try container.decode(ServerConfig.self, forKey: DynamicKey("server"))
    let repos = try container.decodeIfPresent([RepoConfig].self, forKey: DynamicKey("repos")) ?? []
    let sharing = try container.decodeIfPresent(SharingConfig.self, forKey: DynamicKey("sharing")) ?? .defaults
    let presence = try container.decodeIfPresent(PresenceConfig.self, forKey: DynamicKey("presence")) ?? .defaults
    config = VibesConfig(
      identity: identity,
      device: device,
      server: server,
      repos: repos,
      sharing: sharing,
      presence: presence
    )
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: DynamicKey.self)
    try container.encode(config, forKey: DynamicKey("config"))
    try container.encodeIfPresent(token, forKey: DynamicKey("token"))
  }
}

struct DynamicKey: CodingKey {
  var stringValue: String
  var intValue: Int?

  init(_ stringValue: String) {
    self.stringValue = stringValue
  }

  init?(stringValue: String) {
    self.stringValue = stringValue
  }

  init?(intValue: Int) {
    self.stringValue = "\(intValue)"
    self.intValue = intValue
  }
}

enum JSONCoding {
  static let encoder: JSONEncoder = {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    encoder.dateEncodingStrategy = .iso8601
    return encoder
  }()

  static let decoder: JSONDecoder = {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let value = try container.decode(String.self)
      if let date = DateFormatters.isoWithFractional.date(from: value)
        ?? DateFormatters.iso.date(from: value) {
        return date
      }
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Invalid ISO date: \(value)"
      )
    }
    return decoder
  }()
}

enum DateFormatters {
  static let isoWithFractional: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter
  }()

  static let iso: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter
  }()
}

// Where the relay token lives. Release builds use the Keychain exclusively.
// Debug builds prefer a plaintext copy next to config.json ("token.dev",
// chmod 600): every rebuilt dev binary carries a fresh code signature, so a
// Keychain read would otherwise prompt for the login password on each
// iteration. The dev file is seeded from the Keychain once (one last prompt),
// then read thereafter; registration in a Debug build writes the file only.
// Delete token.dev to fall back to the Keychain.
struct TokenStore {
  private let keychain = KeychainStore()

  func readToken() throws -> String? {
    #if DEBUG
      if let token = readDevToken() { return token }
      let token = try keychain.readToken()
      if let token { writeDevToken(token) }
      return token
    #else
      return try keychain.readToken()
    #endif
  }

  func saveToken(_ token: String) throws {
    #if DEBUG
      writeDevToken(token)
    #else
      try keychain.saveToken(token)
    #endif
  }

  #if DEBUG
    private var devTokenURL: URL {
      let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
      return base
        .appendingPathComponent("Vibes", isDirectory: true)
        .appendingPathComponent("token.dev")
    }

    private func readDevToken() -> String? {
      guard let data = try? Data(contentsOf: devTokenURL) else { return nil }
      let token = String(decoding: data, as: UTF8.self)
        .trimmingCharacters(in: .whitespacesAndNewlines)
      return token.isEmpty ? nil : token
    }

    private func writeDevToken(_ token: String) {
      let url = devTokenURL
      try? FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try? Data(token.utf8).write(to: url, options: [.atomic])
      try? FileManager.default.setAttributes(
        [.posixPermissions: 0o600],
        ofItemAtPath: url.path
      )
    }
  #endif
}

// Account hand-off between the user's Macs via iCloud Keychain: one
// synchronizable item holding the relay URL, identity, and a bearer token that
// every signed-in Mac keeps fresh on launch. A brand-new Mac on the same Apple
// ID reads it to offer one-click "continue as @handle" — it uses the synced
// token once to mint its own per-device token (POST /api/tokens) and never
// stores the synced token as its working credential.
//
// Everything here is best-effort by contract: iCloud Keychain may be off, and
// unsigned dev builds may not be able to access synchronizable items at all.
// Callers treat nil/false as "no synced account" and fall back to manual setup.
struct SyncedAccount: Codable, Equatable {
  var relayURL: URL
  var handle: String
  var displayName: String
  var token: String

  enum CodingKeys: String, CodingKey {
    case relayURL = "relay_url"
    case handle
    case displayName = "display_name"
    case token
  }
}

struct SyncedAccountStore {
  private let service = "com.marcusvorwaller.vibes.account"
  private let account = "default"

  func read() -> SyncedAccount? {
    var query = baseQuery()
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecReturnData as String] = true
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess, let data = item as? Data else {
      logFailure("read", status)
      return nil
    }
    return try? JSONCoding.decoder.decode(SyncedAccount.self, from: data)
  }

  func save(_ syncedAccount: SyncedAccount) {
    guard let data = try? JSONCoding.encoder.encode(syncedAccount) else { return }
    var query = baseQuery()
    if SecItemCopyMatching(query as CFDictionary, nil) == errSecSuccess {
      let status = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
      logFailure("update", status)
    } else {
      query[kSecValueData as String] = data
      let status = SecItemAdd(query as CFDictionary, nil)
      logFailure("add", status)
    }
  }

  func delete() {
    logFailure("delete", SecItemDelete(baseQuery() as CFDictionary))
  }

  // Best-effort is the contract, but a dev should still be able to see the
  // OSStatus when the synchronizable keychain says no (e.g. -34018
  // errSecMissingEntitlement on builds without keychain entitlements).
  private func logFailure(_ operation: String, _ status: OSStatus) {
    #if DEBUG
      guard status != errSecSuccess && status != errSecItemNotFound else { return }
      let message = SecCopyErrorMessageString(status, nil) as String? ?? "error \(status)"
      print("SyncedAccountStore \(operation) failed: \(message) (\(status))")
    #endif
  }

  private func baseQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account,
      // The whole point of this item: ride iCloud Keychain to the user's
      // other Macs. Matching must specify it too or reads miss the item.
      kSecAttrSynchronizable as String: true
    ]
  }
}

struct KeychainStore {
  private let service = "com.marcusvorwaller.vibes.relay-token"
  private let account = "default"

  func readToken() throws -> String? {
    var query = baseQuery()
    query[kSecMatchLimit as String] = kSecMatchLimitOne
    query[kSecReturnData as String] = true
    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    if status == errSecItemNotFound { return nil }
    guard status == errSecSuccess else { throw KeychainError(status: status) }
    guard let data = item as? Data else { return nil }
    return String(data: data, encoding: .utf8)
  }

  func saveToken(_ token: String) throws {
    let data = Data(token.utf8)
    var query = baseQuery()
    let status = SecItemCopyMatching(query as CFDictionary, nil)
    if status == errSecSuccess {
      let update = [kSecValueData as String: data]
      let updateStatus = SecItemUpdate(query as CFDictionary, update as CFDictionary)
      guard updateStatus == errSecSuccess else { throw KeychainError(status: updateStatus) }
    } else if status == errSecItemNotFound {
      query[kSecValueData as String] = data
      let addStatus = SecItemAdd(query as CFDictionary, nil)
      guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
    } else {
      throw KeychainError(status: status)
    }
  }

  func deleteToken() throws {
    let status = SecItemDelete(baseQuery() as CFDictionary)
    if status != errSecSuccess && status != errSecItemNotFound {
      throw KeychainError(status: status)
    }
  }

  private func baseQuery() -> [String: Any] {
    [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: account
    ]
  }
}

struct KeychainError: LocalizedError {
  var status: OSStatus
  var errorDescription: String? {
    SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)."
  }
}
