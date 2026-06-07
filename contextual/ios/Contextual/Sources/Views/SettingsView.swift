import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var notificationsEnabled = true
    @State private var locationEnabled = true
    @State private var reduceMotion = false
    @State private var showSignOutConfirm = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Permissions") {
                    Toggle("Location", isOn: $locationEnabled)
                        .onChange(of: locationEnabled) { _, new in
                            if new {
                                GeofenceService.shared.requestAuthorization()
                            }
                        }
                    Toggle("Notifications", isOn: $notificationsEnabled)
                        .onChange(of: notificationsEnabled) { _, new in
                            if new {
                                NotificationService.shared.requestAuthorization()
                            }
                        }
                }

                Section("Accessibility") {
                    Toggle("Reduce Motion", isOn: $reduceMotion)
                }

                Section("Storage") {
                    NavigationLink("Archive old tasks") {
                        Text("Archive screen placeholder")
                    }
                }

                Section {
                    Button("Sign Out", role: .destructive) {
                        showSignOutConfirm = true
                    }
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .alert("Sign out?", isPresented: $showSignOutConfirm) {
                Button("Cancel", role: .cancel) {}
                Button("Sign Out", role: .destructive) {
                    Task {
                        try? await SupabaseService.shared.signOut()
                        dismiss()
                    }
                }
            }
        }
    }
}
