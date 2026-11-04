import Foundation
import CoreGraphics
import PressIfCore

public struct ImageMatch: Sendable {
    public let normalizedRect: CGRect
    public let score: Double
}

public enum ImageSearch {
    public static func matches(reference: CGImage, screen: CGImage) throws -> [ImageMatch] {
        let reduction = min(1, 720 / Double(screen.width))
        let scene = try Raster(image: screen, width: Int(Double(screen.width) * reduction), height: Int(Double(screen.height) * reduction))
        let original = try Raster(image: screen, width: screen.width, height: screen.height)
        var findings: [ImageMatch] = []
        for factor in [0.5, 0.75, 1.0, 1.25, 1.5, 2.0] {
            try Task.checkCancellation()
            let width = Int((Double(reference.width) * reduction * factor).rounded())
            let height = Int((Double(reference.height) * reduction * factor).rounded())
            guard width >= 5, height >= 5, width < scene.width, height < scene.height,
                  Double(width * height) < Double(scene.width * scene.height) * 0.65 else { continue }
            let template = try Raster(image: reference, width: width, height: height)
            let points = template.samplePoints()
            guard points.count >= 16, template.variance(points) > 30 else { continue }
            let stride = min(3, max(1, min(width, height) / 20))
            var coarse: [(x: Int, y: Int, error: Double)] = []
            for y in Swift.stride(from: 0, through: scene.height - height, by: stride) {
                if y % 32 == 0 { try Task.checkCancellation() }
                for x in Swift.stride(from: 0, through: scene.width - width, by: stride) {
                    let error = scene.sampleError(template: template, points: points, x: x, y: y)
                    if error < 22 {
                        coarse.append((x, y, error))
                        if coarse.count >= 160 { coarse.sort { $0.error < $1.error }; coarse.removeLast(80) }
                    }
                }
            }
            coarse.sort { $0.error < $1.error }
            let nativeWidth = Int((Double(reference.width) * factor).rounded())
            let nativeHeight = Int((Double(reference.height) * factor).rounded())
            guard nativeWidth < original.width, nativeHeight < original.height else { continue }
            let nativeTemplate = try Raster(image: reference, width: nativeWidth, height: nativeHeight)
            let nativePoints = nativeTemplate.samplePoints()
            let radius = Int(ceil(Double(stride) / reduction)) + 2
            var refined: [(x: Int, y: Int)] = []
            for candidate in coarse.prefix(60) {
                try Task.checkCancellation()
                let preview = scene.compare(template: template, x: candidate.x, y: candidate.y)
                guard preview.correlation >= 0.75, preview.error <= 22 else { continue }
                guard !refined.contains(where: { abs($0.x - candidate.x) < max(1, width / 4) && abs($0.y - candidate.y) < max(1, height / 4) }) else { continue }
                refined.append((candidate.x, candidate.y))
                let centerX = Int((Double(candidate.x) / reduction).rounded())
                let centerY = Int((Double(candidate.y) / reduction).rounded())
                for y in max(0, centerY - radius)...min(original.height - nativeHeight, centerY + radius) {
                    try Task.checkCancellation()
                    for x in max(0, centerX - radius)...min(original.width - nativeWidth, centerX + radius) {
                        guard original.sampleError(template: nativeTemplate, points: nativePoints, x: x, y: y) < 22 else { continue }
                        let quality = original.compare(template: nativeTemplate, x: x, y: y)
                        guard quality.correlation >= 0.975, quality.error <= 15 else { continue }
                        let rectangle = CGRect(x: Double(x) / Double(original.width), y: Double(y) / Double(original.height), width: Double(nativeWidth) / Double(original.width), height: Double(nativeHeight) / Double(original.height))
                        let match = ImageMatch(normalizedRect: rectangle, score: quality.correlation - quality.error / 510)
                        insert(match, into: &findings)
                    }
                }
            }
        }
        return findings.sorted { $0.score > $1.score }
    }

    private static func insert(_ match: ImageMatch, into findings: inout [ImageMatch]) {
        if let index = findings.firstIndex(where: { existing in
            let overlap = existing.normalizedRect.intersection(match.normalizedRect)
            let area = min(existing.normalizedRect.width * existing.normalizedRect.height, match.normalizedRect.width * match.normalizedRect.height)
            return !overlap.isNull && overlap.width * overlap.height / area > 0.45
        }) {
            if match.score > findings[index].score { findings[index] = match }
        } else {
            findings.append(match)
        }
    }
}

private struct Raster {
    let width: Int
    let height: Int
    let bytes: [UInt8]

    init(image: CGImage, width: Int, height: Int) throws {
        self.width = width
        self.height = height
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let succeeded = bytes.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard succeeded else { throw PressError.message("Could not prepare the screen for image search.") }
        self.bytes = bytes
    }

    func samplePoints() -> [(x: Int, y: Int)] {
        var result: [(Int, Int)] = []
        for row in 0..<10 {
            for column in 0..<10 {
                let x = min(width - 1, (2 * column + 1) * width / 20)
                let y = min(height - 1, (2 * row + 1) * height / 20)
                if bytes[(y * width + x) * 4 + 3] >= 245 { result.append((x, y)) }
            }
        }
        return result
    }

    func variance(_ points: [(x: Int, y: Int)]) -> Double {
        let values = points.map { gray(($0.y * width + $0.x) * 4) }
        let mean = values.reduce(0, +) / Double(values.count)
        return values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(values.count)
    }

    func sampleError(template: Raster, points: [(x: Int, y: Int)], x: Int, y: Int) -> Double {
        var total = 0.0
        for point in points {
            let expected = (point.y * template.width + point.x) * 4
            let actual = ((point.y + y) * width + point.x + x) * 4
            total += abs(Double(bytes[actual]) - Double(template.bytes[expected]))
            total += abs(Double(bytes[actual + 1]) - Double(template.bytes[expected + 1]))
            total += abs(Double(bytes[actual + 2]) - Double(template.bytes[expected + 2]))
            if total > Double(points.count) * 3 * 22 { return 255 }
        }
        return total / Double(points.count * 3)
    }

    func compare(template: Raster, x: Int, y: Int) -> (correlation: Double, error: Double) {
        var count = 0.0
        var a = 0.0, b = 0.0, aa = 0.0, bb = 0.0, ab = 0.0, error = 0.0
        let stride = max(1, min(template.width, template.height) / 80)
        for row in Swift.stride(from: 0, to: template.height, by: stride) {
            for column in Swift.stride(from: 0, to: template.width, by: stride) {
                let expected = (row * template.width + column) * 4
                guard template.bytes[expected + 3] >= 245 else { continue }
                let actual = ((row + y) * width + column + x) * 4
                let first = template.gray(expected), second = gray(actual)
                a += first; b += second; aa += first * first; bb += second * second; ab += first * second
                error += abs(Double(bytes[actual]) - Double(template.bytes[expected]))
                error += abs(Double(bytes[actual + 1]) - Double(template.bytes[expected + 1]))
                error += abs(Double(bytes[actual + 2]) - Double(template.bytes[expected + 2]))
                count += 1
            }
        }
        guard count >= 16 else { return (0, 255) }
        let denominator = sqrt(max(0, (aa - a * a / count) * (bb - b * b / count)))
        return (denominator > 0.001 ? (ab - a * b / count) / denominator : 0, error / (count * 3))
    }

    private func gray(_ offset: Int) -> Double {
        Double(bytes[offset]) * 0.299 + Double(bytes[offset + 1]) * 0.587 + Double(bytes[offset + 2]) * 0.114
    }
}
