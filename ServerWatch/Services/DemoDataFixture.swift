#if DEBUG
import Foundation
import SwiftData

/// Screenshot-capture harness around `DemoMode`. Read by `ContentView`'s
/// `DemoScreenRouter` and the App's launch block to skip onboarding,
/// install the demo dataset, and pick which screen to land on.
///
/// Activated via launch arguments:
///   `--SH_DEMO_MODE`              install the demo dataset on first launch
///   `--SH_DEMO_SCREEN=<name>`     auto-navigate to one of:
///                                   `dashboard` (default), `detail`,
///                                   `paywall`, `addrule`, `settings`
///
/// The actual server / rule / snapshot seeding lives in `DemoMode` so it can
/// also be triggered from a release build via the in-app "Try Demo Mode"
/// button. This file just wires the launch-argument plumbing.
@MainActor
enum DemoDataFixture {

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(where: { $0.hasSuffix("SH_DEMO_MODE") })
    }

    static var initialScreen: String {
        for arg in ProcessInfo.processInfo.arguments {
            if let eq = arg.range(of: "SH_DEMO_SCREEN=") {
                return String(arg[eq.upperBound...])
            }
        }
        return "dashboard"
    }

    /// Installs demo data + fakes background-task counters so the Settings
    /// screenshot doesn't surface the simulator-only BGTaskScheduler error.
    static func installIfNeeded(into context: ModelContext) {
        guard isEnabled else { return }
        let key = "demo.fixture.installed"
        guard !UserDefaults.standard.bool(forKey: key) else { return }

        DemoMode.install(into: context)

        UserDefaults.standard.removeObject(forKey: "bg.lastScheduleError")
        UserDefaults.standard.set(Date().addingTimeInterval(-120), forKey: "bg.lastRunAt")
        UserDefaults.standard.set(Date().addingTimeInterval(-30),  forKey: "bg.lastScheduledAt")
        UserDefaults.standard.set(127, forKey: "bg.runCount")
        UserDefaults.standard.set(840, forKey: "bg.lastRunDurationMs")
        UserDefaults.standard.set(true, forKey: key)
    }
}
#endif
