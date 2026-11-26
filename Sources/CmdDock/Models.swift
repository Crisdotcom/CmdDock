import AppKit
import Carbon
import Foundation

// MARK: - Terminal

enum TerminalApp: String, Codable, CaseIterable, Identifiable {
    case warp, terminal, iterm, ghostty

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .warp: "Warp"
        case .terminal: "Terminal"
        case .iterm: "iTerm2"
        case .ghostty: "Ghostty"
        }
    }

    var bundleID: String {
        switch self {
        case .warp: "dev.warp.Warp-Stable"
        case .terminal: "com.apple.Terminal"
        case .iterm: "com.googlecode.iterm2"
        case .ghostty: "com.mitchellh.ghostty"
        }
    }

    var isInstalled: Bool {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
    }
}

enum OpenMode: String, Codable, CaseIterable, Identifiable {
    case newTab, newWindow, currentTab

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .newTab: "Nueva pestaña"
        case .newWindow: "Nueva ventana"
        case .currentTab: "Pestaña actual"
        }
    }
}

/// Qué hace un clic / doble clic sobre una fila.
enum ClickAction: String, Codable, CaseIterable, Identifiable {
    case none, copy, run, edit

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .none: "Desactivado (solo seleccionar)"
        case .copy: "Copiar comando"
        case .run: "Ejecutar"
        case .edit: "Editar"
        }
    }
}

// MARK: - Command

struct Command: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var command: String
    /// Carpeta donde ejecutar (opcional). Se antepone `cd <dir> &&`.
    var directory: String?
    /// nil = usar la terminal predeterminada de Ajustes.
    var terminal: TerminalApp?
    /// nil = usar el modo predeterminado de Ajustes.
    var openMode: OpenMode?
    /// nil = sin grupo (solo aparece en «Todos»).
    var groupID: UUID?

    var hasOverride: Bool { terminal != nil || openMode != nil }
}

struct CommandGroup: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
}

/// Formato del archivo commands.json.
private struct Library: Codable {
    var groups: [CommandGroup]
    var commands: [Command]
}

// MARK: - HotKey

struct HotKey: Codable, Equatable {
    var keyCode: UInt32
    var modifiers: UInt32 // Carbon modifiers
    var display: String

    static let `default` = HotKey(keyCode: 40, modifiers: UInt32(cmdKey | optionKey), display: "⌥⌘K")

    init(keyCode: UInt32, modifiers: UInt32, display: String) {
        self.keyCode = keyCode
        self.modifiers = modifiers
        self.display = display
    }

    init(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        var carbon: UInt32 = 0
        var symbols = ""
        if flags.contains(.control) { carbon |= UInt32(controlKey); symbols += "⌃" }
        if flags.contains(.option) { carbon |= UInt32(optionKey); symbols += "⌥" }
        if flags.contains(.shift) { carbon |= UInt32(shiftKey); symbols += "⇧" }
        if flags.contains(.command) { carbon |= UInt32(cmdKey); symbols += "⌘" }
        keyCode = UInt32(event.keyCode)
        modifiers = carbon
        display = symbols + HotKey.keyName(event.keyCode, chars: event.charactersIgnoringModifiers)
    }

    static let functionKeys: [UInt16: String] = [
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
        105: "F13", 107: "F14", 113: "F15", 106: "F16", 64: "F17", 79: "F18", 80: "F19",
    ]

    static func keyName(_ code: UInt16, chars: String?) -> String {
        if let f = functionKeys[code] { return f }
        switch code {
        case 49: return "Espacio"
        case 36: return "↩"
        case 48: return "⇥"
        case 51: return "⌫"
        case 53: return "⎋"
        case 123: return "←"
        case 124: return "→"
        case 125: return "↓"
        case 126: return "↑"
        default: return (chars ?? "?").uppercased()
        }
    }
}

// MARK: - Settings

final class AppSettings: ObservableObject {
    static let shared = AppSettings()
    static let minTabDelay = 0.5
    private let d = UserDefaults.standard

    @Published var hotKey: HotKey {
        didSet {
            if let data = try? JSONEncoder().encode(hotKey) { d.set(data, forKey: "hotKey") }
            registerHotKey()
        }
    }
    @Published var defaultTerminal: TerminalApp { didSet { d.set(defaultTerminal.rawValue, forKey: "defaultTerminal") } }
    @Published var defaultMode: OpenMode { didSet { d.set(defaultMode.rawValue, forKey: "defaultMode") } }
    /// Pulsar Enter tras pegar (ejecutar) o solo dejar el comando escrito.
    @Published var pressReturn: Bool { didSet { d.set(pressReturn, forKey: "pressReturn") } }
    /// Espera (segundos) tras abrir la pestaña/ventana antes de pegar.
    @Published var tabDelay: Double { didSet { d.set(tabDelay, forKey: "tabDelay") } }
    /// Ventana fija: no se oculta al perder el foco ni al ejecutar.
    @Published var pinned: Bool { didSet { d.set(pinned, forKey: "pinned") } }
    @Published var singleClickAction: ClickAction { didSet { d.set(singleClickAction.rawValue, forKey: "singleClickAction") } }
    @Published var doubleClickAction: ClickAction { didSet { d.set(doubleClickAction.rawValue, forKey: "doubleClickAction") } }
    @Published var hotKeyFailed = false

