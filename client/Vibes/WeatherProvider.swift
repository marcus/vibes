import Combine
import CoreLocation
import Foundation

// WeatherProvider — the sender side of the weather card.
//
// Resolves a coordinate (Location Services, or a manually configured city
// geocoded through Open-Meteo so no permission prompt is needed), then fetches
// current conditions from Open-Meteo. Keyless and free for non-commercial use;
// chosen over WeatherKit because debug builds carry no entitlements and the
// Developer ID provisioning profile would need regenerating for the WeatherKit
// capability.
//
// Readings are cached for 15 minutes — the publish loop ticks every 3, and
// Open-Meteo's current-conditions model updates on roughly that cadence anyway.

struct WeatherSnapshot: Equatable {
  var condition: String
  var emoji: String
  var tempC: Int
  var tempF: Int
  var city: String?
  var capturedAt: Date

  // "⛅️ 61°" in the sender's units — the fallback summary for clients that
  // don't read the structured fields. Viewers re-render from data when they can.
  var summary: String {
    let temp = Locale.current.measurementSystem == .us ? tempF : tempC
    return "\(emoji) \(temp)°"
  }

  func card(shareCity: Bool) -> StatusCard {
    var data: [String: JSONValue] = [
      "condition": .string(condition),
      "emoji": .string(emoji),
      "temp_c": .int(tempC),
      "temp_f": .int(tempF),
      "captured_at": .string(ISO8601DateFormatter().string(from: capturedAt)),
    ]
    if shareCity, let city, !city.isEmpty {
      data["city"] = .string(city)
    }
    return StatusCard(type: "weather", enabled: true, summary: summary, data: data)
  }
}

final class WeatherProvider: NSObject, ObservableObject {
  private let session: URLSession
  private var cached: WeatherSnapshot?

  // One coordinate per resolution source, cached for the session: a Mac
  // doesn't move much, and re-resolving every tick would re-hit the geocoder
  // (manual city) or Location Services (automatic).
  private var resolvedCoordinate: ResolvedPlace?
  private var resolvedForCity: String?

  private var locationManager: CLLocationManager?
  private var locationContinuation: CheckedContinuation<CLLocation?, Never>?

  // Surfaced in Settings so a denied location prompt or a typo'd city isn't
  // silent — the card just quietly not appearing is undebuggable.
  @Published private(set) var lastProblem: String?

  init(session: URLSession = .shared) {
    self.session = session
  }

  private struct ResolvedPlace {
    var latitude: Double
    var longitude: Double
    var city: String?
  }

  // MARK: - Entry point

  // Returns the current reading, refreshing if the cache is stale or the
  // configured city changed. nil when location can't be resolved or the fetch
  // fails — the card is simply omitted from that publish.
  func snapshot(config: WeatherConfig) async -> WeatherSnapshot? {
    let manualCity = config.manualCity.trimmingCharacters(in: .whitespacesAndNewlines)
    if let cached, Date().timeIntervalSince(cached.capturedAt) < 15 * 60,
      resolvedForCity == manualCity
    {
      return cached
    }

    guard let place = await resolvePlace(manualCity: manualCity) else { return nil }
    guard let reading = await fetchCurrent(place: place) else { return nil }

    lastProblem = nil
    cached = reading
    resolvedForCity = manualCity
    return reading
  }

  func invalidate() {
    cached = nil
    resolvedCoordinate = nil
    resolvedForCity = nil
  }

  // MARK: - Location

  private func resolvePlace(manualCity: String) async -> ResolvedPlace? {
    if let resolvedCoordinate, resolvedForCity == manualCity {
      return resolvedCoordinate
    }
    let place: ResolvedPlace?
    if manualCity.isEmpty {
      place = await currentLocationPlace()
    } else {
      place = await geocode(city: manualCity)
    }
    if let place {
      resolvedCoordinate = place
      resolvedForCity = manualCity
    }
    return place
  }

  private func currentLocationPlace() async -> ResolvedPlace? {
    let manager = locationManager ?? CLLocationManager()
    locationManager = manager
    manager.delegate = self
    manager.desiredAccuracy = kCLLocationAccuracyKilometer

    switch manager.authorizationStatus {
    case .notDetermined:
      manager.requestWhenInUseAuthorization()
      // didChangeAuthorization re-enters location resolution via the pending
      // continuation; simplest is to wait for the callback's requestLocation.
    case .denied, .restricted:
      lastProblem = "Location access is off. Set a city instead, or allow location for Vibes in System Settings → Privacy."
      return nil
    default:
      break
    }

    guard let location = await withCheckedContinuation({ (continuation: CheckedContinuation<CLLocation?, Never>) in
      if locationContinuation != nil {
        continuation.resume(returning: nil)
        return
      }
      locationContinuation = continuation
      if manager.authorizationStatus != .notDetermined {
        manager.requestLocation()
      }
    }) else {
      if lastProblem == nil {
        lastProblem = "Couldn't determine your location. Set a city instead."
      }
      return nil
    }

    let city = await reverseGeocodeCity(location)
    return ResolvedPlace(
      latitude: location.coordinate.latitude,
      longitude: location.coordinate.longitude,
      city: city
    )
  }

