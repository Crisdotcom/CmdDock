import AppKit
import ApplicationServices
import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: CommandStore

    var body: some View {
        TabView {
            GeneralSettings(settings: settings)
                .tabItem { Label("General", systemImage: "gearshape") }
            ImportSettings(store: store)
                .tabItem { Label("Importar", systemImage: "square.and.arrow.down") }
        }
        .frame(width: 560, height: 560)
    }
}

// MARK: - General

struct GeneralSettings: View {
    @ObservedObject var settings: AppSettings
    @State private var axTrusted = AXIsProcessTrusted()
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    private let timer = Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()

    var body: some View {
        Form {
            Section("Atajo de teclado") {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Abrir CmdDock")
                        Text("Haz clic y pulsa la nueva combinación. ⎋ para cancelar.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    HotKeyRecorder(hotKey: $settings.hotKey)
                }
                if settings.hotKeyFailed {
                    Label("Esa combinación ya la usa otra app. Elige otra.", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.callout)
                }
            }

            Section {
                Picker("Terminal predeterminada", selection: $settings.defaultTerminal) {
                    ForEach(TerminalApp.allCases) { t in
                        Text(t.displayName + (t.isInstalled ? "" : " (no instalada)")).tag(t)
                    }
                }
                Picker("Abrir comando en", selection: $settings.defaultMode) {
                    ForEach(OpenMode.allCases) { Text($0.displayName).tag($0) }
                }
                Toggle("Ejecutar automáticamente (pulsar ↩)", isOn: $settings.pressReturn)
                LabeledContent("Espera tras abrir pestaña") {
                    HStack {
                        Slider(value: $settings.tabDelay, in: 0.1...2.0, step: 0.05)
                            .frame(width: 160)
                        Text(String(format: "%.2f s", settings.tabDelay))
                            .monospacedDigit()
                            .frame(width: 50, alignment: .trailing)
                    }
                }
            } header: {
                Text("Terminal")
            } footer: {
                Text("Cada comando puede sobrescribir la terminal y el modo desde su editor. Si la pestaña nueva tarda en abrirse y el comando se pierde, sube la espera. En Terminal.app el comando siempre se ejecuta.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                Picker("Un clic en la fila", selection: $settings.singleClickAction) {
                    ForEach(ClickAction.allCases) { Text($0.displayName).tag($0) }
                }
                Picker("Doble clic en la fila", selection: $settings.doubleClickAction) {
                    ForEach(ClickAction.allCases) { Text($0.displayName).tag($0) }
                }
            } header: {
                Text("Acciones de clic")
            } footer: {
                Text("Los botones de la fila (asa, copiar, editar, ejecutar) mantienen su función. Con el doble clic activado, el clic simple espera un instante para distinguirlos.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                HStack {
                    Image(systemName: axTrusted ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundStyle(axTrusted ? .green : .red)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Accesibilidad")
                        Text(axTrusted ? "Concedido" : "Necesario para Warp, Ghostty y pestañas nuevas en Terminal")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !axTrusted {
                        Button("Conceder…") {
                            let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                            AXIsProcessTrustedWithOptions(opts)
                            NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                }
                HStack {
                    Image(systemName: "applescript").foregroundStyle(.secondary)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Automatización")
                        Text("macOS lo pedirá la primera vez que ejecutes un comando en cada terminal")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Abrir…") {
                        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")!)
                    }
                }
            } header: {
                Text("Permisos")
            }

            Section("Sistema") {
                Toggle("Abrir CmdDock al iniciar sesión", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                            loginError = nil
                        } catch {
                            loginError = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
                if let loginError {
                    Text(loginError).font(.caption).foregroundStyle(.red)
                }
                HStack {
                    Button("Mostrar comandos en Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([CommandStore.fileURL])
                    }
                    Spacer()
                    Button("Salir de CmdDock") { NSApp.terminate(nil) }
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(timer) { _ in axTrusted = AXIsProcessTrusted() }
    }
}

// MARK: - HotKey recorder

struct HotKeyRecorder: View {
    @Binding var hotKey: HotKey
    @State private var recording = false
    @State private var monitor: Any?

    var body: some View {
        Button(action: { recording ? stop() : start() }) {
            Text(recording ? "Pulsa la combinación…" : hotKey.display)
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .frame(minWidth: 150)
                .foregroundStyle(recording ? Color.accentColor : .primary)
        }
        .controlSize(.large)
        .onDisappear { stop() }
    }

    private func start() {
        recording = true
        HotKeyManager.shared.unregister()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                stop()
                return nil
            }
            let mods = event.modifierFlags.intersection([.command, .option, .control])
            let isFKey = HotKey.functionKeys[event.keyCode] != nil
            guard !mods.isEmpty || isFKey else {
                NSSound.beep() // necesita al menos ⌘, ⌥ o ⌃
                return nil
            }
            hotKey = HotKey(event: event) // didSet registra el atajo
            stop(reRegister: false)
            return nil
        }
    }

    private func stop(reRegister: Bool = true) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if recording && reRegister { AppSettings.shared.registerHotKey() }
        recording = false
    }
}

// MARK: - Import

struct ImportSettings: View {
    @ObservedObject var store: CommandStore
    @State private var text = ""
    @State private var result: String?

    private var parsed: [Command] { CommandStore.parseImport(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Pega aquí el contenido de tu nota")
                .font(.headline)
            Text("Una línea = un comando. Para ponerle nombre usa `Nombre :: comando`. Las líneas vacías o que empiezan por # se ignoran, y se quitan viñetas como «- » o «$ ».")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            TextEditor(text: $text)
                .font(.system(size: 12, design: .monospaced))
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).stroke(Color.primary.opacity(0.15)))
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Backend :: cd ~/proyectos/api && npm run dev\ndocker compose up -d\n# esto se ignora")
                            .font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(.tertiary)
                            .padding(13)
                            .allowsHitTesting(false)
                    }
                }

            HStack {
                if let result {
                    Label(result, systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                }
                Spacer()
                Button("Pegar del portapapeles") {
                    text = NSPasteboard.general.string(forType: .string) ?? text
                }
                Button("Importar \(parsed.count) comando\(parsed.count == 1 ? "" : "s")") {
                    let items = parsed
                    store.commands.append(contentsOf: items)
                    result = "\(items.count) importados"
                    text = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(parsed.isEmpty)
            }
        }
        .padding(20)
    }
}
