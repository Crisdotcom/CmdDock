import AppKit
import SwiftUI

struct PanelView: View {
    @ObservedObject var store: CommandStore
    @ObservedObject var settings: AppSettings
    var onRun: (Command) -> Void
    var onHide: () -> Void
    var onSettings: () -> Void

    @State private var query = ""
    @State private var selectedID: UUID?
    @State private var hoveredID: UUID?
    @State private var editing: Command?
    @State private var toast: String?
    @State private var lastDeleted: (Command, Int)?
    @FocusState private var searchFocused: Bool
    @State private var draggingID: UUID?
    @State private var prompting: VariablePrompt?
    @AppStorage("selectedGroup") private var selectedGroupRaw = ""

    /// Grupo activo (nil = «Todos»). Si el grupo ya no existe, vuelve a «Todos».
    private var selectedGroupID: UUID? {
        get {
            guard let id = UUID(uuidString: selectedGroupRaw), store.groups.contains(where: { $0.id == id }) else { return nil }
            return id
        }
        nonmutating set { selectedGroupRaw = newValue?.uuidString ?? "" }
    }

    private var groupSelection: Binding<UUID?> {
        Binding(get: { selectedGroupID }, set: { selectedGroupID = $0 })
    }

    private var inTab: [Command] {
        guard let g = selectedGroupID else { return store.commands }
        return store.commands.filter { $0.groupID == g }
    }

