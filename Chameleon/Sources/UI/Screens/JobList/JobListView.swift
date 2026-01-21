import SwiftUI
import SwiftData

public struct JobListView: View {
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \JobModel.updatedAt, order: .reverse)
    private var jobs: [JobModel]

    @State private var searchText = ""
    @State private var isPresentingNewJobSheet = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if filteredJobs.isEmpty {
                    ContentUnavailableView(
                        "No Jobs",
                        systemImage: "briefcase",
                        description: Text("Create your first job to get started.")
                    )
                    .overlay(alignment: .bottom) {
                        Button("New Job") { isPresentingNewJobSheet = true }
                            .buttonStyle(.borderedProminent)
                            .padding()
                    }
                } else {
                    List {
                        ForEach(filteredJobs, id: \.id) { job in
                            NavigationLink {
                                JobDetailView(job: job)
                            } label: {
                                JobRow(job: job)
                            }
                        }
                        .onDelete(perform: deleteJobs)
                    }
                }
            }
            .navigationTitle("Jobs")
            .onAppear {
                Task { @MainActor in
                    HangDiagnostics.shared.setCurrentScreen("JobList")
                }
            }
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always))
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    NavigationLink {
                        SettingsView()
                    } label: {
                        Image(systemName: "gearshape")
                    }
                    .accessibilityLabel("Settings")

                    Button {
                        isPresentingNewJobSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .accessibilityLabel("New Job")
                }
            }
            .sheet(isPresented: $isPresentingNewJobSheet) {
                NewJobSheet { draft in
                    let repository = JobRepository(modelContext: modelContext)
                    _ = try repository.createJob(
                        clientName: draft.clientName,
                        projectName: draft.projectName,
                        address: draft.address
                    )
                }
            }
        }
    }

    private var filteredJobs: [JobModel] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return jobs }

        let lowercased = query.lowercased()
        return jobs.filter { job in
            if job.clientName.lowercased().contains(lowercased) { return true }
            if let projectName = job.projectName?.lowercased(), projectName.contains(lowercased) { return true }
            if let address = job.address?.lowercased(), address.contains(lowercased) { return true }
            return false
        }
    }

    private func deleteJobs(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(filteredJobs[index])
        }

        do {
            try modelContext.save()
        } catch {
            assertionFailure("Failed to delete jobs: \(error)")
        }
    }
}

private struct JobRow: View {
    let job: JobModel

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(job.clientName)
                .font(.headline)
                .foregroundStyle(.primary)

            if let projectName = job.projectName, !projectName.isEmpty {
                Text(projectName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else if let address = job.address, !address.isEmpty {
                Text(address)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct NewJobDraft {
    var clientName: String = ""
    var projectName: String = ""
    var address: String = ""
}

private struct NewJobSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var draft = NewJobDraft()
    @State private var errorMessage: String?

    let onSave: (NewJobDraft) throws -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section("Client") {
                    TextField("Client Name", text: $draft.clientName)
                        .textInputAutocapitalization(.words)
                }

                Section("Optional") {
                    TextField("Project Name", text: $draft.projectName)
                        .textInputAutocapitalization(.words)
                    TextField("Address", text: $draft.address)
                        .textInputAutocapitalization(.words)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .navigationTitle("New Job")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(draft.clientName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func save() {
        do {
            errorMessage = nil

            let trimmedClientName = draft.clientName.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmedClientName.isEmpty else {
                errorMessage = "Client name is required."
                return
            }

            let normalized = NewJobDraft(
                clientName: trimmedClientName,
                projectName: draft.projectName.trimmingCharacters(in: .whitespacesAndNewlines),
                address: draft.address.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            try onSave(normalized)
            dismiss()
        } catch {
            errorMessage = "Could not save job. Please try again."
        }
    }
}
