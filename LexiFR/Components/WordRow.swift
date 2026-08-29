import ImageIO
import SwiftUI
import UIKit

struct WordRow: View {
    let word: WordSummary

    var body: some View {
        HStack(spacing: 12) {
            if let path = word.thumbnailPath {
                LocalImage(path: path, maximumPixelSize: 240)
                    .frame(width: LexiStyle.thumbnailSize, height: LexiStyle.thumbnailSize)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(word.word)
                    .font(.body.weight(.medium))
                    .foregroundStyle(.primary)
                Text(word.partOfSpeech)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

struct LocalImage: View {
    let path: String
    var contentMode: ContentMode = .fill
    var maximumPixelSize: Int = 1_200
    @State private var image: Image?

    var body: some View {
        Group {
            if let image {
                image
                    .resizable()
                    .aspectRatio(contentMode: contentMode)
            } else {
                Rectangle().fill(.quaternary)
                    .overlay { ProgressView().controlSize(.small) }
            }
        }
        .task(id: "\(path)|\(maximumPixelSize)") {
            image = nil
            if let uiImage = await LocalImageLoader.shared.image(
                path: path,
                maximumPixelSize: maximumPixelSize
            ) {
                guard !Task.isCancelled else { return }
                image = Image(uiImage: uiImage)
            } else {
                image = nil
            }
        }
        .onDisappear { image = nil }
    }
}

private actor LocalImageLoader {
    static let shared = LocalImageLoader()

    private let cache = NSCache<NSString, UIImage>()

    init() {
        cache.countLimit = 16
        cache.totalCostLimit = 24 * 1_024 * 1_024
    }

    func image(path: String, maximumPixelSize: Int) -> UIImage? {
        guard !Task.isCancelled else { return nil }
        let key = "\(path)|\(maximumPixelSize)" as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let url = URL(fileURLWithPath: path)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: max(1, maximumPixelSize)
        ]
        guard let decoded = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              !Task.isCancelled else { return nil }
        let result = UIImage(cgImage: decoded)
        cache.setObject(result, forKey: key, cost: decoded.bytesPerRow * decoded.height)
        return result
    }
}