  private func reverseGeocodeCity(_ location: CLLocation) async -> String? {
    let placemarks = try? await CLGeocoder().reverseGeocodeLocation(location)
    return placemarks?.first?.locality ?? placemarks?.first?.administrativeArea
  }

  // MARK: - Open-Meteo

  private func geocode(city: String) async -> ResolvedPlace? {
    var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
    components.queryItems = [
      URLQueryItem(name: "name", value: city),
      URLQueryItem(name: "count", value: "1"),
      URLQueryItem(name: "language", value: "en"),
      URLQueryItem(name: "format", value: "json"),
    ]
    struct GeocodeResponse: Decodable {
      struct Place: Decodable {
        var latitude: Double
        var longitude: Double
        var name: String
      }
      var results: [Place]?
    }
    do {
      let (data, _) = try await session.data(from: components.url!)
      guard let place = try JSONDecoder().decode(GeocodeResponse.self, from: data).results?.first
      else {
        lastProblem = "Couldn't find \u{201C}\(city)\u{201D} — check the city name in Settings → Sharing."
        return nil
      }
      return ResolvedPlace(latitude: place.latitude, longitude: place.longitude, city: place.name)
    } catch {
      lastProblem = "Weather lookup failed: \(error.localizedDescription)"
      return nil
    }
  }

  private func fetchCurrent(place: ResolvedPlace) async -> WeatherSnapshot? {
    var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
    components.queryItems = [
      URLQueryItem(name: "latitude", value: String(format: "%.4f", place.latitude)),
      URLQueryItem(name: "longitude", value: String(format: "%.4f", place.longitude)),
      URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
    ]
    struct ForecastResponse: Decodable {
      struct Current: Decodable {
        var temperature_2m: Double
        var weather_code: Int
      }
      var current: Current
    }
    do {
      let (data, _) = try await session.data(from: components.url!)
      let current = try JSONDecoder().decode(ForecastResponse.self, from: data).current
      let (emoji, condition) = Self.describe(wmoCode: current.weather_code)
      let tempC = Int(current.temperature_2m.rounded())
      let tempF = Int((current.temperature_2m * 9 / 5 + 32).rounded())
      return WeatherSnapshot(
        condition: condition,
        emoji: emoji,
        tempC: tempC,
        tempF: tempF,
        city: place.city,
        capturedAt: Date()
      )
    } catch {
      lastProblem = "Weather lookup failed: \(error.localizedDescription)"
      return nil
    }
  }

  // WMO weather interpretation codes, as documented by Open-Meteo.
  static func describe(wmoCode: Int) -> (emoji: String, condition: String) {
    switch wmoCode {
    case 0: ("☀️", "Clear")
    case 1: ("🌤", "Mainly clear")
    case 2: ("⛅️", "Partly cloudy")
    case 3: ("☁️", "Overcast")
    case 45, 48: ("🌫", "Fog")
    case 51, 53, 55: ("🌦", "Drizzle")
    case 56, 57: ("🌧", "Freezing drizzle")
    case 61: ("🌧", "Light rain")
    case 63: ("🌧", "Rain")
    case 65: ("🌧", "Heavy rain")
    case 66, 67: ("🌧", "Freezing rain")
    case 71: ("🌨", "Light snow")
    case 73: ("🌨", "Snow")
    case 75: ("❄️", "Heavy snow")
    case 77: ("🌨", "Snow grains")
    case 80, 81: ("🌦", "Rain showers")
    case 82: ("🌧", "Heavy showers")
    case 85, 86: ("🌨", "Snow showers")
    case 95: ("⛈", "Thunderstorm")
    case 96, 99: ("⛈", "Thunderstorm with hail")
    default: ("🌡", "Weather")
    }
  }
}

extension WeatherProvider: CLLocationManagerDelegate {
  func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    guard locationContinuation != nil else { return }
    switch manager.authorizationStatus {
    case .denied, .restricted:
      lastProblem = "Location access is off. Set a city instead, or allow location for Vibes in System Settings → Privacy."
      locationContinuation?.resume(returning: nil)
      locationContinuation = nil
    case .notDetermined:
      break
    default:
      manager.requestLocation()
    }
  }

  func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
    locationContinuation?.resume(returning: locations.last)
    locationContinuation = nil
  }

  func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
    lastProblem = "Couldn't determine your location: \(error.localizedDescription)"
    locationContinuation?.resume(returning: nil)
    locationContinuation = nil
  }
}
