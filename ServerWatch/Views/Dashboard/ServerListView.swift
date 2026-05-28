import SwiftUI
import SwiftData

struct ServerListView: View {

    @Query(sort: \Server.createdAt) private var servers: [Server]
    @Environment(\.modelContext) private var context

    @State private var showAddSheet = false
    @State private var renamingServer: Server?
    @State private var pendingDelete: Server?

    var body: some View {
        NavigationStack {
            Group {
                if servers.isEmpty {
                    ContentUnavailableView {
                        Label("No servers yet", systemImage: "server.rack")
                    } description: {
                        Text("Add a server to start monitoring.\nYour password is only used for the initial setup.")
                    } actions: {
                        Button {
                            showAddSheet = true
                        } label: {
                            Label("Add Server", systemImage: "plus")
                                .font(.body.weight(.semibold))
                        }
                        .buttonStyle(.borderedProminent)
                    }
                } else {
                    List {
                        ForEach(servers) { server in
                            NavigationLink(value: server) {
                                ServerCardView(server: server)
                            }
                            .swipeActions(edge: .leading) {
                                Button {
                                    renamingServer = server
                                } label: {
                                    Label("Rename", systemImage: "pencil")
                                }
                                .tint(.blue)
                            }
                            .swipeActions(edge: .trailing) {
                                Button(role: .destructive) {
                                    pendingDelete = server
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Server Health")
            .navigationDestination(for: Server.self) { server in
                ServerDetailView(server: server)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gear")
                    }
                    .accessibilityLabel("Settings")
                }
                if !servers.isEmpty {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showAddSheet = true
                        } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add Server")
                    }
                }
            }
            .sheet(isPresented: $showAddSheet) {
                AddServerView()
            }
            .sheet(item: $renamingServer) { server in
                RenameServerSheet(server: server)
            }
            .alert(
                "Delete server?",
                isPresented: Binding(
                    get: { pendingDelete != nil },
                    set: { if !$0 { pendingDelete = nil } }
                ),
                presenting: pendingDelete
            ) { server in
                Button("Delete", role: .destructive) {
                    deleteServer(server)
                    pendingDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    pendingDelete = nil
                }
            } message: { server in
                Text("This will remove \(server.name), all its rules and history, and delete its SSH key from the Keychain.")
            }
        }
    }

    private func deleteServer(_ server: Server) {
        // Delete Keychain entry when server is removed (no orphans).
        KeychainService.delete(for: server.keychainKeyId)
        context.delete(server)
        try? context.save()
    }
}

// MARK: - Rename sheet

private struct RenameServerSheet: View {
    @Bindable var server: Server
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context

    @State private var name: String = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Server name", text: $name)
                        .textInputAutocapitalization(.words)
                } footer: {
                    Text("Only the display name changes. Host, port, user, and the SSH key stay the same. To change connection details, delete and re-add the server.")
                }
            }
            .navigationTitle("Edit Server")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            .onAppear {
                name = server.name
            }
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        server.name = trimmed
        try? context.save()
        dismiss()
    }
}
