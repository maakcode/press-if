import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
import PressIfCore

public enum ImageImport {
    public static func reference(data: Data, name: String) throws -> ReferenceImage {
        guard data.count <= 30_000_000, let source = CGImageSourceCreateWithData(data as CFData, nil) else {
            throw PressError.message("Could not read this image. Choose a PNG, JPEG, HEIC or another supported image file.")
        }
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 1024, kCGImageSourceCreateThumbnailWithTransform: true]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary), image.width >= 8, image.height >= 8 else {
            throw PressError.message("The image is too small or damaged. Capture the button again.")
        }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else {
            throw PressError.message("Could not convert the image.")
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination), output.length <= 4_000_000 else {
            throw PressError.message("The image is too large. Crop it to the button you want to click.")
        }
        return ReferenceImage(name: name, png: output as Data)
    }

    public static func decode(_ png: Data) throws -> CGImage {
        guard let source = CGImageSourceCreateWithData(png as CFData, nil), let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PressError.message("Could not read the saved button image.")
        }
        return image
    }
}
