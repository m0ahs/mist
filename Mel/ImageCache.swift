//
//  ImageCache.swift
//  Mel
//

import Foundation
import UIKit
import CryptoKit

final class ImageCache {
    static let shared = ImageCache()

    private let uiImageCache = NSCache<NSString, UIImage>()
    private let compressedCache = NSCache<NSString, NSData>()
    private let thumbnailCache = NSCache<NSString, UIImage>()

    private init() {
        uiImageCache.countLimit = 256
        uiImageCache.totalCostLimit = 32 * 1024 * 1024 // ~32MB
        compressedCache.countLimit = 256
        compressedCache.totalCostLimit = 64 * 1024 * 1024 // ~64MB
        thumbnailCache.countLimit = 512
        thumbnailCache.totalCostLimit = 32 * 1024 * 1024 // ~32MB for small thumbs
    }

    // MARK: - Keys

    private func hash(_ data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.compactMap { String(format: "%02x", $0) }.joined()
    }

    private func compressedKey(for data: Data, config: AIConfig) -> NSString {
        let base = hash(data)
        let key = "cmp:\(base)|max:\(config.maxImageBytes)|q:\(String(format: "%.2f", Double(config.jpegQuality)))"
        return key as NSString
    }

    private func imageKey(for data: Data) -> NSString {
        ("img:" + hash(data)) as NSString
    }

    private func thumbKey(for data: Data, maxPixel: Int) -> NSString {
        ("thm:" + hash(data) + "|px:\(maxPixel)") as NSString
    }

    // MARK: - Public API

    func cachedImage(for data: Data) -> UIImage? {
        uiImageCache.object(forKey: imageKey(for: data))
    }

    func decodeImage(data: Data) -> UIImage? {
        if let cached = cachedImage(for: data) { return cached }
        guard let img = UIImage(data: data) else { return nil }
        uiImageCache.setObject(img, forKey: imageKey(for: data), cost: Int(img.size.width * img.size.height))
        return img
    }

    /// Decode a downsized thumbnail using ImageIO (thread-safe).
    func decodeThumbnail(data: Data, maxPixelSize: Int) -> UIImage? {
        let key = thumbKey(for: data, maxPixel: maxPixelSize)
        if let cached = thumbnailCache.object(forKey: key) { return cached }
        guard let src = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: max(32, maxPixelSize)
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        let img = UIImage(cgImage: cg)
        thumbnailCache.setObject(img, forKey: key, cost: cg.width * cg.height)
        return img
    }

    func compressedData(for data: Data, config: AIConfig) -> Data {
        let key = compressedKey(for: data, config: config)
        if let cached = compressedCache.object(forKey: key) { return cached as Data }
        let out = AIManager.compress(data, config: config)
        compressedCache.setObject(out as NSData, forKey: key, cost: out.count)
        return out
    }
}
