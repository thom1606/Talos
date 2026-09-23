//
//  TalosApp.swift
//  Talos
//
//  Created by Thom van den Broek on 21/09/2026.
//

import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private lazy var toastController = ToastController()
    private lazy var dialogController = DialogController()
    private lazy var extensionWindowController = ExtensionWindowController()
    fileprivate let notificationService = NotificationService()
    fileprivate lazy var repositoriesModel = RepositoriesModel(notifications: notificationService) { [weak self] in
        self?.reloadExtensions()
    }
    private lazy var sdkRuntime = SDKRuntime { [weak self] event in
        if case let .console(message) = event {
            message.writeToLog()
            return
        }
        Task { @MainActor [weak self] in
            self?.handleRuntimeEvent(event)
        }
    }
    private lazy var actionLibrary = WheelActionLibrary(
        runtime: sdkRuntime,
        openSettings: { [weak self] in
            self?.showSettings()
        },
        reportError: { [weak self] message in
            self?.toastController.show(
                TalosToastRequest(message: message, kind: .failure)
            )
        }
    )
    private lazy var wheelController = DragWheelController(
        actionsProvider: { [weak self] files in
            self?.actionLibrary.actions(for: files) ?? []
        },
        hoverHandler: { [weak self] action in
            self?.actionLibrary.prepare(action)
        },
        selectionHandler: { [weak self] action, files in
            self?.actionLibrary.perform(action, files: files)
        }
    )

    private var extensionLoadTask: Task<Void, Never>?
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?
    private var onboardingCloseObserver: NSObjectProtocol?
    private var settingsWindowCloseObserver: NSObjectProtocol?
    fileprivate let advancedSettingsModel = AdvancedSettingsModel()
    private var isTerminating = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        if !ProcessInfo.processInfo.arguments.contains("--background") {
            NSApp.setActivationPolicy(.regular)
        }

        notificationService.openRepositories = { [weak self] in
            TalosPreferences.defaults.set("repositories", forKey: "selectedSettingsPage")
            self?.showSettings()
        }
        notificationService.start()
        repositoriesModel.updateMonitor.start()
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(didWake),
            name: NSWorkspace.didWakeNotification, object: nil)
        advancedSettingsModel.startUpdater()
        reloadExtensions()
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        showSettings()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if onboardingWindow?.isVisible == true {
            closeOnboarding()
            return .terminateCancel
        }
        if settingsWindow?.isVisible == true {
            closeSettings()
            return .terminateCancel
        }

        guard !isTerminating else { return .terminateNow }
        isTerminating = true
        repositoriesModel.updateMonitor.stop()
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        NotificationCenter.default.removeObserver(self)
        extensionLoadTask?.cancel()
        wheelController.stop()
        toastController.stop()
        extensionWindowController.closeAll()

        Task {
            await sdkRuntime.deactivateAll()
            sender.reply(toApplicationShouldTerminate: true)
        }
        return .terminateLater
    }

    func showSettings() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let onboardingWindow, onboardingWindow.isVisible {
            onboardingWindow.makeKeyAndOrderFront(nil)
            return
        }
        if let settingsWindow, settingsWindow.isVisible {
            settingsWindow.makeKeyAndOrderFront(nil)
            return
        }

        // AppKit events (Dock and wheel) enter the same SwiftUI command as ⌘,.
        // The command's openWindow action owns presentation of the scene.
        if let item = settingsMenuItem(in: NSApp.mainMenu),
           let action = item.action {
            NSApp.sendAction(action, to: item.target, from: item)
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        advancedSettingsModel.refreshLoginItemStatus()
        Task { await notificationService.refreshAuthorization() }
    }

    @objc private func didWake() { repositoriesModel.updateMonitor.checkIfDue() }

    func closeOnboarding() { onboardingWindow?.performClose(nil) }

    func finishOnboarding() {
        closeOnboarding()
        NSWorkspace.shared.open(FileManager.default.homeDirectoryForCurrentUser)
    }

    func onboardingWindowDidChange(_ window: NSWindow) {
        guard onboardingWindow !== window else { return }
        if let onboardingCloseObserver { NotificationCenter.default.removeObserver(onboardingCloseObserver) }
        onboardingWindow = window
        onboardingCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                onboardingWindow = nil
                if settingsWindow?.isVisible != true && !isTerminating { NSApp.setActivationPolicy(.accessory) }
            }
        }
    }

    func closeSettings() {
        settingsWindow?.performClose(nil)
    }

    func settingsWindowDidChange(_ window: NSWindow) {
        guard settingsWindow !== window else { return }

        if let settingsWindowCloseObserver {
            NotificationCenter.default.removeObserver(settingsWindowCloseObserver)
        }

        settingsWindow = window
        settingsWindowCloseObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification,
            object: window,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.settingsDidClose()
            }
        }
    }

    private func settingsDidClose() {
        guard !isTerminating else { return }
        settingsWindow = nil
        if onboardingWindow?.isVisible != true { NSApp.setActivationPolicy(.accessory) }
    }

    private func reloadExtensions() {
        extensionLoadTask?.cancel()

        let runtime = sdkRuntime
        let developmentProjects = LocalProjectLinkStore.load()
        extensionLoadTask = Task { [weak self] in
            guard let self else { return }

            do {
                let failures = try await runtime.loadExtensions(
                    developmentProjects: developmentProjects
                )
                guard !Task.isCancelled else { return }

                for failure in failures {
                    NSLog(
                        "Cannot load Talos extension at %@: %@",
                        failure.directory.path,
                        failure.message
                    )
                }
                let extensions = await runtime.loadedExtensions()
                actionLibrary.update(extensions: extensions)
                repositoriesModel.updateBundledExtensions(extensions)
                wheelController.start()
                if extensions.contains(where: {
                    FileManager.default.fileExists(atPath: $0.directory.appendingPathComponent("windows").path)
                }) {
                    extensionWindowController.prepare()
                }
            } catch is CancellationError {
                // A newer repository refresh has replaced this load.
            } catch {
                NSLog("Cannot load Talos extensions: %@", error.localizedDescription)
                toastController.show(
                    TalosToastRequest(
                        message: error.localizedDescription,
                        kind: .failure
                    )
                )
            }
        }
    }

    private func settingsMenuItem(in menu: NSMenu?) -> NSMenuItem? {
        guard let menu else { return nil }

        for item in menu.items {
            if item.keyEquivalent == ",",
               item.keyEquivalentModifierMask.contains(.command) {
                return item
            }
            if let match = settingsMenuItem(in: item.submenu) {
                return match
            }
        }
        return nil
    }

    private func handleRuntimeEvent(_ event: SDKRuntimeEvent) {
        switch event {
        case let .toast(request):
            toastController.show(request)
        case .dismissToast:
            toastController.dismiss()
        case let .openWindow(request):
            Task {
                do {
                    let resources = try await sdkRuntime.windowResources(for: request)
                    try extensionWindowController.show(request, resources: resources, runtime: sdkRuntime)
                } catch {
                    await sdkRuntime.closeWindow(request)
                    toastController.show(.init(message: error.localizedDescription, kind: .failure))
                }
            }
        case let .dialog(request):
            let value = dialogController.present(request)
            Task { [sdkRuntime] in
                do {
                    try await sdkRuntime.respond(to: request, with: value)
                } catch {
                    NSLog("Cannot answer Talos extension dialog: %@", error.localizedDescription)
                }
            }
        case let .sessionStopped(extensionID, sessionID):
            Task { await sdkRuntime.sessionStopped(extensionID: extensionID, sessionID: sessionID) }
        case let .windowReply(reply):
            Task { await sdkRuntime.completeWindowRequest(reply) }
        case .console:
            break // Console output is handled directly on the pipe's callback queue.
        }
    }
}

