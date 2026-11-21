import SwiftUI
import MapKit
import CoreLocation

struct PlaceChoice: Identifiable, Hashable {
    let name: String
    let subtitle: String
    let lat: Double?
    let lon: Double?

    var id: String { "\(name)|\(lat ?? 0)|\(lon ?? 0)" }
}

final class LocationHelper: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var coordinate: CLLocationCoordinate2D?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
    }

    func request() {
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default: break
        }
    }

    func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        if m.authorizationStatus == .authorizedWhenInUse || m.authorizationStatus == .authorizedAlways {
            m.requestLocation()
        }
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let l = locations.last else { return }
        DispatchQueue.main.async { self.coordinate = l.coordinate }
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {}
}

enum Places {
    /// Restaurants, cafes and food shops within about 250 m, nearest first.
    static func nearby(lat: Double, lon: Double) async -> [PlaceChoice] {
        let center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
        let req = MKLocalPointsOfInterestRequest(center: center, radius: 250)
        req.pointOfInterestFilter = MKPointOfInterestFilter(including: [.restaurant, .cafe, .bakery, .foodMarket, .brewery, .winery, .nightlife])
        do {
            let resp = try await MKLocalSearch(request: req).start()
            return choices(resp.mapItems, origin: CLLocation(latitude: lat, longitude: lon))
        } catch {
            return []
        }
    }

    static func search(_ query: String, lat: Double?, lon: Double?) async -> [PlaceChoice] {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        req.resultTypes = [.pointOfInterest, .address]
        var origin: CLLocation?
        if let lat, let lon {
            req.region = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                                            latitudinalMeters: 20_000, longitudinalMeters: 20_000)
            origin = CLLocation(latitude: lat, longitude: lon)
        }
        do {
            let resp = try await MKLocalSearch(request: req).start()
            return choices(resp.mapItems, origin: origin)
        } catch {
            return []
        }
    }

    private static func choices(_ items: [MKMapItem], origin: CLLocation?) -> [PlaceChoice] {
        var rows: [(Double, PlaceChoice)] = []
        var seen = Set<String>()
        for item in items {
            let c = item.placemark.coordinate
            let name = item.name ?? "Place"
            guard !seen.contains(name) else { continue }
            seen.insert(name)
            var parts: [String] = []
            var dist = Double.greatestFiniteMagnitude
            if let origin {
                dist = origin.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
                parts.append(Fmt.distance(dist))
            }
            if let street = item.placemark.thoroughfare { parts.append(street) }
            else if let area = item.placemark.locality { parts.append(area) }
            rows.append((dist, PlaceChoice(name: name, subtitle: parts.joined(separator: " · "), lat: c.latitude, lon: c.longitude)))
        }
        return rows.sorted { $0.0 < $1.0 }.map { $0.1 }
    }
}

struct PlacePicker: View {
    let lat: Double?
    let lon: Double?
    var initial: [PlaceChoice] = []
    var onPick: (PlaceChoice) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var nearby: [PlaceChoice] = []
    @State private var results: [PlaceChoice] = []
    @State private var loading = false

    private var trimmed: String { query.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            List {
                if !trimmed.isEmpty {
                    Button { pick(PlaceChoice(name: trimmed, subtitle: "", lat: lat, lon: lon)) } label: {
                        Label("Use “\(trimmed)”", systemImage: "square.and.pencil")
                    }
                }
                Button { pick(PlaceChoice(name: "Home", subtitle: "", lat: nil, lon: nil)) } label: {
                    Label("Home", systemImage: "house")
                }
                Section(trimmed.isEmpty ? "Nearby" : "Results") {
                    if loading { ProgressView() }
                    ForEach(trimmed.isEmpty ? nearby : results) { c in
                        Button { pick(c) } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(c.name).foregroundStyle(.primary)
                                if !c.subtitle.isEmpty {
                                    Text(c.subtitle).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    if !loading && (trimmed.isEmpty ? nearby : results).isEmpty {
                        Text(trimmed.isEmpty ? "No restaurants found nearby. Search for one above." : "No matches.")
                            .font(.subheadline).foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search restaurants")
            .navigationTitle("Where did you eat?")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
            .task {
                nearby = initial
                if initial.isEmpty, let lat, let lon {
                    loading = true
                    nearby = await Places.nearby(lat: lat, lon: lon)
                    loading = false
                }
            }
            .task(id: trimmed) {
                guard !trimmed.isEmpty else { results = []; return }
                try? await Task.sleep(nanoseconds: 350_000_000)
                if Task.isCancelled { return }
                loading = true
                let r = await Places.search(trimmed, lat: lat, lon: lon)
                if !Task.isCancelled { results = r }
                loading = false
            }
        }
    }

    private func pick(_ c: PlaceChoice) {
        onPick(c)
        dismiss()
    }
}
