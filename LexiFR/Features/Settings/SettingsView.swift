import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var app: AppModel
    @State private var info: DictionaryInfo?
    @State private var showingLicenses = false
    @State private var showingClearConfirmation = false
    @State private var clearedRecents = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("LexiFR") {
                    LabeledContent("Version", value: version)
                    LabeledContent("Build", value: build)
                    Text("Votre dictionnaire français personnel, sans compte, publicité ni suivi.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section("Dictionnaire hors ligne") {
                    if let info {
                        LabeledContent("Entrées", value: info.entries.formatted())
                        LabeledContent("Mots distincts", value: info.distinctWords.formatted())
                        LabeledContent("Sens", value: info.senses.formatted())
                        LabeledContent("Exemples", value: info.examples.formatted())
                        LabeledContent("Taille", value: ByteCountFormatter.string(fromByteCount: info.databaseBytes, countStyle: .file))
                        LabeledContent("Source", value: info.sourceName)
                    } else {
                        HStack { ProgressView(); Text("Lecture des informations…") }
                    }
                }
                Section("Données et confidentialité") {
                    Label("Toutes vos données restent sur cet iPhone", systemImage: "hand.raised")
                    Button("Effacer les mots récemment consultés", role: .destructive) {
                        showingClearConfirmation = true
                    }
                    if clearedRecents {
                        Label("Historique effacé", systemImage: "checkmark.circle")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
                Section("Sources") {
                    Button("Sources et licences") { showingLicenses = true }
                }
            }
            .navigationTitle("Réglages")
            .task { await loadInfo() }
            .sheet(isPresented: $showingLicenses) { LicensesView() }
            .confirmationDialog(
                "Effacer l’historique récent ?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Effacer", role: .destructive) { clearRecents() }
                Button("Annuler", role: .cancel) {}
            }
            .alert("Une erreur est survenue", isPresented: Binding(
                get: { errorMessage != nil }, set: { if !$0 { errorMessage = nil } }
            )) { Button("OK", role: .cancel) {} } message: { Text(errorMessage ?? "") }
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }

    private var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"
    }

    private func loadInfo() async {
        do { info = try await app.dictionary?.metadata() }
        catch { errorMessage = error.localizedDescription }
    }

    private func clearRecents() {
        Task {
            do {
                try await app.userStore?.clearRecents()
                clearedRecents = true
            } catch { errorMessage = error.localizedDescription }
        }
    }
}

private struct LicensesView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Sources et licences")
                        .font(.largeTitle.bold())
                    Text("Les définitions et informations lexicales sont extraites du Wiktionnaire par Kaikki.org.")
                    Text("Le contenu du Wiktionnaire est disponible sous licence Creative Commons Attribution – Partage dans les mêmes conditions 4.0 (CC BY-SA 4.0) ou, pour les contenus compatibles, sous GNU Free Documentation License (GFDL).")
                    Text("LexiFR conserve l’attribution à Wiktionnaire et Kaikki. En cas de redistribution de la base modifiée, les obligations d’attribution et de partage à l’identique s’appliquent.")
                    if let rightsURL = URL(string: "https://fr.wiktionary.org/wiki/Wiktionnaire:R%C3%A9utilisation_du_contenu_du_Wiktionnaire") {
                        Link("Wiktionnaire — réutilisation du contenu", destination: rightsURL)
                    }
                    if let kaikkiURL = URL(string: "https://kaikki.org/") {
                        Link("Kaikki.org", destination: kaikkiURL)
                    }
                }
                .padding(LexiStyle.horizontalMargin)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .toolbar { Button("Terminé") { dismiss() } }
        }
    }
}
