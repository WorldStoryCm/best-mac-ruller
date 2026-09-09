import AppKit
import Sparkle

/// Direct-download update support is isolated here. An eventual Mac App Store target must omit Sparkle.
@MainActor final class UpdateController: NSObject, SPUUpdaterDelegate, SPUStandardUserDriverDelegate, NSMenuItemValidation {
    private var controller: SPUStandardUpdaterController!
    private let prepareForUpdate: () -> Void

    init(prepareForUpdate: @escaping () -> Void) {
        self.prepareForUpdate = prepareForUpdate
        super.init()
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: self)
    }

    func start() { controller.startUpdater() }

    func addMenuItems(to menu: NSMenu) {
        let check = NSMenuItem(title: "Check for Updates…", action: #selector(checkForUpdates), keyEquivalent: "")
        check.target = self; menu.addItem(check)
        let automatic = NSMenuItem(title: "Check Automatically", action: #selector(toggleAutomaticChecks), keyEquivalent: "")
        automatic.target = self; menu.addItem(automatic)
    }

    @objc private func checkForUpdates() {
        prepareForUpdate()
        NSApp.activate(ignoringOtherApps: true)
        controller.checkForUpdates(nil)
    }

    @objc private func toggleAutomaticChecks() {
        controller.updater.automaticallyChecksForUpdates.toggle()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(checkForUpdates) { return controller.updater.canCheckForUpdates }
        if menuItem.action == #selector(toggleAutomaticChecks) {
            menuItem.state = controller.updater.automaticallyChecksForUpdates ? .on : .off
        }
        return true
    }

    nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
        // Sparkle invokes its user-driver delegate on the main thread.
        MainActor.assumeIsolated { if handleShowingUpdate { prepareForUpdate() } }
    }

    func updater(_ updater: SPUUpdater, willInstallUpdate item: SUAppcastItem) { prepareForUpdate() }
}
