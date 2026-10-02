import Foundation

struct Emoji: Decodable, Identifiable, Hashable {
    let id: String
    let name: String
    let keywords: [String]
    let aliases: [String]
    let native: String
}

final class EmojiStore {
    private let emojis: [Emoji]
    private let emojisById: [String: Emoji]
    private let recentsDefaultsKey = "recentEmojiIds"
    private let maxRecents = 30
    private let maxRecentsBoost = 40
    private let maxLengthPenalty = 50

    init() {
        guard
            let url = Bundle.main.url(forResource: "emoji", withExtension: "json"),
            let data = try? Data(contentsOf: url),
            let decoded = try? JSONDecoder().decode([Emoji].self, from: data)
        else {
            fatalError("emoji.json missing from app bundle Resources")
        }
        emojis = decoded
        var byId: [String: Emoji] = [:]
        for emoji in decoded {
            byId[emoji.id] = emoji
            for alias in emoji.aliases {
                byId[alias] = emoji
            }
        }
        emojisById = byId
        for (slang, emojiIds) in Slang.emojiIdsBySlang {
            for emojiId in emojiIds where byId[emojiId] == nil {
                NSLog("ColonEmoji: slang '\(slang)' points at unknown emoji '\(emojiId)'")
            }
        }
    }

    func exactMatch(shortcode: String) -> Emoji? {
        emojisById[shortcode]
    }

    func search(_ rawQuery: String, limit: Int) -> [Emoji] {
        let query = rawQuery.lowercased()
        if query.isEmpty {
            return []
        }
        let recentIds = UserDefaults.standard.stringArray(forKey: recentsDefaultsKey) ?? []
        let slangScores = slangScores(for: query)

        var scored: [(emoji: Emoji, score: Int, order: Int)] = []
        for (order, emoji) in emojis.enumerated() {
            let textScore = matchScore(emoji: emoji, query: query)
            let slangScore = slangScores[emoji.id]
            guard var score = [textScore, slangScore].compactMap({ $0 }).max() else {
                continue
            }
            if let recentIndex = recentIds.firstIndex(of: emoji.id) {
                score += max(maxRecentsBoost - recentIndex, 0)
            }
            scored.append((emoji, score, order))
        }

        scored.sort { left, right in
            if left.score != right.score {
                return left.score > right.score
            }
            return left.order < right.order
        }
        return scored.prefix(limit).map(\.emoji)
    }

    func recordUse(_ emoji: Emoji) {
        var recentIds = UserDefaults.standard.stringArray(forKey: recentsDefaultsKey) ?? []
        recentIds.removeAll { $0 == emoji.id }
        recentIds.insert(emoji.id, at: 0)
        UserDefaults.standard.set(Array(recentIds.prefix(maxRecents)), forKey: recentsDefaultsKey)
    }

    /// Tiers are 100 apart; recents and length tie-breaks stay under that so they only reorder within a tier.
    private func matchScore(emoji: Emoji, query: String) -> Int? {
        let shortcodes = [emoji.id] + emoji.aliases
        if shortcodes.contains(query) {
            return 1000
        }
        let prefixMatchLengths = shortcodes.filter { $0.hasPrefix(query) }.map(\.count)
        if let shortestPrefixMatch = prefixMatchLengths.min() {
            // `:smi` should offer smile before smiley_cat.
            return 800 - min(shortestPrefixMatch - query.count, maxLengthPenalty)
        }
        if shortcodes.flatMap(Self.words(in:)).contains(where: { $0.hasPrefix(query) }) {
            return 600
        }
        let keywords = emoji.keywords.map { $0.lowercased() }
        if keywords.contains(query) {
            return 550
        }
        if keywords.contains(where: { $0.hasPrefix(query) }) {
            return 450
        }
        if Self.words(in: emoji.name.lowercased()).contains(where: { $0.hasPrefix(query) }) {
            return 300
        }
        if query.count >= 3, shortcodes.contains(where: { $0.contains(query) }) {
            return 100
        }
        return nil
    }

    /// Exact slang (`lmao`) ranks just under an exact shortcode; a slang prefix (`lma`) ranks under shortcode prefixes.
    private func slangScores(for query: String) -> [String: Int] {
        var scores: [String: Int] = [:]
        for (slang, emojiIds) in Slang.emojiIdsBySlang {
            let baseScore: Int
            if slang == query {
                baseScore = 900
            } else if query.count >= 2, slang.hasPrefix(query) {
                baseScore = 700
            } else {
                continue
            }
            for (position, emojiId) in emojiIds.enumerated() {
                guard let emoji = emojisById[emojiId] else {
                    continue
                }
                let score = baseScore - min(position * 5, maxLengthPenalty)
                scores[emoji.id] = max(scores[emoji.id] ?? 0, score)
            }
        }
        return scores
    }

    private static func words(in text: String) -> [String] {
        text.split(whereSeparator: { $0 == "_" || $0 == "-" || $0 == " " }).map(String.init)
    }
}
