import CryptoKit
import Foundation
import ImageIO
import UIKit

actor WordImageStore {
    private let originalsDirectory: URL
    private let thumbnailsDirectory: URL
    private let fileManager: FileManager

    init(fileManager: FileManager = .default) throws {
        self.fileManager = fileManager
        let support = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = support.appendingPathComponent("LexiFR/WordImages", isDirectory: true)
        originalsDirectory = root.appendingPathComponent("originals", isDirectory: true)
        thumbnailsDirectory = root.appendingPathComponent("thumbnails", isDirectory: true)
        try fileManager.createDirectory(at: originalsDirectory, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: thumbnailsDirectory, withIntermediateDirectories: true)
    }

    func save(data: Data, wordID: String) throws -> WordImageRecord {
        try Task.checkCancellation()
        guard let source = Self.downsampledImage(data: data, maximumPixelSize: 1_800) else {
            throw WordImageError.invalidImage
        }
        let wordKey = SHA256.hash(data: Data(wordID.utf8)).map { String(format: "%02x", $0) }.joined()
        let contentKey = SHA256.hash(data: data).prefix(6).map { String(format: "%02x", $0) }.joined()
        let key = "\(wordKey)-\(contentKey)"
        let originalURL = originalsDirectory.appendingPathComponent("\(key).jpg")
        let thumbnailURL = thumbnailsDirectory.appendingPathComponent("\(key).jpg")
        let thumbnail = Self.squareThumbnail(source, dimension: 240)
        try Task.checkCancellation()
        guard let originalData = UIImage(cgImage: source).jpegData(compressionQuality: 0.84),
              let thumbnailData = thumbnail.jpegData(compressionQuality: 0.78) else {
            throw WordImageError.encodingFailed
        }
        try Task.checkCancellation()
        let originalAlreadyExisted = fileManager.fileExists(atPath: originalURL.path)
        let thumbnailAlreadyExisted = fileManager.fileExists(atPath: thumbnailURL.path)
        do {
            try originalData.write(to: originalURL, options: .atomic)
            try thumbnailData.write(to: thumbnailURL, options: .atomic)
        } catch {
            if !originalAlreadyExisted { try? fileManager.removeItem(at: originalURL) }
            if !thumbnailAlreadyExisted { try? fileManager.removeItem(at: thumbnailURL) }
            throw error
        }
        return WordImageRecord(originalPath: originalURL.path, thumbnailPath: thumbnailURL.path)
    }

    func delete(_ record: WordImageRecord) throws {
        for path in [record.originalPath, record.thumbnailPath] where fileManager.fileExists(atPath: path) {
            try fileManager.removeItem(atPath: path)
        }
    }

    private static func downsampledImage(data: Data, maximumPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maximumPixelSize
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func squareThumbnail(_ source: CGImage, dimension: CGFloat) -> UIImage {
        let image = UIImage(cgImage: source)
        let sourceSize = image.size
        let targetSize = CGSize(width: dimension, height: dimension)
        let scale = max(dimension / sourceSize.width, dimension / sourceSize.height)
        let scaled = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
        let drawRect = CGRect(
            x: (dimension - scaled.width) / 2,
            y: (dimension - scaled.height) / 2,
            width: scaled.width,
            height: scaled.height
        )
        let format = UIGraphicsImageRendererFormat.preferred()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: targetSize, format: format).image { _ in
            UIColor.systemBackground.setFill()
            UIRectFill(CGRect(origin: .zero, size: targetSize))
            image.draw(in: drawRect)
        }
    }
}

enum WordImageError: LocalizedError {
    case invalidImage
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidImage: "Cette image ne peut pas être lue."
        case .encodingFailed: "Cette image ne peut pas être enregistrée."
        }
    }
}
