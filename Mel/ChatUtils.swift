import SwiftUI
import UIKit
import UniformTypeIdentifiers
import ImageIO

func clamp(_ v: CGFloat, _ minV: CGFloat = 0, _ maxV: CGFloat = 1) -> CGFloat {
    return max(minV, min(maxV, v))
}

// Early downscale utility: cap longest side and compress to JPEG
func earlyDownscale(image: UIImage, maxDimension: CGFloat = 2048, quality: CGFloat = 0.82) -> Data? {
    let size = image.size
    guard size.width > 0, size.height > 0 else { return image.jpegData(compressionQuality: quality) ?? image.pngData() }
    let maxSide = max(size.width, size.height)
    let scale = min(1.0, maxDimension / maxSide)
    let target = CGSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
    let renderer = UIGraphicsImageRenderer(size: target)
    let scaled = renderer.image { _ in
        image.draw(in: CGRect(origin: .zero, size: target))
    }
    return scaled.jpegData(compressionQuality: quality) ?? image.pngData()
}

func earlyDownscale(data: Data, maxDimension: CGFloat = 2048, quality: CGFloat = 0.82) -> Data? {
    guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return data }
    var maxPixel = Int(maxDimension)
    if let props = CGImageSourceCopyPropertiesAtIndex(src, 0, nil) as? [CFString: Any] {
        let w = (props[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
        let h = (props[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
        if w > 0, h > 0 {
            let maxSide = max(w, h)
            let scale = min(1.0, Double(maxDimension) / maxSide)
            maxPixel = max(1, Int(maxSide * scale))
        }
    }
    let opts: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxPixel
    ]
    guard let cgThumb = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else {
        return data
    }
    let outData = CFDataCreateMutable(nil, 0)!
    guard let dest = CGImageDestinationCreateWithData(outData, UTType.jpeg.identifier as CFString, 1, nil) else {
        return data
    }
    let destOpts: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: quality]
    CGImageDestinationAddImage(dest, cgThumb, destOpts as CFDictionary)
    guard CGImageDestinationFinalize(dest) else { return data }
    return outData as Data
}

/// Courbe douce (cubic Hermite) pour éviter les à-coups visuels.
func smoothstep(_ x: CGFloat) -> CGFloat {
    let t = clamp(x)
    return t * t * (3 - 2 * t)
}

extension Animation {
    static var smoothCompat: Animation {
        if #available(iOS 17.0, *) {
            return .smooth(duration: 0.28, extraBounce: 0)
        } else {
            return .easeOut(duration: 0.28)
        }
    }
}

@inline(__always)
func scaleForDynamicType(_ size: DynamicTypeSize, base: CGFloat) -> CGFloat {
    switch size {
    case .xSmall: return base * 0.9
    case .small: return base * 0.95
    case .medium: return base * 1.0
    case .large: return base * 1.05
    case .xLarge: return base * 1.1
    case .xxLarge: return base * 1.15
    case .xxxLarge: return base * 1.2
    case .accessibility1: return base * 1.28
    case .accessibility2: return base * 1.36
    case .accessibility3: return base * 1.44
    case .accessibility4: return base * 1.54
    case .accessibility5: return base * 1.64
    @unknown default: return base * 1.0
    }
}
