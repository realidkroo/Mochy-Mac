import Foundation

// youtube's answers are deep, loose trees, so we walk them by key instead of decoding a type for every renderer
nonisolated struct JSON: @unchecked Sendable {
    let raw: Any?

    init(_ raw: Any?) {
        self.raw = raw is NSNull ? nil : raw
    }

    init(data: Data) throws {
        self.init(try JSONSerialization.jsonObject(with: data))
    }

    subscript(key: String) -> JSON {
        JSON((raw as? [String: Any])?[key])
    }

    subscript(index: Int) -> JSON {
        guard let list = raw as? [Any], list.indices.contains(index) else { return JSON(nil) }
        return JSON(list[index])
    }

    var exists: Bool { raw != nil }
    var array: [JSON] { (raw as? [Any])?.map(JSON.init) ?? [] }
    var first: JSON { self[0] }
    var last: JSON { array.last ?? JSON(nil) }
    var string: String? { raw as? String }
    var bool: Bool? { (raw as? NSNumber)?.boolValue }

    var int: Int? {
        if let number = raw as? NSNumber { return number.intValue }
        return (raw as? String).flatMap { Int($0) }
    }

    var double: Double? {
        if let number = raw as? NSNumber { return number.doubleValue }
        return (raw as? String).flatMap { Double($0) }
    }

    // the first child that has the key, handy for lists of one-key wrappers like contents[].musicShelfRenderer
    func firstChild(_ key: String) -> JSON {
        array.first { $0[key].exists }?[key] ?? JSON(nil)
    }

    func children(_ key: String) -> [JSON] {
        array.compactMap { $0[key].exists ? $0[key] : nil }
    }
}
