import AppKit
import Foundation

struct ApplicationItem: Identifiable, Hashable {
    let name: String
    let url: URL
    let bundleIdentifier: String?
    let icon: NSImage

    var id: String {
        bundleIdentifier ?? url.path
    }

    static func == (lhs: ApplicationItem, rhs: ApplicationItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
