import AppKit
import CoreImage
import CoreImage.CIFilterBuiltins

/// Génère un QR code (image nette, non interpolée) à partir d'une chaîne.
/// 100 % natif via CIQRCodeGenerator — aucune dépendance.
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
