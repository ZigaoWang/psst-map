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
        return VisitorInfo(mapItem: await Self.fullItem(item), website: item.url, phone: item.phoneNumber)
    }

    /// Search results can be partial; Apple's place card shows everything (opening hours included) only for the
    /// item looked up by its identifier.
    private static func fullItem(_ item: MKMapItem) async -> MKMapItem {
        if #available(iOS 18.0, *), let identifier = item.identifier,
           let full = try? await MKMapItemRequest(mapItemIdentifier: identifier).mapItem {
            return full
        }
        return item
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
                guard let name = item.name else { return nil }
                let distance = location(of: item).distance(from: here)
                // A loose match only counts right next to the pin.
                switch match(normalize(name), names) {
                case .strong where distance <= radius: return (item, distance)
                case .loose where distance <= min(radius, 60): return (item, distance)
                default: return nil
                }
            }
            .min { $0.1 < $1.1 }?.0
    }

    enum Match: Comparable { case none, loose, strong }

    /// Strong: the same name, or one containing the other as whole words and making up most of it ("Belsize
    /// Park" and "Belsize Park Station"). Loose: exactly half of it, when that half is a real name ("George
    /// Inn" and "The George"), never a common word ("Bank" and "HSBC Bank").
    static func match(_ candidate: String, _ names: [String]) -> Match {
        guard !candidate.isEmpty else { return .none }
        return names.map { name -> Match in
            if candidate == name { return .strong }
            let (short, long) = name.count < candidate.count ? (name, candidate) : (candidate, name)
            // Chinese, Japanese, and Korean names have no spaces between words, so compare characters.
            if short.unicodeScalars.contains(where: { $0.value >= 0x3000 }) {
                return long.contains(short) && Double(short.count) / Double(long.count) > 0.5 ? .strong : .none
            }
            let shortWords = short.split(separator: " "), longWords = long.split(separator: " ")
            guard " \(long) ".contains(" \(short) ") || shortWords.allSatisfy(longWords.contains) else { return .none }
            let share = Double(shortWords.count) / Double(longWords.count)
            if share > 0.5 { return .strong }
            if share == 0.5 && (shortWords.count >= 2 || short.count >= 5) { return .loose }
            return .none
        }.max() ?? .none
    }

    static func matches(_ candidate: String, _ names: [String]) -> Bool {
        match(candidate, names) != .none
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