    private var filtered: [Command] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !q.isEmpty else { return inTab }
        return inTab.filter {
            $0.name.lowercased().contains(q) || $0.command.lowercased().contains(q)
        }
    }

    private var selected: Command? {
        filtered.first { $0.id == selectedID } ?? filtered.first
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                header
                GroupTabBar(
                    store: store,
                    selection: groupSelection,
                    draggingID: draggingID,
                    onDropCommand: { cmdID, groupID in
                        withAnimation(.easeOut(duration: 0.2)) { store.setGroup(cmdID, to: groupID) }
                        draggingID = nil
                        if let name = store.groupName(groupID) { showToast("Movido a «\(name)»") }
                    }
                )
                Divider()
                list
                Divider()
                footer
            }
            .disabled(editing != nil || prompting != nil)

            if let prompting {
                Color.black.opacity(0.25).ignoresSafeArea()
                VariablePromptView(
                    prompt: prompting,
                    onSubmit: { values in finishPrompt(prompting, values: values) },
                    onCancel: {
                        self.prompting = nil
                        searchFocused = true
                    }
                )
                .id(prompting.id)
                .transition(.scale(scale: 0.97).combined(with: .opacity))
            }

            if let editing {
                Color.black.opacity(0.25).ignoresSafeArea()
                CommandEditor(
                    command: editing,
                    settings: settings,
                    groups: store.groups,
                    onSave: { c in
                        store.upsert(c)
                        selectedID = c.id
                        self.editing = nil
                        searchFocused = true
                    },
                    onCancel: {
                        self.editing = nil
                        searchFocused = true
                    }
                )
                .transition(.scale(scale: 0.97).combined(with: .opacity))
            }

            if let toast {
                VStack {
                    Spacer()
                    HStack(spacing: 10) {
                        Text(toast)
                        if lastDeleted != nil {
                            Button("Deshacer") { undoDelete() }
                                .buttonStyle(.link)
                        }
                    }
                    .font(.callout)
                    .padding(.horizontal, 14).padding(.vertical, 8)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 6)
                    .padding(.bottom, 44)
                }
                .transition(.opacity)
            }
        }
        .frame(width: 680, height: 440)
        .background(.regularMaterial)
        .animation(.easeOut(duration: 0.15), value: editing?.id)
        .animation(.easeOut(duration: 0.15), value: prompting?.id)
        .animation(.easeOut(duration: 0.15), value: toast)
        .onReceive(NotificationCenter.default.publisher(for: .panelDidShow)) { note in
            query = ""
            editing = nil
            draggingID = nil
            selectedID = filtered.first?.id
            // Desde la barra de menú: abrir directamente el formulario de variables
            if let id = note.object as? UUID, let cmd = store.commands.first(where: { $0.id == id }) {
                selectedID = cmd.id
                prompting = VariablePrompt(command: cmd, action: .run)
            } else {
                prompting = nil
                searchFocused = true
            }
        }
        .onChange(of: query) { selectedID = filtered.first?.id }
        .onChange(of: selectedGroupRaw) { selectedID = filtered.first?.id }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(.secondary)
            TextField("Buscar comandos…", text: $query)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($searchFocused)
                .onSubmit { if let c = selected { requestRun(c) } }
                .onKeyPress(.upArrow) { moveSelection(-1); return .handled }
                .onKeyPress(.downArrow) { moveSelection(1); return .handled }
                .onKeyPress(.escape) { onHide(); return .handled }
            Button {
                settings.pinned.toggle()
            } label: {
                Image(systemName: settings.pinned ? "pin.fill" : "pin")
                    .font(.system(size: 13, weight: .semibold))
                    .rotationEffect(.degrees(settings.pinned ? 0 : 45))
                    .foregroundStyle(settings.pinned ? Color.accentColor : .secondary)
                    .frame(width: 26, height: 26)
                    .background(
                        Circle().fill(settings.pinned ? Color.accentColor.opacity(0.15) : .clear)
                    )
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("p", modifiers: .command)
            .help(settings.pinned ? "Desfijar ventana (⌘P)" : "Fijar ventana: no se cierra al ejecutar ni al cambiar de app (⌘P)")
            .animation(.spring(duration: 0.25), value: settings.pinned)

            Button {
                editing = Command(name: "", command: "", groupID: selectedGroupID)
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .semibold))
                    .frame(width: 26, height: 26)
            }
            .buttonStyle(.borderless)
            .keyboardShortcut("n", modifiers: .command)
            .help("Nuevo comando (⌘N)")
        }
        .padding(.horizontal, 18)
        .padding(.top, 16)
        .padding(.bottom, 12)
    }

    // MARK: List

    @ViewBuilder
    private var list: some View {
        if filtered.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "terminal")
                    .font(.system(size: 34, weight: .light))
                    .foregroundStyle(.tertiary)
                Text(emptyMessage)
                    .foregroundStyle(.secondary)
                Button(query.isEmpty ? "Añadir comando" : "Crear «\(query)» como comando") {
                    editing = Command(name: query, command: query, groupID: selectedGroupID)
                }
                Spacer()
            }
            .frame(maxWidth: .infinity)
        } else {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(filtered) { cmd in
                            row(cmd)
                                .id(cmd.id)
                                .onDrop(of: [.text], delegate: RowDropDelegate(
                                    target: cmd.id, store: store, draggingID: $draggingID
                                ))
                        }
                    }
                    .padding(8)
                    .animation(.easeInOut(duration: 0.18), value: filtered.map(\.id))
                }
                // Soltar fuera de una fila: termina el arrastre
                .onDrop(of: [.text], isTargeted: nil) { _ in draggingID = nil; return true }
                .onChange(of: selectedID) { _, id in
                    if let id { withAnimation(.linear(duration: 0.08)) { proxy.scrollTo(id) } }
                }
            }
        }
    }

    private func row(_ cmd: Command) -> some View {
        let isSelected = cmd.id == selected?.id
        let isHovered = cmd.id == hoveredID
        return HStack(spacing: 12) {
          // Zona de contenido: recibe el clic / doble clic configurables.
          // La barra de acciones queda fuera para que sus botones reciban sus propios clics.
          HStack(spacing: 12) {
            DragHandle(isActive: draggingID == cmd.id)
                .onDrag {
                    draggingID = cmd.id
                    selectedID = cmd.id
                    return NSItemProvider(object: cmd.id.uuidString as NSString)
                } preview: {
                    Text(cmd.name.isEmpty ? cmd.command : cmd.name)
                        .font(.system(size: 12.5, weight: .semibold))
                        .padding(.horizontal, 12).padding(.vertical, 6)
                        .background(Color.barFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .padding(.trailing, -6)
            Image(systemName: "chevron.right.square")
                .font(.system(size: 16))
                .foregroundStyle(isSelected ? Color.accentColor : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(cmd.name.isEmpty ? cmd.command : cmd.name)
                    .font(.system(size: 13.5, weight: .semibold))
                    .lineLimit(1)
                Text(cmd.command)
                    .font(.system(size: 11.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 8)

            if selectedGroupID == nil, let group = store.groupName(cmd.groupID) {
                Text(group)
                    .font(.system(size: 10.5, weight: .medium))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .overlay(Capsule().strokeBorder(Color.barStroke, lineWidth: 1))
                    .foregroundStyle(.secondary)
            }

            if cmd.hasOverride {
                Text(overrideLabel(cmd))
                    .font(.system(size: 10.5, weight: .medium))
                    .padding(.horizontal, 7).padding(.vertical, 2)
                    .background(Color.primary.opacity(0.07), in: Capsule())
                    .foregroundStyle(.secondary)
            }
          }
          .padding(.vertical, 8)
          .contentShape(Rectangle())
          .gesture(rowTapGesture(cmd))

            ActionBar(
                isRunning: store.running.contains(cmd.id),
                showSecondary: isHovered,
                onCopy: { selectedID = cmd.id; requestCopy(cmd) },
                onEdit: { selectedID = cmd.id; editing = cmd },
                onRun: { requestRun(cmd) }
            )
            .onHover { if $0 { hoveredID = cmd.id } } // mantiene visibles copiar/editar
        }
        .padding(.horizontal, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.16) : (isHovered ? Color.primary.opacity(0.05) : .clear))
        )
        .opacity(draggingID == cmd.id ? 0.45 : 1)
        .contentShape(Rectangle())
        .onHover { hoveredID = $0 ? cmd.id : (hoveredID == cmd.id ? nil : hoveredID) }
        .contextMenu {
            Button("Ejecutar") { requestRun(cmd) }
            Button("Copiar comando") { requestCopy(cmd) }
            Button("Editar…") { editing = cmd }
            Button("Duplicar") {
                var c = cmd
                c.id = UUID()
                c.name += " (copia)"
                store.upsert(c)
            }
            Menu("Mover a grupo") {
                Button("Sin grupo") { store.setGroup(cmd.id, to: nil) }
                    .disabled(cmd.groupID == nil)
                if !store.groups.isEmpty { Divider() }
                ForEach(store.groups) { g in
                    Button(g.name) { store.setGroup(cmd.id, to: g.id) }
                        .disabled(cmd.groupID == g.id)
                }
            }
            Divider()
            Button("Subir") { store.move(cmd, by: -1) }
            Button("Bajar") { store.move(cmd, by: 1) }
            Divider()
            Button("Eliminar", role: .destructive) { delete(cmd) }
        }
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 14) {
            hint("↩", "ejecutar")
            hint("↑↓", "navegar")
            hint("⌘E", "editar")
            hint("⌘P", settings.pinned ? "desfijar" : "fijar")
            hint("⎋", "cerrar")
            Spacer(minLength: 8)
            Button { onSettings() } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
                .keyboardShortcut(",", modifiers: .command)
                .help("Ajustes (⌘,)")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(hiddenShortcuts)
    }

    /// Atajos de teclado sin botón visible (fuera del layout del pie).
    private var hiddenShortcuts: some View {
        ZStack {
            Button("") { if let c = selected { editing = c } }
                .keyboardShortcut("e", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0)
            Button("") { if let c = selected { requestCopy(c) } }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .frame(width: 0, height: 0).opacity(0)
            Button("") { if let c = selected { delete(c) } }
                .keyboardShortcut(.delete, modifiers: .command)
                .frame(width: 0, height: 0).opacity(0)
            // ⌘1 = Todos, ⌘2…⌘9 = grupos
            ForEach(1...9, id: \.self) { n in
                Button("") {
                    if n == 1 { selectedGroupID = nil }
                    else if n - 2 < store.groups.count { selectedGroupID = store.groups[n - 2].id }
                }
                .keyboardShortcut(KeyEquivalent(Character("\(n)")), modifiers: .command)
                .frame(width: 0, height: 0).opacity(0)
            }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(key)
                .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 4))
            Text(label).font(.system(size: 11))
        }
        .lineLimit(1)
        .fixedSize()
        .foregroundStyle(.secondary)
    }

    // MARK: Actions

    /// Clic / doble clic configurables desde Ajustes. Si el doble clic está desactivado,
    /// el clic simple responde al instante (sin esperar a descartar un doble clic).
    private func rowTapGesture(_ cmd: Command) -> AnyGesture<Void> {
        let single = TapGesture().onEnded {
            selectedID = cmd.id
            perform(settings.singleClickAction, on: cmd)
        }
        guard settings.doubleClickAction != .none else { return AnyGesture(single) }
        let double = TapGesture(count: 2).onEnded {
            selectedID = cmd.id
            perform(settings.doubleClickAction, on: cmd)
        }
        return AnyGesture(double.exclusively(before: single).map { _ in () })
    }

    private func perform(_ action: ClickAction, on cmd: Command) {
        switch action {
        case .none: break
        case .copy: requestCopy(cmd)
        case .run: requestRun(cmd)
        case .edit: editing = cmd
        }
    }

    private var emptyMessage: String {
        if !query.isEmpty { return "Ningún comando coincide con «\(query)»" }
        if let name = store.groupName(selectedGroupID) {
            return "«\(name)» está vacío. Crea un comando o arrastra uno a esta pestaña."
        }
        return "Aún no tienes comandos guardados"
    }

    private func overrideLabel(_ c: Command) -> String {
        [c.terminal?.displayName, c.openMode?.displayName].compactMap { $0 }.joined(separator: " · ")
    }

    private func moveSelection(_ delta: Int) {
        let list = filtered
        guard !list.isEmpty else { return }
        let idx = list.firstIndex { $0.id == selected?.id } ?? 0
        let next = max(0, min(list.count - 1, idx + delta))
        selectedID = list[next].id
    }

    // MARK: Variables

    /// Ejecuta, o primero pide los valores de sus `{{variables}}`.
    private func requestRun(_ cmd: Command) {
        if cmd.variables.isEmpty { onRun(cmd) } else { prompting = VariablePrompt(command: cmd, action: .run) }
    }

    private func requestCopy(_ cmd: Command) {
        if cmd.variables.isEmpty { copy(cmd) } else { prompting = VariablePrompt(command: cmd, action: .copy) }
    }

    private func finishPrompt(_ prompt: VariablePrompt, values: [String: String]) {
        store.rememberValues(values, for: prompt.command.id)
        var resolved = prompt.command
        resolved.command = CommandTemplate.render(prompt.command.command, values: values)
        prompting = nil
        searchFocused = true
        if prompt.action == .copy { copy(resolved) } else { onRun(resolved) }
    }

    private func copy(_ cmd: Command) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(cmd.command, forType: .string)
        lastDeleted = nil
        showToast("Copiado al portapapeles")
    }

    private func delete(_ cmd: Command) {
        if let i = store.delete(cmd) {
            lastDeleted = (cmd, i)
            showToast("«\(cmd.name)» eliminado")
        }
    }

    private func undoDelete() {
        if let (c, i) = lastDeleted { store.insert(c, at: i); selectedID = c.id }
        lastDeleted = nil
        toast = nil
    }

    private func showToast(_ text: String) {
        toast = text
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.5) {
            if toast == text { toast = nil; lastDeleted = nil }
        }
    }
}

