import Foundation
import SQLite3

/// Analiza el historial de la terminal (Warp, zsh, bash, fish) y propone una agrupación
/// inicial de los comandos más usados. Algoritmo determinista basado en reglas, sin IA:
///
/// 1. **Lectura**: comandos de cada fuente. Warp aporta además la carpeta (`pwd`) de cada uso.
/// 2. **Normalización**: une líneas con `\` final, colapsa espacios y extrae `cd <dir> && …`.
/// 3. **Filtrado**: descarta comandos triviales (`ls`, `cd`…), destructivos (`rm`, `delete`…)
///    y cualquiera que parezca contener un secreto (contraseñas, tokens, credenciales en URL).
/// 4. **Recuento**: frecuencia por comando. Como Warp también escribe en el historial de zsh,
///    entre fuentes se toma el máximo (no la suma) para no contar dos veces.
/// 5. **Carpeta**: si el comando depende de la carpeta (`./script`, `npm`, `make`, `.`…) y la
///    mayoría de sus usos fueron en la misma carpeta, se guarda; si no se puede saber, se descarta.
/// 6. **Clasificación**: primero por proyecto (raíz git de su carpeta, si ≥2 comandos la
///    comparten); si no, por categoría según la herramienta (git, docker, cloud, node…).
///    Los grupos de un solo comando poco usado van a «Otros». También se descartan los
///    comandos que casi siempre fallan (typos con código 127, compilaciones rotas).
enum HistoryScanner {

    // MARK: - Modelo

    struct Proposal {
        var sources: [String]
        var totalEntries: Int
        var groups: [ProposedGroup]
    }

    struct ProposedGroup: Identifiable {
        let id = UUID()
        var name: String
        var commands: [ProposedCommand]
        var totalUses: Int { commands.reduce(0) { $0 + $1.count } }
    }

    struct ProposedCommand: Identifiable {
        let id = UUID()
        var name: String
        var command: String
        var directory: String?
        var count: Int
    }

    struct Options {
        var limit = 40
        var minCount = 3
        var excluding: Set<String> = [] // comandos que ya existen en CmdDock
    }

    // MARK: - Entrada

    private struct Entry {
        var command: String
        var pwd: String?
        var exitCode: Int? = nil // solo Warp
    }

    static func scan(_ options: Options = Options()) -> Proposal {
        var sources: [String] = []
        var perSource: [[Entry]] = []

        if let warp = readWarp() { sources.append("Warp"); perSource.append(warp) }
        for (name, path, parser) in shellHistories() {
            if let data = FileManager.default.contents(atPath: path) {
                sources.append(name)
                perSource.append(parser(data).map { Entry(command: $0, pwd: nil) })
            }
        }
        let total = perSource.reduce(0) { $0 + $1.count }
        let groups = classify(perSource: perSource, options: options)
        return Proposal(sources: sources, totalEntries: total, groups: groups)
    }

    // MARK: - Fuentes

    static var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    private static func readWarp() -> [Entry]? {
        let base = home + "/Library/Application Support/"
        let candidates = ["dev.warp.Warp-Stable", "dev.warp.Warp-Preview", "dev.warp.Warp"]
            .map { base + $0 + "/warp.sqlite" }
            .filter { FileManager.default.fileExists(atPath: $0) }
        guard !candidates.isEmpty else { return nil }

        var entries: [Entry] = []
        for path in candidates {
            var db: OpaquePointer?
            guard sqlite3_open_v2(path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
                sqlite3_close(db); continue
            }
            defer { sqlite3_close(db) }
            var stmt: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT command, pwd, exit_code FROM commands", -1, &stmt, nil) == SQLITE_OK else { continue }
            defer { sqlite3_finalize(stmt) }
            while sqlite3_step(stmt) == SQLITE_ROW {
                guard let c = sqlite3_column_text(stmt, 0) else { continue }
                let pwd = sqlite3_column_text(stmt, 1).map { String(cString: $0) }
                let exit: Int? = sqlite3_column_type(stmt, 2) == SQLITE_NULL ? nil : Int(sqlite3_column_int(stmt, 2))
                entries.append(Entry(command: String(cString: c), pwd: pwd, exitCode: exit))
            }
        }
        return entries.isEmpty ? nil : entries
    }

