import PhotosUI
import SwiftUI

struct WordDetailView: View {
    let summary: WordSummary
    @EnvironmentObject private var app: AppModel
    @Environment(\.openURL) private var openURL
    @StateObject private var viewModel = WordDetailViewModel()
    @State private var photoItem: PhotosPickerItem?
    @State private var showingCollections = false

    var body: some View {
        ScrollView {
            if viewModel.isLoading {
                ProgressView().padding(.top, 80)
            } else if let entry = viewModel.entry {
                LazyVStack(alignment: .leading, spacing: LexiStyle.sectionSpacing) {
                    header(entry)
                    personalImage
                    definitions(entry)
                    relationSections(entry.relationSections)
                    forms(entry)
                    if let etymology = entry.etymology, !etymology.isEmpty {
                        section(title: "Étymologie") {
                            Text(etymology).font(.body).textSelection(.enabled)
                        }
                    }
                    actions(entry)
                }
                .id(entry.id)
                .padding(.horizontal, LexiStyle.horizontalMargin)
                .padding(.vertical, 18)
            } else {
                ContentUnavailableView(
                    "Entrée introuvable",
                    systemImage: "doc.text.magnifyingglass",
                    description: Text("La base du dictionnaire ne contient plus cette entrée.")
                )
                .padding(.top, 60)
            }
        }
        .background(Color(uiColor: .systemBackground))
        .navigationTitle(summary.word)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button(action: viewModel.toggleFavorite) {
                    Image(systemName: viewModel.isFavorite ? "heart.fill" : "heart")
                }
                .disabled(viewModel.isLoading || viewModel.entry == nil)
                .accessibilityLabel(viewModel.isFavorite ? "Retirer des favoris" : "Ajouter aux favoris")
                Button { showingCollections = true } label: {
                    Image(systemName: "square.stack.badge.plus")
                }
                .disabled(viewModel.isLoading || viewModel.entry == nil)
                .accessibilityLabel("Gérer les collections")
            }
        }
        .task(id: summary.id) {
            await viewModel.load(
                summary: summary,
                dictionary: app.dictionary,
                userStore: app.userStore,
                imageStore: app.imageStore
            )
        }
        .onChange(of: photoItem) { _, item in viewModel.importPhoto(item) }
        .sheet(isPresented: $showingCollections) {
            CollectionPickerSheet(viewModel: viewModel)
                .presentationDetents([.medium, .large])
        }
        .alert("Une erreur est survenue", isPresented: Binding(
            get: { viewModel.errorMessage != nil },
            set: { if !$0 { viewModel.errorMessage = nil } }
        )) { Button("OK", role: .cancel) {} } message: {
            Text(viewModel.errorMessage ?? "")
        }
    }

    private func header(_ entry: WordEntry) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(entry.word)
                .font(.system(.largeTitle, design: .serif, weight: .semibold))
                .minimumScaleFactor(0.75)
                .textSelection(.enabled)
            HStack(spacing: 8) {
                Text(entry.partOfSpeech)
                if let gender = entry.gender { Text("·"); Text(localizedGender(gender)) }
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            if !entry.pronunciations.isEmpty {
                Text(entry.pronunciations.map(\.ipa).joined(separator: "  ·  "))
                    .font(.body.monospaced())
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var personalImage: some View {
        if let image = viewModel.image {
            VStack(alignment: .leading, spacing: 10) {
                LocalImage(path: image.originalPath, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .frame(maxHeight: 330)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .accessibilityLabel("Image personnelle du mot")
                HStack {
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Label("Remplacer", systemImage: "photo.badge.arrow.down")
                    }
                    Spacer()
                    Button("Supprimer", role: .destructive, action: viewModel.deletePhoto)
                }
                .font(.subheadline)
            }
        }
    }

    private func definitions(_ entry: WordEntry) -> some View {
        ProgressiveDefinitionsView(senses: entry.senses)
    }

    @ViewBuilder
    private func relationSections(_ sections: [WordRelationSection]) -> some View {
        ForEach(sections) { relationSection in
            ProgressiveRelationSection(section: relationSection)
        }
    }

    @ViewBuilder
    private func forms(_ entry: WordEntry) -> some View {
        if !entry.forms.isEmpty {
            ProgressiveFormsView(forms: entry.forms)
        }
    }

    private func actions(_ entry: WordEntry) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            if viewModel.image == nil {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Label("Ajouter une image personnelle", systemImage: "photo.badge.plus")
                }
            }
            if let url = GoogleImagesService.url(for: entry.word) {
                Button { openURL(url) } label: {
                    Label("Voir sur Google Images", systemImage: "safari")
                }
            }
            if let definition = entry.senses.first?.definition {
                ShareLink(item: "\(entry.word) — \(definition)") {
                    Label("Partager le mot", systemImage: "square.and.arrow.up")
                }
            }
        }
        .font(.body)
        .padding(.bottom, 24)
    }

    private func section<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: title)
            content()
        }
    }

    private func localizedGender(_ value: String) -> String {
        value
            .replacingOccurrences(of: "masculine", with: "masculin")
            .replacingOccurrences(of: "feminine", with: "féminin")
            .replacingOccurrences(of: "common-gender", with: "genre commun")
            .replacingOccurrences(of: "neuter", with: "neutre")
    }
}

