import AppKit
import CryptoKit
import Sparkle

// Runs only against a disposable host bundle supplied by test-updates.py.
// Auto-accepting updates is deliberately confined to this test executable.
@MainActor final class Harness: NSObject, NSApplicationDelegate, SPUUserDriver, SPUUpdaterDelegate {
    private var updater: SPUUpdater!

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard CommandLine.arguments.count == 3,
              let host = Bundle(path: CommandLine.arguments[1]),
              host.bundleIdentifier?.hasPrefix("local.ruller.integration.") == true else { exit(2) }
        // The target is not running, so Sparkle installs without relaunching it.
        updater = SPUUpdater(hostBundle: host, applicationBundle: host, userDriver: self, delegate: self)
        do {
            try updater.start()
            updater.checkForUpdates()
        } catch { finish(error: error) }
        DispatchQueue.main.asyncAfter(deadline: .now() + 60) { print("FAIL: timed out"); exit(3) }
    }

    func show(_ request: SPUUpdatePermissionRequest, reply: @escaping (SUUpdatePermissionResponse) -> Void) {
        reply(SUUpdatePermissionResponse(automaticUpdateChecks: false, sendSystemProfile: false))
    }
    func showUserInitiatedUpdateCheck(cancellation: @escaping () -> Void) { print("Checking signed feed") }
    func showUpdateFound(with appcastItem: SUAppcastItem, state: SPUUserUpdateState, reply: @escaping (SPUUserUpdateChoice) -> Void) {
        print("Found build \(appcastItem.versionString)")
        reply(.install)
    }
    func showUpdateReleaseNotes(with downloadData: SPUDownloadData) {}
    func showUpdateReleaseNotesFailedToDownloadWithError(_ error: Error) { finish(error: error) }
    func showUpdateNotFoundWithError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        let issue = error as NSError
        if CommandLine.arguments[2] == "latest", issue.domain == SUSparkleErrorDomain, issue.code == 1001,
           issue.userInfo[SPUNoUpdateFoundReasonKey] as? Int == 1 {
            print("PASS: current version reports up to date"); exit(0)
        }
        finish(error: error)
    }
    func showUpdaterError(_ error: Error, acknowledgement: @escaping () -> Void) {
        acknowledgement(); finish(error: error)
    }
    func showDownloadInitiated(cancellation: @escaping () -> Void) { print("Downloading") }
    func showDownloadDidReceiveExpectedContentLength(_ expectedContentLength: UInt64) {}
    func showDownloadDidReceiveData(ofLength length: UInt64) {}
    func showDownloadDidStartExtractingUpdate() { print("Validating archive") }
    func showExtractionReceivedProgress(_ progress: Double) {}
    func showReady(toInstallAndRelaunch reply: @escaping (SPUUserUpdateChoice) -> Void) { reply(.install) }
    func showInstallingUpdate(withApplicationTerminated applicationTerminated: Bool, retryTerminatingApplication: @escaping () -> Void) {
        print("Installing; target terminated: \(applicationTerminated)")
    }
    func showUpdateInstalledAndRelaunched(_ relaunched: Bool, acknowledgement: @escaping () -> Void) {
        acknowledgement()
        guard CommandLine.arguments[2] == "install" else { print("FAIL: accepted tampered update"); exit(1) }
        print("PASS: installed signed update"); exit(0)
    }
    func dismissUpdateInstallation() {}

    private func finish(error: Error) {
        var chain: [NSError] = [error as NSError]
        while let next = chain.last?.userInfo[NSUnderlyingErrorKey] as? NSError { chain.append(next) }
        let validationFailure = chain.contains { $0.domain == SUSparkleErrorDomain && [3001, 3002].contains($0.code) }
        print(chain.map { "\($0.domain):\($0.code) \($0.localizedDescription)" }.joined(separator: "\n"))
        if CommandLine.arguments[2] == "reject" && validationFailure {
            print("PASS: rejected invalid signature"); exit(0)
        }
        print("FAIL: unexpected updater error"); exit(1)
    }
}

@main struct Main {
    static func main() {
        setbuf(stdout, nil)
        if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--make-test-key" {
            // Ephemeral test identity; never reads the production Keychain key.
            let key = Curve25519.Signing.PrivateKey()
            let url = URL(fileURLWithPath: CommandLine.arguments[2])
            try! key.rawRepresentation.base64EncodedData().write(to: url, options: .atomic)
            try! FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            print(key.publicKey.rawRepresentation.base64EncodedString())
            return
        }
        let app = NSApplication.shared
        let harness = Harness()
        app.delegate = harness
        app.setActivationPolicy(.prohibited)
        app.run()
        withExtendedLifetime(harness) {}
    }
}
