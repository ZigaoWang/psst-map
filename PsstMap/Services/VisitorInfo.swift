import Foundation
import MapKit

/// What Apple Maps knows about visiting a place: its own entry (whose place card shows live opening hours),
/// website, and phone. Looked up on the device when a place page opens; Psst never stores or sends it.
struct VisitorInfo {
    let mapItem: MKMapItem
    let website: URL?
    let phone: String?

    var phoneURL: URL? {
        guard let phone else { return nil }
        let digits = phone.filter { $0.isNumber || $0 == "+" }
        return digits.isEmpty ? nil : URL(string: "tel:\(digits)")
    }
}

/// Finds a place's entry in Apple Maps: a point of interest close to the pin whose name matches one of the
/// place's names. Statues, streets, and anything Apple doesn't list as somewhere to visit get nothing.
@MainActor
final class VisitorInfoLookup {
    static let shared = VisitorInfoLookup()

    /// Kept for this launch only, so reopening a page doesn't ask again.
    private var cache: [String: VisitorInfo?] = [:]

    func info(for place: Place) async -> VisitorInfo? {
        if let cached = cache[place.id] { return cached }
        let found = await lookUp(place)
        if !Task.isCancelled { cache[place.id] = found }
        return found
    }

    private func lookUp(_ place: Place) async -> VisitorInfo? {
        let center = place.mapCoordinate
        let radius: CLLocationDistance = switch place.spot.size {
        case .small: 80
        case .large: 400
        default: 150
        }
        let names = Self.names(of: place)
        var candidates: [MKMapItem] = []

        let nearby = MKLocalPointsOfInterestRequest(center: center, radius: radius)
        if let response = try? await MKLocalSearch(request: nearby).start() {
            candidates += response.mapItems
        }
        if Self.bestMatch(in: candidates, names: names, near: center, within: radius) == nil {
            let search = MKLocalSearch.Request()
            search.naturalLanguageQuery = place.name
            search.region = MKCoordinateRegion(center: center, latitudinalMeters: radius * 4, longitudinalMeters: radius * 4)
            search.resultTypes = .pointOfInterest
            if let response = try? await MKLocalSearch(request: search).start() {
                candidates += response.mapItems
            }
        }
        guard let item = Self.bestMatch(in: candidates, names: names, near: center, within: radius) else { return nil }
        // Without a website or phone there's nothing to visit (a landmark), so the section stays hidden.
        guard item.url != nil || item.phoneNumber?.isEmpty == false else { return nil }
        return VisitorInfo(mapItem: item, website: item.url, phone: item.phoneNumber)
    }

    /// Every name the place goes by, normalized for comparison.
    static func names(of place: Place) -> [String] {
        ([place.name, place.spot.localName].compactMap { $0 } + Array(place.spot.names.values))
            .map(normalize)
            .filter { $0.count >= 2 }
    }

    static func bestMatch(in items: [MKMapItem], names: [String], near center: CLLocationCoordinate2D,
                          within radius: CLLocationDistance) -> MKMapItem? {
        let here = CLLocation(latitude: center.latitude, longitude: center.longitude)
        return items
            .compactMap { item -> (MKMapItem, CLLocationDistance)? in
                guard let name = item.name, matches(normalize(name), names) else { return nil }
                let distance = location(of: item).distance(from: here)
                return distance <= radius ? (item, distance) : nil
            }
            .min { $0.1 < $1.1 }?.0
    }

    /// The same name, or one containing the other as whole words and making up most of it ("Belsize Park"
    /// and "Belsize Park Station", but not "Bank" and "HSBC Bank").
    static func matches(_ candidate: String, _ names: [String]) -> Bool {
        guard !candidate.isEmpty else { return false }
        return names.contains { name in
            if candidate == name { return true }
            // Chinese, Japanese, and Korean names have no spaces between words, so compare characters.
            let cjk = name.unicodeScalars.contains { $0.value >= 0x3000 }
            let (short, long) = name.count < candidate.count ? (name, candidate) : (candidate, name)
            if cjk {
                return long.contains(short) && Double(short.count) / Double(long.count) > 0.5
            }
            let shortWords = short.split(separator: " ").count, longWords = long.split(separator: " ").count
            return " \(long) ".contains(" \(short) ") && Double(shortWords) / Double(longWords) > 0.5
        }
    }

    static func normalize(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        let spaced = String(folded.map { (character: Character) -> Character in
            character.isLetter || character.isNumber ? character : " "
        })
        let words: [String] = spaced.split(separator: " ").map(String.init).filter { $0 != "the" }
        return words.joined(separator: " ")
    }

    private static func location(of item: MKMapItem) -> CLLocation {
        if #available(iOS 26.0, *) {
            return item.location
        }
        let coordinate = item.placemark.coordinate
        return CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
    }
}