// MARK: - Drag & drop

/// Asa de 9 puntos al inicio de la fila. Mantén pulsado y arrastra para reordenar.
struct DragHandle: View {
    var isActive: Bool
    @State private var hovering = false

    var body: some View {
        Image(systemName: "circle.grid.3x3.fill")
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(hovering || isActive ? Color.iconHover : Color.iconNeutral.opacity(0.55))
            .frame(width: 18, height: 30)
            .background(
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.hoverFill.opacity(hovering || isActive ? 1 : 0))
            )
            .contentShape(Rectangle())
            .onHover { inside in
                hovering = inside
                if inside { NSCursor.openHand.push() } else { NSCursor.pop() }
            }
            .animation(.easeOut(duration: 0.12), value: hovering)
            .help("Arrastra para reordenar o suelta sobre una pestaña para cambiar de grupo")
    }
}

/// Reordena en vivo mientras la fila arrastrada pasa por encima de otras.
struct RowDropDelegate: DropDelegate {
    let target: UUID
    let store: CommandStore
    @Binding var draggingID: UUID?

    func dropEntered(info: DropInfo) {
        guard let id = draggingID, id != target else { return }
        withAnimation(.easeInOut(duration: 0.18)) { store.moveCommand(id, to: target) }
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        draggingID = nil
        return true
    }
}

