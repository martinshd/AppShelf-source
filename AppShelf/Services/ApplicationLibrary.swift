import AppKit
import Foundation

@MainActor
final class ApplicationLibrary: ObservableObject {
    @Published private(set) var applications: [ApplicationItem] = []
    @Published private(set) var pinnedApplicationIDs: [String] = []
    @Published private(set) var categories: [AppCategory] = []
    @Published var searchText = ""
    @Published var selection: LibrarySelection? = .all

    private let pinnedDefaultsKey = "pinnedApplicationIDs"
    private let categoriesDefaultsKey = "appCategories"

    init() {
        pinnedApplicationIDs = UserDefaults.standard.stringArray(forKey: pinnedDefaultsKey) ?? []
        categories = loadCategories()
        refresh()
    }

    var visibleApplications: [ApplicationItem] {
        let matchingApplications = applications.filter(matchesSearch)

        switch selection {
        case .pinned:
            return matchingApplications.filter(isPinned)
        case let .category(categoryID):
            guard let category = categories.first(where: { $0.id == categoryID }) else {
                return []
            }

            return matchingApplications.filter { category.applicationIDs.contains($0.id) }
        case .all, .none:
            return matchingApplications
        }
    }

    var pinnedApplications: [ApplicationItem] {
        let visibleApplicationsByID = Dictionary(uniqueKeysWithValues: visibleApplications.map { ($0.id, $0) })
        return pinnedApplicationIDs.compactMap { visibleApplicationsByID[$0] }
    }

    var unpinnedApplications: [ApplicationItem] {
        visibleApplications.filter { !isPinned($0) }
    }

    var selectionTitle: String {
        guard case let .category(categoryID) = selection else {
            return selection?.title ?? String(localized: "全部应用")
        }

        return categories.first(where: { $0.id == categoryID })?.name ?? String(localized: "分组")
    }

    func refresh() {
        let searchRoots = [
            URL(fileURLWithPath: "/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Applications", isDirectory: true),
            URL(fileURLWithPath: "/System/Cryptexes/App/System/Applications", isDirectory: true),
            FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications", isDirectory: true)
        ]

        var applicationsByID: [String: ApplicationItem] = [:]

        for root in searchRoots where FileManager.default.fileExists(atPath: root.path) {
            for application in scanApplications(in: root) {
                applicationsByID[application.id] = application
            }
        }

        applications = applicationsByID.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func launch(_ application: ApplicationItem) {
        let configuration = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: application.url, configuration: configuration)
    }

    func revealInFinder(_ application: ApplicationItem) {
        NSWorkspace.shared.activateFileViewerSelecting([application.url])
    }

    func togglePin(_ application: ApplicationItem) {
        var updatedApplicationIDs = pinnedApplicationIDs

        if let index = updatedApplicationIDs.firstIndex(of: application.id) {
            updatedApplicationIDs.remove(at: index)
        } else {
            updatedApplicationIDs.append(application.id)
        }

        pinnedApplicationIDs = updatedApplicationIDs
        persistPinnedApplications()
    }

    func isPinned(_ application: ApplicationItem) -> Bool {
        pinnedApplicationIDs.contains(application.id)
    }

    func movePinnedApplication(_ applicationID: String, to targetApplicationID: String) {
        guard applicationID != targetApplicationID,
              let sourceIndex = pinnedApplicationIDs.firstIndex(of: applicationID),
              let targetIndex = pinnedApplicationIDs.firstIndex(of: targetApplicationID) else {
            return
        }

        var updatedApplicationIDs = pinnedApplicationIDs
        updatedApplicationIDs.remove(at: sourceIndex)
        updatedApplicationIDs.insert(applicationID, at: min(targetIndex, updatedApplicationIDs.endIndex))
        pinnedApplicationIDs = updatedApplicationIDs
        persistPinnedApplications()
    }

    func addCategory(named name: String) {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            return
        }

        var updatedCategories = categories
        updatedCategories.append(AppCategory(name: trimmedName))
        updatedCategories.sort { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        categories = updatedCategories
        persistCategories()
    }

    func toggle(_ application: ApplicationItem, in category: AppCategory) {
        guard let index = categories.firstIndex(where: { $0.id == category.id }) else {
            return
        }

        var updatedCategories = categories

        if updatedCategories[index].applicationIDs.contains(application.id) {
            updatedCategories[index].applicationIDs.remove(application.id)
        } else {
            updatedCategories[index].applicationIDs.insert(application.id)
        }

        categories = updatedCategories
        persistCategories()
    }

    func contains(_ application: ApplicationItem, in category: AppCategory) -> Bool {
        category.applicationIDs.contains(application.id)
    }

    func deleteCategory(_ category: AppCategory) {
        categories = categories.filter { $0.id != category.id }
        if selection == .category(category.id) {
            selection = .all
        }
        persistCategories()
    }

    private func matchesSearch(_ application: ApplicationItem) -> Bool {
        searchText.isEmpty || application.name.localizedCaseInsensitiveContains(searchText)
    }

    private func persistPinnedApplications() {
        UserDefaults.standard.set(pinnedApplicationIDs, forKey: pinnedDefaultsKey)
    }

    private func loadCategories() -> [AppCategory] {
        guard let data = UserDefaults.standard.data(forKey: categoriesDefaultsKey),
              let categories = try? JSONDecoder().decode([AppCategory].self, from: data) else {
            return []
        }

        return categories
    }

    private func persistCategories() {
        guard let data = try? JSONEncoder().encode(categories) else {
            return
        }

        UserDefaults.standard.set(data, forKey: categoriesDefaultsKey)
    }

    private func scanApplications(in root: URL) -> [ApplicationItem] {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            return []
        }

        return enumerator.compactMap { element in
            guard let url = element as? URL, url.pathExtension.lowercased() == "app" else {
                return nil
            }

            let bundle = Bundle(url: url)
            let bundleName = bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
                ?? bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String
            let name = bundleName ?? url.deletingPathExtension().lastPathComponent
            let icon = NSWorkspace.shared.icon(forFile: url.path)

            return ApplicationItem(name: name, url: url, bundleIdentifier: bundle?.bundleIdentifier, icon: icon)
        }
    }
}

enum LibrarySelection: Hashable {
    case all
    case pinned
    case category(UUID)

    var title: String {
        switch self {
        case .all:
            return String(localized: "全部应用")
        case .pinned:
            return String(localized: "已置顶")
        case .category:
            return String(localized: "分组")
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            return "square.grid.3x3.fill"
        case .pinned:
            return "pin.fill"
        case .category:
            return "folder.fill"
        }
    }
}
