import SwiftUI

@main
struct LexiFRApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            Group {
                if let error = model.launchError {
                    LaunchErrorView(message: error)
                } else {
                    RootView()
                        .environmentObject(model)
                }
            }
            .tint(.accentColor)
        }
    }
}

@MainActor
final class AppModel: ObservableObject {
    let dictionary: DictionaryRepository?
    let userStore: UserStore?
    let imageStore: WordImageStore?
    @Published private(set) var launchError: String?

    init() {
        do {
            dictionary = try DictionaryRepository()
            userStore = try UserStore()
            imageStore = try WordImageStore()
        } catch {
            dictionary = nil
            userStore = nil
            imageStore = nil
            launchError = error.localizedDescription
        }
    }
}

private struct LaunchErrorView: View {
    let message: String

    var body: some View {
        ContentUnavailableView {
            Label("LexiFR indisponible", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        }
        .padding()
    }
}
