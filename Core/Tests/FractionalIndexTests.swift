import Foundation
import Testing

@testable import SyncThingsCore

/// Deterministic PRNG so the fuzz tests are reproducible across runs.
private struct SeededGenerator: RandomNumberGenerator {
    var state: UInt64
    init(seed: UInt64) { self.state = seed }
    mutating func next() -> UInt64 {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return state
    }
}

@Suite struct FractionalIndexTests {
    // MARK: - Known vectors (faithful to the reference `fractional-indexing` impl)

    @Test func firstKeyIsA0() {
        #expect(FractionalIndex.keyBetween(nil, nil) == "a0")
    }

    @Test func appendIncrementsIntegerPart() {
        #expect(FractionalIndex.keyBetween("a0", nil) == "a1")
        #expect(FractionalIndex.keyBetween("a1", nil) == "a2")
    }

    @Test func prependDecrementsIntegerPart() {
        #expect(FractionalIndex.keyBetween(nil, "a0") == "Zz")
        #expect(FractionalIndex.keyBetween(nil, "Zz") == "Zy")
    }

    @Test func betweenAdjacentKeysAddsFractionalPart() {
        #expect(FractionalIndex.keyBetween("a0", "a1") == "a0V")
        #expect(FractionalIndex.keyBetween("a0", "a0V") == "a0G")
    }

    // MARK: - Invariants

    @Test func tiesDegradeGracefullyInsteadOfTrapping() {
        // Equal bounds (e.g. a concurrent-sync tie) must not crash; the result
        // sorts after the lower bound rather than strictly between.
        let key = FractionalIndex.keyBetween("a1", "a1")
        #expect(key > "a1")
    }

    @Test func emptyStringBoundsAreTreatedAsNil() {
        // An empty `rank` is "no position" (the column default), not a real key.
        // Records can arrive empty from older data or iCloud sync; treating "" as
        // a bound must behave like `nil` rather than trapping in `getIntegerPart`.
        #expect(FractionalIndex.keyBetween("", nil) == "a0") // append after all-empty
        #expect(FractionalIndex.keyBetween(nil, "") == "a0") // prepend before empty
        #expect(FractionalIndex.keyBetween("", "") == "a0") // both empty
        // A real lower bound with an empty upper bound appends after it, and the
        // result sorts after any empty-rank record (since "" sorts first).
        let afterReal = FractionalIndex.keyBetween("a0", "")
        #expect(afterReal == "a1")
        #expect(afterReal > "")
    }

    @Test func malformedBoundsAreTreatedAsNil() {
        // A bound that isn't a well-formed key (foreign data from an older app
        // version over iCloud sync) must be ignored like `nil` rather than trap
        // deep inside the parser. Each of these would previously have hit a
        // `preconditionFailure`/force-unwrap on a different code path:
        let malformed = [
            "!",   // invalid integer head (not A-Z/a-z)
            "5",   // digit head — also not a valid header char
            "a",   // valid head but too short for the header it announces
            "a$",  // valid head, but '$' isn't in the base-62 alphabet
            "a0G0" // valid prefix but a trailing zero in the fractional part
        ]
        for key in malformed {
            #expect(!FractionalIndex.isValidKey(key))
            // Treated as "no position": behaves exactly like the `nil` bound.
            #expect(FractionalIndex.keyBetween(key, nil) == FractionalIndex.keyBetween(nil, nil))
            #expect(FractionalIndex.keyBetween(nil, key) == FractionalIndex.keyBetween(nil, nil))
            let afterReal = FractionalIndex.keyBetween("a0", key)
            #expect(afterReal == FractionalIndex.keyBetween("a0", nil))
        }
    }

    @Test func generatedKeysAreAlwaysValid() {
        // Whatever the algorithm emits must round-trip as valid — otherwise a
        // generated key fed back as a bound would be wrongly discarded.
        var rng = SeededGenerator(seed: 0xF00D_CAFE)
        var keys: [String] = []
        for _ in 0..<2000 {
            let i = keys.isEmpty ? 0 : Int.random(in: 0...keys.count, using: &rng)
            let lo = i > 0 ? keys[i - 1] : nil
            let hi = i < keys.count ? keys[i] : nil
            let key = FractionalIndex.keyBetween(lo, hi)
            #expect(FractionalIndex.isValidKey(key))
            keys.insert(key, at: i)
        }
    }

    @Test func appendingStaysShort() {
        var keys: [String] = []
        var last: String?
        for _ in 0..<1000 {
            let key = FractionalIndex.keyBetween(last, nil)
            keys.append(key)
            last = key
        }
        // Strictly increasing, all distinct.
        #expect(keys == keys.sorted())
        #expect(Set(keys).count == keys.count)
        // The integer-part header keeps append keys compact (no unbounded growth).
        #expect(keys.map(\.count).max()! <= 4)
    }

    @Test func repeatedInsertionAtSameSpotNeverLosesPrecision() {
        // The classic Double-precision failure: insert between the same two
        // neighbors hundreds of times. String keys must keep finding room.
        let lo = FractionalIndex.keyBetween(nil, nil)
        var hi = FractionalIndex.keyBetween(lo, nil)
        for _ in 0..<500 {
            let mid = FractionalIndex.keyBetween(lo, hi)
            #expect(mid > lo)
            #expect(mid < hi)
            hi = mid
        }
    }

    @Test func fuzzRandomInsertionsStayStrictlyOrdered() {
        var rng = SeededGenerator(seed: 0xDEAD_BEEF)
        var keys: [String] = []
        for _ in 0..<2000 {
            let i = keys.isEmpty ? 0 : Int.random(in: 0...keys.count, using: &rng)
            let lo = i > 0 ? keys[i - 1] : nil
            let hi = i < keys.count ? keys[i] : nil
            let key = FractionalIndex.keyBetween(lo, hi)
            keys.insert(key, at: i)
        }
        // The list stays strictly sorted and collision-free no matter where we
        // inserted — which is the whole point.
        #expect(keys == keys.sorted())
        #expect(Set(keys).count == keys.count)
    }
}
