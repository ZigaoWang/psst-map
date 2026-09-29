import SwiftUI

/// Settings and everything about Psst: preferences, privacy, what's inside, and credits.
struct SettingsView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @AppStorage(StoryTranslation.autoKey) private var translateAutomatically = false
    @AppStorage(DemandSignal.settingKey) private var helpChooseAreas = true

    static let privacyPolicyURL = URL(string: "https://psst.zigao.wang/privacy/")!

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Wordmark(size: 40, color: .primary)
                        Text("The stories behind the places people walk past. Every place here has at least one thing about it worth leaning over to tell a friend.")
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 8)
                }

                if StoryTranslation.targetLanguage != nil {
                    Section {
                        Toggle("Translate stories automatically", isOn: $translateAutomatically)
                    } header: {
                        Text("Stories")
                    } footer: {
                        Text("Stories are written in English. When a translation into \(StoryTranslation.targetLanguageName) is available on this device, it's shown instead, with a way back to the original.")
                    }
                }

                Section {
                    Toggle("Help choose new areas", isOn: $helpChooseAreas)
                    Link("Privacy policy", destination: Self.privacyPolicyURL)
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("When you look at a part of the map with no stories yet, Psst sends the rough middle of that area (to about 10 km), and nothing else, so we know where to research next. Your saved places, history, and location stay on this device.")
                }

                Section {
                    LabeledContent("Places", value: "\(app.catalog.places.count)")
                    LabeledContent("Stories", value: "\(app.catalog.factCount)")
                    ForEach(app.catalog.cities) { city in
                        LabeledContent(city.displayName, value: city.neighborhoods.count == 1
                                       ? String(localized: "1 neighborhood")
                                       : String(localized: "\(city.neighborhoods.count) neighborhoods"))
                    }
                } header: {
                    Text("What's inside")
                }

                Section {
                    AboutRow(symbol: Fact.Status.fact.symbol, color: .secondary, title: "Facts",
                             text: "Documented by sources you can open from every story.")
                    AboutRow(symbol: Fact.Status.legend.symbol, color: Theme.legend, title: "Legends",
                             text: "Stories people tell that aren't proven, or are known to be untrue. They're always labeled.")
                    AboutRow(symbol: Fact.Status.disputed.symbol, color: Theme.disputed, title: "Disputed",
                             text: "Where reliable sources disagree. The full story explains how.")
                } header: {
                    Text("How to read it")
                } footer: {
                    Text("Each place was researched from published sources, and its location comes from Wikidata or OpenStreetMap. If something looks wrong, the sources are one tap away.")
                }

                Section {
                    Text("Maps and street-level imagery by Apple Maps. In mainland China, map data is licensed by Apple from local providers.")
                    Link("Location data from Wikidata (CC0)", destination: URL(string: "https://www.wikidata.org/wiki/Wikidata:Licensing")!)
                    Link("Location data © OpenStreetMap contributors (ODbL)", destination: URL(string: "https://www.openstreetmap.org/copyright")!)
                } header: {
                    Text("Credits")
                }
                .font(.subheadline)

                Section {
                    LabeledContent("Version", value: version)
                    if let content = app.content {
                        LabeledContent("Stories updated", value: content.manifest.contentVersion.prefix(8)
                            .replacingOccurrences(of: #"(\d{4})(\d{2})(\d{2})"#, with: "$1-$2-$3", options: .regularExpression))
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

private struct AboutRow: View {
    let symbol: String
    let color: Color
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 22)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.body.weight(.semibold))
                Text(text).font(.subheadline).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }
}
