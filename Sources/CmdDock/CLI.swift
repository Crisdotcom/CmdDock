import Foundation

/// Uso desde la terminal (Homebrew instala el binario como `cmddock`):
///
///     cmddock                    abre la app
///     cmddock scan               muestra la propuesta de grupos a partir del historial
///     cmddock scan --apply       la añade a CmdDock (pide confirmación; -y para no preguntar)
///     cmddock scan --json        salida en JSON
///     cmddock scan --limit 60    número máximo de comandos (40 por defecto)
///     cmddock --version
enum CLI {
    static let reloadNotification = Notification.Name("io.github.crisdotcom.CmdDock.reload")

    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    /// Devuelve un código de salida si los argumentos piden el modo CLI; nil para abrir la app.
    static func runIfRequested(_ args: [String]) -> Int32? {
        // LaunchServices puede pasar argumentos propios (-psn_…, -NSDocumentRevisionsDebugMode…)
        guard let first = args.first, !first.hasPrefix("-psn"), !first.hasPrefix("-NS"), !first.hasPrefix("-Apple") else {
            return nil
        }
        switch first {
        case "scan": return scan(Array(args.dropFirst()))
        case "--version", "-v", "version": print("CmdDock \(version)"); return 0
        case "--help", "-h", "help": printHelp(); return 0
        default:
            FileHandle.standardError.write("Opción desconocida: \(first)\n\n".data(using: .utf8)!)
            printHelp()
            return 64
        }
    }

    private static func printHelp() {
        print("""
        CmdDock \(version) — lanzador de comandos de terminal

        Uso:
          cmddock                    abre la app (o usa el atajo de teclado)
          cmddock scan               analiza tu historial y propone grupos (no cambia nada)
          cmddock scan --apply       añade la propuesta a CmdDock (-y para no preguntar)
          cmddock scan --json        salida en JSON
          cmddock scan --limit N     máximo de comandos a proponer (por defecto 40)
          cmddock --version

        El análisis es local: lee el historial de Warp, zsh, bash y fish en tu Mac,
        descarta comandos triviales, destructivos o con secretos, y no envía nada fuera.
        """)
    }

    private static func scan(_ args: [String]) -> Int32 {
        let apply = args.contains("--apply")
        let json = args.contains("--json")
        let yes = args.contains("-y") || args.contains("--yes")
        var options = HistoryScanner.Options()
        if let i = args.firstIndex(of: "--limit"), i + 1 < args.count, let n = Int(args[i + 1]), n > 0 {
            options.limit = n
        }
        let store = CommandStore.shared
        if !args.contains("--include-existing") {
            options.excluding = Set(store.commands.map(\.command))
        }

        let proposal = HistoryScanner.scan(options)
        let count = proposal.groups.reduce(0) { $0 + $1.commands.count }

        if json {
            let payload: [String: Any] = [
                "sources": proposal.sources,
                "entries": proposal.totalEntries,
                "groups": proposal.groups.map { g in
                    ["name": g.name, "commands": g.commands.map { c in
                        ["name": c.name, "command": c.command, "directory": c.directory as Any, "count": c.count]
                    }]
                },
            ]
            if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
                print(String(decoding: data, as: UTF8.self))
            }
        } else {
            printProposal(proposal)
        }

        guard count > 0 else {
            if !json { print("No hay comandos nuevos que proponer.") }
            return 0
        }
        guard apply else {
            if !json { print("\nNo se ha cambiado nada. Para añadirlos: cmddock scan --apply") }
            return 0
        }
        if !yes {
            guard isatty(STDIN_FILENO) != 0 else {
                FileHandle.standardError.write("Usa --apply -y para confirmar sin terminal interactiva.\n".data(using: .utf8)!)
                return 1
            }
            print("\n¿Añadir \(count) comandos a CmdDock? [s/N] ", terminator: "")
            let answer = (readLine() ?? "").trimmingCharacters(in: .whitespaces).lowercased()
            guard ["s", "si", "sí", "y", "yes"].contains(answer) else {
                print("Cancelado.")
                return 0
            }
        }
        let added = HistoryScanner.apply(proposal.groups, to: store)
        DistributedNotificationCenter.default().postNotificationName(reloadNotification, object: nil, userInfo: nil, deliverImmediately: true)
        print("✓ \(added) comandos añadidos a CmdDock.")
        return 0
    }

    private static func printProposal(_ p: HistoryScanner.Proposal) {
        let tty = isatty(STDOUT_FILENO) != 0
        func bold(_ s: String) -> String { tty ? "\u{1B}[1m\(s)\u{1B}[0m" : s }
        func dim(_ s: String) -> String { tty ? "\u{1B}[2m\(s)\u{1B}[0m" : s }

        let sources = p.sources.isEmpty ? "ninguna" : Array(Set(p.sources)).sorted().joined(separator: ", ")
        print(bold("CmdDock") + " — propuesta a partir de \(p.totalEntries) entradas de historial (\(sources))\n")
        for g in p.groups {
            print(bold("■ \(g.name)") + dim("  (\(g.commands.count))"))
            for c in g.commands {
                let count = String(format: "%5d×", c.count)
                let dir = c.directory.map { dim("  en \($0)") } ?? ""
                print("  \(dim(count))  \(c.name)\(dir)")
                if c.name != c.command {
                    let line = c.command.replacingOccurrences(of: "\n", with: " ⏎ ")
                    print("          " + dim(line.count > 100 ? String(line.prefix(99)) + "…" : line))
                }
            }
            print("")
        }
    }
}

/// Copia los ajustes de la versión anterior (bundle id `local.cmddock.app`).
func migrateLegacyDefaults() {
    let d = UserDefaults.standard
    guard !d.bool(forKey: "migratedLegacyDefaults") else { return }
    if let old = d.persistentDomain(forName: "local.cmddock.app") {
        for (key, value) in old where d.object(forKey: key) == nil {
            d.set(value, forKey: key)
        }
    }
    d.set(true, forKey: "migratedLegacyDefaults")
}
