import SwiftUI

struct AboutView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

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

                Section {
                    LabeledContent("Places", value: "\(app.catalog.places.count)")
                    LabeledContent("Facts", value: "\(app.catalog.factCount)")
                    ForEach(app.catalog.cities) { city in
                        LabeledContent(city.name, value: "\(city.areas.count) \(city.areas.count == 1 ? "area" : "areas")")
                    }
                } header: {
                    Text("What's inside")
                }

                Section {
                    AboutRow(symbol: Fact.Status.fact.symbol, color: .secondary, title: "Facts",
                             text: "Documented by sources you can open. Tap Read more on any fact to see them.")
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
                } footer: {
                    Text("Psst doesn't collect or send any data. Your saved places and location stay on this device.")
                }
            }
            .navigationTitle("About")
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
