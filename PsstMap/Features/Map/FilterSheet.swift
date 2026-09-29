import SwiftUI

/// The map key and filter: what each pin color and story label means, and which to show.
struct FilterSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(Fact.Category.displayOrder, id: \.self) { category in
                        CategoryFilterRow(category: category, count: count(of: category),
                                          state: state(chosen: app.shownCategories.contains(category),
                                                       anyChosen: !app.shownCategories.isEmpty)) {
                            withAnimation(.snappy) { app.toggle(category) }
                        }
                    }
                } header: {
                    FilterHeader(title: String(localized: "Stories"), isFiltered: !app.shownCategories.isEmpty) {
                        withAnimation(.snappy) { app.shownCategories = [] }
                    }
                } footer: {
                    Text("Tap one to see only those stories, then tap more to add them.")
                }

                Section {
                    ForEach(Spot.Kind.allCases, id: \.self) { kind in
                        KindFilterRow(kind: kind, count: count(of: kind),
                                      state: state(chosen: app.shownKinds.contains(kind),
                                                   anyChosen: !app.shownKinds.isEmpty)) {
                            withAnimation(.snappy) { app.toggle(kind) }
                        }
                    }
                } header: {
                    FilterHeader(title: String(localized: "Places"), isFiltered: !app.shownKinds.isEmpty) {
                        withAnimation(.snappy) { app.shownKinds = [] }
                    }
                } footer: {
                    Text("Pin colors on the map follow these kinds.")
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
            .navigationTitle("Filter")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func state(chosen: Bool, anyChosen: Bool) -> FilterRowState {
        anyChosen ? (chosen ? .chosen : .off) : .all
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

/// How a filter row looks: everything shown (nothing chosen), chosen, or left out.
enum FilterRowState {
    case all, chosen, off
}

private struct FilterHeader: View {
    let title: String
    let isFiltered: Bool
    let onShowAll: () -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            if isFiltered {
                Button("Show all", action: onShowAll)
                    .font(.subheadline.weight(.semibold))
                    .textCase(nil)
            }
        }
    }
}

private struct FilterRow<Icon: View>: View {
    let title: String
    let detail: String
    let count: Int
    let color: Color
    let state: FilterRowState
    @ViewBuilder let icon: () -> Icon
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 14) {
                icon()
                    .saturation(state == .off ? 0 : 1)
                    .opacity(state == .off ? 0.45 : 1)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.semibold))
                        .foregroundStyle(state == .off ? .secondary : .primary)
                    Text(detail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                Text("\(count)")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                // Everything is shown until something is chosen, so every row carries a check then.
                Image(systemName: state == .off ? "circle" : "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(state == .off ? Color.secondary.opacity(0.5) : color)
                    .contentTransition(.symbolEffect(.replace))
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: state)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(title), \(count)")
        .accessibilityValue(state == .off ? String(localized: "Hidden") : String(localized: "Shown"))
        .accessibilityHint(String(localized: "Shows only these. Choose more to add them."))
        .accessibilityAddTraits(state == .chosen ? [.isButton, .isSelected] : .isButton)
    }
}

private struct KindFilterRow: View {
    let kind: Spot.Kind
    let count: Int
    let state: FilterRowState
    let action: () -> Void

    var body: some View {
        FilterRow(title: kind.label, detail: kind.keyDescription, count: count, color: kind.color, state: state,
                  icon: { KindTile(kind: kind, size: 34) }, action: action)
    }
}

private struct CategoryFilterRow: View {
    let category: Fact.Category
    let count: Int
    let state: FilterRowState
    let action: () -> Void

    var body: some View {
        FilterRow(title: category.label, detail: category.filterDescription, count: count, color: category.color,
                  state: state, icon: {
                      Image(systemName: category.symbol)
                          .font(.body.weight(.semibold))
                          .foregroundStyle(category.color)
                          .frame(width: 34, height: 34)
                          .background(category.color.opacity(0.14), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                  }, action: action)
    }
}