// MARK: - Action bar

/// Colores adaptativos sobrios (grafito en oscuro, gris claro en claro).
extension Color {
    static func dynamic(light: NSColor, dark: NSColor) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
    static let barFill = dynamic(light: NSColor(white: 0.93, alpha: 1), dark: NSColor(white: 0.155, alpha: 1))
    static let barStroke = dynamic(light: NSColor(white: 0, alpha: 0.08), dark: NSColor(white: 1, alpha: 0.07))
    static let barDivider = dynamic(light: NSColor(white: 0, alpha: 0.10), dark: NSColor(white: 1, alpha: 0.09))
    static let iconNeutral = dynamic(light: NSColor(white: 0.40, alpha: 1), dark: NSColor(white: 0.62, alpha: 1))
    static let iconHover = dynamic(light: NSColor(white: 0.12, alpha: 1), dark: NSColor(white: 0.92, alpha: 1))
    static let hoverFill = dynamic(light: NSColor(white: 0, alpha: 0.06), dark: NSColor(white: 1, alpha: 0.07))
    static let runGreen = Color(red: 0.180, green: 0.365, blue: 0.275)        // verde oscuro desaturado
    static let runGreenHover = Color(red: 0.208, green: 0.412, blue: 0.312)
    static let runGreenPressed = Color(red: 0.150, green: 0.310, blue: 0.235)
}

