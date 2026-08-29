import CryptoKit
import Foundation
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
        guard let source = UIImage(data: data) else { throw WordImageError.invalidImage }
        let key = SHA256.hash(data: Data(wordID.utf8)).map { String(format: "%02x", $0) }.joined()
        let originalURL = originalsDirectory.appendingPathComponent("\(key).jpg")
        let thumbnailURL = thumbnailsDirectory.appendingPathComponent("\(key).jpg")
        let original = Self.resized(source, maximumDimension: 1_800, cropSquare: false)
        let thumbnail = Self.resized(source, maximumDimension: 240, cropSquare: true)
        guard let originalData = original.jpegData(compressionQuality: 0.84),
              let thumbnailData = thumbnail.jpegData(compressionQuality: 0.78) else {
            throw WordImageError.encodingFailed
        }
        try originalData.write(to: originalURL, options: .atomic)
        try thumbnailData.write(to: thumbnailURL, options: .atomic)
        return WordImageRecord(originalPath: originalURL.path, thumbnailPath: thumbnailURL.path)
    }

    func delete(_ record: WordImageRecord) throws {
        for path in [record.originalPath, record.thumbnailPath] where fileManager.fileExists(atPath: path) {
            try fileManager.removeItem(atPath: path)
        }
    }

    private static func resized(_ image: UIImage, maximumDimension: CGFloat, cropSquare: Bool) -> UIImage {
        let sourceSize = image.size
        let targetSize: CGSize
        let drawRect: CGRect
        if cropSquare {
            targetSize = CGSize(width: maximumDimension, height: maximumDimension)
            let scale = max(maximumDimension / sourceSize.width, maximumDimension / sourceSize.height)
            let scaled = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
            drawRect = CGRect(
                x: (maximumDimension - scaled.width) / 2,
                y: (maximumDimension - scaled.height) / 2,
                width: scaled.width,
                height: scaled.height
            )
        } else {
            let scale = min(1, maximumDimension / max(sourceSize.width, sourceSize.height))
            targetSize = CGSize(width: sourceSize.width * scale, height: sourceSize.height * scale)
            drawRect = CGRect(origin: .zero, size: targetSize)
        }
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
