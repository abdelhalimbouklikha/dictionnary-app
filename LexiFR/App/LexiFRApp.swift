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
            let dictionary = try DictionaryRepository()
            let userStore = try UserStore()
            let imageStore = try WordImageStore()

            self.dictionary = dictionary
            self.userStore = userStore
            self.imageStore = imageStore
        } catch {
            self.dictionary = nil
            self.userStore = nil
            self.imageStore = nil
            self.launchError = error.localizedDescription
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
