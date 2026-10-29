import Foundation

// Ce qui a vraiment changé entre le texte d'origine et le texte corrigé. On ne se
// fie pas à la liste de l'IA pour savoir quoi souligner (elle peut oublier un mot
// qu'elle a pourtant modifié) ; sa liste sert seulement à donner les raisons et à
// découper les changements qui se touchent.
enum Diff {
    struct Change: Equatable {
        let oldText: String
        let newText: String
        let oldRange: NSRange
        let newRange: NSRange  // position dans le texte corrigé (unités UTF-16, comme l'Accessibilité)
    }

    static var noReason: String { L("Corrected without an explanation from the AI.", "Corrigé sans explication de l'IA.") }

    // Au-delà, le calcul serait trop long : on renvoie nil et l'app affiche la bulle.
    private static let maxCells = 4_000_000

    static func changes(from old: String, to new: String) -> [Change]? {
        let a = tokens(old)
        let b = tokens(new)
        guard (a.count + 1) * (b.count + 1) <= maxCells else { return nil }

        // Plus longue suite commune (programmation dynamique classique).
        let width = b.count + 1
        var table = [Int32](repeating: 0, count: (a.count + 1) * width)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i * width + j] = a[i].text == b[j].text
                    ? table[(i + 1) * width + j + 1] + 1
                    : max(table[(i + 1) * width + j], table[i * width + j + 1])
            }
        }

        let oldNS = old as NSString
        let newNS = new as NSString
        func position(_ list: [Token], _ index: Int, _ total: Int) -> Int {
            index < list.count ? list[index].range.location : total
        }

        var raw: [(old: NSRange, new: NSRange)] = []
        var i = 0, j = 0, oldStart = 0, newStart = 0
        func flush() {
            guard i > oldStart || j > newStart else { return }
            let o = position(a, oldStart, oldNS.length)
            let n = position(b, newStart, newNS.length)
            raw.append((NSRange(location: o, length: position(a, i, oldNS.length) - o),
                        NSRange(location: n, length: position(b, j, newNS.length) - n)))
        }
        while i < a.count || j < b.count {
            if i < a.count, j < b.count, a[i].text == b[j].text {
                flush()
                i += 1
                j += 1
                oldStart = i
                newStart = j
            } else if j < b.count, i == a.count || table[i * width + j + 1] >= table[(i + 1) * width + j] {
                j += 1
            } else {
                i += 1
            }
        }
        flush()

        // Deux changements séparés seulement par des espaces n'en font qu'un :
        // « orthogrpahe ducoup » → « orthographe du coup » se compare d'un bloc.
        var merged: [(old: NSRange, new: NSRange)] = []
        for hunk in raw {
            if let last = merged.last,
               isBlank(oldNS, from: NSMaxRange(last.old), to: hunk.old.location),
               isBlank(newNS, from: NSMaxRange(last.new), to: hunk.new.location) {
                merged[merged.count - 1] = (
                    NSRange(location: last.old.location, length: NSMaxRange(hunk.old) - last.old.location),
                    NSRange(location: last.new.location, length: NSMaxRange(hunk.new) - last.new.location)
                )
            } else {
                merged.append(hunk)
            }
        }
        return merged.map { hunk in
            let o = trimmed(oldNS, hunk.old)
            let n = trimmed(newNS, hunk.new)
            return Change(oldText: oldNS.substring(with: o), newText: newNS.substring(with: n), oldRange: o, newRange: n)
        }
    }

    // Découpe chaque changement selon la liste de l'IA et y met ses raisons.
    // Ce que l'IA n'a pas signalé reste souligné, avec `noReason`.
    static func explain(_ changes: [Change], with corrections: [Correction]) -> [(range: NSRange, correction: Correction)] {
        var unused = corrections.filter { !$0.apres.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        var result: [(range: NSRange, correction: Correction)] = []
        for change in changes where change.newRange.length > 0 {
            let text = change.newText as NSString
            var parts: [(range: NSRange, correction: Correction)] = []
            var index = 0
            while index < unused.count {
                let target = unused[index].apres.trimmingCharacters(in: .whitespacesAndNewlines)
                let found = text.range(of: target)
                if found.location != NSNotFound, !parts.contains(where: { NSIntersectionRange($0.range, found).length > 0 }) {
                    parts.append((found, Correction(avant: unused[index].avant, apres: target, raison: unused[index].raison)))
                    unused.remove(at: index)
                } else {
                    index += 1
                }
            }
            if parts.isEmpty, let match = unused.firstIndex(where: { c in
                let apres = normalize(c.apres)
                return apres.contains(normalize(change.newText))
                    || (!change.oldText.isEmpty && normalize(c.avant) == normalize(change.oldText))
            }) {
                parts.append((NSRange(location: 0, length: text.length),
                              Correction(avant: change.oldText, apres: change.newText, raison: unused[match].raison)))
                unused.remove(at: match)
            }
            // Les morceaux restants, que l'IA n'a pas expliqués.
            parts.sort { $0.range.location < $1.range.location }
            var cursor = 0
            var leftovers: [(range: NSRange, correction: Correction)] = []
            for gap in parts.map(\.range) + [NSRange(location: text.length, length: 0)] {
                let piece = trimmed(text, NSRange(location: cursor, length: max(0, gap.location - cursor)))
                if piece.length > 0 {
                    let alone = parts.isEmpty
                    leftovers.append((piece, Correction(avant: alone ? change.oldText : "",
                                                        apres: text.substring(with: piece), raison: noReason)))
                }
                cursor = max(cursor, NSMaxRange(gap))
            }
            for part in (parts + leftovers).sorted(by: { $0.range.location < $1.range.location }) {
                let absolute = NSRange(location: change.newRange.location + part.range.location, length: part.range.length)
                result.append((absolute, part.correction))
            }
        }
        return result
    }

    private struct Token {
        let text: String
        let range: NSRange
    }

    // Un mot = une suite de lettres ou de chiffres ; chaque autre caractère est seul.
    private static func tokens(_ s: String) -> [Token] {
        var out: [Token] = []
        var word = ""
        var start = 0
        var position = 0
        for character in s {
            let length = character.utf16.count
            if character.isLetter || character.isNumber {
                if word.isEmpty { start = position }
                word.append(character)
            } else {
                if !word.isEmpty {
                    out.append(Token(text: word, range: NSRange(location: start, length: position - start)))
                    word = ""
                }
                out.append(Token(text: String(character), range: NSRange(location: position, length: length)))
            }
            position += length
        }
        if !word.isEmpty {
            out.append(Token(text: word, range: NSRange(location: start, length: position - start)))
        }
        return out
    }

    private static func isBlank(_ s: NSString, from: Int, to: Int) -> Bool {
        guard to >= from else { return false }
        return s.substring(with: NSRange(location: from, length: to - from))
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // Retire les espaces au début et à la fin d'un morceau.
    private static func trimmed(_ s: NSString, _ range: NSRange) -> NSRange {
        var start = range.location
        var end = NSMaxRange(range)
        let blanks = CharacterSet.whitespacesAndNewlines
        while start < end, let u = UnicodeScalar(s.character(at: start)), blanks.contains(u) { start += 1 }
        while end > start, let u = UnicodeScalar(s.character(at: end - 1)), blanks.contains(u) { end -= 1 }
        return NSRange(location: start, length: end - start)
    }

    private static func normalize(_ s: String) -> String {
        s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