    private static func shellHistories() -> [(String, String, (Data) -> [String])] {
        [
            ("zsh", home + "/.zsh_history", parseZsh),
            ("zsh", home + "/.zhistory", parseZsh),
            ("bash", home + "/.bash_history", parseBash),
            ("fish", home + "/.local/share/fish/fish_history", parseFish),
        ]
    }

    /// zsh guarda caracteres no ASCII "metafied" (0x83 + byte^0x20) y, con EXTENDED_HISTORY,
    /// cada entrada como `: <ts>:<dur>;<comando>`. Las líneas con `\` final continúan.
    static func parseZsh(_ data: Data) -> [String] {
        var bytes = [UInt8]()
        bytes.reserveCapacity(data.count)
        var meta = false
        for b in data {
            if meta { bytes.append(b ^ 0x20); meta = false } else if b == 0x83 { meta = true } else { bytes.append(b) }
        }
        let text = String(decoding: bytes, as: UTF8.self)
        var result: [String] = []
        var current: String?
        for line in text.components(separatedBy: "\n") {
            if let c = current, c.hasSuffix("\\") {
                current = c + "\n" + line
                continue
            }
            if let c = current { result.append(c) }
            if line.hasPrefix(": "), let semi = line.firstIndex(of: ";") {
                current = String(line[line.index(after: semi)...])
            } else {
                current = line
            }
        }
        if let c = current { result.append(c) }
        return result
    }

    static func parseBash(_ data: Data) -> [String] {
        String(decoding: data, as: UTF8.self)
            .components(separatedBy: "\n")
            .filter { !$0.hasPrefix("#") } // marcas de tiempo de HISTTIMEFORMAT
    }

    static func parseFish(_ data: Data) -> [String] {
        String(decoding: data, as: UTF8.self)
            .components(separatedBy: "\n")
            .compactMap { line in
                guard line.hasPrefix("- cmd: ") else { return nil }
                return String(line.dropFirst(7))
                    .replacingOccurrences(of: "\\n", with: "\n")
                    .replacingOccurrences(of: "\\\\", with: "\\")
            }
    }

    // MARK: - Normalización y filtros

    struct Normalized: Hashable {
        var command: String
        var directory: String? // de un prefijo `cd <dir> &&`
    }

    static func normalize(_ raw: String) -> Normalized? {
        var s = raw.replacingOccurrences(of: "\\\n", with: " ")
        s = s.replacingOccurrences(of: "\r", with: "")
        // Colapsar espacios fuera de comillas es complejo; basta con los extremos y los saltos.
        s = s.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.contains("  ") && !s.contains("\"") && !s.contains("'") {
            s = s.replacingOccurrences(of: "  ", with: " ")
        }
        guard s.count >= 2, s.count <= 400 else { return nil }

        var directory: String?
        if s.hasPrefix("cd "), let r = s.range(of: " && ") {
            var dir = String(s[s.index(s.startIndex, offsetBy: 3)..<r.lowerBound]).trimmingCharacters(in: .whitespaces)
            if (dir.hasPrefix("'") && dir.hasSuffix("'")) || (dir.hasPrefix("\"") && dir.hasSuffix("\"")), dir.count >= 2 {
                dir = String(dir.dropFirst().dropLast())
            }
            dir = dir.replacingOccurrences(of: "\\ ", with: " ")
            if dir.hasPrefix("/") || dir.hasPrefix("~") {
                directory = abbreviate(dir)
                s = String(s[r.upperBound...]).trimmingCharacters(in: .whitespaces)
            }
        }
        return Normalized(command: s, directory: directory)
    }

    static let trivial: Set<String> = [
        "ls", "ll", "la", "l", "cd", "pwd", "clear", "cls", "exit", "logout", "history", "cat", "less",
        "more", "echo", "which", "where", "whoami", "man", "z", "j", "reset", "source", ".", "q", ":q",
        "open", "head", "tail", "touch", "mkdir", "cp", "mv", "true", "false", "help", "type", "export",
        "unset", "alias", "date", "cal",
    ]

    static let destructive: Set<String> = ["rm", "rmdir", "shred", "kill", "pkill", "shutdown", "reboot", "halt", "dd", "mkfs", "diskutil"]
    static let destructiveWords: Set<String> = ["delete", "destroy", "drop", "prune", "--force", "purge", "truncate", "uninstall", "reset"]

