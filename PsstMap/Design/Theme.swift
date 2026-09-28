import SwiftUI
import UIKit

/// Color in Psst always means something: a pin's color says what kind of place it is, and a fact's
/// badge says whether it is a legend or disputed. Everything else stays neutral.
enum Theme {
    static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(UIColor { traits in
            UIColor(hex: traits.userInterfaceStyle == .dark ? dark : light)
        })
    }

    /// Warm off-white paper and deep ink, used for brand moments (welcome, empty states).
    static let ink = Color(UIColor(hex: 0x10182B))
    static let paper = Color(UIColor(hex: 0xF6F3EC))

    static let legend = dynamic(light: 0x6B3FA0, dark: 0xB794E6)
    static let disputed = dynamic(light: 0xA14A00, dark: 0xF0A04B)

    static let cardBackground = Color(uiColor: .secondarySystemGroupedBackground)
    static let screenBackground = Color(uiColor: .systemGroupedBackground)
}

extension UIColor {
    convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(red: CGFloat((hex >> 16) & 0xFF) / 255,
                  green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255,
                  alpha: alpha)
    }
}

extension Spot.Kind {
    /// Pin and chip color. Each passes 3:1 against its glyph color.
    var uiColor: UIColor {
        switch self {
        case .transit: UIColor(hex: 0xD3221B)
        case .crossing: UIColor(hex: 0x0067B1)
        case .street: UIColor(hex: 0xF2A900)
        case .building: UIColor(hex: 0x1F3A93)
        case .worship: UIColor(hex: 0x7A1F5C)
        case .memorial: UIColor(hex: 0x74613F)
        case .green: UIColor(hex: 0x00783A)
        case .water: UIColor(hex: 0x00838C)
        case .culture: UIColor(hex: 0xC4005F)
        }
    }

    var color: Color { Color(uiColor: uiColor) }

    /// Glyph color on top of `color`.
    var onColor: Color { self == .street ? Color(UIColor(hex: 0x1A1A1A)) : .white }
    var onUIColor: UIColor { self == .street ? UIColor(hex: 0x1A1A1A) : .white }

    var symbol: String {
        switch self {
        case .transit: "tram.fill"
        case .crossing: "arrow.left.and.right"
        case .street: "signpost.right.fill"
        case .building: "building.2.fill"
        case .worship: "bell.fill"
        case .memorial: "figure.stand"
        case .green: "tree.fill"
        case .water: "drop.fill"
        case .culture: "theatermasks.fill"
        }
    }

    var label: String {
        switch self {
        case .transit: String(localized: "Transport")
        case .crossing: String(localized: "Bridge or tunnel")
        case .street: String(localized: "Street")
        case .building: String(localized: "Building")
        case .worship: String(localized: "Place of worship")
        case .memorial: String(localized: "Monument")
        case .green: String(localized: "Park or garden")
        case .water: String(localized: "Water")
        case .culture: String(localized: "Culture")
        }
    }

    var keyDescription: String {
        switch self {
        case .transit: String(localized: "Stations, stops, and piers")
        case .crossing: String(localized: "Bridges, tunnels, and subways")
        case .street: String(localized: "Streets, alleys, corners, and roundabouts")
        case .building: String(localized: "Offices, homes, hotels, shops, and pubs")
        case .worship: String(localized: "Churches, temples, and mosques")
        case .memorial: String(localized: "Statues, plaques, and markers")
        case .green: String(localized: "Parks, gardens, and squares")
        case .water: String(localized: "Docks, rivers, canals, and fountains")
        case .culture: String(localized: "Museums, theaters, and markets")
        }
    }
}

extension Fact.Category {
    var label: String {
        switch self {
        case .name: String(localized: "Name")
        case .hidden: String(localized: "Hidden detail")
        case .history: String(localized: "History")
        case .design: String(localized: "Design")
        case .engineering: String(localized: "Engineering")
        case .people: String(localized: "People")
        case .quirk: String(localized: "Quirk")
        }
    }
}

extension Fact.Status {
    var label: String {
        switch self {
        case .fact: String(localized: "Fact")
        case .legend: String(localized: "Legend")
        case .disputed: String(localized: "Disputed")
        }
    }

    var explanation: String {
        switch self {
        case .fact: String(localized: "Backed by reliable sources.")
        case .legend: String(localized: "A story people tell. It isn't proven, or it's known to be untrue.")
        case .disputed: String(localized: "Reliable sources disagree about this.")
        }
    }

    var symbol: String {
        switch self {
        case .fact: "checkmark.seal.fill"
        case .legend: "book.closed.fill"
        case .disputed: "questionmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .fact: .secondary
        case .legend: Theme.legend
        case .disputed: Theme.disputed
        }
    }
}
