import Foundation

struct AppCategory: Codable, Hashable, Identifiable {
    let id: UUID
    var name: String
    var applicationIDs: Set<String>

    init(id: UUID = UUID(), name: String, applicationIDs: Set<String> = []) {
        self.id = id
        self.name = name
        self.applicationIDs = applicationIDs
    }
}