enum WordDetailRenderingPolicy {
    static let initialSenseCount = 30
    static let senseBatchSize = 30
    static let initialExampleCount = 8
    static let exampleBatchSize = 20
    static let initialRelationCount = 24
    static let relationBatchSize = 48
    static let initialFormCount = 60
    static let formBatchSize = 60

    static func expandedCount(current: Int, total: Int, batchSize: Int) -> Int {
        min(total, current + batchSize)
    }
}

private struct ProgressiveDefinitionsView: View {
    let senses: [WordSense]
    @State private var visibleCount = WordDetailRenderingPolicy.initialSenseCount

    var body: some View {
        LazyVStack(alignment: .leading, spacing: 22) {
            ForEach(senses.indices.prefix(visibleCount), id: \.self) { index in
                SenseRow(number: index + 1, sense: senses[index])
            }
            if visibleCount < senses.count {
                ShowMoreButton(
                    remaining: senses.count - visibleCount,
                    noun: "sens"
                ) {
                    visibleCount = WordDetailRenderingPolicy.expandedCount(
                        current: visibleCount,
                        total: senses.count,
                        batchSize: WordDetailRenderingPolicy.senseBatchSize
                    )
                }
            }
        }
    }
}

private struct SenseRow: View {
    let number: Int
    let sense: WordSense
    @State private var visibleExampleCount = WordDetailRenderingPolicy.initialExampleCount

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("\(number)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
                    .frame(width: 18, alignment: .trailing)
                Text(sense.definition)
                    .font(.system(.body, design: .serif))
                    .lineSpacing(4)
                    .textSelection(.enabled)
            }
            LazyVStack(alignment: .leading, spacing: 10) {
                ForEach(sense.examples.prefix(visibleExampleCount)) { example in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(example.text)
                            .font(.callout)
                            .italic()
                            .foregroundStyle(.secondary)
                        if let source = example.source {
                            Text(source).font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 30)
                }
                if visibleExampleCount < sense.examples.count {
                    ShowMoreButton(
                        remaining: sense.examples.count - visibleExampleCount,
                        noun: "exemple"
                    ) {
                        visibleExampleCount = WordDetailRenderingPolicy.expandedCount(
                            current: visibleExampleCount,
                            total: sense.examples.count,
                            batchSize: WordDetailRenderingPolicy.exampleBatchSize
                        )
                    }
                    .padding(.leading, 30)
                }
            }
        }
    }
}

private struct ProgressiveRelationSection: View {
    let section: WordRelationSection
    @State private var visibleCount = WordDetailRenderingPolicy.initialRelationCount

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: section.kind.title)
            FlowLayout(spacing: 8) {
                ForEach(section.relations.prefix(visibleCount)) { relation in
                    NavigationLink {
                        RelatedWordDestination(word: relation.word)
                    } label: {
                        Text(relation.word)
                            .font(.subheadline)
                            .lineLimit(1)
                            .padding(.horizontal, 11)
                            .padding(.vertical, 7)
                            .background(.quaternary, in: Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
            if visibleCount < section.relations.count {
                ShowMoreButton(
                    remaining: section.relations.count - visibleCount,
                    noun: "terme"
                ) {
                    visibleCount = WordDetailRenderingPolicy.expandedCount(
                        current: visibleCount,
                        total: section.relations.count,
                        batchSize: WordDetailRenderingPolicy.relationBatchSize
                    )
                }
            }
        }
    }
}

private struct ProgressiveFormsView: View {
    let forms: [WordForm]
    @State private var visibleCount = WordDetailRenderingPolicy.initialFormCount

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(title: "Formes")
            Text(forms.prefix(visibleCount).map(\.form).joined(separator: " · "))
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            if visibleCount < forms.count {
                ShowMoreButton(remaining: forms.count - visibleCount, noun: "forme") {
                    visibleCount = WordDetailRenderingPolicy.expandedCount(
                        current: visibleCount,
                        total: forms.count,
                        batchSize: WordDetailRenderingPolicy.formBatchSize
                    )
                }
            }
        }
    }
}