    private init() {
        if let data = d.data(forKey: "hotKey"), let hk = try? JSONDecoder().decode(HotKey.self, from: data) {
            hotKey = hk
        } else {
            hotKey = .default
        }
        let installedDefault: TerminalApp = TerminalApp.warp.isInstalled ? .warp : .terminal
        defaultTerminal = TerminalApp(rawValue: d.string(forKey: "defaultTerminal") ?? "") ?? installedDefault
        defaultMode = OpenMode(rawValue: d.string(forKey: "defaultMode") ?? "") ?? .newTab
        pressReturn = d.object(forKey: "pressReturn") as? Bool ?? true
        // Mínimo 0,5 s: Warp descarta lo que se escribe antes de terminar de arrancar la shell.
        tabDelay = max(d.object(forKey: "tabDelay") as? Double ?? 0.8, AppSettings.minTabDelay)
        pinned = d.bool(forKey: "pinned")
        singleClickAction = ClickAction(rawValue: d.string(forKey: "singleClickAction") ?? "") ?? .copy
        doubleClickAction = ClickAction(rawValue: d.string(forKey: "doubleClickAction") ?? "") ?? .run
    }

    func registerHotKey() {
        hotKeyFailed = !HotKeyManager.shared.register(hotKey)
    }
}

// MARK: - Store

final class CommandStore: ObservableObject {
    static let shared = CommandStore()

    @Published var commands: [Command] = [] {
        didSet { save() }
    }
    @Published var groups: [CommandGroup] = [] {
        didSet { save() }
    }

    /// Comandos en ejecución (estado temporal, no se guarda).
    @Published var running: Set<UUID> = []

    static var folderURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("CmdDock", isDirectory: true)
    }

    static var fileURL: URL { folderURL.appendingPathComponent("commands.json") }

    private var loading = false

    private init() { load() }

    func load() {
        loading = true
        defer { loading = false }
        let data = try? Data(contentsOf: Self.fileURL)
        if let data, let lib = try? JSONDecoder().decode(Library.self, from: data) {
            groups = lib.groups
            commands = lib.commands
        } else if let data, let list = try? JSONDecoder().decode([Command].self, from: data) {
            commands = list // formato antiguo (solo lista de comandos)
        } else {
            commands = [
                Command(name: "Estado de git", command: "git status"),
                Command(name: "Puertos escuchando", command: "lsof -iTCP -sTCP:LISTEN -n -P"),
                Command(name: "Actualizar Homebrew", command: "brew update && brew upgrade"),
            ]
            loading = false
            save()
        }
    }

    func save() {
        guard !loading else { return }
        try? FileManager.default.createDirectory(at: Self.folderURL, withIntermediateDirectories: true)
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? enc.encode(Library(groups: groups, commands: commands)) {
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }

    func upsert(_ c: Command) {
        if let i = commands.firstIndex(where: { $0.id == c.id }) {
            commands[i] = c
        } else {
            commands.append(c)
        }
    }

    func delete(_ c: Command) -> Int? {
        guard let i = commands.firstIndex(where: { $0.id == c.id }) else { return nil }
        commands.remove(at: i)
        return i
    }

    func insert(_ c: Command, at i: Int) {
        commands.insert(c, at: min(i, commands.count))
    }

    func move(_ c: Command, by offset: Int) {
        guard let i = commands.firstIndex(where: { $0.id == c.id }) else { return }
        let j = i + offset
        guard j >= 0, j < commands.count else { return }
        commands.swapAt(i, j)
    }

    /// Mueve `id` a la posición de `target` (para arrastrar y soltar).
    func moveCommand(_ id: UUID, to target: UUID) {
        guard id != target,
              let from = commands.firstIndex(where: { $0.id == id }),
              let to = commands.firstIndex(where: { $0.id == target }) else { return }
        let item = commands.remove(at: from)
        commands.insert(item, at: to)
    }

    func setGroup(_ commandID: UUID, to groupID: UUID?) {
        guard let i = commands.firstIndex(where: { $0.id == commandID }) else { return }
        commands[i].groupID = groupID
    }

    // MARK: Grupos

    @discardableResult
    func addGroup(named name: String) -> CommandGroup {
        let g = CommandGroup(name: name)
        groups.append(g)
        return g
    }

    func renameGroup(_ id: UUID, to name: String) {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        groups[i].name = name
    }

    /// Elimina el grupo; sus comandos se conservan sin grupo.
    func deleteGroup(_ id: UUID) {
        for i in commands.indices where commands[i].groupID == id {
            commands[i].groupID = nil
        }
        groups.removeAll { $0.id == id }
    }

    func moveGroup(_ id: UUID, by offset: Int) {
        guard let i = groups.firstIndex(where: { $0.id == id }) else { return }
        let j = i + offset
        guard j >= 0, j < groups.count else { return }
        groups.swapAt(i, j)
    }

    func groupName(_ id: UUID?) -> String? {
        guard let id else { return nil }
        return groups.first { $0.id == id }?.name
    }

    /// Importa texto pegado (p. ej. desde Notas). Una línea = un comando.
    /// Formato opcional: `Nombre :: comando`. Las líneas vacías o que empiezan por `#` se ignoran.
    static func parseImport(_ text: String) -> [Command] {
        text.components(separatedBy: .newlines).compactMap { raw in
            var line = raw.trimmingCharacters(in: .whitespaces)
            // Quitar viñetas típicas de Notas
            for prefix in ["- ", "• ", "* ", "$ "] where line.hasPrefix(prefix) {
                line = String(line.dropFirst(prefix.count))
            }
            guard !line.isEmpty, !line.hasPrefix("#") else { return nil }
            if let r = line.range(of: " :: ") {
                let name = String(line[..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
                let cmd = String(line[r.upperBound...]).trimmingCharacters(in: .whitespaces)
                guard !cmd.isEmpty else { return nil }
                return Command(name: name.isEmpty ? cmd : name, command: cmd)
            }
            let name = line.count > 40 ? String(line.prefix(40)) + "…" : line
            return Command(name: name, command: line)
        }
    }
}
