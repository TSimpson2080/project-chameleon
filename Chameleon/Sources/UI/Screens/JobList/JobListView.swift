import SwiftUI
import SwiftData

public struct JobListView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var jobs: [JobModel] = []
    @State private var isLoadingJobs = true
    @State private var jobsErrorMessage: String?

    @State private var searchText = ""
    @State private var isPresentingNewJobSheet = false

    public init() {}

    public var body: some View {
        NavigationStack {
            Group {
                if isLoadingJobs {
                    ProgressView("Loading Jobs…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if let jobsErrorMessage {
                    ContentUnavailableView("Jobs Unavailable", systemImage: "exclamationmark.triangle")
                        .overlay(alignment: .bottom) {
                            Text(jobsErrorMessage)
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .padding()
                        }
                } else if filteredJobs.isEmpty {
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
            .task { await loadJobs() }
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
                    Task { await loadJobs() }
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
        Task { @MainActor in
            do {
                let repository = JobRepository(modelContext: modelContext)
                for index in offsets {
                    try repository.deleteJob(filteredJobs[index])
                }
                await loadJobs()
            } catch {
                jobsErrorMessage = "Failed to delete job(s)."
            }
        }
    }

    @MainActor
    private func loadJobs() async {
        do {
            isLoadingJobs = true
            jobsErrorMessage = nil

            let repository = JobRepository(modelContext: modelContext)
            jobs = try repository.fetchJobs(search: nil)
        } catch {
            jobsErrorMessage = "Could not load jobs."
        }
        isLoadingJobs = false
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
