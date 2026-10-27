import CoreLocation
import SwiftUI

// Weather from Open-Meteo (open-meteo.com): free, no account or API key.
// Apple's WeatherKit needs a paid developer account, so it's not an option for a sideloaded app.

struct WeatherPlace: Codable, Hashable {
    var name: String
    var latitude: Double
    var longitude: Double
}

struct WeatherReport {
    struct Hour: Identifiable {
        let time: Date
        let temperature: Double
        let code: Int
        let isDay: Bool
        let rainChance: Int
        var id: Date { time }
    }

    let temperature: Double
    let feelsLike: Double
    let high: Double
    let low: Double
    let code: Int
    let isDay: Bool
    let humidity: Int
    let wind: Double
    let hours: [Hour]
    let airQuality: Int?     // European AQI
    let timeZone: TimeZone
    let updated: Date
}

/// WMO weather code -> SF Symbol.
func weatherSymbol(_ code: Int, isDay: Bool) -> String {
    switch code {
    case 0: isDay ? "sun.max.fill" : "moon.stars.fill"
    case 1, 2: isDay ? "cloud.sun.fill" : "cloud.moon.fill"
    case 3: "cloud.fill"
    case 45, 48: "cloud.fog.fill"
    case 51...57: "cloud.drizzle.fill"
    case 65, 82: "cloud.heavyrain.fill"
    case 61...67, 80...82: "cloud.rain.fill"
    case 71...77, 85, 86: "cloud.snow.fill"
    case 95...99: "cloud.bolt.rain.fill"
    default: "cloud.fill"
    }
}

/// WMO weather code -> (short name, one-line description).
func weatherWords(_ code: Int) -> (short: String, line: String) {
    switch code {
    case 0: ("Clear", "Clear skies all round")
    case 1, 2: ("Partly cloudy", "Sun with a few clouds")
    case 3: ("Cloudy", "Grey and overcast")
    case 45, 48: ("Fog", "Foggy, take it slow")
    case 51...57: ("Drizzle", "Light drizzle about")
    case 61...67, 80...82: ("Rain", "Rainy, grab a coat")
    case 71...77, 85, 86: ("Snow", "Snow is falling")
    case 95...99: ("Thunderstorm", "Thunderstorms nearby")
    default: ("Cloudy", "Grey and overcast")
    }
}

let usesFahrenheit = Locale.current.measurementSystem == .us
let usesMph = Locale.current.measurementSystem != .metric   // US and UK

@MainActor
final class WeatherModel: ObservableObject {
    @Published var place: WeatherPlace? {
        didSet {
            UserDefaults.standard.set(try? JSONEncoder().encode(place), forKey: "weatherPlace")
            report = nil
            Task { await refresh() }
        }
    }
    @Published private(set) var report: WeatherReport?
    @Published private(set) var failed = false
    private let locator = LocationFetcher()

    init() {
        whenDataReadable { [weak self] in
            if let data = UserDefaults.standard.data(forKey: "weatherPlace") {
                self?.place = try? JSONDecoder().decode(WeatherPlace.self, from: data)
            }
        }
    }

