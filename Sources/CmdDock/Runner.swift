import AppKit
import Foundation

/// Envía un comando a la terminal elegida mediante AppleScript.
enum Runner {
    static func run(_ cmd: Command, settings: AppSettings, completion: @escaping (String?) -> Void) {
        let terminal = cmd.terminal ?? settings.defaultTerminal
        let mode = cmd.openMode ?? settings.defaultMode

        var text = cmd.command.trimmingCharacters(in: .whitespacesAndNewlines)
        if let dir = cmd.directory?.trimmingCharacters(in: .whitespaces), !dir.isEmpty {
            let expanded = (dir as NSString).expandingTildeInPath
            text = "cd \(shellQuote(expanded)) && \(text)"
        }

        guard terminal.isInstalled else {
            completion("\(terminal.displayName) no está instalada.")
            return
        }

        var restoreClipboard: (() -> Void)?
        let script: String

        switch terminal {
        case .terminal:
            script = terminalScript(text, mode: mode, delay: settings.tabDelay)
        case .iterm:
            script = itermScript(text, mode: mode, pressReturn: settings.pressReturn)
        case .warp, .ghostty:
            // Estas apps no tienen diccionario AppleScript para escribir texto:
            // se pega desde el portapapeles y se restaura después.
            let pb = NSPasteboard.general
            let previous = pb.string(forType: .string)
            pb.clearContents()
            pb.setString(text, forType: .string)
            restoreClipboard = {
                pb.clearContents()
                if let previous { pb.setString(previous, forType: .string) }
            }
            script = keystrokeScript(bundleID: terminal.bundleID, mode: mode,
                                     delay: max(settings.tabDelay, AppSettings.minTabDelay),
                                     pressReturn: settings.pressReturn)
        }

        runAppleScript(script) { error in
            if let restoreClipboard {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: restoreClipboard)
            }
            completion(error.map(friendlyError))
        }
    }

    // MARK: Scripts

    private static func terminalScript(_ text: String, mode: OpenMode, delay: Double) -> String {
        let t = asString(text)
        let openTab = mode == .newTab
            ? "tell application \"System Events\" to keystroke \"t\" using command down\n    delay \(delay)"
            : ""
        let target = mode == .newWindow ? "" : " in front window"
        return """
        set wasRunning to application id "com.apple.Terminal" is running
        tell application id "com.apple.Terminal" to activate
        if not wasRunning then
            delay 0.6
            tell application id "com.apple.Terminal"
                if (count of windows) > 0 then
                    do script \(t) in front window
                else
                    do script \(t)
                end if
            end tell
        else
            tell application id "com.apple.Terminal"
                set hasWindow to (count of windows) > 0
            end tell
            if hasWindow then
                \(openTab)
                tell application id "com.apple.Terminal" to do script \(t)\(target)
            else
                tell application id "com.apple.Terminal" to do script \(t)
            end if
        end if
        """
    }

    private static func itermScript(_ text: String, mode: OpenMode, pressReturn: Bool) -> String {
        let t = asString(text)
        let open: String
        switch mode {
        case .newTab: open = "tell current window to create tab with default profile"
        case .newWindow: open = "create window with default profile"
        case .currentTab: open = ""
        }
        return """
        tell application id "com.googlecode.iterm2"
            activate
            if (count of windows) = 0 then
                create window with default profile
            else
                \(open)
            end if
            tell current session of current window to write text \(t) newline \(pressReturn ? "yes" : "no")
        end tell
        """
    }

    private static func keystrokeScript(bundleID: String, mode: OpenMode, delay: Double, pressReturn: Bool) -> String {
        let open: String
        switch mode {
        case .newTab: open = "keystroke \"t\" using command down\n            delay \(delay)"
        case .newWindow: open = "keystroke \"n\" using command down\n            delay \(delay + 0.3)"
        case .currentTab: open = ""
        }
        return """
        set wasRunning to application id "\(bundleID)" is running
        tell application id "\(bundleID)" to activate
        if not wasRunning then delay 2.5
        tell application "System Events"
            set p to first application process whose bundle identifier is "\(bundleID)"
            repeat 60 times
                if frontmost of p then exit repeat
                delay 0.05
            end repeat
            if wasRunning then
                \(open)
            end if
            -- Si el usuario cambió de app mientras esperábamos, no escribir en otra ventana
            if not (frontmost of p) then
                tell application id "\(bundleID)" to activate
                delay 0.2
            end if
            keystroke "v" using command down
            \(pressReturn ? "delay 0.4\n            key code 36" : "")
        end tell
        """
    }

    // MARK: Helpers

    private static func runAppleScript(_ source: String, completion: @escaping (String?) -> Void) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
        p.arguments = ["-"]
        let input = Pipe(), err = Pipe()
        p.standardInput = input
        p.standardError = err
        p.standardOutput = Pipe()
        p.terminationHandler = { proc in
            let msg = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            DispatchQueue.main.async {
                completion(proc.terminationStatus == 0 ? nil : (msg?.isEmpty == false ? msg : "Error desconocido"))
            }
        }
        do {
            try p.run()
            input.fileHandleForWriting.write(source.data(using: .utf8)!)
            try? input.fileHandleForWriting.close()
        } catch {
            completion(error.localizedDescription)
        }
    }

    private static func friendlyError(_ raw: String) -> String {
        if raw.contains("1002") || raw.contains("-25211") || raw.contains("assistive") || raw.contains("pulsaciones") {
            return "CmdDock necesita permiso de Accesibilidad para enviar teclas.\nAjustes del Sistema → Privacidad y seguridad → Accesibilidad → activa CmdDock."
        }
        if raw.contains("-1743") || raw.contains("Not authorized") || raw.contains("No autorizado") {
            return "CmdDock no tiene permiso de Automatización.\nAjustes del Sistema → Privacidad y seguridad → Automatización → CmdDock."
        }
        return raw
    }

    /// Literal de cadena AppleScript.
    static func asString(_ s: String) -> String {
        let escaped = s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    static func shellQuote(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
