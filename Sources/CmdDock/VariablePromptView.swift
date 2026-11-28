import SwiftUI

struct VariablePrompt: Identifiable {
    let id = UUID()
    var command: Command
    var action: ClickAction // .run o .copy
}

/// Formulario que pide los valores de las `{{variables}}` antes de ejecutar o copiar.
/// ↩ en un campo pasa al siguiente; en el último, ejecuta. ⎋ cancela.
struct VariablePromptView: View {
    let prompt: VariablePrompt
    var onSubmit: ([String: String]) -> Void
    var onCancel: () -> Void

    @State private var values: [String: String] = [:]
    @FocusState private var focused: String?

    private var variables: [CommandTemplate.Variable] { prompt.command.variables }
    private var preview: String { CommandTemplate.render(prompt.command.command, values: values) }
    private var isRun: Bool { prompt.action != .copy }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: isRun ? "play.fill" : "doc.on.doc")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.secondary)
                Text(prompt.command.name.isEmpty ? "Completa el comando" : prompt.command.name)
                    .font(.headline)
                    .lineLimit(1)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(variables.enumerated()), id: \.element.id) { index, v in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(v.name)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.secondary)
                        TextField(v.defaultValue ?? "", text: binding(for: v.name))
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 12.5, design: .monospaced))
                            .focused($focused, equals: v.name)
                            .onSubmit { advance(from: index) }
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Se \(isRun ? "ejecutará" : "copiará")")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(preview)
                    .font(.system(size: 12, design: .monospaced))
                    .textSelection(.enabled)
                    .lineLimit(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(Color.barFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.barStroke))
            }

            HStack {
                Text("↩ siguiente · ⌘↩ \(isRun ? "ejecutar" : "copiar") · ⎋ cancelar")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Cancelar", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button(isRun ? "Ejecutar" : "Copiar") { onSubmit(values) }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(.borderedProminent)
                    .tint(.runGreen)
            }
        }
        .padding(20)
        .frame(width: 500)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
        .onAppear {
            values = CommandTemplate.initialValues(for: prompt.command)
            DispatchQueue.main.async { focused = variables.first?.name }
        }
    }

    private func binding(for name: String) -> Binding<String> {
        Binding(get: { values[name] ?? "" }, set: { values[name] = $0 })
    }

    private func advance(from index: Int) {
        if index + 1 < variables.count {
            focused = variables[index + 1].name
        } else {
            onSubmit(values)
        }
    }
}
