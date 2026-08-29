import SwiftUI

struct RootView: View {
    var body: some View {
        TabView {
            SearchView()
                .tabItem { Label("Recherche", systemImage: "magnifyingglass") }
            FavoritesView()
                .tabItem { Label("Favoris", systemImage: "heart") }
            CollectionsView()
                .tabItem { Label("Collections", systemImage: "square.stack") }
            SettingsView()
                .tabItem { Label("Réglages", systemImage: "gearshape") }
        }
    }
}