    private static let secretPatterns: [NSRegularExpression] = [
        #"(?i)(password|passwd|secret|token|api[_-]?key|apikey|access[_-]?key|private[_-]?key|client[_-]?secret)\s*[=:]\s*\S+"#,
        #"(?i)--(password|pass|token|secret|api-key)[= ]\S+"#,
        #"(?i)\bauthorization:\s*\S+"#,
        #"(?i)\bbearer\s+[A-Za-z0-9._~+/-]{10,}"#,
        #"(?:--user|-u)\s+["']?[^"'\s:]+:[^"'\s]+"#,                // curl usuario:clave
        #"[a-z][a-z0-9+.-]*://[^/\s:@]+:[^/\s@]+@"#,                // credenciales en URL
        #"\b(sk|pk|rk)-[A-Za-z0-9_-]{20,}"#,                        // OpenAI / Stripe…
        #"\bgh[pousr]_[A-Za-z0-9]{20,}"#,                           // GitHub
        #"\bxox[abprs]-[A-Za-z0-9-]{10,}"#,                         // Slack
        #"\bAKIA[0-9A-Z]{16}\b"#,                                   // AWS
        #"\bAIza[0-9A-Za-z_-]{30,}"#,                               // Google API key
        #"\beyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"#,            // JWT
        #"(?i)\bexport\s+\w*(KEY|TOKEN|SECRET|PASSWORD|PASS)\w*="#,
    ].compactMap { try? NSRegularExpression(pattern: $0) }

    /// `mysql -pClave`, `mysqldump -u root -pClave`…
    private static let inlinePasswordTools: Set<String> = ["mysql", "mysqldump", "mysqladmin", "mariadb"]

    static func containsSecret(_ s: String) -> Bool {
        let range = NSRange(s.startIndex..., in: s)
        if secretPatterns.contains(where: { $0.firstMatch(in: s, range: range) != nil }) { return true }
        let tokens = tokenize(s)
        if let first = tokens.first.map(executableName), inlinePasswordTools.contains(first),
           tokens.contains(where: { $0.hasPrefix("-p") && $0.count > 2 }) {
            return true
        }
        return false
    }

    static func shouldSkip(_ s: String) -> Bool {
        let tokens = tokenize(s)
        guard let firstRaw = tokens.first else { return true }
        let first = executableName(firstRaw).lowercased()
        if first.hasPrefix("cd.") || first.hasPrefix("cd/") { return true }
        if trivial.contains(first) { return true }
        // `sudo X` → se evalúa X
        let effective = (first == "sudo" && tokens.count > 1) ? executableName(tokens[1]).lowercased() : first
        if destructive.contains(effective) && !s.contains("mDNSResponder") { return true }
        if tokens.contains(where: { destructiveWords.contains($0.lowercased()) }) { return true }
        if tokens.contains("-rf") || tokens.contains("-fr") { return true }
        // Consultas de versión (`php -v`, `node --version`)
        if tokens.count == 2, ["--version", "-v", "-V", "version"].contains(tokens[1]) { return true }
        // Acciones puntuales: clonar repos o instalar un paquete concreto
        if tokens.contains("clone") { return true }
        if tokens.count > 2, tokens[1] == "install" || tokens[1] == "add",
           ["brew", "pip", "pip3", "npm", "pnpm", "yarn", "bun", "gem", "cargo", "go", "uv", "pipx", "mas"].contains(effective),
           tokens.dropFirst(2).contains(where: { !$0.hasPrefix("-") }) {
            return true
        }
        if containsSecret(s) { return true }
        return false
    }

    /// Códigos de salida que indican que el usuario cortó el proceso (Ctrl-C, kill, ssh cerrado):
    /// habituales en túneles y servidores, no son errores.
    static let interruptedExitCodes: Set<Int> = [129, 130, 137, 143, 254, 255]

    /// Carpeta "real": quita los worktrees (`repo/.claude/worktrees/x/sub` → `repo/sub`).
    static func canonicalDirectory(_ path: String) -> String {
        var p = abbreviate(path)
        if let r = p.range(of: #"/\.claude/worktrees/[^/]+"#, options: .regularExpression) {
            p.removeSubrange(r)
        }
        return p
    }

    /// Carpetas temporales donde no tiene sentido fijar un comando.
    static func isTransientDirectory(_ dir: String) -> Bool {
        let d = abbreviate(dir)
        return d == "~/Downloads" || d == "~/Descargas" || d.hasPrefix("~/Downloads/") || d.hasPrefix("~/Descargas/")
            || d.hasPrefix("/tmp") || d.hasPrefix("/private/")
    }

