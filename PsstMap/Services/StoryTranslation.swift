import CryptoKit
import Foundation
import SwiftUI
@preconcurrency import Translation

/// On-device translation of stories into the reader's language. Stories are written in English; nothing
/// translated is ever stored on the server. Results are cached on the device, keyed by the story, the
/// language, and the exact English text, so an edited story is never shown a stale translation.
enum StoryTranslation {
    static let autoKey = "translate.automatically"

    /// The reader's language, when it isn't English.
    static var targetLanguage: Locale.Language? {
        guard let preferred = Locale.preferredLanguages.first else { return nil }
        let language = Locale.Language(identifier: preferred)
        return language.languageCode?.identifier == "en" ? nil : language
    }

    static var targetLanguageName: String {
        guard let target = targetLanguage, let code = target.languageCode?.identifier else { return "" }
        return Locale.current.localizedString(forLanguageCode: code) ?? code
    }

    struct Text: Codable, Equatable {
        let headline: String
        let short: String
        let long: String
    }
}

/// Translations kept in Caches, so the system can reclaim the space if it needs to.
nonisolated final class TranslationCache: @unchecked Sendable {
    static let shared = TranslationCache()
    private let lock = NSLock()
    private var entries: [String: StoryTranslation.Text]
    private let file: URL

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        file = caches.appendingPathComponent("translations-v1.json")
        entries = (try? JSONDecoder().decode([String: StoryTranslation.Text].self, from: Data(contentsOf: file))) ?? [:]
    }

    static func key(for fact: Fact, language: String) -> String {
        let digest = SHA256.hash(data: Data("\(fact.headline)\u{1F}\(fact.short)\u{1F}\(fact.long)".utf8))
        return "\(fact.id)|\(language)|" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }

    func translation(for key: String) -> StoryTranslation.Text? {
        lock.withLock { entries[key] }
    }

    func store(_ text: StoryTranslation.Text, for key: String) {
        let snapshot: [String: StoryTranslation.Text] = lock.withLock {
            entries[key] = text
            return entries
        }
        if let data = try? JSONEncoder().encode(snapshot) {
            try? data.write(to: file, options: .atomic)
        }
    }
}

/// The Translate control and the translated text for one story.
struct StoryTranslator: ViewModifier {
    let fact: Fact
    @Binding var translated: StoryTranslation.Text?
    @Binding var showsTranslation: Bool
    @Binding var isAvailable: Bool
    @Binding var request: Int
    @AppStorage(StoryTranslation.autoKey) private var translateAutomatically = false

    func body(content: Content) -> some View {
        if #available(iOS 18.0, *) {
            content.modifier(StoryTranslator18(fact: fact, translated: $translated, showsTranslation: $showsTranslation,
                                               isAvailable: $isAvailable, request: $request,
                                               automatic: translateAutomatically))
        } else if #available(iOS 17.4, *) {
            content.modifier(StoryTranslatorSheet(fact: fact, isAvailable: $isAvailable, request: $request))
        } else {
            content
        }
    }
}

@available(iOS 18.0, *)
private struct StoryTranslator18: ViewModifier {
    let fact: Fact
    @Binding var translated: StoryTranslation.Text?
    @Binding var showsTranslation: Bool
    @Binding var isAvailable: Bool
    @Binding var request: Int
    let automatic: Bool
    @State private var configuration: TranslationSession.Configuration?

    func body(content: Content) -> some View {
        content
            .task(id: fact.id) {
                guard let target = StoryTranslation.targetLanguage else { return }
                let status = await LanguageAvailability().status(from: Locale.Language(identifier: "en"), to: target)
                isAvailable = status != .unsupported
                let key = TranslationCache.key(for: fact, language: target.minimalIdentifier)
                if let cached = TranslationCache.shared.translation(for: key) {
                    translated = cached
                    if automatic { showsTranslation = true }
                } else if automatic && status == .installed {
                    start(target)
                }
            }
            .onChange(of: request) {
                guard let target = StoryTranslation.targetLanguage else { return }
                if translated != nil {
                    showsTranslation.toggle()
                } else {
                    start(target)
                }
            }
            .translationTask(configuration) { session in
                guard let target = StoryTranslation.targetLanguage else { return }
                let headline = TranslationSession.Request(sourceText: fact.headline, clientIdentifier: "headline")
                let short = TranslationSession.Request(sourceText: fact.short, clientIdentifier: "short")
                let long = TranslationSession.Request(sourceText: fact.long, clientIdentifier: "long")
                // An About has no separate long version, so there's nothing more to translate.
                let requests = fact.long.isEmpty ? [headline, short] : [headline, short, long]
                guard let responses = try? await session.translations(from: requests) else { return }
                let byID = Dictionary(responses.map { ($0.clientIdentifier ?? "", $0.targetText) },
                                      uniquingKeysWith: { first, _ in first })
                let text = StoryTranslation.Text(headline: byID["headline"] ?? fact.headline,
                                                 short: byID["short"] ?? fact.short, long: byID["long"] ?? fact.long)
                TranslationCache.shared.store(text, for: TranslationCache.key(for: fact, language: target.minimalIdentifier))
                await MainActor.run {
                    translated = text
                    showsTranslation = true
                }
            }
    }

    private func start(_ target: Locale.Language) {
        let config = TranslationSession.Configuration(source: Locale.Language(identifier: "en"), target: target)
        if configuration == config {
            configuration?.invalidate()
        } else {
            configuration = config
        }
    }
}

/// iOS 17.4 to 17.7: the system translation sheet, since in-place translation needs iOS 18.
@available(iOS 17.4, *)
private struct StoryTranslatorSheet: ViewModifier {
    let fact: Fact
    @Binding var isAvailable: Bool
    @Binding var request: Int
    @State private var isPresented = false

    func body(content: Content) -> some View {
        content
            .onAppear { isAvailable = StoryTranslation.targetLanguage != nil }
            .onChange(of: request) { isPresented = true }
            .translationPresentation(isPresented: $isPresented,
                                     text: [fact.headline, fact.short, fact.long].filter { !$0.isEmpty }.joined(separator: "\n\n"))
    }
}
