import SwiftUI

// the app's own icons from the android svg paths, built once and never changed, so they're safe to share across threads
nonisolated struct VectorIcon: @unchecked Sendable {
    let viewBox: CGRect
    // every stroke is turned into a filled outline up front, so one shape fills the whole icon
    let path: CGPath

    enum Part {
        case fill(String)
        case stroke(String, width: CGFloat, round: Bool = false)
        case circleFill(x: CGFloat, y: CGFloat, r: CGFloat)
        case circleStroke(x: CGFloat, y: CGFloat, r: CGFloat, width: CGFloat)
        case line(x1: CGFloat, y1: CGFloat, x2: CGFloat, y2: CGFloat, width: CGFloat)
    }

    init(viewBox: CGRect, parts: [Part]) {
        self.viewBox = viewBox
        let combined = CGMutablePath()
        for part in parts {
            switch part {
            case .fill(let data):
                combined.addPath(SVGPath.parse(data))
            case .stroke(let data, let width, let round):
                combined.addPath(SVGPath.parse(data).copy(strokingWithWidth: width, lineCap: round ? .round : .butt, lineJoin: .round, miterLimit: 4))
            case .circleFill(let x, let y, let r):
                combined.addEllipse(in: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2))
            case .circleStroke(let x, let y, let r, let width):
                let circle = CGPath(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2), transform: nil)
                combined.addPath(circle.copy(strokingWithWidth: width, lineCap: .butt, lineJoin: .round, miterLimit: 4))
            case .line(let x1, let y1, let x2, let y2, let width):
                let line = CGMutablePath()
                line.move(to: CGPoint(x: x1, y: y1))
                line.addLine(to: CGPoint(x: x2, y: y2))
                combined.addPath(line.copy(strokingWithWidth: width, lineCap: .round, lineJoin: .round, miterLimit: 4))
            }
        }
        path = combined
    }
}

// an icon scaled into whatever frame it's given, keeping its proportions
nonisolated struct IconShape: Shape {
    let icon: VectorIcon

    func path(in rect: CGRect) -> Path {
        let box = icon.viewBox
        let scale = min(rect.width / box.width, rect.height / box.height)
        let offsetX = rect.minX + (rect.width - box.width * scale) / 2 - box.minX * scale
        let offsetY = rect.minY + (rect.height - box.height * scale) / 2 - box.minY * scale
        var transform = CGAffineTransform(translationX: offsetX, y: offsetY).scaledBy(x: scale, y: scale)
        guard let moved = icon.path.copy(using: &transform) else { return Path() }
        return Path(moved)
    }
}

// just enough of svg's path language for our icons: absolute m, l, h, v, c, q and z
nonisolated enum SVGPath {
    static func parse(_ data: String) -> CGPath {
        let path = CGMutablePath()
        var tokens = tokenize(data)[...]
        var command: Character = "M"
        var point = CGPoint.zero

        func number() -> CGFloat {
            guard case .number(let value)? = tokens.first else { return 0 }
            tokens.removeFirst()
            return value
        }
        func nextPoint() -> CGPoint { CGPoint(x: number(), y: number()) }

        while let token = tokens.first {
            if case .command(let letter) = token {
                command = letter
                tokens.removeFirst()
                if letter == "Z" || letter == "z" {
                    path.closeSubpath()
                    continue
                }
            }
            switch command {
            case "M":
                point = nextPoint()
                path.move(to: point)
                command = "L"
            case "L":
                point = nextPoint()
                path.addLine(to: point)
            case "H":
                point.x = number()
                path.addLine(to: point)
            case "V":
                point.y = number()
                path.addLine(to: point)
            case "C":
                let first = nextPoint(), second = nextPoint()
                point = nextPoint()
                path.addCurve(to: point, control1: first, control2: second)
            case "Q":
                let control = nextPoint()
                point = nextPoint()
                path.addQuadCurve(to: point, control: control)
            default:
                tokens.removeFirst()
            }
        }
        return path
    }

    private enum Token {
        case command(Character)
        case number(CGFloat)
    }

    private static func tokenize(_ data: String) -> [Token] {
        var tokens: [Token] = []
        var current = ""
        func flush() {
            if let value = Double(current) { tokens.append(.number(CGFloat(value))) }
            current = ""
        }
        for character in data {
            if character.isLetter && character != "e" {
                flush()
                tokens.append(.command(character))
            } else if character == " " || character == "," {
                flush()
            } else if character == "-" && !current.isEmpty && current.last != "e" {
                flush()
                current.append(character)
            } else if character == "." && current.contains(".") {
                flush()
                current = "."
            } else {
                current.append(character)
            }
        }
        flush()
        return tokens
    }
}

