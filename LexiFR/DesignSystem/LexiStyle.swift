import SwiftUI

enum LexiStyle {
    static let horizontalMargin: CGFloat = 20
    static let sectionSpacing: CGFloat = 28
    static let thumbnailSize: CGFloat = 48
}

struct SectionLabel: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .tracking(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityAddTraits(.isHeader)
    }
}
