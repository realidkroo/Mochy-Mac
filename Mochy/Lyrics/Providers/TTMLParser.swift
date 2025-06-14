import Foundation

// apple music's ttml (from better lyrics and paxsenix) into the app's lyrics format, with duet voices and backing vocals kept
nonisolated enum TTMLParser {
    private struct Span {
        let text: String
        let start: Double
        let end: Double
        let spaceAfter: Bool
    }

    private struct Line {
        let text: String
        let start: Double
        let words: [(text: String, start: Double, end: Double)]
        let agent: String?
        let backing: [Line]
    }

    static func toLRC(_ ttml: String) -> String? {
        // xmldocument throws away the spaces between spans, and those spaces are the only thing that says where a word ends
        let marked = ttml.replacingOccurrences(of: "</span>[ \\t\u{00A0}]+<span", with: "</span><ws/><span", options: .regularExpression)
        guard let document = try? XMLDocument(xmlString: marked, options: [.nodePreserveWhitespace]) else { return nil }
        let paragraphs = (try? document.nodes(forXPath: "//*[local-name()='p']")) ?? []
        var out = ""
        for case let paragraph as XMLElement in paragraphs {
            guard let line = parseLine(paragraph) else { continue }
            out += stamp(line.start) + (line.agent.map { "{agent:\($0)}" } ?? "") + line.text + "\n"
            if !line.words.isEmpty { out += wordLine(line.words) + "\n" }
            for backing in line.backing {
                out += stamp(backing.start) + "{bg}" + backing.text + "\n"
                if !backing.words.isEmpty { out += wordLine(backing.words) + "\n" }
            }
        }
        let trimmed = out.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func parseLine(_ element: XMLElement) -> Line? {
        guard let begin = element.attribute(forName: "begin")?.stringValue, !begin.isEmpty else { return nil }
        let start = time(begin)
        var spans: [Span] = []
        var backing: [Line] = []
        let children = element.children ?? []
        for (index, node) in children.enumerated() {
            guard let span = node as? XMLElement, span.localName == "span" else { continue }
            switch attribute(span, "role") {
            case "x-bg":
                if let line = parseBacking(span, parentStart: start) { backing.append(line) }
            case "x-translation", "x-roman":
                continue
            default:
                if let timed = timedSpan(span, next: children.indices.contains(index + 1) ? children[index + 1] : nil) {
                    spans.append(timed)
                }
            }
        }
        let words = merge(spans)
        var text = words.map(\.text).joined(separator: " ")
        if text.isEmpty { text = directText(element).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !text.isEmpty else { return nil }
        let agent = attribute(element, "agent")
        return Line(text: text, start: start, words: words, agent: agent?.isEmpty == false ? agent : nil, backing: backing)
    }

    private static func parseBacking(_ span: XMLElement, parentStart: Double) -> Line? {
        let start = span.attribute(forName: "begin")?.stringValue.map(time) ?? parentStart
        var spans: [Span] = []
        let children = span.children ?? []
        for (index, node) in children.enumerated() {
            guard let inner = node as? XMLElement, inner.localName == "span" else { continue }
            let role = attribute(inner, "role")
            if role == "x-translation" || role == "x-roman" { continue }
            if let timed = timedSpan(inner, next: children.indices.contains(index + 1) ? children[index + 1] : nil) {
                spans.append(timed)
            }
        }
        let words = merge(spans)
        var text = words.map(\.text).joined(separator: " ")
        if text.isEmpty { text = directText(span).trimmingCharacters(in: .whitespacesAndNewlines) }
        guard !text.isEmpty else { return nil }
        return Line(text: text, start: start, words: words, agent: nil, backing: [])
    }

    private static func timedSpan(_ span: XMLElement, next: XMLNode?) -> Span? {
        let text = (span.stringValue ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty,
              let begin = span.attribute(forName: "begin")?.stringValue, !begin.isEmpty,
              let end = span.attribute(forName: "end")?.stringValue, !end.isEmpty
        else { return nil }
        return Span(text: text, start: time(begin), end: time(end), spaceAfter: isWordBoundary(next))
    }

    // a span followed by a space on the same line ends a word, syllables sit flush against each other
    private static func isWordBoundary(_ node: XMLNode?) -> Bool {
        if let marker = node as? XMLElement, marker.localName == "ws" { return true }
        guard let node, node.kind == .text, let between = node.stringValue, !between.isEmpty else { return false }
        if between.contains("\n") || between.contains("\r") { return false }
        return between.contains { $0 == " " || $0 == "\t" || $0 == "\u{00A0}" }
    }

    private static func merge(_ spans: [Span]) -> [(text: String, start: Double, end: Double)] {
        var words: [(text: String, start: Double, end: Double)] = []
        var previous: Span?
        for span in spans {
            if let previous, !previous.spaceAfter, var last = words.popLast() {
                last.text += span.text
                last.end = span.end
                words.append(last)
            } else {
                words.append((span.text, span.start, span.end))
            }
            previous = span
        }
        return words
    }

    private static func directText(_ element: XMLElement) -> String {
        (element.children ?? []).map { node -> String in
            if node.kind == .text { return node.stringValue ?? "" }
            guard let child = node as? XMLElement, child.localName == "span" else { return "" }
            let role = attribute(child, "role")
            return ["x-bg", "x-translation", "x-roman"].contains(role) ? "" : child.stringValue ?? ""
        }.joined()
    }

    // ttm:agent and ttm:role, read by their local name whatever prefix the file uses
    private static func attribute(_ element: XMLElement, _ localName: String) -> String? {
        for attribute in element.attributes ?? [] {
            let name = attribute.name ?? ""
            if name == localName || name.hasSuffix(":" + localName) || attribute.localName == localName {
                return attribute.stringValue
            }
        }
        return nil
    }

    // "12.3", "1:02.345", "1:02:03.4" or "12.3s" into seconds
    private static func time(_ raw: String) -> Double {
        let value = raw.hasSuffix("s") && !raw.hasSuffix("ms") ? String(raw.dropLast()) : raw
        let parts = value.split(separator: ":").compactMap { Double($0) }
        switch parts.count {
        case 2: return parts[0] * 60 + parts[1]
        case 3: return parts[0] * 3600 + parts[1] * 60 + parts[2]
        default: return Double(value) ?? 0
        }
    }

    private static func stamp(_ seconds: Double) -> String {
        let ms = Int((seconds * 1000).rounded())
        return String(format: "[%02d:%02d.%02d]", ms / 60_000, ms / 1000 % 60, ms % 1000 / 10)
    }

    private static func wordLine(_ words: [(text: String, start: Double, end: Double)]) -> String {
        "<" + words.map { "\($0.text.filter { !":|<>".contains($0) }):\($0.start):\($0.end)" }.joined(separator: "|") + ">"
    }
}
