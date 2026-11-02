import Foundation
import UIKit
import UniformTypeIdentifiers
import SetlistCore

/// What arrived through the share sheet (or the in-app "Try it" box).
enum SharedInput {
    case text(String)
    case url(URL)
    case image(UIImage)
}

struct LoadedShare {
    var input: SharedInput
    /// Page title Safari/YouTube pass alongside a URL. Used to name the playlist when the page gives nothing better.
    var titleHint: String?
}

/// Reads `NSExtensionItem` attachments. Priority: web URL, then text, then image.
enum ExtensionInputLoader {
    static func load(from items: [NSExtensionItem]) async -> LoadedShare? {
        var titleHint: String?
        var text: String?
        var image: UIImage?

        for item in items {
            if let content = item.attributedContentText?.string.trimmingCharacters(in: .whitespacesAndNewlines),
               !content.isEmpty, content.count <= 120, !content.contains("\n") {
                titleHint = titleHint ?? content
            }

            for provider in item.attachments ?? [] {
                if provider.hasItemConformingToTypeIdentifier(UTType.url.identifier), let url = await loadURL(provider) {
                    if url.isFileURL {
                        if image == nil, let loaded = UIImage(contentsOfFile: url.path) { image = loaded }
                    } else {
                        return LoadedShare(input: .url(url), titleHint: titleHint)
                    }
                }
                if text == nil, provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier),
                   let loaded = await loadText(provider), !loaded.isEmpty {
                    text = loaded
                }
                if image == nil, provider.hasItemConformingToTypeIdentifier(UTType.image.identifier),
                   let loaded = await loadImage(provider) {
                    image = loaded
                }
            }
        }

        if let text {
            if let url = SetlistDetector.soleURL(in: text) {
                return LoadedShare(input: .url(url), titleHint: nil)
            }
            return LoadedShare(input: .text(text), titleHint: nil)
        }
        if let image {
            return LoadedShare(input: .image(image), titleHint: nil)
        }
        return nil
    }

    private static func loadItem(_ provider: NSItemProvider, _ type: UTType) async -> Any? {
        guard let item = try? await provider.loadItem(forTypeIdentifier: type.identifier) else { return nil }
        return item as Any
    }

    private static func loadURL(_ provider: NSItemProvider) async -> URL? {
        guard let item = await loadItem(provider, .url) else { return nil }
        if let url = item as? URL { return url }
        if let url = item as? NSURL { return url as URL }
        if let data = item as? Data, let string = String(data: data, encoding: .utf8) { return URL(string: string) }
        return nil
    }

    private static func loadText(_ provider: NSItemProvider) async -> String? {
        guard let item = await loadItem(provider, .plainText) else { return nil }
        if let string = item as? String { return string }
        if let string = item as? NSString { return string as String }
        if let attributed = item as? NSAttributedString { return attributed.string }
        if let data = item as? Data { return String(data: data, encoding: .utf8) }
        return nil
    }

    private static func loadImage(_ provider: NSItemProvider) async -> UIImage? {
        if let item = await loadItem(provider, .image) {
            if let image = item as? UIImage { return image }
            if let url = item as? URL, let image = UIImage(contentsOfFile: url.path) { return image }
            if let url = item as? NSURL, let image = UIImage(contentsOfFile: url.path) { return image }
            if let data = item as? Data, let image = UIImage(data: data) { return image }
        }
        // Photos sometimes only offers a data representation.
        let data: Data? = await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
        return data.flatMap(UIImage.init(data:))
    }
}
