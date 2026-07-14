import Foundation

/// A dotted numeric version (e.g. `1.4.0`), tolerant of a leading `v` and of
/// pre-release/build suffixes. Comparison is numeric per component, with missing
/// trailing components treated as zero (`1.2` == `1.2.0`).
struct SemanticVersion: Comparable, Equatable {
    let components: [Int]

    init?(_ string: String) {
        var trimmed = string.trimmingCharacters(in: .whitespaces)
        if trimmed.first == "v" || trimmed.first == "V" {
            trimmed.removeFirst()
        }
        // Drop pre-release / build metadata: keep only the numeric "x.y.z" head.
        let core = trimmed.prefix { $0.isNumber || $0 == "." }
        let parsed = core.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard !parsed.isEmpty, parsed.allSatisfy({ $0 != nil }) else { return nil }
        components = parsed.compactMap { $0 }
    }

    static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }
}