    // MARK: - Utilidades

    static func tokenize(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
    }

    /// `~/google-cloud-sdk/bin/gcloud` → `gcloud`; `./bin/docker-up` → `docker-up`.
    static func executableName(_ token: String) -> String {
        (token as NSString).lastPathComponent
    }

    static func abbreviate(_ path: String) -> String {
        var p = path
        if p.hasPrefix(home) { p = "~" + p.dropFirst(home.count) }
        if p.count > 1, p.hasSuffix("/") { p.removeLast() }
        return p
    }

    static func expand(_ path: String) -> String { (path as NSString).expandingTildeInPath }

    /// Herramientas cuyo resultado depende de la carpeta actual.
    static let cwdTools: Set<String> = [
        "npm", "npx", "yarn", "pnpm", "bun", "deno", "make", "docker-compose", "composer", "artisan",
        "cargo", "go", "swift", "mvn", "gradle", "./gradlew", "eas", "expo", "terraform", "pulumi",
        "poetry", "uv", "pytest", "tox", "bundle", "rails", "rake", "mix", "flutter", "dart", "pod",
        "xcodebuild", "firebase", "vercel", "netlify", "wrangler", "air", "nodemon", "tsc", "vite",
    ]

    static func dependsOnCwd(_ command: String) -> Bool {
        let tokens = tokenize(command)
        guard let first = tokens.first else { return false }
        if first.hasPrefix("./") || first.hasPrefix("../") { return true }
        if first.contains("/") && !first.hasPrefix("/") && !first.hasPrefix("~") { return true }
        if cwdTools.contains(executableName(first)) { return true }
        if tokens.contains(".") || tokens.contains("./") { return true }
        if first == "docker", tokens.count > 1, tokens[1] == "compose" { return true }
        if ["python", "python3", "node", "php", "ruby", "bash", "sh", "zsh"].contains(first),
           let arg = tokens.dropFirst().first(where: { !$0.hasPrefix("-") }),
           !arg.hasPrefix("/"), !arg.hasPrefix("~"), arg.contains(".") || arg.contains("/") {
            return true // python3 script.py, php -S localhost:8000 no entra (sin '/')… salvo `php artisan`
        }
        if first == "php", tokens.contains("-S") || tokens.contains("artisan") { return true }
        return false
    }

    private static let genericDirs: Set<String> = ["~", "/", "~/Desktop", "~/Documents", "~/Downloads", "~/Escritorio", "~/Documentos", "~/Descargas"]

    /// Nombre del proyecto: carpeta raíz con `.git` por encima de `dir`, o la propia carpeta.
    static func projectName(for dir: String) -> String? {
        let abbreviated = abbreviate(dir)
        guard !genericDirs.contains(abbreviated) else { return nil }
        var url = URL(fileURLWithPath: expand(dir))
        let homeURL = URL(fileURLWithPath: home)
        while url.path.count > homeURL.path.count {
            if FileManager.default.fileExists(atPath: url.appendingPathComponent(".git").path) {
                return url.lastPathComponent
            }
            url.deleteLastPathComponent()
        }
        return URL(fileURLWithPath: expand(dir)).lastPathComponent
    }

    // MARK: - Categorías

