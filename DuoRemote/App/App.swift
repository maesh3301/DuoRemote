import DuoRemoteKit
import SwiftUI
import UIKit

@main
struct DuoRemoteApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var coordinator = SessionCoordinator()

    init() {
        Diagnostics.shared.start()
        PrivacyShield.shared.start()
    }

    var body: some Scene {
        WindowGroup {
            RemoteRootView(coordinator: coordinator)
                .task { await coordinator.prepare() }
        }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    /// Only the system keyboard: a third-party one could see what's typed into the Mac,
    /// passwords included.
    func application(_ application: UIApplication,
                     shouldAllowExtensionPointIdentifier extensionPointIdentifier: UIApplication.ExtensionPointIdentifier) -> Bool {
        extensionPointIdentifier != .keyboard
    }
}
