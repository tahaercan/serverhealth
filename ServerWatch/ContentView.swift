import SwiftUI

/// Uygulamanın kök ekranı. İlk açılışta `OnboardingView`'i gösterir; kullanıcı
/// tour'u tamamlayınca `@AppStorage("hasCompletedOnboarding")` true olur ve
/// kalıcı olarak `ServerListView`'e geçer.
struct ContentView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding: Bool = false

    var body: some View {
        Group {
            if hasCompletedOnboarding {
                ServerListView()
            } else {
                OnboardingView()
            }
        }
    }
}

#Preview {
    ContentView()
}