    func refresh() async {
        guard let place else { return }
        var url = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        url.queryItems = coordinates(place) + [
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,weather_code,is_day,relative_humidity_2m,wind_speed_10m"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day,precipitation_probability"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "2"),
            URLQueryItem(name: "forecast_hours", value: "12"),   // starts at the current hour
            URLQueryItem(name: "timezone", value: "auto"),
            URLQueryItem(name: "temperature_unit", value: usesFahrenheit ? "fahrenheit" : "celsius"),
            URLQueryItem(name: "wind_speed_unit", value: usesMph ? "mph" : "kmh"),
        ]
        var aqiURL = URLComponents(string: "https://air-quality-api.open-meteo.com/v1/air-quality")!
        aqiURL.queryItems = coordinates(place) + [URLQueryItem(name: "current", value: "european_aqi")]
        let aqiRequest = aqiURL.url!
        do {
            async let aqiData = try? URLSession.shared.data(from: aqiRequest)
            let (data, _) = try await URLSession.shared.data(from: url.url!)
            let f = try JSONDecoder().decode(Forecast.self, from: data)
            let aqi = (await aqiData).flatMap { try? JSONDecoder().decode(AirQuality.self, from: $0.0) }

            let tz = TimeZone(secondsFromGMT: f.utcOffsetSeconds) ?? .current
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.timeZone = tz
            parser.dateFormat = "yyyy-MM-dd'T'HH:mm"
            let h = f.hourly
            let hours = h.time.indices.compactMap { i -> WeatherReport.Hour? in
                guard let time = parser.date(from: h.time[i]) else { return nil }
                return .init(time: time, temperature: h.temperature[i], code: h.weatherCode[i],
                             isDay: h.isDay[i] == 1, rainChance: h.rainChance[i] ?? 0)
            }
            report = WeatherReport(temperature: f.current.temperature, feelsLike: f.current.feelsLike,
                                   high: f.daily.high.first ?? f.current.temperature,
                                   low: f.daily.low.first ?? f.current.temperature,
                                   code: f.current.weatherCode, isDay: f.current.isDay == 1,
                                   humidity: f.current.humidity, wind: f.current.wind, hours: hours,
                                   airQuality: aqi?.current.europeanAqi, timeZone: tz, updated: Date())
            failed = false
        } catch {
            failed = true
        }
    }

    /// Asks iOS for the location (shows the permission prompt the first time). False if denied or it fails.
    // ponytail: location is captured once; tap "Use my current location" again after moving town.
    func useCurrentLocation() async -> Bool {
        guard let location = await locator.current() else { return false }
        let mark = try? await CLGeocoder().reverseGeocodeLocation(location).first
        place = WeatherPlace(name: mark?.locality ?? mark?.name ?? "Current location",
                             latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
        return true
    }

    static func search(_ query: String) async -> [WeatherPlace] {
        guard query.trimmingCharacters(in: .whitespaces).count >= 2 else { return [] }
        var url = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        url.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "10"),
            URLQueryItem(name: "language", value: "en"),
        ]
        guard let response = try? await URLSession.shared.data(from: url.url!),
              let r = try? JSONDecoder().decode(Geocoding.self, from: response.0) else { return [] }
        return (r.results ?? []).map { hit in
            let area = [hit.admin1, hit.country].compactMap { $0 }.joined(separator: ", ")
            return WeatherPlace(name: area.isEmpty ? hit.name : "\(hit.name), \(area)",
                                latitude: hit.latitude, longitude: hit.longitude)
        }
    }

    private func coordinates(_ place: WeatherPlace) -> [URLQueryItem] {
        [URLQueryItem(name: "latitude", value: "\(place.latitude)"),
         URLQueryItem(name: "longitude", value: "\(place.longitude)")]
    }

    // Explicit keys: .convertFromSnakeCase turns "temperature_2m" into "temperature2M", which never matches.
    private struct Forecast: Decodable {
        struct Current: Decodable {
            let temperature: Double, feelsLike: Double, weatherCode: Int, isDay: Int, humidity: Int, wind: Double
            enum CodingKeys: String, CodingKey {
                case temperature = "temperature_2m", feelsLike = "apparent_temperature", weatherCode = "weather_code"
                case isDay = "is_day", humidity = "relative_humidity_2m", wind = "wind_speed_10m"
            }
        }
        struct Hourly: Decodable {
            let time: [String], temperature: [Double], weatherCode: [Int], isDay: [Int], rainChance: [Int?]
            enum CodingKeys: String, CodingKey {
                case time, temperature = "temperature_2m", weatherCode = "weather_code", isDay = "is_day"
                case rainChance = "precipitation_probability"
            }
        }
        struct Daily: Decodable {
            let high: [Double], low: [Double]
            enum CodingKeys: String, CodingKey { case high = "temperature_2m_max", low = "temperature_2m_min" }
        }
        let utcOffsetSeconds: Int
        let current: Current
        let hourly: Hourly
        let daily: Daily
        enum CodingKeys: String, CodingKey { case utcOffsetSeconds = "utc_offset_seconds", current, hourly, daily }
    }

    private struct AirQuality: Decodable {
        struct Current: Decodable {
            let europeanAqi: Int?
            enum CodingKeys: String, CodingKey { case europeanAqi = "european_aqi" }
        }
        let current: Current
    }

    private struct Geocoding: Decodable {
        struct Hit: Decodable {
            let name: String
            let latitude: Double
            let longitude: Double
            let country: String?
            let admin1: String?
        }
        let results: [Hit]?
    }
}

