import Foundation

public struct ReferenceImage: Codable, Equatable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let png: Data

    public init(id: String = UUID().uuidString, name: String, png: Data) {
        self.id = id
        self.name = name
        self.png = png
    }
}

public enum RequestPart: Codable, Equatable, Sendable {
    case text(String)
    case image(ReferenceImage)
}

public struct RequestDocument: Codable, Equatable, Sendable {
    public var parts: [RequestPart]

    public init(text: String = "") { parts = text.isEmpty ? [] : [.text(text)] }
    public init(parts: [RequestPart]) { self.parts = parts }

    public var images: [ReferenceImage] {
        parts.compactMap { if case .image(let image) = $0 { return image }; return nil }
    }

    public var plainText: String {
        var imageNumber = 0
        return parts.map { part in
            switch part {
            case .text(let text): return text
            case .image:
                imageNumber += 1
                return "[Image \(imageNumber)]"
            }
        }.joined()
    }

    public var isEmpty: Bool { plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    public func validate() throws {
        guard !isEmpty, plainText.count <= 4000 else { throw PressError.message("Enter a request of 1–4,000 characters.") }
        guard images.count <= 8 else { throw PressError.message("You can add up to 8 images per request.") }
        guard Set(images.map(\.id)).count == images.count else { throw PressError.message("Duplicate image references found. Add the images again.") }
        let pngSignature = Data([137, 80, 78, 71, 13, 10, 26, 10])
        guard images.allSatisfy({ !$0.id.isEmpty && $0.png.starts(with: pngSignature) && $0.png.count <= 4_000_000 }),
              images.reduce(0, { $0 + $1.png.count }) <= 16_000_000 else {
            throw PressError.message("This image is unreadable or too large. Crop it to the button you want to click.")
        }
    }
}
