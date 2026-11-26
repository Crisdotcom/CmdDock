import AppKit
import SwiftUI

extension Notification.Name {
    static let panelDidShow = Notification.Name("CmdDockPanelDidShow")
}

final class CommandPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    override func cancelOperation(_ sender: Any?) { AppDelegate.shared.hidePanel(restoreFocus: true) }
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    static var shared: AppDelegate!

    let store = CommandStore.shared
    let settings = AppSettings.shared
    private var statusItem: NSStatusItem!
    private var panel: CommandPanel!
    private var settingsWindow: NSWindow?
    private var onboardingWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        buildPanel()
        buildStatusItem()
        HotKeyManager.shared.onPress = { [weak self] in self?.togglePanel() }
        settings.registerHotKey()

        // `cmddock scan --apply` avisa para recargar los comandos sin reiniciar la app.
        DistributedNotificationCenter.default().addObserver(
            forName: CLI.reloadNotification, object: nil, queue: .main
        ) { [weak self] _ in self?.store.load() }

        let d = UserDefaults.standard
        let firstLaunch = !d.bool(forKey: "launchedBefore")
        d.set(true, forKey: "launchedBefore")
        if !d.bool(forKey: "onboardingDone") {
            if store.hasOnlySeedCommands {
                // Instalación nueva: ofrecer analizar el historial (se puede omitir).
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.openOnboarding() }
                return
            }
            d.set(true, forKey: "onboardingDone") // usuario existente con comandos propios
        }
        if firstLaunch {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self.showPanel() }
        }
    }

    // MARK: Onboarding

    @objc func openOnboarding() {
        hidePanel(restoreFocus: false)
        if onboardingWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 580),
                styleMask: [.titled, .closable],
                backing: .buffered, defer: false
            )
            w.title = "Bienvenido a CmdDock"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: OnboardingView(
                store: store,
                hotKey: settings.hotKey.display,
                onFinish: { [weak self] in self?.finishOnboarding() }
            ))
            w.center()
            onboardingWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow?.makeKeyAndOrderFront(nil)
    }

    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingDone")
        onboardingWindow?.close()
        onboardingWindow = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.showPanel() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showPanel()
        return true
    }

    // MARK: Panel

    private func buildPanel() {
        panel = CommandPanel(
            contentRect: NSRect(x: 0, y: 0, width: 680, height: 440),
            styleMask: [.titled, .fullSizeContentView, .closable],
            backing: .buffered, defer: false
        )
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = false // evita conflicto con arrastrar filas
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        [.closeButton, .miniaturizeButton, .zoomButton].forEach { panel.standardWindowButton($0)?.isHidden = true }
        panel.delegate = self

        let view = PanelView(
            store: store, settings: settings,
            onRun: { [weak self] cmd in self?.run(cmd) },
            onHide: { [weak self] in self?.hidePanel(restoreFocus: true) },
            onSettings: { [weak self] in self?.openSettings() }
        )
        panel.contentView = NSHostingView(rootView: view)
    }

    func togglePanel() {
        if panel.isVisible && panel.isKeyWindow {
            hidePanel(restoreFocus: true)
        } else {
            showPanel()
        }
    }

    func showPanel() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        if let vf = screen?.visibleFrame {
            let size = panel.frame.size
            let origin = NSPoint(x: vf.midX - size.width / 2, y: vf.minY + vf.height * 0.62 - size.height / 2)
            panel.setFrameOrigin(origin)
        }
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .panelDidShow, object: nil)
    }

    func hidePanel(restoreFocus: Bool) {
        guard panel.isVisible else { return }
        panel.orderOut(nil)
        if restoreFocus, settingsWindow?.isVisible != true {
            NSApp.hide(nil) // devuelve el foco a la app anterior
        }
    }

    func windowDidResignKey(_ notification: Notification) {
        if (notification.object as? NSWindow) === panel, !settings.pinned {
            hidePanel(restoreFocus: false)
        }
    }

    private func run(_ cmd: Command) {
        guard !store.running.contains(cmd.id) else { return } // evita ejecuciones duplicadas
        store.running.insert(cmd.id)
        if !settings.pinned { hidePanel(restoreFocus: false) }
        Runner.run(cmd, settings: settings) { [weak self] error in
            self?.store.running.remove(cmd.id)
            guard let error else { return }
            NSApp.activate(ignoringOtherApps: true)
            let alert = NSAlert()
            alert.messageText = "No se pudo ejecutar «\(cmd.name)»"
            alert.informativeText = error
            alert.addButton(withTitle: "OK")
            if error.contains("Accesibilidad") || error.contains("Automatización") {
                alert.addButton(withTitle: "Abrir Ajustes del Sistema")
            }
            if alert.runModal() == .alertSecondButtonReturn {
                let pane = error.contains("Accesibilidad") ? "Privacy_Accessibility" : "Privacy_Automation"
                NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?\(pane)")!)
            }
        }
    }

    // MARK: Settings

    @objc func openSettings() {
        hidePanel(restoreFocus: false)
        if settingsWindow == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered, defer: false
            )
            w.title = "Ajustes de CmdDock"
            w.isReleasedWhenClosed = false
            w.contentViewController = NSHostingController(rootView: SettingsView(settings: settings, store: store))
            w.center()
            settingsWindow = w
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Status item

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "terminal", accessibilityDescription: "CmdDock")
        let menu = NSMenu()
        menu.delegate = self
        statusItem.menu = menu
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        let open = NSMenuItem(title: "Abrir CmdDock   \(settings.hotKey.display)", action: #selector(menuOpen), keyEquivalent: "")
        open.target = self
        menu.addItem(open)

        let runItem = NSMenuItem(title: "Ejecutar", action: nil, keyEquivalent: "")
        let sub = NSMenu()
        func commandItem(_ cmd: Command) -> NSMenuItem {
            let item = NSMenuItem(title: cmd.name, action: #selector(menuRun(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = cmd.id
            item.toolTip = cmd.command
            return item
        }
        // Un submenú por grupo y, debajo, los comandos sin grupo
        for g in store.groups {
            let cmds = store.commands.filter { $0.groupID == g.id }
            guard !cmds.isEmpty else { continue }
            let groupItem = NSMenuItem(title: g.name, action: nil, keyEquivalent: "")
            let groupMenu = NSMenu()
            cmds.forEach { groupMenu.addItem(commandItem($0)) }
            groupItem.submenu = groupMenu
            sub.addItem(groupItem)
        }
        let ungrouped = store.commands.filter { store.groupName($0.groupID) == nil }
        if !ungrouped.isEmpty && sub.numberOfItems > 0 { sub.addItem(.separator()) }
        ungrouped.forEach { sub.addItem(commandItem($0)) }
        if store.commands.isEmpty { sub.addItem(NSMenuItem(title: "Sin comandos", action: nil, keyEquivalent: "")) }
        runItem.submenu = sub
        menu.addItem(runItem)

        menu.addItem(.separator())
        let scan = NSMenuItem(title: "Analizar historial…", action: #selector(openOnboarding), keyEquivalent: "")
        scan.target = self
        menu.addItem(scan)
        let s = NSMenuItem(title: "Ajustes…", action: #selector(openSettings), keyEquivalent: ",")
        s.target = self
        menu.addItem(s)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Salir de CmdDock", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
    }

    @objc private func menuOpen() { DispatchQueue.main.async { self.showPanel() } }

    @objc private func menuRun(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? UUID, let cmd = store.commands.first(where: { $0.id == id }) else { return }
        run(cmd)
    }
}

// Modo línea de comandos: `cmddock scan`, `cmddock --version`… (sin interfaz).
if let code = CLI.runIfRequested(Array(CommandLine.arguments.dropFirst())) {
    exit(code)
}

migrateLegacyDefaults()

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
