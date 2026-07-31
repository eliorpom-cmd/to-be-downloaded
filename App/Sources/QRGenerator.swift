// TBD — To be downloaded. Copyright (C) 2026 Elior Pommier.
// Licensed under the GNU AGPL v3 or later. See LICENSE and NOTICE.
import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Generate a QR code (sharp, uninterpolated image) from a string.
/// 100% native via CIQRCodeGenerator — no dependencies.
enum QRGenerator {
    static func image(from string: String, size: CGFloat = 240) -> NSImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(string.utf8)
        filter.correctionLevel = "M"

        guard let output = filter.outputImage, output.extent.width > 0 else { return nil }

        let scale = size / output.extent.width
        let scaled = output.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        let rep = NSCIImageRep(ciImage: scaled)
        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return image
    }
}