/// Barra compacta: [copiar] [editar] │ [▶ ejecutar]
struct ActionBar: View {
    var isRunning: Bool
    /// Copiar/editar solo se muestran al pasar el ratón por la fila.
    var showSecondary: Bool
    var onCopy: () -> Void
    var onEdit: () -> Void
    var onRun: () -> Void

    var body: some View {
        HStack(spacing: 2) {
            if showSecondary {
                Group {
                    Button(action: onCopy) { Image(systemName: "doc.on.doc") }
                        .buttonStyle(GhostIconButtonStyle())
                        .help("Copiar al portapapeles")
                    Button(action: onEdit) { Image(systemName: "pencil") }
                        .buttonStyle(GhostIconButtonStyle())
                        .help("Editar")

                    Rectangle()
                        .fill(Color.barDivider)
                        .frame(width: 1, height: 14)
                        .padding(.horizontal, 4)
                }
                .transition(.opacity.combined(with: .move(edge: .trailing)))
            }

            Button(action: onRun) {
                ZStack {
                    Image(systemName: "play.fill")
                        .opacity(isRunning ? 0 : 1)
                        .scaleEffect(isRunning ? 0.6 : 1)
                    ProgressView()
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                        .tint(.white)
                        .colorScheme(.dark)
                        .opacity(isRunning ? 1 : 0)
                }
                .animation(.easeOut(duration: 0.18), value: isRunning)
            }
            .buttonStyle(RunButtonStyle(isRunning: isRunning))
            .disabled(isRunning)
            .help(isRunning ? "Ejecutando…" : "Ejecutar")
        }
        .padding(3)
        .background(Color.barFill, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.barStroke, lineWidth: 1))
        .animation(.easeOut(duration: 0.15), value: showSecondary)
    }
}

/// Icono gris neutro sin fondo propio; hover discreto.
struct GhostIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        GhostIcon(configuration: configuration)
    }

    private struct GhostIcon: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(hovering && isEnabled ? Color.iconHover : Color.iconNeutral)
                .frame(width: 24, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color.hoverFill.opacity(hovering && isEnabled ? (configuration.isPressed ? 1.6 : 1) : 0))
                )
                .opacity(isEnabled ? 1 : 0.4)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
        }
    }
}

/// Acción principal: verde oscuro desaturado, icono blanco, sin brillos ni sombras.
struct RunButtonStyle: ButtonStyle {
    var isRunning: Bool

    func makeBody(configuration: Configuration) -> some View {
        RunBody(configuration: configuration, isRunning: isRunning)
    }

    private struct RunBody: View {
        let configuration: ButtonStyleConfiguration
        let isRunning: Bool
        @Environment(\.isEnabled) private var isEnabled
        @State private var hovering = false

