import SwiftUI
import UniformTypeIdentifiers

struct SettingsView: View {
    @Bindable var model: ModuleLibraryModel
    @State private var selection: Page? = .wheel
    @State private var addingRepository = false
    @State private var editingCredential: RepositorySource?

    private enum Page: String, CaseIterable {
        case wheel = "Wheel", repositories = "Repositories", advanced = "Advanced"
        var symbol: String {
            switch self {
            case .advanced: "gearshape.2"
            case .wheel: "circle.hexagonpath"
            case .repositories: "externaldrive.connected.to.line.below"
            }
        }
    }
    var body: some View {
        NavigationSplitView {
            List(Page.allCases, id: \.self, selection: $selection) { page in
                Label(LocalizedStringKey(page.rawValue), systemImage: page.symbol)
                    .accessibilityIdentifier("settings.page.\(page.rawValue.lowercased())")
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(180)
        } detail: {
            Group {
                switch selection ?? .wheel {
                case .advanced: GeneralSettingsView()
                case .wheel: wheel
                case .repositories: repositories
                }
            }
            .navigationTitle("Talos")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 780, height: 600)
        .overlay(alignment: .bottom) {
            if model.isBusy { ProgressView().controlSize(.small).padding(12).background(.regularMaterial, in: Capsule()).padding() }
        }
        .sheet(isPresented: $addingRepository) { RepositoryEditor(model: model) }
        .sheet(item: $editingCredential) { source in RepositoryEditor(model: model, source: source) }
        .alert("Talos", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
            Button("OK") { model.error = nil }
        } message: { Text(model.error ?? "") }
        .task {
            await model.load()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(1)) } catch { break }
                if !model.isBusy { await model.reload() }
            }
        }
    }
    private var wheel: some View {
        WheelEditor(model: model)
    }
    private var repositories: some View {
        Form {
            if !model.snapshot.repositories.isEmpty {
                Section {
                    ForEach(model.snapshot.repositories) { source in
                        HStack(spacing: 12) {
                            Image(systemName: source.isLocal ? "folder" : "externaldrive.connected.to.line.below")
                                .frame(width: 24, height: 24)
                                .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(source.name)
                                Text(source.slug).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                            if let error = source.error {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                                    .accessibilityLabel("Repository error: \(error)")
                            }
                            }
                            Spacer()
                            if model.hasUpdate(source) {
                                Button("Update") { Task { await model.update(source) } }
                                    .accessibilityIdentifier("repositories.update.\(source.id.uuidString)")
                            }
                            Button("Remove") { Task { await model.removeRepository(source) } }
                                .accessibilityIdentifier("repositories.remove.\(source.id.uuidString)")
                        }
                        .accessibilityIdentifier("repositories.row.\(source.slug)")
                        .contextMenu {
                            if !source.isLocal { Button("Credentials…") { editingCredential = source } }
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .overlay {
            if model.snapshot.repositories.isEmpty {
                ContentUnavailableView("No repositories", systemImage: "externaldrive", description: Text("Add a GitHub repository or a local folder."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .toolbar {
            ToolbarSpacer(.flexible, placement: .primaryAction)
            ToolbarItemGroup(placement: .primaryAction) {
                Button("Refresh repositories", systemImage: "arrow.clockwise") { Task { await model.refresh() } }
                    .accessibilityIdentifier("repositories.refresh")
                Menu {
                    Button("GitHub repository…", systemImage: "network") { addingRepository = true }
                        .accessibilityIdentifier("repositories.add.github")
                    Button("Import extension…", systemImage: "shippingbox") { importPackage() }
                    Button("Local repository…", systemImage: "folder") { importLocal() }
                        .accessibilityIdentifier("repositories.add.local")
                } label: {
                    Label("Add repository", systemImage: "folder.badge.plus")
                }
                .accessibilityIdentifier("repositories.add")
            }
        }
        .disabled(model.isBusy)
    }
    private func importPackage() {
        let panel = NSOpenPanel()
        panel.title = "Import Talos extension"
        panel.allowedContentTypes = [UTType(filenameExtension: "talos") ?? .zip]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url {
            Task { await model.importPackage(url) }
        }
    }

    private func importLocal() {
        let panel = NSOpenPanel()
        panel.title = "Choose a local Talos repository"
        panel.canChooseDirectories = true; panel.canChooseFiles = false; panel.allowsMultipleSelection = false
        if panel.runModal() == .OK, let url = panel.url { Task { await model.importLocal(url) } }
    }
}

