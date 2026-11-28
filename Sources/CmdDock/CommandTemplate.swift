import Foundation

/// Variables en los comandos: `{{nombre}}` o `{{nombre:valor por defecto}}`.
///
///     ssh {{usuario:root}}@{{host}}
///     gcloud compute ssh {{vm}} -- -N -L {{puerto:8080}}:localhost:{{puerto}}
///
/// Al ejecutar o copiar, CmdDock pide un valor por cada variable distinta (una variable repetida
/// se pide una sola vez) y recuerda el último valor usado. Los valores se insertan tal cual:
/// si necesitan comillas, ponlas en el comando (`"{{mensaje}}"`).
enum CommandTemplate {
    struct Variable: Hashable, Identifiable {
        var name: String
        var defaultValue: String?
        var id: String { name }
    }

    private static let pattern = try! NSRegularExpression(
        pattern: #"\{\{\s*([A-Za-z_][A-Za-z0-9_.-]*)\s*(?::([^}]*))?\}\}"#
    )

    /// Variables en orden de aparición, sin repetir. El primer valor por defecto que aparezca gana.
    static func variables(in text: String) -> [Variable] {
        var seen: [String: Int] = [:]
        var result: [Variable] = []
        let ns = text as NSString
        for m in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            let name = ns.substring(with: m.range(at: 1))
            let def: String? = m.range(at: 2).location == NSNotFound
                ? nil
                : ns.substring(with: m.range(at: 2)).trimmingCharacters(in: .whitespaces)
            if let i = seen[name] {
                if result[i].defaultValue == nil, let def, !def.isEmpty { result[i].defaultValue = def }
                continue
            }
            seen[name] = result.count
            result.append(Variable(name: name, defaultValue: (def?.isEmpty ?? true) ? nil : def))
        }
        return result
    }

    /// Sustituye cada `{{nombre…}}` por su valor (o por el valor por defecto si falta).
    static func render(_ text: String, values: [String: String]) -> String {
        let defaults = Dictionary(uniqueKeysWithValues: variables(in: text).map { ($0.name, $0.defaultValue ?? "") })
        let ns = text as NSString
        var out = ""
        var cursor = 0
        for m in pattern.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: cursor, length: m.range.location - cursor))
            let name = ns.substring(with: m.range(at: 1))
            let value = values[name].flatMap { $0.isEmpty ? nil : $0 } ?? defaults[name] ?? ""
            out += value
            cursor = m.range.location + m.range.length
        }
        out += ns.substring(from: cursor)
        return out
    }

    /// Valores iniciales del formulario: último usado → valor por defecto → vacío.
    static func initialValues(for command: Command) -> [String: String] {
        var values: [String: String] = [:]
        for v in command.variables {
            values[v.name] = command.lastValues?[v.name] ?? v.defaultValue ?? ""
        }
        return values
    }
}