nonisolated extension VectorIcon {
    static let home = VectorIcon(viewBox: CGRect(x: 0, y: 0, width: 46, height: 46), parts: [
        .stroke("M7 44H15C15.5523 44 16 43.5523 16 43V30C16 27.2386 18.2386 25 21 25H25C27.7614 25 30 27.2386 30 30V43C30 43.5523 30.4477 44 31 44H39C41.7614 44 44 41.7614 44 39V16.1553C44 15.8119 43.8236 15.4927 43.5332 15.3096L25.667 4.04492C24.0377 3.01776 21.9623 3.01776 20.333 4.04492L2.4668 15.3096C2.17637 15.4927 2 15.8119 2 16.1553V39C2 41.7614 4.23858 44 7 44Z", width: 4),
    ])

    static let homeFilled = VectorIcon(viewBox: CGRect(x: 0, y: 0, width: 46, height: 46), parts: [
        .fill("M0 39C0 42.866 3.13401 46 7 46H12C13.6569 46 15 44.6569 15 43V30C15 28.3431 16.3431 27 18 27H27.5C29.1569 27 30.5 28.3431 30.5 30V43C30.5 44.6569 31.8431 46 33.5 46H39C42.866 46 46 42.866 46 39V16.1551C46 15.1249 45.4714 14.1667 44.5999 13.6173L26.7331 2.35348C24.4521 0.915455 21.5479 0.915451 19.2669 2.35348L1.4001 13.6173C0.528615 14.1667 0 15.1249 0 16.1551V39Z"),
    ])

    static let search = VectorIcon(viewBox: CGRect(x: 0, y: 0, width: 43, height: 44), parts: [
        .circleStroke(x: 17, y: 17, r: 14.5, width: 5),
        .line(x1: 28.5355, y1: 30, x2: 40, y2: 41.4645, width: 5),
    ])

    static let searchFilled = VectorIcon(viewBox: CGRect(x: 0, y: 0, width: 43, height: 44), parts: [
        .circleFill(x: 17, y: 17, r: 17),
        .line(x1: 15.5334, y1: 15.1218, x2: 40.1218, y2: 41.4666, width: 5),
    ])

    static let library = VectorIcon(viewBox: CGRect(x: 0, y: 0, width: 57, height: 51), parts: [
        .stroke("M45 4H18C13.5817 4 10 7.58172 10 12V39C10 43.4183 13.5817 47 18 47H45C49.4183 47 53 43.4183 53 39V12C53 7.58172 49.4183 4 45 4Z", width: 5),
        .line(x1: 2, y1: 10, x2: 2, y2: 43, width: 4),
        .fill("M22 31.5C22 28.4624 24.4624 26 27.5 26H29.5C32.5376 26 35 28.4624 35 31.5C35 34.5376 32.5376 37 29.5 37H27.5C24.4624 37 22 34.5376 22 31.5Z"),
        .fill("M31 17C31 15.8954 31.8954 15 33 15C34.1046 15 35 15.8954 35 17V30C35 31.1046 34.1046 32 33 32C31.8954 32 31 31.1046 31 30V17Z"),
        .fill("M31 17C31 15.8954 31.8954 15 33 15H39C40.1046 15 41 15.8954 41 17C41 18.1046 40.1046 19 39 19H33C31.8954 19 31 18.1046 31 17Z"),
    ])

    static let libraryFilled = VectorIcon(viewBox: CGRect(x: 0, y: 0, width: 57, height: 51), parts: [
        .line(x1: 2, y1: 10, x2: 2, y2: 43, width: 4),
        .fill("M45 0.5C51.3513 0.5 56.5 5.64873 56.5 12V39C56.5 45.3513 51.3513 50.5 45 50.5H18C11.6487 50.5 6.5 45.3513 6.5 39V12C6.5 5.64873 11.6487 0.5 18 0.5H45ZM33 15C31.8954 15 31 15.8954 31 17V26.208C30.5231 26.0731 30.0201 26 29.5 26H27.5C24.4624 26 22 28.4624 22 31.5C22 34.5376 24.4624 37 27.5 37H29.5C32.5376 37 35 34.5376 35 31.5C35 31.1796 34.9705 30.8659 34.918 30.5605C34.9699 30.3825 35 30.1948 35 30V19H39C40.1046 19 41 18.1046 41 17C41 15.8954 40.1046 15 39 15H33Z"),
    ])

    // the mochy mark, the android vector's group offset is folded into the view box
    static let mochy = VectorIcon(viewBox: CGRect(x: 55.67, y: 50.42, width: 135.16, height: 135.16), parts: [
        .stroke("M163.5 96.3493C180.167 105.972 180.167 130.028 163.5 139.651L108 171.694C91.3333 181.316 70.5 169.288 70.5 150.043V85.9569C70.5 66.7119 91.3333 54.6838 108 64.3063L163.5 96.3493Z", width: 19, round: true),
        .stroke("M97 112L108.5 98L120 112", width: 11, round: true),
        .stroke("M110.325 125C111.871 133.439 121.868 148.704 142.944 149.92", width: 11, round: true),
    ])
}
