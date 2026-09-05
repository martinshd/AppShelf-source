import SwiftUI

struct AppTileView: View {
    let application: ApplicationItem
    var allowsPinnedReordering = false

    @EnvironmentObject private var library: ApplicationLibrary

    @ViewBuilder
    var body: some View {
        if allowsPinnedReordering {
            tile
                .draggable(application.id)
                .dropDestination(for: String.self) { applicationIDs, _ in
                    guard let applicationID = applicationIDs.first else {
                        return false
                    }

                    library.movePinnedApplication(applicationID, to: application.id)
                    return true
                }
        } else {
            tile
        }
    }

    private var tile: some View {
        Button {
            library.launch(application)
        } label: {
            VStack(spacing: 10) {
                Image(nsImage: application.icon)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 72, height: 72)

                Text(application.name)
                    .font(.callout)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 34, alignment: .top)
            }
            .padding(10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(library.isPinned(application)
                ? String(localized: "menu.unpin", defaultValue: "取消置顶")
                : String(localized: "menu.pin", defaultValue: "置顶")) {
                library.togglePin(application)
            }

            if !library.categories.isEmpty {
                Menu("加入分组") {
                    ForEach(library.categories) { category in
                        Button {
                            library.toggle(application, in: category)
                        } label: {
                            if library.contains(application, in: category) {
                                Label(category.name, systemImage: "checkmark")
                            } else {
                                Text(category.name)
                            }
                        }
                    }
                }
            }

            Divider()

            Button("在访达中显示") {
                library.revealInFinder(application)
            }
        }
        .help(application.name)
    }
}
