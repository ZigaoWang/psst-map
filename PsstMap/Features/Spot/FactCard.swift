import SwiftUI

/// One story on a place page, set like a short article: a small line naming the kind of story (and, for
/// legends and disputes, saying so), the whisper in full weight, the rest of the story, its threads, and a
/// quiet row with its sources, translation, and a way to report a problem.
struct FactCard: View {
    let fact: Fact

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

    /// The language the story is shown in: English, or the translation's. It sets line breaking and
    /// the VoiceOver voice, which would otherwise follow the interface language.
    private var textLanguage: Locale.Language {
        showsTranslation && translated != nil
            ? (StoryTranslation.targetLanguage ?? Locale.Language(identifier: "en"))
            : Locale.Language(identifier: "en")
    }

    private func story(_ string: String) -> Text { Text.story(string, language: textLanguage) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            kicker

            story(text.headline)
                .font(.system(.title2, design: .serif).weight(.bold))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            story(text.short)
                .font(.system(.title3, design: .serif))
                .fixedSize(horizontal: false, vertical: true)

            story(text.long)
                .font(.system(.body, design: .serif))
                .foregroundStyle(.primary.opacity(0.78))
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 2)

            if fact.status != .fact {
                Text(fact.status.explanation)
                    .font(.footnote)
                    .foregroundStyle(fact.status.color)
            }

            TagChips(tagIDs: fact.tags)
                .padding(.top, 4)

            toolbar
                .padding(.top, 2)
        }
        .animation(.snappy, value: showsTranslation)
        .modifier(StoryTranslator(fact: fact, translated: $translated, showsTranslation: $showsTranslation,
                                  isAvailable: $canTranslate, request: $translationRequest))
        .sheet(isPresented: $reporting) {
            ReportSheet(fact: fact)
        }
    }

    /// "Name origin", or "Name origin · Disputed", in the story type's color.
    private var kicker: some View {
        HStack(spacing: 0) {
            Text(fact.category.label)
                .foregroundStyle(fact.category.color)
            if fact.status != .fact {
                Text(" · \(fact.status.label)")
                    .foregroundStyle(fact.status.color)
            }
            if showsTranslation, translated != nil {
                Text(" · \(String(localized: "Translated from English"))")
                    .foregroundStyle(.secondary)
            }
        }
        .font(.footnote.weight(.semibold))
        .accessibilityElement(children: .combine)
    }

    private var toolbar: some View {
        HStack(spacing: 18) {
            SourcesMenu(sources: fact.sources)
            if canTranslate {
                Button {
                    translationRequest += 1
                } label: {
                    Label(showsTranslation ? String(localized: "Show original") : String(localized: "Translate"),
                          systemImage: "translate")
                }
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
                    .frame(width: 32, height: 32)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel(String(localized: "More"))
        }
        .font(.footnote.weight(.medium))
        .foregroundStyle(.secondary)
        .buttonStyle(.plain)
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
            Label(summary, systemImage: "books.vertical")
                .lineLimit(1)
                .contentShape(Rectangle())
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

    enum SendState { case editing, sending, sent, queued, alreadyReported, dailyLimit }

    private var isFinished: Bool { state != .editing && state != .sending }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text.story(fact.headline)
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
                if isFinished {
                    Section {
                        switch state {
                        case .sent:
                            Label(String(localized: "Thanks. We'll take a look."), systemImage: "checkmark.circle.fill")
                        case .queued:
                            Label(String(localized: "Saved. It will send when you're back online."), systemImage: "clock")
                        case .alreadyReported:
                            Label(String(localized: "You've already reported this story. Thanks, we have it."),
                                  systemImage: "checkmark.circle")
                        default:
                            Label(String(localized: "That's the most reports for one day. Please try again tomorrow."),
                                  systemImage: "hourglass")
                        }
                    }
                }
            }
            .navigationTitle("Report a problem")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(isFinished ? String(localized: "Done") : String(localized: "Cancel")) {
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
            state = switch await app.reports.submit(factID: fact.id, reason: reason, message: message) {
            case .sent: .sent
            case .queued: .queued
            case .alreadyReported: .alreadyReported
            case .dailyLimit: .dailyLimit
            }
        }
    }
}
