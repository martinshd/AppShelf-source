import SwiftUI

@main
struct AppShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var library = ApplicationLibrary()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(library)
                .frame(minWidth: 820, minHeight: 560)
        }
        .defaultSize(width: 1040, height: 720)
        .commands {
            CommandMenu("AppShelf") {
                Button("显示或隐藏 AppShelf") {
                    appDelegate.toggleMainWindow()
                }
                .keyboardShortcut(.space, modifiers: [.option])
            }
        }
    }
}
