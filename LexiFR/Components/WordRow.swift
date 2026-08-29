import SwiftUI
import UIKit

struct WordRow: View {
    let word: WordSummary

    var body: some View {
        HStack(spacing: 12) {
            if let path = word.thumbnailPath {
                LocalImage(path: path)
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
        .task(id: path) {
            let data = await Task.detached(priority: .utility) { try? Data(contentsOf: URL(fileURLWithPath: path)) }.value
            if let data, let uiImage = UIImage(data: data) {
                image = Image(uiImage: uiImage)
            } else {
                image = nil
            }
        }
    }
}
