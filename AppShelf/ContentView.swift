import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var library: ApplicationLibrary
    @State private var isCreatingCategory = false
    @State private var newCategoryName = ""

    private let columns = [GridItem(.adaptive(minimum: 112, maximum: 140), spacing: 18)]

    var body: some View {
        NavigationSplitView {
            List(selection: $library.selection) {
                Label("全部应用", systemImage: LibrarySelection.all.systemImage)
                    .tag(LibrarySelection.all)

                Label("已置顶", systemImage: LibrarySelection.pinned.systemImage)
                    .tag(LibrarySelection.pinned)

                Section {
                    ForEach(library.categories) { category in
                        Label(category.name, systemImage: "folder.fill")
                            .tag(LibrarySelection.category(category.id))
                            .contextMenu {
                                Button("删除分组", role: .destructive) {
                                    library.deleteCategory(category)
                                }
                            }
                    }
                } header: {
                    HStack {
                        Text("我的分组")

                        Spacer()

                        Button {
                            newCategoryName = ""
                            isCreatingCategory = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.plain)
                        .help("新建分组")
                    }
                }
            }
            .navigationTitle("AppShelf")
            .navigationSplitViewColumnWidth(min: 180, ideal: 210)
        } detail: {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    if library.selection == .all && !library.pinnedApplications.isEmpty {
                        applicationSection(
                            title: "置顶",
                            applications: library.pinnedApplications,
                            allowsReordering: true
                        )
                    }

                    applicationSection(
                        title: library.selectionTitle,
                        applications: detailApplications,
                        allowsReordering: library.selection == .pinned
                    )
                }
                .padding(24)
            }
            .navigationTitle(library.selectionTitle)
            .searchable(text: $library.searchText, placement: .toolbar, prompt: "搜索应用名称")
            .toolbar {
                ToolbarItem {
                    Button {
                        library.refresh()
                    } label: {
                        Label("刷新应用", systemImage: "arrow.clockwise")
                    }
                }
            }
            .overlay {
                if detailApplications.isEmpty {
                    emptyState
                }
            }
        }
        .alert("新建分组", isPresented: $isCreatingCategory) {
            TextField("分组名称", text: $newCategoryName)

            Button("取消", role: .cancel) {}

            Button("创建") {
                library.addCategory(named: newCategoryName)
            }
            .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("创建后，可通过应用的右键菜单将它加入分组。")
        }
    }

    private var detailApplications: [ApplicationItem] {
        switch library.selection {
        case .all, .none:
            return library.visibleApplications
        case .pinned:
            return library.pinnedApplications
        case .category:
            return library.visibleApplications
        }
    }

    @ViewBuilder
    private var emptyState: some View {
        if !library.searchText.isEmpty {
            ContentUnavailableView.search(text: library.searchText)
        } else {
            switch library.selection {
            case .pinned:
                collectionEmptyState(
                    title: "还没有置顶应用",
                    systemImage: "pin",
                    description: "浏览全部应用，右键应用即可置顶。"
                )
            case .category:
                collectionEmptyState(
                    title: "此分组还没有应用",
                    systemImage: "folder",
                    description: "浏览全部应用，右键应用即可加入分组。"
                )
            case .all, .none:
                ContentUnavailableView {
                    Label("未找到应用", systemImage: "square.grid.3x3")
                } description: {
                    Text("点按刷新，重新扫描应用目录。")
                } actions: {
                    Button("刷新应用") {
                        library.refresh()
                    }
                }
            }
        }
    }

    private func collectionEmptyState(title: String, systemImage: String, description: String) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(description)
        } actions: {
            Button("浏览全部应用") {
                library.selection = .all
            }
        }
    }

    @ViewBuilder
    private func applicationSection(
        title: String,
        applications: [ApplicationItem],
        allowsReordering: Bool = false
    ) -> some View {
        if !applications.isEmpty {
            VStack(alignment: .leading, spacing: 14) {
                Text(title)
                    .font(.title2.bold())

                LazyVGrid(columns: columns, alignment: .leading, spacing: 22) {
                    ForEach(applications) { application in
                        AppTileView(application: application, allowsPinnedReordering: allowsReordering)
                    }
                }
            }
        }
    }
}