/// One-shot location fix, asking permission first if needed.
@MainActor
final class LocationFetcher: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var waiting: CheckedContinuation<CLLocation?, Never>?

    func current() async -> CLLocation? {
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        return await withCheckedContinuation { continuation in
            waiting = continuation
            switch manager.authorizationStatus {
            case .notDetermined: manager.requestWhenInUseAuthorization()   // answer arrives below
            case .denied, .restricted: finish(nil)
            default: manager.requestLocation()
            }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard waiting != nil else { return }
            switch status {
            case .authorizedWhenInUse, .authorizedAlways: self.manager.requestLocation()
            case .denied, .restricted: finish(nil)
            default: break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        let location = locations.last
        Task { @MainActor in finish(location) }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in finish(nil) }
    }

    private func finish(_ location: CLLocation?) {
        waiting?.resume(returning: location)
        waiting = nil
    }
}

// MARK: - Views

private func hourLabel(_ date: Date, _ tz: TimeZone) -> String {
    var style = Date.FormatStyle.dateTime.hour()
    style.timeZone = tz
    return date.formatted(style)
}

private func degrees(_ value: Double) -> String { "\(Int(value.rounded()))°" }

private func skyGradient(isDay: Bool) -> LinearGradient {
    isDay
        ? LinearGradient(colors: [Color(red: 0.13, green: 0.36, blue: 0.80), Color(red: 0.38, green: 0.62, blue: 0.93)],
                         startPoint: .top, endPoint: .bottom)
        : LinearGradient(colors: [Color(red: 0.04, green: 0.06, blue: 0.20), Color(red: 0.16, green: 0.21, blue: 0.45)],
                         startPoint: .top, endPoint: .bottom)
}

/// Top of the alarm list: place, temperature, today's range and the next 12 hours.
struct WeatherHeader: View {
    @ObservedObject var weather: WeatherModel
    let openDetail: () -> Void
    let pickPlace: () -> Void

    var body: some View {
        if let place = weather.place, let r = weather.report {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Button(action: openDetail) {
                            HStack(spacing: 4) {
                                Text(place.name.components(separatedBy: ",").first ?? place.name)
                                    .font(.title3.weight(.semibold))
                                Image(systemName: "chevron.right").font(.subheadline.weight(.bold))
                            }
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.white)
                        Text(degrees(r.temperature))
                            .font(.system(size: 64, weight: .light, design: .rounded))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(weatherWords(r.code).short).font(.headline)
                            Image(systemName: weatherSymbol(r.code, isDay: r.isDay)).symbolRenderingMode(.multicolor)
                        }
                        Text("high \(degrees(r.high)) | low \(degrees(r.low))").font(.subheadline.weight(.semibold))
                    }
                    .padding(.top, 36)
                }
                HourlyRow(report: r, showRain: false)
            }
            .foregroundStyle(.white)
            .padding(.vertical, 8)
            .listRowBackground(skyGradient(isDay: r.isDay))
        } else if weather.place != nil {
            Text(weather.failed ? "Weather unavailable. Pull down to retry." : "Loading weather…")
                .foregroundStyle(.secondary)
        } else {
            Button(action: pickPlace) {
                Label("Add your location to see the weather", systemImage: "location.circle")
            }
        }
    }
}

