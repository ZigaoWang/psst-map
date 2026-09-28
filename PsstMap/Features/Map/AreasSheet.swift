import SwiftUI

/// Every area, grouped by city.
struct AreasSheet: View {
    let onSelect: (String) -> Void
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(app.catalog.cities) { city in
                    Section {
                        ForEach(city.areas) { area in
                            Button { onSelect(area.id) } label: {
                                AreaRow(area: area)
                            }
                            .buttonStyle(.plain)
                        }
                    } header: {
                        Text(city.name)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Areas")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

struct AreaRow: View {
    let area: Area

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(area.name)
                    .font(.body.weight(.semibold))
                Text(area.summary)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Text("\(area.spots.count)")
                .font(.subheadline.monospacedDigit().weight(.semibold))
                .foregroundStyle(.secondary)
                .accessibilityLabel(String(localized: "\(area.spots.count) places"))
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

/// What the pin colors and badges mean.
struct MapKeySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Spot.Kind.allCases, id: \.self) { kind in
                        HStack(spacing: 14) {
                            KindTile(kind: kind, size: 34)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(kind.label).font(.body.weight(.semibold))
                                Text(kind.keyDescription).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Pins")
                }
                Section {
                    ForEach([Fact.Status.legend, .disputed], id: \.self) { status in
                        VStack(alignment: .leading, spacing: 6) {
                            StatusBadge(status: status)
                            Text(status.explanation)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Labels")
                } footer: {
                    Text("Everything without a label is a documented fact with sources you can check.")
                }
            }
            .navigationTitle("Map key")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
