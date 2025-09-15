import CoreGraphics
import SwiftUI

// four soft tones pulled from a cover, kept dark enough for white lyrics to read on top
nonisolated struct CoverPalette: Hashable, Sendable {
    // red, green, blue from 0 to 1, darkest first
    let tones: [SIMD3<Double>]

    static let fallback = CoverPalette(tones: [
        SIMD3(0.16, 0.10, 0.14), SIMD3(0.42, 0.20, 0.26), SIMD3(0.56, 0.30, 0.34), SIMD3(0.30, 0.16, 0.24),
    ])

    var colors: [Color] { tones.map { Color(red: $0.x, green: $0.y, blue: $0.z) } }
    var deep: Color { colors[0] }
    var accent: Color { colors[2] }

    func tone(_ index: Int) -> Color { colors[index % colors.count] }

    static func extract(from image: DecodedImage) async -> CoverPalette {
        await Task.detached(priority: .utility) { compute(image.cgImage) }.value
    }

    // the most common lively colours of a tiny copy of the cover, nudged into a calm, dim range
    private static func compute(_ image: CGImage) -> CoverPalette {
        let side = 24
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        let drawn = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.interpolationQuality = .medium
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drawn else { return .fallback }

        struct Bucket { var sum = SIMD3<Double>(0, 0, 0); var count = 0.0; var weight = 0.0 }
        var buckets: [Int: Bucket] = [:]
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let rgb = SIMD3(Double(pixels[index]), Double(pixels[index + 1]), Double(pixels[index + 2])) / 255
            let (hue, saturation, brightness) = hsb(rgb)
            let key = Int(hue * 12) % 12 * 4 + (saturation > 0.35 ? 2 : 0) + (brightness > 0.5 ? 1 : 0)
            var bucket = buckets[key, default: Bucket()]
            bucket.sum += rgb
            bucket.count += 1
            // lively colours count for more, near black and near white barely count
            bucket.weight += (0.25 + saturation) * (brightness < 0.1 || (saturation < 0.08 && brightness > 0.92) ? 0.15 : 1)
            buckets[key] = bucket
        }
        let ranked = buckets.values.sorted { $0.weight > $1.weight }.map { $0.sum / $0.count }
        var picked: [SIMD3<Double>] = []
        for color in ranked where picked.count < 4 {
            let (hue, _, brightness) = hsb(color)
            let distinct = picked.allSatisfy { other in
                let (otherHue, _, otherBrightness) = hsb(other)
                let hueGap = min(abs(hue - otherHue), 1 - abs(hue - otherHue))
                return hueGap > 0.06 || abs(brightness - otherBrightness) > 0.25
            }
            if distinct { picked.append(color) }
        }
        if picked.isEmpty { return .fallback }
        while picked.count < 4 { picked.append(picked[picked.count % max(picked.count, 1)] * (picked.count.isMultiple(of: 2) ? 0.7 : 1.25)) }

        let toned = picked.enumerated().map { offset, color -> SIMD3<Double> in
            let (hue, saturation, brightness) = hsb(color)
            let targets = [0.22, 0.42, 0.56, 0.34]
            let tunedBrightness = targets[offset] * 0.6 + min(brightness, 0.7) * 0.4
            return rgbFrom(hue: hue, saturation: min(saturation * 1.1, 0.72), brightness: tunedBrightness)
        }
        return CoverPalette(tones: toned.sorted { luminance($0) < luminance($1) }.reorderedForPools())
    }

    private static func luminance(_ c: SIMD3<Double>) -> Double { 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z }

    private static func hsb(_ c: SIMD3<Double>) -> (Double, Double, Double) {
        let maxValue = max(c.x, c.y, c.z), minValue = min(c.x, c.y, c.z)
        let delta = maxValue - minValue
        var hue = 0.0
        if delta > 0 {
            if maxValue == c.x { hue = ((c.y - c.z) / delta).truncatingRemainder(dividingBy: 6) }
            else if maxValue == c.y { hue = (c.z - c.x) / delta + 2 }
            else { hue = (c.x - c.y) / delta + 4 }
            hue /= 6
            if hue < 0 { hue += 1 }
        }
        return (hue, maxValue == 0 ? 0 : delta / maxValue, maxValue)
    }

    private static func rgbFrom(hue: Double, saturation: Double, brightness: Double) -> SIMD3<Double> {
        let h = hue * 6
        let c = brightness * saturation
        let x = c * (1 - abs(h.truncatingRemainder(dividingBy: 2) - 1))
        let m = brightness - c
        let rgb: SIMD3<Double> = switch Int(h) % 6 {
        case 0: SIMD3(c, x, 0)
        case 1: SIMD3(x, c, 0)
        case 2: SIMD3(0, c, x)
        case 3: SIMD3(0, x, c)
        case 4: SIMD3(x, 0, c)
        default: SIMD3(c, 0, x)
        }
        return rgb + SIMD3(repeating: m)
    }
}

private extension Array where Element == SIMD3<Double> {
    // darkest, two brighter pools, then a middle one, the order the ambient shader spreads them in
    nonisolated func reorderedForPools() -> [SIMD3<Double>] {
        guard count == 4 else { return self }
        return [self[0], self[2], self[3], self[1]]
    }
}
