import SwiftUI

struct TaskDetailView: View {
    let task: CTask
    @State private var showShareSheet = false
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text(task.title)
                        .font(.body)

                    if let notes = task.notes {
                        Text(notes)
                            .font(.body)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Location") {
                    if let locId = task.locationId {
                        // Map placeholder
                        MapThumbnailView(locationId: locId)
                            .frame(height: 200)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    } else {
                        Text("No location set")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Status") {
                    HStack {
                        Text("Priority")
                        Spacer()
                        Text(task.priority.rawValue.capitalized)
                            .foregroundStyle(priorityColor)
                    }

                    if let completedAt = task.completedAt {
                        HStack {
                            Text("Completed")
                            Spacer()
                            Text(completedAt, style: .date)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section {
                    Button("Complete Task") {
                        // Complete
                    }
                    .disabled(task.status == .completed)
                }

                Section {
                    Button("Share with partner") {
                        showShareSheet = true
                    }

                    Button("Delete", role: .destructive) {
                        showDeleteConfirm = true
                    }
                }
            }
            .navigationTitle("Task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showShareSheet) {
                PartnerInviteView(task: task)
            }
            .alert("Delete task?", isPresented: $showDeleteConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Delete", role: .destructive) {
                    Task {
                        try? await SupabaseService.shared.deleteTask(id: task.id)
                        dismiss()
                    }
                }
            }
        }
    }

    private var priorityColor: Color {
        switch task.priority {
        case .low: return .secondary
        case .normal: return .accentColor
        case .high: return .orange
        case .urgent: return .red
        }
    }
}

struct MapThumbnailView: View {
    let locationId: UUID

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            Image(systemName: "map")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
        }
    }
}

struct PartnerInviteView: View {
    let task: CTask
    @State private var inviteMethod: InviteMethod = .sms
    @State private var recipient = ""
    @State private var isSending = false
    @State private var sent = false
    @Environment(\.dismiss) private var dismiss

    enum InviteMethod: String, CaseIterable {
        case sms = "SMS"
        case email = "Email"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Send invite") {
                    Picker("Method", selection: $inviteMethod) {
                        ForEach(InviteMethod.allCases, id: \.self) { method in
                            Text(method.rawValue).tag(method)
                        }
                    }
                    .pickerStyle(.segmented)

                    TextField(inviteMethod == .sms ? "Phone number" : "Email", text: $recipient)
                        .keyboardType(inviteMethod == .sms ? .phonePad : .emailAddress)
                }

                Section {
                    Text("They'll see this task once they join Contextual.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if sent {
                    Section {
                        Label("Invite sent!", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                }
            }
            .navigationTitle("Partner Invite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Send") {
                        sendInvite()
                    }
                    .disabled(recipient.isEmpty || isSending || sent)
                }
            }
        }
    }

    private func sendInvite() {
        isSending = true
        Task {
            // In production: generate deep link, send via backend or MessageUI
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            sent = true
            isSending = false
        }
    }
}
