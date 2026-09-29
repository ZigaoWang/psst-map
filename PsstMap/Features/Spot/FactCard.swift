import SwiftUI

/// One story on a place page. The whisper comes first in full weight, then the rest of the story, its
/// threads (tags), and a row with its sources, translation, and a way to report a problem.
/// Legends and disputes carry their label and a colored rule.
struct FactCard: View {
    let fact: Fact
    var number = 1

    @State private var translated: StoryTranslation.Text?
    @State private var showsTranslation = false
    @State private var canTranslate = false
    @State private var translationRequest = 0
    @State private var reporting = false

    private var text: StoryTranslation.Text {
        showsTranslation ? (translated ?? original) : original
    }

    private var original: StoryTranslation.Text {
        StoryTranslation.Text(headline: fact.headline, short: fact.short, long: fact.long)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(String(format: "%02d", number))
                    .font(.caption.weight(.heavy).monospacedDigit())
                    .foregroundStyle(.secondary)
                Label(fact.category.label, systemImage: fact.category.symbol)
                    .font(.caption.weight(.bold))
                    .textCase(.uppercase)
                    .tracking(0.8)
                    .foregroundStyle(fact.category.color)
                Spacer(minLength: 0)
                StatusBadge(status: fact.status)
            }
            .accessibilityElement(children: .combine)

            if showsTranslation, translated != nil {
                Label(String(localized: "Translated from English"), systemImage: "translate")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            Text(text.headline)
                .font(.title2.weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            Text(text.short)
                .font(.title3)
                .fixedSize(horizontal: false, vertical: true)

            Text(text.long)
                .font(.body)
                .foregroundStyle(.primary.opacity(0.75))
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

            if fact.status != .fact {
                Label(fact.status.explanation, systemImage: fact.status.symbol)
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(fact.status.color)
                    .padding(.top, 2)
            }

            TagChips(tagIDs: fact.tags)
                .padding(.top, 2)

            HStack(spacing: 8) {
                SourcesMenu(sources: fact.sources)
                if canTranslate {
                    Button {
                        translationRequest += 1
                    } label: {
                        Label(showsTranslation ? String(localized: "Show original") : String(localized: "Translate"),
                              systemImage: "translate")
                            .labelStyle(.titleAndIcon)
                    }
                    .buttonStyle(SmallPillButtonStyle())
                    .accessibilityHint(showsTranslation ? "" : String(localized: "Translates into \(StoryTranslation.targetLanguageName)"))
                }
                Spacer(minLength: 0)
                Menu {
                    Button {
                        reporting = true
                    } label: {
                        Label("Report a problem", systemImage: "exclamationmark.bubble")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.secondary)
                        .frame(width: 34, height: 34)
                        .background(Color.primary.opacity(0.06), in: Circle())
                        .contentShape(Circle())
                }
                .accessibilityLabel(String(localized: "More"))
            }
            .padding(.top, 4)
        }
        .padding(.leading, fact.status == .fact ? 0 : 14)
        .overlay(alignment: .leading) {
            if fact.status != .fact {
                Capsule()
                    .fill(fact.status.color)
                    .frame(width: 3)
            }
        }
        .animation(.snappy, value: showsTranslation)
        .modifier(StoryTranslator(fact: fact, translated: $translated, showsTranslation: $showsTranslation,
                                  isAvailable: $canTranslate, request: $translationRequest))
        .sheet(isPresented: $reporting) {
            ReportSheet(fact: fact)
        }
    }
}

struct SmallPillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(configuration.isPressed ? 0.12 : 0.06), in: Capsule())
            .contentShape(Capsule())
    }
}

/// The sources of a story, folded into one small menu so they don't crowd the reading.
struct SourcesMenu: View {
    let sources: [Fact.Source]
    @Environment(\.openURL) private var openURL

    var body: some View {
        Menu {
            ForEach(Array(sources.enumerated()), id: \.offset) { _, source in
                Button {
                    openURL(source.url)
                } label: {
                    Text(source.publisher)
                    Text(source.title)
                }
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "books.vertical")
                Text(summary)
                    .lineLimit(1)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.caption2.weight(.bold))
            }
            .font(.footnote.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.primary.opacity(0.06), in: Capsule())
            .contentShape(Capsule())
        }
        .accessibilityLabel(String(localized: "Sources: \(summary)"))
        .accessibilityHint(String(localized: "Choose a source to open it"))
    }

    private var summary: String {
        let publishers = sources.map(\.publisher)
        guard let first = publishers.first else { return "" }
        return publishers.count == 1 ? first : String(localized: "\(first) and \(publishers.count - 1) more")
    }
}

/// "Report a problem": a reason, an optional note, and it's sent (or queued until the phone is online).
struct ReportSheet: View {
    let fact: Fact
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss
    @State private var reason: ReportOutbox.Reason?
    @State private var message = ""
    @State private var state: SendState = .editing

    enum SendState { case editing, sending, sent, queued }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(fact.headline)
                        .font(.headline)
                } header: {
                    Text("Story")
                }
                Section {
                    ForEach(ReportOutbox.Reason.allCases) { option in
                        Button {
                            reason = option
                        } label: {
                            HStack {
                                Text(option.label)
                                    .foregroundStyle(.primary)
                                Spacer()
                                if reason == option {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.tint)
                                }
                            }
                            .contentShape(Rectangle())
                        }
                        .accessibilityAddTraits(reason == option ? .isSelected : [])
                    }
                } header: {
                    Text("What's the problem?")
                }
                Section {
                    TextField("Tell us more (optional)", text: $message, axis: .vertical)
                        .lineLimit(3...8)
                } footer: {
                    Text("Reports go to the people who check Psst's stories. They aren't linked to you. Please don't include personal information.")
                }
                if state == .sent || state == .queued {
                    Section {
                        Label(state == .sent ? String(localized: "Thanks. We'll take a look.")
                                             : String(localized: "Saved. It will send when you're back online."),
                              systemImage: state == .sent ? "checkmark.circle.fill" : "clock")
                    }
                }
            }
            .navigationTitle("Report a problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(state == .sent || state == .queued ? String(localized: "Done") : String(localized: "Cancel")) {
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if state == .editing || state == .sending {
                        Button("Send") { send() }
                            .disabled(reason == nil || state == .sending)
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func send() {
        guard let reason else { return }
        state = .sending
        Task {
            let sent = await app.reports.submit(factID: fact.id, reason: reason, message: message)
            state = sent ? .sent : .queued
        }
    }
}