    static let categories: [(String, Set<String>)] = [
        ("Git", ["git", "gh", "lazygit", "tig", "glab"]),
        ("Docker y Kubernetes", ["docker", "docker-compose", "podman", "kubectl", "k9s", "helm", "minikube", "kind", "colima", "orb"]),
        ("Cloud", ["gcloud", "gsutil", "bq", "aws", "az", "terraform", "pulumi", "firebase", "vercel", "netlify", "fly", "flyctl",
                   "heroku", "doctl", "wrangler", "cloud-sql-proxy", "cloud_sql_proxy", "eas", "railway", "supabase"]),
        ("Node y JavaScript", ["npm", "npx", "yarn", "pnpm", "bun", "node", "deno", "nvm", "tsc", "vite", "next", "expo", "nodemon"]),
        ("Python", ["python", "python3", "pip", "pip3", "poetry", "uv", "pytest", "jupyter", "jupyter-notebook", "jupyter-lab",
                    "conda", "pyenv", "airflow", "ipython", "streamlit", "uvicorn", "gunicorn", "celery", "flask"]),
        ("Bases de datos", ["mysql", "mysqldump", "mariadb", "psql", "pg_dump", "pg_ctl", "redis-cli", "redis-server", "mongo",
                            "mongosh", "mongod", "sqlite3", "sqlcmd", "clickhouse"]),
        ("Servidores web y PHP", ["php", "composer", "artisan", "apachectl", "httpd", "nginx", "valet", "caddy", "symfony"]),
        ("IA local", ["ollama", "llm", "lms", "llama", "llama-server", "mlx_lm", "whisper"]),
        ("Compilación", ["make", "cmake", "cargo", "go", "swift", "xcodebuild", "gradle", "mvn", "flutter", "dart", "pod", "rustc", "gcc", "clang"]),
        ("Red y SSH", ["ssh", "scp", "sftp", "rsync", "ping", "curl", "wget", "http", "ifconfig", "ipconfig", "dig", "nslookup",
                       "nc", "netstat", "traceroute", "mtr", "telnet", "ngrok", "cloudflared", "tailscale", "networkquality", "speedtest"]),
        ("Editores", ["code", "cursor", "zed", "subl", "vim", "nvim", "nano", "emacs", "idea", "webstorm", "xed"]),
        ("Sistema", ["brew", "top", "htop", "btop", "macmon", "ps", "lsof", "df", "du", "memory_pressure", "vm_stat",
                     "softwareupdate", "defaults", "launchctl", "dscacheutil", "killall", "caffeinate", "pmset", "mas",
                     "tmux", "screen", "watch", "tree", "fd", "rg", "fzf", "bat", "jq", "ncdu", "uptime", "sw_vers", "system_profiler"]),
    ]

    static func category(of command: String) -> String? {
        var tokens = tokenize(command)
        if tokens.first == "sudo" { tokens.removeFirst() }
        guard let first = tokens.first.map(executableName)?.lowercased() else { return nil }
        // php -S / php artisan siguen siendo "Servidores web"; python manage.py también es Python.
        return categories.first { $0.1.contains(first) }?.0
    }

    // MARK: - Nombre legible

    static func displayName(_ command: String) -> String {
        let firstLine = command.components(separatedBy: "\n").first ?? command
        var tokens = tokenize(firstLine)
        guard !tokens.isEmpty else { return command }
        if tokens[0] == "sudo", tokens.count > 1 { tokens.removeFirst() }
        tokens[0] = executableName(tokens[0])
        let short = tokens.joined(separator: " ")
        if short.count <= 42 { return command.contains("\n") ? short + " …" : short }
        // Ejecutable + hasta 4 argumentos que no sean flags
        var parts = [tokens[0]]
        for t in tokens.dropFirst() where !t.hasPrefix("-") && !t.hasPrefix("\"") && !t.hasPrefix("'") {
            var part = t
            // `proyecto:region:instancia` → `instancia`
            if part.count > 24, part.contains(":"), let last = part.split(separator: ":").last { part = String(last) }
            if part.count > 24 { part = String(part.prefix(24)) + "…" }
            parts.append(part)
            if parts.count == 5 || parts.joined(separator: " ").count > 44 { break }
        }
        let name = parts.joined(separator: " ")
        return name.count > 48 ? String(name.prefix(47)) + "…" : name
    }

    // MARK: - Clasificación

    private struct Stat {
        var count = 0
        var dirCounts: [String: Int] = [:]
        var explicitDir: String?
        var exitKnown = 0
        var notFound = 0   // 126/127: typo o ruta que no existe
        var hardFail = 0   // otros errores (sin contar interrupciones)

        /// Comandos que casi siempre fallan (typos, compilaciones rotas…).
        var mostlyFails: Bool {
            guard exitKnown >= 3 else { return false }
            return Double(notFound) / Double(exitKnown) >= 0.6 || Double(hardFail) / Double(exitKnown) >= 0.9
        }
    }

