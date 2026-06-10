import SwiftUI
import SwiftData

struct ServerListView: View {

    @Query(sort: \Server.createdAt) private var servers: [Server]
    @Environment(\.modelContext) private var context
    @EnvironmentObject private var purchaseManager: PurchaseManager

    @State private var showAddSheet = false
    @State private var renamingServer: Server?
    @State private var pendingDelete: Server?
    @State private var showPaywall = false

    /// Free tier allows exactly one server. Adding a second triggers paywall.
    private var canAddMoreServers: Bool {
        purchaseManager.isPro || servers.isEmpty
    }

    /// Centralized handler for both the "+" toolbar button and the empty-state
    /// "Add Server" button. Gates behind paywall when at the free limit.
    private func addServerTapped() {
        if canAddMoreServers {
            showAddSheet = true
        } else {
            showPaywall = true
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if servers.isEmpty {
                    ContentUnavailableView {
                        Label("No servers yet", systemImage: "server.rack")
                    } description: {
                        Text("Add a server to start monitoring.\nYour password is only used for the initial setup.")
                    } actions: {
                        VStack(spacing: 12) {
                            Button {
                                addServerTapped()
                            } label: {
                                Label("Add Server", systemImage: "plus")
                                    .font(.body.weight(.semibold))
                            }
                            .buttonStyle(.borderedProminent)

                            // Demo Mode entry — populates the dashboard with
                            // two pretend servers so anyone (including App
                            // Store reviewers without their own Linux box)
                            // can explore the UI end-to-end without doing
                            // the SSH handshake.
                            Button {
                                DemoMode.install(into: context)
                            } label: {
                                Label("Or try a demo with sample servers",
                                      systemImage: "sparkles")
                                    .font(.footnote.weight(.medium))
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }
                } else {
                    ZStack {
                        BrandBackground()
                        List {
                            ForEach(servers) { server in
                                NavigationLink(value: server) {
                                    ServerCardView(server: server)
                                }
                                .listRowBackground(Color.clear)
                                .listRowSeparator(.hidden)
                                .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 4, trailing: 16))
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
                        .listStyle(.plain)
                        .scrollContentBackground(.hidden)
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
                            addServerTapped()
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
            .sheet(isPresented: $showPaywall) {
                PaywallView(
                    priceText: purchaseManager.priceText,
                    monthlyEquivalentText: purchaseManager.monthlyEquivalentText,
                    isPurchasing: purchaseManager.isPurchasing,
                    isProductAvailable: purchaseManager.isProductAvailable,
                    errorMessage: purchaseManager.lastErrorMessage,
                    onPurchase: { await purchaseManager.purchase() },
                    onRestore:  { await purchaseManager.restore() }
                )
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