struct HourlyRow: View {
    let report: WeatherReport
    let showRain: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 22) {
                ForEach(Array(report.hours.enumerated()), id: \.element.id) { index, hour in
                    VStack(spacing: 8) {
                        Text(index == 0 ? "Now" : hourLabel(hour.time, report.timeZone))
                            .font(.caption.weight(.medium))
                            .opacity(0.75)
                        Image(systemName: weatherSymbol(hour.code, isDay: hour.isDay))
                            .symbolRenderingMode(.multicolor)
                            .font(.title3)
                            .frame(height: 28)
                        Text(degrees(hour.temperature)).font(.subheadline.weight(.medium))
                        if showRain {
                            Label("\(hour.rainChance)%", systemImage: "drop.fill")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }
}

struct WeatherDetailView: View {
    @ObservedObject var weather: WeatherModel
    @State private var picking = false

    var body: some View {
        ScrollView {
            if let place = weather.place, let r = weather.report {
                VStack(spacing: 24) {
                    VStack(spacing: 4) {
                        Text(place.name.components(separatedBy: ",").first ?? place.name).font(.title2.bold())
                        Text(subtitle(r)).font(.subheadline).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))

                    VStack(spacing: 10) {
                        Text(weatherWords(r.code).line).font(.title3.bold())
                        HStack(spacing: 14) {
                            Image(systemName: weatherSymbol(r.code, isDay: r.isDay))
                                .symbolRenderingMode(.multicolor)
                                .font(.system(size: 56))
                            Text(degrees(r.temperature)).font(.system(size: 64, weight: .light, design: .rounded))
                        }
                        Text("Feels like \(degrees(r.feelsLike))").foregroundStyle(.secondary)
                    }

                    if let aqi = r.airQuality {
                        HStack(spacing: 12) {
                            Text("Air quality").font(.headline)
                            Gauge(value: Double(min(aqi, 100)), in: 0...100) {
                                EmptyView()
                            } currentValueLabel: {
                                Text("\(aqi)")
                            }
                            .gaugeStyle(.accessoryCircular)
                            .tint(Gradient(colors: [.green, .yellow, .orange, .red, .purple]))
                            Text(airQualityWord(aqi).0).font(.headline).foregroundStyle(airQualityWord(aqi).1)
                        }
                    }

                    HStack(spacing: 8) {
                        tile("High", degrees(r.high))
                        tile("Low", degrees(r.low))
                        tile("Wind", "\(Int(r.wind.rounded())) \(usesMph ? "mph" : "km/h")")
                        tile("Humidity", "\(r.humidity)%")
                    }

                    Divider()

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Hourly weather").font(.title3.bold())
                        HourlyRow(report: r, showRain: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Weather data by Open-Meteo.com").font(.caption2).foregroundStyle(.tertiary)
                }
                .padding()
            } else {
                Text(weather.failed ? "Weather unavailable" : "Loading weather…")
                    .foregroundStyle(.secondary)
                    .padding(.top, 80)
            }
        }
        .refreshable { await weather.refresh() }
        .navigationTitle("Weather")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { picking = true } label: { Image(systemName: "slider.horizontal.3") }
            }
        }
        .sheet(isPresented: $picking) { PlacePicker(weather: weather) }
    }

    private func subtitle(_ r: WeatherReport) -> String {
        var style = Date.FormatStyle.dateTime.weekday(.wide).day().month(.wide).hour()
        style.timeZone = r.timeZone
        return "\(r.updated.formatted(style)) | \(usesFahrenheit ? "°F" : "°C")"
    }

    private func tile(_ title: String, _ value: String) -> some View {
        VStack(spacing: 8) {
            Text(title).font(.caption.bold())
            Text(value).font(.subheadline).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
    }

    /// European AQI bands.
    private func airQualityWord(_ aqi: Int) -> (String, Color) {
        switch aqi {
        case ..<20: ("Good", .green)
        case ..<40: ("Fair", .mint)
        case ..<60: ("Moderate", .yellow)
        case ..<80: ("Poor", .orange)
        case ..<100: ("Very poor", .red)
        default: ("Extremely poor", .purple)
        }
    }
}

struct PlacePicker: View {
    @ObservedObject var weather: WeatherModel
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [WeatherPlace] = []
    @State private var locating = false
    @State private var locationFailed = false

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        locating = true
                        Task {
                            let ok = await weather.useCurrentLocation()
                            locating = false
                            if ok { dismiss() } else { locationFailed = true }
                        }
                    } label: {
                        HStack {
                            Label("Use my current location", systemImage: "location.fill")
                            if locating { Spacer(); ProgressView() }
                        }
                    }
                    .disabled(locating)
                } footer: {
                    if locationFailed {
                        Text("Couldn't get your location. If you said no, allow it in iPhone Settings → Rise → Location, or search for your town below.")
                    }
                }
                Section {
                    ForEach(results, id: \.self) { place in
                        Button(place.name) {
                            weather.place = place
                            dismiss()
                        }
                    }
                } footer: {
                    Text("Weather data by Open-Meteo.com")
                }
                if weather.place != nil {
                    Section {
                        Button("Remove location", role: .destructive) {
                            weather.place = nil
                            dismiss()
                        }
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search for a town or city")
            .task(id: query) {
                try? await Task.sleep(for: .milliseconds(350))   // wait for typing to pause
                guard !Task.isCancelled else { return }
                results = await WeatherModel.search(query)
            }
            .navigationTitle("Weather location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