    private static func classify(perSource: [[Entry]], options: Options) -> [ProposedGroup] {
        // Recuento por fuente y, entre fuentes, el máximo.
        var merged: [String: Stat] = [:]
        for entries in perSource {
            var local: [String: Stat] = [:]
            for e in entries {
                guard let n = normalize(e.command), !shouldSkip(n.command) else { continue }
                let key = n.command
                var st = local[key, default: Stat()]
                st.count += 1
                if let d = n.directory { st.explicitDir = canonicalDirectory(d) }
                if let pwd = e.pwd, !pwd.isEmpty { st.dirCounts[canonicalDirectory(pwd), default: 0] += 1 }
                if let code = e.exitCode {
                    st.exitKnown += 1
                    if code == 126 || code == 127 { st.notFound += 1 }
                    else if code != 0 && !interruptedExitCodes.contains(code) { st.hardFail += 1 }
                }
                local[key] = st
            }
            for (k, v) in local {
                var m = merged[k, default: Stat()]
                m.count = max(m.count, v.count)
                m.explicitDir = m.explicitDir ?? v.explicitDir
                for (d, c) in v.dirCounts { m.dirCounts[d, default: 0] += c }
                m.exitKnown += v.exitKnown
                m.notFound += v.notFound
                m.hardFail += v.hardFail
                merged[k] = m
            }
        }

        // Selección: los más usados, resolviendo la carpeta cuando hace falta.
        var picked: [ProposedCommand] = []
        let sorted = merged.sorted { $0.value.count > $1.value.count }
        var minCount = options.minCount
        if sorted.filter({ $0.value.count >= minCount }).count < 10 { minCount = 2 }

        for (original, st) in sorted where st.count >= minCount {
            if st.mostlyFails { continue }
            var command = original
            var directory = st.explicitDir
            if directory == nil, dependsOnCwd(command) {
                let total = st.dirCounts.values.reduce(0, +)
                if let (dir, c) = st.dirCounts.max(by: { $0.value < $1.value }),
                   total > 0, Double(c) / Double(total) >= 0.6,
                   FileManager.default.fileExists(atPath: expand(dir)) {
                    directory = dir
                } else {
                    continue // no sabemos dónde ejecutarlo: mejor no proponerlo
                }
            }
            // `./bin/x` ejecutado en ~ → `~/bin/x`, sin carpeta (más claro y portable)
            if directory == "~", command.hasPrefix("./") {
                command = "~/" + command.dropFirst(2)
                directory = nil
            }
            if let d = directory {
                if isTransientDirectory(d) || !FileManager.default.fileExists(atPath: expand(d)) { continue }
            }
            if options.excluding.contains(command) || options.excluding.contains(original) { continue }
            if picked.contains(where: { $0.command == command }) { continue }
            picked.append(ProposedCommand(name: displayName(command), command: command, directory: directory, count: st.count))
            if picked.count >= options.limit { break }
        }

        // Agrupación: proyecto (≥2 comandos) → categoría → «Otros».
        var projectOf: [UUID: String] = [:]
        var projectCounts: [String: Int] = [:]
        for c in picked {
            if let d = c.directory, let p = projectName(for: d) {
                projectOf[c.id] = p
                projectCounts[p, default: 0] += 1
            }
        }
        var buckets: [String: [ProposedCommand]] = [:]
        for c in picked {
            let group: String
            if let p = projectOf[c.id], projectCounts[p, default: 0] >= 2 {
                group = p
            } else {
                group = category(of: c.command) ?? "Otros"
            }
            buckets[group, default: []].append(c)
        }
        // Grupos de un solo comando poco usado → «Otros»
        for (name, cmds) in buckets where cmds.count == 1 && cmds[0].count < 10 && name != "Otros" {
            buckets[name] = nil
            buckets["Otros", default: []].append(contentsOf: cmds)
        }

        return buckets
            .map { ProposedGroup(name: $0.key, commands: $0.value.sorted { $0.count > $1.count }) }
            .sorted { a, b in
                if a.name == "Otros" { return false }
                if b.name == "Otros" { return true }
                return a.totalUses > b.totalUses
            }
    }

    // MARK: - Aplicar

    /// Añade la propuesta a CmdDock, reutilizando grupos con el mismo nombre.
    @discardableResult
    static func apply(_ groups: [ProposedGroup], to store: CommandStore) -> Int {
        var added = 0
        var newCommands = store.commands
        var newGroups = store.groups
        let existing = Set(newCommands.map(\.command))
        for g in groups where !g.commands.isEmpty {
            let gid: UUID
            if let found = newGroups.first(where: { $0.name.caseInsensitiveCompare(g.name) == .orderedSame }) {
                gid = found.id
            } else {
                let ng = CommandGroup(name: g.name)
                newGroups.append(ng)
                gid = ng.id
            }
            for c in g.commands where !existing.contains(c.command) {
                newCommands.append(Command(name: c.name, command: c.command, directory: c.directory, groupID: gid))
                added += 1
            }
        }
        store.groups = newGroups
        store.commands = newCommands
        return added
    }
}
