import MapKit
import SwiftUI

extension Guide.KeyFact {
    /// The label in the interface language, chosen by the Wikidata property. Unknown properties keep the
    /// English label from the content.
    nonisolated var localizedLabel: String {
        switch property {
        case "P170": String(localized: "Creator")
        case "P84": String(localized: "Architect")
        case "P631": String(localized: "Structural engineer")
        case "P193": String(localized: "Builder")
        case "P88": String(localized: "Commissioned by")
        case "P571":
            switch label {
            case "Made": String(localized: "Made", comment: "When a statue or monument was made")
            case "Founded": String(localized: "Founded")
            case "Established": String(localized: "Established")
            default: String(localized: "Built")
            }
        case "P1619": String(localized: "Opened")
        case "P149": String(localized: "Style")
        case "P186": String(localized: "Material")
        case "P2048": String(localized: "Height")
        case "P2043": String(localized: "Length")
        case "P2046": String(localized: "Area", comment: "The size of a place, in square meters or hectares")
        case "P2044": String(localized: "Elevation")
        case "P1101": String(localized: "Floors")
        case "P1083": String(localized: "Capacity")
        case "P547": String(localized: "Commemorates")
        case "P825": String(localized: "Dedicated to")
        case "P138": String(localized: "Named after")
        case "P140": String(localized: "Religion")
        case "P137": String(localized: "Operator")
        case "P1435": String(localized: "Heritage status")
        default: label
        }
    }
}

/// "About": what the place is, in two or three plain sentences, and its key facts as an info box. Kept
/// apart from the stories, which come after it.
struct AboutSection: View {
    let guide: Guide

    @State private var translated: StoryTranslation.Text?
    @State private var showsTranslation = false
    @State private var canTranslate = false
    @State private var translationRequest = 0

    /// The About goes through the same on-device translation as stories, as a story with no headline.
    private var asStory: Fact {
        Fact(id: guide.id, category: .other, status: .fact, headline: guide.identifier, short: guide.about,
             long: guide.about, sources: guide.sources)
    }

    private var language: Locale.Language {
        showsTranslation && translated != nil
            ? (StoryTranslation.targetLanguage ?? Locale.Language(identifier: "en"))
            : Locale.Language(identifier: "en")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 0) {
                Text("About")
                if showsTranslation, translated != nil {
                    Text(" · \(String(localized: "Translated from English"))")
                        .foregroundStyle(.secondary)
                        .font(.footnote.weight(.semibold))
                }
            }
            .font(.title3.weight(.bold))
            .accessibilityAddTraits(.isHeader)

            Text.story(showsTranslation ? (translated?.short ?? guide.about) : guide.about, language: language)
                .font(.body)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            if !guide.keyFacts.isEmpty {
                KeyFactsBox(guide: guide)
                    .padding(.top, 4)
            }

            HStack(spacing: 18) {
                if !guide.sources.isEmpty {
                    SourcesMenu(sources: guide.sources)
                }
                if canTranslate {
                    Button {
                        translationRequest += 1
                    } label: {
                        Label(showsTranslation ? String(localized: "Show original") : String(localized: "Translate"),
                              systemImage: "translate")
                    }
                }
                Spacer(minLength: 0)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.secondary)
            .buttonStyle(.plain)
        }
        .animation(.snappy, value: showsTranslation)
        .modifier(StoryTranslator(fact: asStory, translated: $translated, showsTranslation: $showsTranslation,
                                  isAvailable: $canTranslate, request: $translationRequest))
    }
}

/// The key facts, label beside value, like an encyclopedia's info box.
struct KeyFactsBox: View {
    let guide: Guide

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(guide.keyFacts.enumerated()), id: \.offset) { index, fact in
                if index > 0 { Divider() }
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        label(fact)
                            .frame(width: 120, alignment: .leading)
                        value(fact)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        label(fact)
                        value(fact)
                    }
                }
                .padding(.vertical, 9)
                .accessibilityElement(children: .combine)
            }
            if let url = guide.wikidataURL {
                Divider()
                Link(destination: url) {
                    Text("Key facts from Wikidata")
                        .underline()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, 9)
            }
        }
        .padding(.horizontal, 14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
    }

    private func label(_ fact: Guide.KeyFact) -> some View {
        Text(fact.localizedLabel)
            .font(.subheadline)
            .foregroundStyle(.secondary)
    }

    private func value(_ fact: Guide.KeyFact) -> some View {
        Text.story(fact.value)
            .font(.subheadline.weight(.medium))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }
}

/// Opening hours, website, and phone from Apple Maps, looked up when the page opens (`VisitorInfoLookup`) and
/// never stored by Psst. Shown only when Apple Maps knows the place as somewhere you can visit.
struct VisitingSection: View {
    let info: VisitorInfo

    @State private var showsPlaceCard = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Visiting")
                .font(.title3.weight(.bold))
                .accessibilityAddTraits(.isHeader)
            VStack(alignment: .leading, spacing: 0) {
                row(symbol: "clock", title: String(localized: "Hours and details"),
                    detail: String(localized: "In Apple Maps")) {
                    showPlaceCard(info)
                }
                if let website = info.website {
                    Divider().padding(.leading, 40)
                    row(symbol: "safari", title: String(localized: "Website"),
                        detail: website.host(percentEncoded: false) ?? website.absoluteString) {
                        openURL(website)
                    }
                }
                if let phone = info.phone, let call = info.phoneURL {
                    Divider().padding(.leading, 40)
                    row(symbol: "phone", title: String(localized: "Phone"), detail: phone) {
                        openURL(call)
                    }
                }
            }
            .padding(.horizontal, 14)
            .background(Color(.secondarySystemGroupedBackground),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(Color.primary.opacity(0.06)))
            Text("From Apple Maps. Check before you go.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .modifier(PlaceCardSheet(isPresented: $showsPlaceCard, item: info.mapItem))
    }

    private func showPlaceCard(_ info: VisitorInfo) {
        if #available(iOS 18.0, *) {
            showsPlaceCard = true
        } else {
            info.mapItem.openInMaps()
        }
    }

    private func row(symbol: String, title: String, detail: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: symbol)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    Text(detail)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

/// Apple's own place card, which shows live opening hours. iOS 18 and later; earlier versions open Maps.
private struct PlaceCardSheet: ViewModifier {
    @Binding var isPresented: Bool
    let item: MKMapItem

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.mapItemDetailSheet(isPresented: $isPresented, item: item, displaysMap: true)
        } else {
            content
        }
    }
}
