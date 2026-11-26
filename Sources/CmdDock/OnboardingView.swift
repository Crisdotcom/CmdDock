import SwiftUI

/// Primer arranque: ofrece analizar el historial y proponer grupos. Todo es opcional.
struct OnboardingView: View {
    @ObservedObject var store: CommandStore
    var hotKey: String
    var onFinish: () -> Void

    private enum Step { case intro, scanning, review, empty, done }

    @State private var step: Step = .intro
    @State private var proposal: HistoryScanner.Proposal?
    @State private var groups: [HistoryScanner.ProposedGroup] = []
    @State private var excluded: Set<UUID> = []
    @State private var added = 0

    private var selectedCount: Int {
        groups.reduce(0) { $0 + $1.commands.filter { !excluded.contains($0.id) }.count }
    }

    var body: some View {
        VStack(spacing: 0) {
            switch step {
            case .intro: intro
            case .scanning: scanning
            case .review: review
            case .empty: message(icon: "tray", title: "No hay comandos que proponer",
                                 text: "No encontré comandos repetidos en tu historial (Warp, zsh, bash o fish). Puedes añadirlos a mano con ⌘N o importar una lista desde Ajustes.")
            case .done: message(icon: "checkmark.circle", title: "\(added) comandos añadidos",
                                text: "Abre CmdDock cuando quieras con \(hotKey). Puedes reorganizarlos arrastrando el asa ⠿ o cambiarlos de grupo desde el menú contextual.")
            }
        }
        .frame(width: 640, height: 580)
        .animation(.easeOut(duration: 0.2), value: step)
    }

    // MARK: Intro

    private var intro: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "terminal")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(.secondary)
            Text("¿Analizo tu historial de comandos?")
                .font(.title2.weight(.semibold))
            Text("CmdDock puede revisar los comandos que más repites en Warp, zsh, bash y fish y proponerte una agrupación inicial. Tú decides qué se añade.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(maxWidth: 440)
            VStack(alignment: .leading, spacing: 8) {
                bullet("lock.shield", "Todo ocurre en tu Mac: no se envía nada fuera ni se usa IA.")
                bullet("eye.slash", "Se descartan comandos con contraseñas, tokens o credenciales.")
                bullet("trash.slash", "No se proponen comandos destructivos (rm, delete, drop…).")
            }
            .padding(16)
            .background(Color.barFill, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.barStroke))
            Spacer()
            HStack {
                Button("Omitir") { onFinish() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Analizar mi historial") { runScan() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.runGreen)
            }
            .controlSize(.large)
        }
        .padding(28)
    }

    private func bullet(_ icon: String, _ text: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: icon).frame(width: 18).foregroundStyle(.secondary)
            Text(text).font(.callout)
        }
    }

    private var scanning: some View {
        VStack(spacing: 14) {
            Spacer()
            ProgressView().controlSize(.large)
            Text("Analizando tu historial…").foregroundStyle(.secondary)
            Spacer()
        }
    }

    // MARK: Review

    private var review: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Propuesta de grupos").font(.title3.weight(.semibold))
                if let p = proposal {
                    Text("\(p.totalEntries) entradas analizadas (\(Array(Set(p.sources)).sorted().joined(separator: ", "))). Desmarca lo que no quieras y renombra los grupos si quieres.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)

            Divider()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach($groups) { $group in
                        groupSection($group)
                    }
                }
                .padding(20)
            }

            Divider()

            HStack {
                Button("Omitir") { onFinish() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Text("\(selectedCount) seleccionados").foregroundStyle(.secondary).font(.callout)
                Button("Añadir a CmdDock") { applySelection() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .tint(.runGreen)
                    .disabled(selectedCount == 0)
            }
            .controlSize(.large)
            .padding(20)
        }
    }

    private func groupSection(_ group: Binding<HistoryScanner.ProposedGroup>) -> some View {
        let ids = Set(group.wrappedValue.commands.map(\.id))
        let allOn = ids.isDisjoint(with: excluded)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Toggle("", isOn: Binding(
                    get: { allOn },
                    set: { on in if on { excluded.subtract(ids) } else { excluded.formUnion(ids) } }
                ))
                .toggleStyle(.checkbox)
                .labelsHidden()
                TextField("Nombre del grupo", text: group.name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13.5, weight: .semibold))
                Text("\(group.wrappedValue.commands.count)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            ForEach(group.wrappedValue.commands) { cmd in
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Toggle("", isOn: Binding(
                        get: { !excluded.contains(cmd.id) },
                        set: { on in if on { excluded.remove(cmd.id) } else { excluded.insert(cmd.id) } }
                    ))
                    .toggleStyle(.checkbox)
                    .labelsHidden()
                    VStack(alignment: .leading, spacing: 2) {
                        Text(cmd.name).font(.system(size: 12.5, weight: .medium))
                        Text(cmd.command)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1).truncationMode(.middle)
                        if let dir = cmd.directory {
                            Label(dir, systemImage: "folder")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Text("\(cmd.count)×")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
                .padding(.leading, 26)
                .opacity(excluded.contains(cmd.id) ? 0.45 : 1)
            }
        }
    }

    private func message(icon: String, title: String, text: String) -> some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: icon).font(.system(size: 40, weight: .light)).foregroundStyle(.secondary)
            Text(title).font(.title2.weight(.semibold))
            Text(text).multilineTextAlignment(.center).foregroundStyle(.secondary).frame(maxWidth: 440)
            Spacer()
            Button("Empezar") { onFinish() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(.runGreen)
                .controlSize(.large)
        }
        .padding(28)
    }

    // MARK: Acciones

    private func runScan() {
        step = .scanning
        var options = HistoryScanner.Options()
        options.excluding = Set(store.commands.map(\.command))
        DispatchQueue.global(qos: .userInitiated).async {
            let p = HistoryScanner.scan(options)
            DispatchQueue.main.async {
                proposal = p
                groups = p.groups
                excluded = []
                step = p.groups.isEmpty ? .empty : .review
            }
        }
    }

    private func applySelection() {
        let chosen = groups.map { g -> HistoryScanner.ProposedGroup in
            var g = g
            g.name = g.name.trimmingCharacters(in: .whitespaces).isEmpty ? "Otros" : g.name
            g.commands = g.commands.filter { !excluded.contains($0.id) }
            return g
        }
        added = HistoryScanner.apply(chosen, to: store)
        step = .done
    }
}
