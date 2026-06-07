import SwiftUI
import MapKit

struct TripView: View {
    let tasks: [CTask]
    @State private var route: ProxyService.RouteResponse?
    @State private var isOptimizing = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Map {
                    // In production: add annotations for task locations
                    ForEach(tasks) { task in
                        Marker(task.title, coordinate: CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194))
                    }
                }
                .mapStyle(.standard)
                .frame(maxHeight: .infinity)

                // Bottom sheet with task list
                VStack(spacing: 0) {
                    Capsule()
                        .frame(width: 36, height: 4)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)

                    if isOptimizing {
                        ProgressView("Optimizing route...")
                            .padding()
                    } else if let route = route {
                        HStack {
                            Label(formatDuration(route.durationSeconds), systemImage: "clock")
                            Spacer()
                            Label(formatDistance(route.distanceMeters), systemImage: "arrow.left.arrow.right")
                        }
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal)

                        List {
                            ForEach(tasks) { task in
                                HStack {
                                    Text(task.title)
                                        .font(.body)
                                    Spacer()
                                    Image(systemName: "line.3.horizontal")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .onMove { from, to in
                                // Reorder and recalculate route
                            }
                        }
                        .listStyle(.plain)
                    } else {
                        Button("Optimize route") {
                            optimizeRoute()
                        }
                        .padding()
                    }
                }
                .background(Color(.systemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .shadow(color: .black.opacity(0.1), radius: 8, y: -4)
            }
            .navigationTitle("Trip")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func optimizeRoute() {
        isOptimizing = true
        Task {
            do {
                let waypoints = tasks.map { _ in
                    // In production, use actual task coordinates
                    CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194)
                }
                let result = try await ProxyService.shared.route(waypoints: waypoints, optimize: true)
                self.route = result
            } catch {
                // Show error
            }
            isOptimizing = false
        }
    }

    private func formatDuration(_ seconds: Double) -> String {
        let mins = Int(seconds / 60)
        if mins < 60 {
            return "\(mins) min"
        }
        let hours = mins / 60
        let remainingMins = mins % 60
        return "\(hours)h \(remainingMins)m"
    }

    private func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters)) m"
        }
        return String(format: "%.1f km", meters / 1000)
    }
}
