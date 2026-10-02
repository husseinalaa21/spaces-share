import SwiftUI
@main struct SpacesShareApp: App {
    @StateObject private var store = ShareStore()
    @StateObject private var purchases = ShareMembershipStore()
    var body: some Scene {
        WindowGroup {
            ContentView().environmentObject(store).environmentObject(purchases).tint(ShareTheme.ink).preferredColorScheme(.light)
                .task { await store.restore() }
                .task(id: store.session) {
                    purchases.reset()
                    guard store.session != nil else { return }
                    purchases.observe(store: store)
                    await store.refreshAccount()
                    await purchases.reconcile(store: store)
                }
#if os(macOS)
                .frame(minWidth: 400, minHeight: 600)
#endif
        }
        .defaultSize(width: 480, height: 760)
    }
}
