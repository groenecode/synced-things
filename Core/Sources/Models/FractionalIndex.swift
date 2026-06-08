import Foundation

/// Generates lexicographically-ordered "order keys" for positioning items in a
/// list, so that inserting or moving an item only ever rewrites *that one item's*
/// key — never its neighbors. This is what makes ordering robust under iCloud
/// sync: a reorder is a single-record change rather than a renumber of the whole
/// list, which would otherwise race and collide under CloudKit's last-writer-wins.
///
/// Keys are base-62 strings (`0-9A-Za-z`, which sort in plain byte/lexicographic
/// order — matching SQLite's default `BINARY` collation), so comparing them with
/// `<` orders the list. Unlike a `Double` "midpoint", string keys never run out
/// of precision: there is always room to generate a key between any two others.
///
/// This is a faithful port of the well-established `fractional-indexing`
/// algorithm (David Greenspan / Figma lineage). Keys carry a variable-length
/// "integer" header so that the common case — appending to the end — keeps keys
/// short and stable (`a0`, `a1`, …, `az`, `b00`, …) rather than growing without
/// bound.
///
/// Concurrent inserts at the same spot on two devices can produce the *same*
/// key; that is a tie, not corruption. Always break ties with a stable secondary
/// sort (the record `id`) in the query: `ORDER BY rank, id`.
public enum FractionalIndex {
    static let digits = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    static let zero = digits[0]
    static let indexOf: [Character: Int] = Dictionary(
        uniqueKeysWithValues: digits.enumerated().map { ($1, $0) }
    )
    /// The single forbidden key: the absolute minimum, which nothing can precede.
    static let smallestInteger = "A" + String(repeating: zero, count: getIntegerLength("A") - 1)

    /// Returns a key that sorts strictly between `a` and `b`.
    ///
    /// Pass `nil` for `a` to generate a key before everything (prepend), `nil`
    /// for `b` to generate a key after everything (append), and `nil` for both
    /// for the very first key in an empty list. `a` must sort before `b`.
    ///
    /// If `a >= b` (e.g. two items ended up tied via a concurrent sync insert),
    /// this degrades gracefully by returning a key just after `a` rather than
    /// trapping.
    public static func keyBetween(_ a: String?, _ b: String?) -> String {
        if let a, let b, a >= b { return keyBetween(a, nil) }

        if a == nil {
            guard let b else { return "a" + String(zero) }
            let ib = getIntegerPart(b)
            let fb = String(b.dropFirst(ib.count))
            if ib == smallestInteger {
                return ib + midpoint("", fb)
            }
            if ib < b { return ib }
            guard let res = decrementInteger(ib) else {
                // Unreachable: `ib == smallestInteger` is handled above.
                return ib + midpoint("", fb)
            }
            return res
        }

        let a = a!
        if b == nil {
            let ia = getIntegerPart(a)
            let fa = String(a.dropFirst(ia.count))
            if let i = incrementInteger(ia) { return i }
            return ia + midpoint(fa, nil)
        }

        let b = b!
        let ia = getIntegerPart(a)
        let fa = String(a.dropFirst(ia.count))
        let ib = getIntegerPart(b)
        let fb = String(b.dropFirst(ib.count))
        if ia == ib {
            return ia + midpoint(fa, fb)
        }
        // `ia < ib`, so `ia` can always be incremented.
        let i = incrementInteger(ia)!
        if i < b { return i }
        return ia + midpoint(fa, nil)
    }

    // MARK: - Internals

    /// Returns a fractional digit-string strictly between `a` and `b` that does
    /// not end in a zero digit. `a` is treated as `0.aaa…`, `b` (when `nil`) as
    /// `1.000…`. `a` must sort before `b`, and neither may end in a zero digit.
    static func midpoint(_ a: String, _ b: String?) -> String {
        if let b { precondition(a < b, "midpoint: \(a) >= \(b)") }
        precondition(a.last != zero, "midpoint: trailing zero in \(a)")
        if let b { precondition(b.last != zero, "midpoint: trailing zero in \(b)") }

        if let b {
            // Carry over the longest common prefix, then recurse on the rest.
            let aArr = Array(a)
            let bArr = Array(b)
            var n = 0
            while n < bArr.count, (n < aArr.count ? aArr[n] : zero) == bArr[n] {
                n += 1
            }
            if n > 0 {
                let aRest = String(aArr[min(n, aArr.count)...])
                let bRest = String(bArr[n...])
                return String(bArr[0..<n]) + midpoint(aRest, bRest)
            }
        }

        let digitA = a.isEmpty ? 0 : indexOf[a.first!]!
        let digitB = b != nil ? indexOf[b!.first!]! : digits.count
        if digitB - digitA > 1 {
            let midDigit = Int((0.5 * Double(digitA + digitB)).rounded())
            return String(digits[midDigit])
        } else {
            if let b, b.count > 1 {
                return String(b.first!)
            } else {
                let aRest = a.isEmpty ? "" : String(a.dropFirst())
                return String(digits[digitA]) + midpoint(aRest, nil)
            }
        }
    }

    /// The length of the variable-length integer header that begins with `head`.
    static func getIntegerLength(_ head: Character) -> Int {
        guard let value = head.asciiValue else {
            preconditionFailure("invalid order key head: \(head)")
        }
        if head >= "a", head <= "z" {
            return Int(value - Character("a").asciiValue!) + 2
        } else if head >= "A", head <= "Z" {
            return Int(Character("Z").asciiValue! - value) + 2
        }
        preconditionFailure("invalid order key head: \(head)")
    }

    static func getIntegerPart(_ key: String) -> String {
        let length = getIntegerLength(key.first!)
        precondition(length <= key.count, "invalid order key: \(key)")
        return String(key.prefix(length))
    }

    /// Returns the next integer header after `x`, or `nil` if `x` is the maximum.
    static func incrementInteger(_ x: String) -> String? {
        let chars = Array(x)
        let head = chars[0]
        var digs = Array(chars.dropFirst())
        var carry = true
        var i = digs.count - 1
        while carry, i >= 0 {
            let d = indexOf[digs[i]]! + 1
            if d == digits.count {
                digs[i] = digits[0]
            } else {
                digs[i] = digits[d]
                carry = false
            }
            i -= 1
        }
        if carry {
            if head == "Z" { return "a" + String(digits[0]) }
            if head == "z" { return nil }
            let h = Character(UnicodeScalar(head.asciiValue! + 1))
            if h > "a" {
                digs.append(digits[0])
            } else {
                digs.removeLast()
            }
            return String(h) + String(digs)
        }
        return String(head) + String(digs)
    }

    /// Returns the previous integer header before `x`, or `nil` if `x` is the minimum.
    static func decrementInteger(_ x: String) -> String? {
        let chars = Array(x)
        let head = chars[0]
        var digs = Array(chars.dropFirst())
        var borrow = true
        var i = digs.count - 1
        while borrow, i >= 0 {
            let d = indexOf[digs[i]]! - 1
            if d == -1 {
                digs[i] = digits[digits.count - 1]
            } else {
                digs[i] = digits[d]
                borrow = false
            }
            i -= 1
        }
        if borrow {
            if head == "a" { return "Z" + String(digits[digits.count - 1]) }
            if head == "A" { return nil }
            let h = Character(UnicodeScalar(head.asciiValue! - 1))
            if h < "Z" {
                digs.append(digits[digits.count - 1])
            } else {
                digs.removeLast()
            }
            return String(h) + String(digs)
        }
        return String(head) + String(digs)
    }
}
