import SwiftUI
import SwiftData

/// Uygulamanın kök ekranı. İlk açılışta `OnboardingView`'i gösterir; kullanıcı
/// tour'u tamamlayınca `@AppStorage("hasCompletedOnboarding")` true olur ve
/// kalıcı olarak `ServerListView`'e geçer.
struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                ServerListView()
                    #if DEBUG
                    .modifier(DemoScreenRouter())
                    #endif
            } else {
                OnboardingView()
            }
        }
    }
}

#if DEBUG

/// Drives the screenshot pipeline. When the app launches with
/// `--SH_DEMO_SCREEN=<name>` we present the requested screen on top of the
/// dashboard so simctl can grab a clean PNG of it. Recognized values match
/// `DemoDataFixture.initialScreen`.
private struct DemoScreenRouter: ViewModifier {

    @EnvironmentObject private var purchaseManager: PurchaseManager
    @Environment(\.modelContext) private var context

    @State private var showPaywall = false
    @State private var showSettings = false
    @State private var detailServer: Server?
    @State private var detailWithAddRule = false

    func body(content: Content) -> some View {
        let screen = DemoDataFixture.initialScreen
        return content
            .onAppear {
                guard DemoDataFixture.isEnabled else { return }
                switch screen {
                case "paywall":
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        showPaywall = true
                    }
                case "settings":
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                        showSettings = true
                    }
                case "detail", "addrule":
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                        let descriptor = FetchDescriptor<Server>(sortBy: [SortDescriptor(\.createdAt)])
                        if let server = try? context.fetch(descriptor).first {
                            detailServer = server
                            detailWithAddRule = (screen == "addrule")
                        }
                    }
                default:
                    break
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView(
                    priceText: purchaseManager.priceText,
                    monthlyEquivalentText: purchaseManager.monthlyEquivalentText,
                    isPurchasing: purchaseManager.isPurchasing,
                    isProductAvailable: purchaseManager.isProductAvailable,
                    errorMessage: purchaseManager.lastErrorMessage,
                    onPurchase: { await purchaseManager.purchase() },
                    onRestore:  { await purchaseManager.restore() }
                )
            }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView() }
            }
            .sheet(item: $detailServer) { server in
                NavigationStack {
                    ServerDetailView(server: server)
                        .onAppear {
                            if detailWithAddRule {
                                // Note: this opens detail; user/screenshot
                                // script can tap "Add Rule" themselves.
                                // Programmatic sheet stacking from inside
                                // detail is harder than capture is worth.
                            }
                        }
                }
            }
    }
}

#endif

#Preview {
    ContentView()
}