private struct ShowMoreButton: View {
    let remaining: Int
    let noun: String
    let action: () -> Void

    var body: some View {
        let displayedNoun = noun == "sens" || remaining == 1 ? noun : "\(noun)s"
        Button(action: action) {
            Label(
                "Afficher plus (\(remaining) \(displayedNoun))",
                systemImage: "chevron.down"
            )
            .font(.subheadline.weight(.medium))
        }
        .buttonStyle(.plain)
        .foregroundStyle(.tint)
    }
}

private struct CollectionPickerSheet: View {
    @ObservedObject var viewModel: WordDetailViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(viewModel.collections) { collection in
                Button {
                    viewModel.setMembership(
                        collectionID: collection.id,
                        included: !viewModel.memberships.contains(collection.id)
                    )
                } label: {
                    HStack {
                        Text(collection.name).foregroundStyle(.primary)
                        Spacer()
                        if viewModel.memberships.contains(collection.id) {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                }
            }
            .overlay {
                if viewModel.collections.isEmpty {
                    ContentUnavailableView(
                        "Aucune collection",
                        systemImage: "square.stack",
                        description: Text("Créez d’abord une collection depuis l’onglet Collections.")
                    )
                }
            }
            .navigationTitle("Collections")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("Terminé") { dismiss() } }
        }
    }
}

private struct RelatedWordDestination: View {
    let word: String
    @EnvironmentObject private var app: AppModel
    @State private var result: WordSummary?
    @State private var loaded = false

    var body: some View {
        Group {
            if let result {
                WordDetailView(summary: result)
            } else if loaded {
                ContentUnavailableView("Mot introuvable", systemImage: "questionmark.circle")
            } else {
                ProgressView()
            }
        }
        .task {
            if let dictionary = app.dictionary {
                let matches = try? await dictionary.search(word, limit: 1)
                result = matches?.first
            }
            loaded = true
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat

    struct Cache {
        var sizes: [CGSize]
    }

    func makeCache(subviews: Subviews) -> Cache {
        Cache(sizes: subviews.map { $0.sizeThatFits(.unspecified) })
    }

    func updateCache(_ cache: inout Cache, subviews: Subviews) {
        if cache.sizes.count < subviews.count {
            cache.sizes.append(contentsOf: subviews.dropFirst(cache.sizes.count).map {
                $0.sizeThatFits(.unspecified)
            })
        } else {
            cache.sizes = subviews.map { $0.sizeThatFits(.unspecified) }
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let result = arrangement(maximumWidth: proposal.width, sizes: cache.sizes)
        return CGSize(width: proposal.width ?? result.contentWidth, height: result.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        let result = arrangement(maximumWidth: bounds.width, sizes: cache.sizes)
        for (index, subview) in subviews.enumerated()
        where index < result.origins.count && index < cache.sizes.count {
            let origin = result.origins[index]
            let size = cache.sizes[index]
            subview.place(
                at: CGPoint(x: bounds.minX + origin.x, y: bounds.minY + origin.y),
                proposal: ProposedViewSize(size)
            )
        }
    }

    private func arrangement(maximumWidth: CGFloat?, sizes: [CGSize]) -> LayoutResult {
        let width = maximumWidth.flatMap { $0 > 0 ? $0 : nil } ?? .infinity
        var origins: [CGPoint] = []
        origins.reserveCapacity(sizes.count)
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var contentWidth: CGFloat = 0
        for size in sizes {
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            origins.append(CGPoint(x: x, y: y))
            contentWidth = max(contentWidth, x + size.width)
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return LayoutResult(origins: origins, contentWidth: contentWidth, height: y + rowHeight)
    }

    private struct LayoutResult {
        let origins: [CGPoint]
        let contentWidth: CGFloat
        let height: CGFloat
    }
}
