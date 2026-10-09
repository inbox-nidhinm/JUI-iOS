import SwiftUI

@main
struct JUIApp: App {
    @StateObject private var store = NotesStore()

    var body: some Scene {
        WindowGroup {
            ContentView(store: store)
        }
    }
}
