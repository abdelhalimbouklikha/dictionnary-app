import Foundation

enum GoogleImagesService {
    static func url(for word: String) -> URL? {
        var components = URLComponents(string: "https://www.google.com/search")
        components?.queryItems = [
            URLQueryItem(name: "tbm", value: "isch"),
            URLQueryItem(name: "q", value: word)
        ]
        return components?.url
    }
}
