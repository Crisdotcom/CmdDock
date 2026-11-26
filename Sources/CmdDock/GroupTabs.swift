import AppKit
import SwiftUI

/// Pestañas superiores: «Todos» + grupos creados por el usuario.
/// - Clic: cambia de grupo. Clic derecho: renombrar, mover, eliminar.
/// - Soltar una fila (arrastrada por su asa) sobre una pestaña la mueve a ese grupo.
struct GroupTabBar: View {
    @ObservedObject var store: CommandStore
    @Binding var selection: UUID? // nil = Todos
    var draggingID: UUID?
    var onDropCommand: (UUID, UUID?) -> Void

    @State private var adding = false
    @State private var renamingID: UUID?
    @State private var draft = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 4) {
                        GroupTab(
                            title: "Todos",
                            count: store.commands.count,
                            isSelected: selection == nil,
                            acceptsDrop: false,
                            draggingID: draggingID,
                            onSelect: { selection = nil },
                            onDrop: { _ in }
                        )
                        .id("all")

                        ForEach(store.groups) { g in
                            if renamingID == g.id {
                                nameField(placeholder: "Nombre del grupo") { commitRename(g.id) }
                            } else {
                                GroupTab(
                                    title: g.name,
                                    count: store.commands.filter { $0.groupID == g.id }.count,
                                    isSelected: selection == g.id,
                                    acceptsDrop: true,
                                    draggingID: draggingID,
                                    onSelect: { selection = g.id },
                                    onDrop: { cmdID in onDropCommand(cmdID, g.id) }
                                )
                                .id(g.id)
                                .contextMenu {
                                    Button("Renombrar…") { startRename(g) }
                                    Button("Mover a la izquierda") { store.moveGroup(g.id, by: -1) }
                                        .disabled(store.groups.first?.id == g.id)
                                    Button("Mover a la derecha") { store.moveGroup(g.id, by: 1) }
                                        .disabled(store.groups.last?.id == g.id)
                                    Divider()
                                    Button("Eliminar grupo (conserva los comandos)", role: .destructive) {
                                        if selection == g.id { selection = nil }
                                        store.deleteGroup(g.id)
                                    }
                                }
                            }
                        }

                        if adding {
                            nameField(placeholder: "Nuevo grupo") { commitAdd() }
                                .id("new")
                        }
                    }
                    .padding(.leading, 14)
                    .padding(.vertical, 2)
                }
                .onChange(of: selection) { _, id in
                    withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id.map { AnyHashable($0) } ?? AnyHashable("all")) }
                }
                .onChange(of: adding) { _, on in
                    if on { withAnimation { proxy.scrollTo("new") } }
                }
            }

            Button {
                renamingID = nil
                draft = ""
                adding = true
                DispatchQueue.main.async { fieldFocused = true }
            } label: {
                Image(systemName: "plus")
            }
            .buttonStyle(GhostIconButtonStyle())
            .help("Nuevo grupo")
            .padding(.trailing, 12)
        }
        .frame(height: 34)
        .padding(.bottom, 6)
    }

    // MARK: Inline name field

    private func nameField(placeholder: String, commit: @escaping () -> Void) -> some View {
        TextField(placeholder, text: $draft)
            .textFieldStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .frame(width: 120)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Color.barFill, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1))
            .focused($fieldFocused)
            .onSubmit(commit)
            .onKeyPress(.escape) { cancelField(); return .handled }
            .onChange(of: fieldFocused) { _, focused in
                if !focused { commit() } // al hacer clic fuera, guarda
            }
    }

    private func commitAdd() {
        guard adding else { return }
        let name = draft.trimmingCharacters(in: .whitespaces)
        adding = false
        draft = ""
        guard !name.isEmpty else { return }
        let g = store.addGroup(named: name)
        selection = g.id
    }

    private func startRename(_ g: CommandGroup) {
        adding = false
        draft = g.name
        renamingID = g.id
        DispatchQueue.main.async { fieldFocused = true }
    }

    private func commitRename(_ id: UUID) {
        guard renamingID == id else { return }
        let name = draft.trimmingCharacters(in: .whitespaces)
        if !name.isEmpty { store.renameGroup(id, to: name) }
        renamingID = nil
        draft = ""
    }

    private func cancelField() {
        adding = false
        renamingID = nil
        draft = ""
    }
}

// MARK: - Tab

private struct GroupTab: View {
    let title: String
    let count: Int
    let isSelected: Bool
    let acceptsDrop: Bool
    let draggingID: UUID?
    let onSelect: () -> Void
    let onDrop: (UUID) -> Void

    @State private var hovering = false
    @State private var targeted = false

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.system(size: 12, weight: isSelected ? .semibold : .medium))
                    .lineLimit(1)
                Text("\(count)")
                    .font(.system(size: 10.5, weight: .medium).monospacedDigit())
                    .foregroundStyle(.tertiary)
            }
            .foregroundStyle(isSelected || hovering ? Color.primary : Color.secondary)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isSelected ? Color.barFill : (hovering ? Color.hoverFill : .clear))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(
                        targeted ? Color.accentColor.opacity(0.7) : (isSelected ? Color.barStroke : .clear),
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
        .animation(.easeOut(duration: 0.12), value: targeted)
        .animation(.easeOut(duration: 0.15), value: isSelected)
        .onDrop(of: [.text], isTargeted: acceptsDrop ? $targeted : .constant(false)) { _ in
            guard acceptsDrop, let id = draggingID else { return false }
            onDrop(id)
            return true
        }
    }
}
