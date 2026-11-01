import AppKit
import Foundation
import NotchCore
import Observation
import UniformTypeIdentifiers

/// Manages the temporary file stashing shelf inside the notch, including AirDrop
/// sharing and Quick Look / Finder reveal.
@MainActor
@Observable
final class ShelfService {
    private(set) var items: [ShelfItem] = []

    /// Adds file URLs dropped onto the shelf, ignoring duplicates.
    func addFiles(_ urls: [URL]) {
        for url in urls {
            let standardized = url.standardizedFileURL
            guard !items.contains(where: { $0.url.standardizedFileURL == standardized }) else {
                continue
            }
            items.append(ShelfItem(url: standardized))
        }
    }

    /// Extracts file URLs from SwiftUI `NSItemProvider` drops.
    func handleDrop(providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else if let directURL = item as? URL {
                    url = directURL
                } else {
                    url = nil
                }
                guard let url else { return }
                Task { @MainActor [weak self] in
                    self?.addFiles([url])
                }
            }
        }
        return accepted
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
    }

    func clearAll() {
        items.removeAll()
    }

    func revealInFinder(_ item: ShelfItem) {
        NSWorkspace.shared.activateFileViewerSelecting([item.url])
    }

    func shareViaAirDrop(_ urls: [URL]? = nil) {
        let targets = urls ?? items.map(\.url)
        guard !targets.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop) else {
            return
        }
        service.perform(withItems: targets)
    }
}