        private var fill: Color {
            if isRunning { return .runGreen }
            if !isEnabled { return .runGreen.opacity(0.45) }
            if configuration.isPressed { return .runGreenPressed }
            return hovering ? .runGreenHover : .runGreen
        }

        var body: some View {
            configuration.label
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white.opacity(isEnabled || isRunning ? 1 : 0.6))
                .frame(width: 30, height: 22)
                .background(fill, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
                .scaleEffect(configuration.isPressed ? 0.96 : 1)
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
                .animation(.easeOut(duration: 0.12), value: hovering)
                .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
                .animation(.easeOut(duration: 0.18), value: isRunning)
                .animation(.easeOut(duration: 0.18), value: isEnabled)
        }
    }
}

// MARK: - Editor

struct CommandEditor: View {
    @State var command: Command
    @ObservedObject var settings: AppSettings
    var groups: [CommandGroup]
    var onSave: (Command) -> Void
    var onCancel: () -> Void

    private var isValid: Bool { !command.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(command.name.isEmpty && command.command.isEmpty ? "Nuevo comando" : "Editar comando")
                .font(.headline)

            field("Nombre") {
                TextField("p. ej. Levantar backend", text: $command.name)
                    .textFieldStyle(.roundedBorder)
            }

            field("Comando") {
                TextEditor(text: $command.command)
                    .font(.system(size: 12.5, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .padding(6)
                    .frame(height: 74)
                    .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.primary.opacity(0.15)))
                variablesHint
            }

            HStack(alignment: .top, spacing: 16) {
                field("Carpeta (opcional)") {
                    TextField("~/proyectos/mi-app", text: Binding(
                        get: { command.directory ?? "" },
                        set: { command.directory = $0.isEmpty ? nil : $0 }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12.5, design: .monospaced))
                }
                field("Grupo") {
                    Picker("", selection: $command.groupID) {
                        Text("Sin grupo").tag(UUID?.none)
                        if !groups.isEmpty { Divider() }
                        ForEach(groups) { g in Text(g.name).tag(UUID?.some(g.id)) }
                    }
                    .labelsHidden()
                    .frame(width: 160)
                }
            }

            HStack(spacing: 16) {
                field("Terminal") {
                    Picker("", selection: $command.terminal) {
                        Text("Predeterminada (\(settings.defaultTerminal.displayName))").tag(TerminalApp?.none)
                        Divider()
                        ForEach(TerminalApp.allCases) { t in
                            Text(t.displayName + (t.isInstalled ? "" : " — no instalada")).tag(TerminalApp?.some(t))
                        }
                    }
                    .labelsHidden()
                }
                field("Abrir en") {
                    Picker("", selection: $command.openMode) {
                        Text("Predeterminado (\(settings.defaultMode.displayName))").tag(OpenMode?.none)
                        Divider()
                        ForEach(OpenMode.allCases) { m in Text(m.displayName).tag(OpenMode?.some(m)) }
                    }
                    .labelsHidden()
                }
            }

            HStack {
                Spacer()
                Button("Cancelar", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button("Guardar") {
                    var c = command
                    c.command = c.command.trimmingCharacters(in: .whitespacesAndNewlines)
                    c.name = c.name.trimmingCharacters(in: .whitespaces)
                    if c.name.isEmpty { c.name = String(c.command.prefix(40)) }
                    onSave(c)
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(.borderedProminent)
                .disabled(!isValid)
            }
            Text("⌘↩ guardar · ⎋ cancelar")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(20)
        .frame(width: 500)
        .background(.thickMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 18, y: 6)
    }

    /// Variables detectadas en el comando, o una pista de la sintaxis si no hay ninguna.
    @ViewBuilder
    private var variablesHint: some View {
        let vars = CommandTemplate.variables(in: command.command)
        if vars.isEmpty {
            Text("Usa {{nombre}} o {{nombre:valor}} para pedir datos al ejecutar.")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
        } else {
            HStack(spacing: 6) {
                Text("Al ejecutar pedirá:")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                ForEach(vars) { v in
                    Text(v.defaultValue.map { "\(v.name) = \($0)" } ?? v.name)
                        .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 6).padding(.vertical, 1)
                        .background(Color.barFill, in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.barStroke))
                }
            }
            .lineLimit(1)
        }
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            content()
        }
    }
}