@main
struct TalosApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        Window("Talos", id: "settings") {
            SettingsView(
                advancedSettingsModel: delegate.advancedSettingsModel,
                repositoriesModel: delegate.repositoriesModel
            )
            .background {
                SettingsWindowReader { window in
                    delegate.settingsWindowDidChange(window)
                }
            }
        }
        .defaultSize(width: 940, height: 620)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .defaultLaunchBehavior(
            (ProcessInfo.processInfo.arguments.contains("--background") || !TalosPreferences.defaults.bool(forKey: TalosPreferenceKey.completedOnboarding)) ? .suppressed : .presented
        )
        .restorationBehavior(.disabled)
        .commands {
            TalosSettingsCommands()
            SidebarCommands()
        }

        Window("Welcome to Talos", id: "onboarding") {
            OnboardingView(model: delegate.advancedSettingsModel,
                           notifications: delegate.notificationService,
                           onFinish: delegate.finishOnboarding)
                .background {
                    SettingsWindowReader { delegate.onboardingWindowDidChange($0) }
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultPosition(.center)
        .defaultLaunchBehavior(
            (!ProcessInfo.processInfo.arguments.contains("--background") && !TalosPreferences.defaults.bool(forKey: TalosPreferenceKey.completedOnboarding)) ? .presented : .suppressed
        )
        .restorationBehavior(.disabled)
    }
}

private struct TalosSettingsCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                NSApp.setActivationPolicy(.regular)
                openWindow(id: TalosPreferences.defaults.bool(forKey: TalosPreferenceKey.completedOnboarding) ? "settings" : "onboarding")
                NSApp.activate(ignoringOtherApps: true)
            }
            .keyboardShortcut(",", modifiers: .command)
        }
    }
}
