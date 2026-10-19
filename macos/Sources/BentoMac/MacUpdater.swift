import AppKit
import SwiftUI
import Sparkle
import BentoCore

@MainActor final class MacUpdater: NSObject, ObservableObject, SPUUpdaterDelegate {
    @Published private(set) var ready = false
    @Published private(set) var canCheck = false
    @Published private(set) var status = ""
    @Published private(set) var automaticallyChecks = false
    @Published private(set) var automaticallyInstalls = false
    @Published private(set) var pendingInstallation = false
    @Published private(set) var installationHistory: [String] = []
    @Published private(set) var preparingInstallation = false
    private(set) var installationPrepared = false
    var onInstallationNeedsAttention: (() -> Void)?
    private var installationTask: Task<Void, Never>?
    var beforeInstall: (() async -> Bool)?
    private var controller: SPUStandardUpdaterController?
    private var observation: NSKeyValueObservation?
    private var resumeInstallation: (() -> Void)?
    var version: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.2.0" }
    func start() {
        guard controller == nil else { return }
        let defaults = UserDefaults.standard
        var history = defaults.stringArray(forKey: "BentoVersionHistory") ?? []
        if defaults.string(forKey: "BentoLastLaunchedVersion") != version {
            history.insert("Version \(version) first opened · \(Date.now.formatted(date: .abbreviated, time: .omitted))", at: 0)
            history = Array(history.prefix(10))
            defaults.set(history, forKey: "BentoVersionHistory"); defaults.set(version, forKey: "BentoLastLaunchedVersion")
        }
        installationHistory = history
        do {
            let info = Bundle.main.infoDictionary ?? [:]
            try UpdateConfiguration.validate(feed: (info["SUFeedURL"] as? String).flatMap(URL.init(string:)), publicKey: info["SUPublicEDKey"] as? String, developmentBuild: info["BentoDevelopmentBuild"] as? Bool ?? true)
            let instance = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: self, userDriverDelegate: nil)
            controller = instance
            // Start with the standard user-driven UI; checks/downloads are opt-in and
            // update statistics are disabled in Info.plist.
            try instance.updater.start()
            automaticallyChecks = instance.updater.automaticallyChecksForUpdates
            automaticallyInstalls = instance.updater.automaticallyDownloadsUpdates
            observation = instance.updater.observe(\.canCheckForUpdates, options: [.initial, .new]) { [weak self] updater, _ in
                let allowed = updater.canCheckForUpdates
                Task { @MainActor in self?.canCheck = allowed }
            }
            ready = true; status = "Signed updates from Bento’s Mac release feed."
        } catch { ready = false; status = error.localizedDescription }
    }
    func check() {
        guard ready, canCheck, let controller else { return }
        status = "Checking for updates…"; controller.checkForUpdates(nil)
    }
    func setAutomaticChecks(_ enabled: Bool) {
        guard let controller, ready else { return }
        controller.updater.automaticallyChecksForUpdates = enabled; automaticallyChecks = enabled
    }
    func setAutomaticInstall(_ enabled: Bool) {
        guard let controller, ready else { return }
        controller.updater.automaticallyDownloadsUpdates = enabled; automaticallyInstalls = enabled
    }
    func updater(_ updater: SPUUpdater, didFindValidUpdate item: SUAppcastItem) {
        status = "Bento \(item.displayVersionString) is available."
    }
    func updaterDidNotFindUpdate(_ updater: SPUUpdater, error: Error) { status = "No compatible update is available." }
    func updater(_ updater: SPUUpdater, didAbortWithError error: Error) {
        installationTask?.cancel(); installationTask = nil
        preparingInstallation = false; installationPrepared = false; pendingInstallation = false; resumeInstallation = nil
        status = "Update check stopped: \(error.localizedDescription)"
    }
    func updater(_ updater: SPUUpdater, shouldPostponeRelaunchForUpdate item: SUAppcastItem, untilInvokingBlock installHandler: @escaping () -> Void) -> Bool {
        shouldPostponeInstallation(installHandler)
    }
    func shouldPostponeInstallation(_ handler: @escaping () -> Void) -> Bool {
        // Sparkle can ask again after its retained continuation resumes. Returning
        // true a second time without retaining a continuation leaves Relaunch inert.
        guard !installationPrepared else { return false }
        postponeInstallation(handler)
        return true
    }
    func postponeInstallation(_ handler: @escaping () -> Void) {
        guard resumeInstallation == nil, !installationPrepared else { return }
        resumeInstallation = handler; pendingInstallation = true
        retryInstall()
    }
    func retryInstall() {
        guard installationTask == nil, resumeInstallation != nil else { return }
        preparingInstallation = true; status = "Preparing to install — keeping your windows in place…"
        installationTask = Task { @MainActor in
            let prepared = await beforeInstall?() ?? true
            guard !Task.isCancelled else { return }
            preparingInstallation = false; installationTask = nil
            if prepared {
                installationPrepared = true
                let resume = resumeInstallation; resumeInstallation = nil; pendingInstallation = false
                status = "Installing update and relaunching Bento…"
                resume?()
            } else {
                pendingInstallation = true
                status = "The update is ready, but desktop preferences could not be released. Retry installation here."
                onInstallationNeedsAttention?()
            }
        }
    }
}

struct UpdatesView: View {
    @ObservedObject var updater: MacUpdater
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                Image(nsImage: BentoStyle.icon).resizable().frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 5) {
                    Text("Bento for macOS").font(.system(size: 18, weight: .semibold))
                    Text("Version \(updater.version)").font(.system(size: 12)).foregroundStyle(BentoStyle.secondary)
                }
            }
            BentoCard {
                VStack(alignment: .leading, spacing: 18) {
                    Text(updater.status).font(.system(size: 13)).lineSpacing(4).foregroundStyle(BentoStyle.secondary)
                    Button("Check for updates") { updater.check() }.buttonStyle(PrimaryButtonStyle()).disabled(!updater.ready || !updater.canCheck)
                    if updater.preparingInstallation { ProgressView("Preparing installation…") }
                    else if updater.pendingInstallation { Button("Retry installation") { updater.retryInstall() } }
                    Divider()
                    HStack(spacing: 20) {
                        Text("Check for updates automatically").frame(maxWidth: .infinity, alignment: .leading)
                        Toggle("Check for updates automatically", isOn: Binding(get: { updater.automaticallyChecks }, set: { updater.setAutomaticChecks($0) })).labelsHidden().toggleStyle(.switch).fixedSize()
                    }
                    HStack(spacing: 20) {
                        Text("Download updates automatically").frame(maxWidth: .infinity, alignment: .leading)
                        Toggle("Download updates automatically", isOn: Binding(get: { updater.automaticallyInstalls }, set: { updater.setAutomaticInstall($0) })).labelsHidden().toggleStyle(.switch).fixedSize()
                    }
                    Text("Bento verifies update signatures and keeps windows in place when updating or quitting. Session saves end when Bento restarts.").font(.system(size: 11)).lineSpacing(4).foregroundStyle(BentoStyle.secondary)
                }.font(.system(size: 12)).disabled(!updater.ready)
            }
            Link(destination: URL(string: "https://github.com/AbdullahEgh/Bento-Layout/releases")!) { Label("View releases on GitHub", systemImage: "arrow.up.right.square") }
        }
    }
}
