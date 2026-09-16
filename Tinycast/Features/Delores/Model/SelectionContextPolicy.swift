import Foundation

struct DeloresSelectionFingerprint: Equatable, Hashable, Sendable {
    let hash: Int
    let length: Int
}

struct DeloresPreparedSelection: Equatable, Sendable {
    let text: String
    let fingerprint: DeloresSelectionFingerprint
}

enum DeloresSelectionContextPolicy {
    static let maxInputBytes = 32_768
    static let duplicateWindow: TimeInterval = 0.5

    static func prepare(_ rawText: String) -> DeloresPreparedSelection? {
        let text = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        let fingerprint = DeloresSelectionFingerprint(hash: text.hashValue, length: text.count)
        guard text.utf8.count > maxInputBytes else {
            return DeloresPreparedSelection(text: text, fingerprint: fingerprint)
        }

        var bytes = 0
        var clipped = ""
        for character in text {
            let characterBytes = character.utf8.count
            guard bytes + characterBytes <= maxInputBytes else { break }
            clipped.append(character)
            bytes += characterBytes
        }
        guard !clipped.isEmpty else { return nil }
        return DeloresPreparedSelection(text: clipped, fingerprint: fingerprint)
    }

    static func isDuplicate(
        _ candidate: DeloresSelectionFingerprint,
        previous: DeloresSelectionFingerprint?,
        elapsed: TimeInterval
    ) -> Bool {
        candidate == previous && elapsed < duplicateWindow
    }
}
