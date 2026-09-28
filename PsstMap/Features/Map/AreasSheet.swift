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

/// The map key, which is also the filter: tap a kind to show or hide its pins.
struct MapKeySheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Spot.Kind.allCases, id: \.self) { kind in
                        KindFilterRow(kind: kind, count: count(of: kind), isShown: !app.hiddenKinds.contains(kind)) {
                            withAnimation(.snappy) { app.toggle(kind) }
                        }
                        .contextMenu {
                            Button("Show only \(kind.label)", systemImage: "line.3.horizontal.decrease") {
                                withAnimation(.snappy) { app.showOnly(kind) }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Only") { withAnimation(.snappy) { app.showOnly(kind) } }
                                .tint(kind.color)
                        }
                    }
                } header: {
                    HStack {
                        Text("Places")
                        Spacer()
                        if !app.hiddenKinds.isEmpty {
                            Button("Show all") { withAnimation(.snappy) { app.showAllKinds() } }
                                .font(.subheadline.weight(.semibold))
                                .textCase(nil)
                        }
                    }
                }

                Section {
                    ForEach(Fact.Category.allCases, id: \.self) { category in
                        CategoryFilterRow(category: category, count: count(of: category),
                                          isShown: !app.hiddenCategories.contains(category)) {
                            withAnimation(.snappy) { app.toggle(category) }
                        }
                        .contextMenu {
                            Button("Show only \(category.label)", systemImage: "line.3.horizontal.decrease") {
                                withAnimation(.snappy) { app.showOnly(category) }
                            }
                        }
                        .swipeActions(edge: .trailing) {
                            Button("Only") { withAnimation(.snappy) { app.showOnly(category) } }
                                .tint(category.color)
                        }
                    }
                } header: {
                    HStack {
                        Text("Stories")
                        Spacer()
                        if !app.hiddenCategories.isEmpty {
                            Button("Show all") { withAnimation(.snappy) { app.hiddenCategories = [] } }
                                .font(.subheadline.weight(.semibold))
                                .textCase(nil)
                        }
                    }
                } footer: {
                    Text("Places stay on the map while they have at least one story you've kept.")
                }

                Section {
                    ForEach([Fact.Status.legend, .disputed], id: \.self) { status in
                        HStack(spacing: 14) {
                            Image(systemName: status.symbol)
                                .font(.body.weight(.semibold))
                                .foregroundStyle(status.color)
                                .frame(width: 34, height: 34)
                                .background(status.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(status.label).font(.body.weight(.semibold))
                                Text(status.explanation).font(.subheadline).foregroundStyle(.secondary)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    }
                } header: {
                    Text("Labels on stories")
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

    private func count(of kind: Spot.Kind) -> Int {
        app.catalog.places.reduce(0) { $0 + ($1.spot.kind == kind ? 1 : 0) }
    }

    private func count(of category: Fact.Category) -> Int {
        app.catalog.places.reduce(0) { total, place in
            total + place.spot.facts.reduce(0) { $0 + ($1.category == category ? 1 : 0) }
        }
    }
}

private struct KindFilterRow: View {
    let kind: Spot.Kind
    let count: Int
    let isShown: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                KindTile(kind: kind, size: 34)
                    .saturation(isShown ? 1 : 0)
                    .opacity(isShown ? 1 : 0.45)
                VStack(alignment: .leading, spacing: 2) {
                    Text(kind.label)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isShown ? .primary : .secondary)
                    Text(kind.keyDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text("\(count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Image(systemName: isShown ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isShown ? kind.color : Color.secondary.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isShown)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(kind.label), \(count) places")
        .accessibilityValue(isShown ? String(localized: "Shown") : String(localized: "Hidden"))
        .accessibilityHint(String(localized: "Shows or hides these pins"))
        .accessibilityAddTraits(isShown ? [.isButton, .isSelected] : .isButton)
    }
}

private struct CategoryFilterRow: View {
    let category: Fact.Category
    let count: Int
    let isShown: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: category.symbol)
                    .font(.body.weight(.semibold))
                    .foregroundStyle(isShown ? category.color : .secondary)
                    .frame(width: 34, height: 34)
                    .background((isShown ? category.color : Color.secondary).opacity(0.14),
                                in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(category.label)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(isShown ? .primary : .secondary)
                    Text(category.filterDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text("\(count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                Image(systemName: isShown ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isShown ? category.color : Color.secondary.opacity(0.5))
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: isShown)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(category.label), \(count) stories")
        .accessibilityValue(isShown ? String(localized: "Shown") : String(localized: "Hidden"))
        .accessibilityHint(String(localized: "Shows or hides places with these stories"))
        .accessibilityAddTraits(isShown ? [.isButton, .isSelected] : .isButton)
    }
}
