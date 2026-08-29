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
                    relationSections(entry)
                    forms(entry)
                    if let etymology = entry.etymology, !etymology.isEmpty {
                        section(title: "Étymologie") {
                            Text(etymology).font(.body).textSelection(.enabled)
                        }
                    }
                    actions(entry)
                }
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
                .accessibilityLabel(viewModel.isFavorite ? "Retirer des favoris" : "Ajouter aux favoris")
                Button { showingCollections = true } label: {
                    Image(systemName: "square.stack.badge.plus")
                }
                .accessibilityLabel("Gérer les collections")
            }
        }
        .task {
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
        VStack(alignment: .leading, spacing: 22) {
            ForEach(Array(entry.senses.enumerated()), id: \.element.id) { index, sense in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                            .frame(width: 18, alignment: .trailing)
                        Text(sense.definition)
                            .font(.system(.body, design: .serif))
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                    ForEach(sense.examples) { example in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(example.text)
                                .font(.callout)
                                .italic()
                                .foregroundStyle(.secondary)
                            if let source = example.source {
                                Text(source).font(.caption2).foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.leading, 30)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func relationSections(_ entry: WordEntry) -> some View {
        ForEach(RelationKind.allCases, id: \.self) { kind in
            let relations = entry.relations.filter { $0.kind == kind }
            if !relations.isEmpty {
                section(title: kind.title) {
                    FlowLayout(spacing: 8) {
                        ForEach(relations) { relation in
                            NavigationLink {
                                RelatedWordDestination(word: relation.word)
                            } label: {
                                Text(relation.word)
                                    .font(.subheadline)
                                    .padding(.horizontal, 11)
                                    .padding(.vertical, 7)
                                    .background(.quaternary, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func forms(_ entry: WordEntry) -> some View {
        if !entry.forms.isEmpty {
            section(title: "Formes") {
                Text(entry.forms.prefix(60).map(\.form).joined(separator: " · "))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
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

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x > bounds.minX, x + size.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
