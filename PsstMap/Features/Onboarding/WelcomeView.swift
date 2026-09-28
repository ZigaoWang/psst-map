import SwiftUI

/// Shown once, on first launch.
struct WelcomeView: View {
    let onContinue: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                Wordmark(size: 72, color: Theme.ink)
                    .padding(.top, 40)
                Text("Every place has a secret. Here are the good ones.")
                    .font(.title2.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 22) {
                    Point(symbol: "mappin.and.ellipse", title: "Find them on the map",
                          text: "Tap a pin to see a place and what's surprising about it.")
                    Point(symbol: "rectangle.stack", title: "Or just swipe",
                          text: "The feed brings you one place at a time, from everywhere Psst knows.")
                    Point(symbol: Fact.Status.legend.symbol, title: "Legends are labeled",
                          text: "Some stories are too good to leave out and too shaky to call facts. You'll always know which is which.")
                }
            }
            .padding(.horizontal, 28)
            .padding(.bottom, 24)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .safeAreaInset(edge: .bottom) {
            Button(action: onContinue) {
                Text("Start exploring")
                    .font(.headline)
                    .frame(maxWidth: 520)
                    .frame(minHeight: 54)
                    .foregroundStyle(Theme.paper)
                    .background(Theme.ink, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 28)
            .padding(.bottom, 12)
        }
        .background(Theme.paper.ignoresSafeArea())
        .environment(\.colorScheme, .light)
    }
}

private struct Point: View {
    let symbol: String
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: symbol)
                .font(.title2)
                .foregroundStyle(Theme.ink)
                .frame(width: 32)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(Theme.ink)
                Text(text)
                    .font(.body)
                    .foregroundStyle(Theme.ink.opacity(0.72))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .accessibilityElement(children: .combine)
    }
}
