import SwiftUI
import Combine

enum TaskContextGroup: String, CaseIterable {
    case hereNow = "Here Now"
    case onYourWay = "On Your Way"
    case later = "Later"
}

@MainActor
class HomeViewModel: ObservableObject {
    @Published var tasks: [CTask] = []
    @Published var isLoading = false
    @Published var errorMessage: String?
    @Published var showTripBanner = false
    @Published var tripTasks: [CTask] = []

    private var cancellables = Set<AnyCancellable>()
    private var realtimeChannel: RealtimeChannel?

    func loadTasks() async {
        isLoading = true
        defer { isLoading = false }

        do {
            guard let userId = SupabaseService.shared.currentUser?.id else { return }
            let fetched = try await SupabaseService.shared.fetchTasks(for: userId)
            self.tasks = fetched
            checkTripOpportunities()
        } catch {
            errorMessage = "Can't load tasks — pull to retry"
        }
    }

    func checkTripOpportunities() {
        // Simple rule: 3+ active tasks within 2km of each other = trip suggestion
        let active = tasks.filter { $0.status == .active }
        guard active.count >= 3 else {
            showTripBanner = false
            return
        }
        // In production, use actual coordinates and clustering algorithm
        tripTasks = Array(active.prefix(5))
        showTripBanner = true
    }

    func completeTask(_ task: CTask) {
        Task {
            do {
                try await SupabaseService.shared.completeTask(id: task.id)
                if let index = tasks.firstIndex(where: { $0.id == task.id }) {
                    tasks[index].status = .completed
                    tasks[index].completedAt = Date()
                }
                checkTripOpportunities()
            } catch {
                errorMessage = "Failed to complete task"
            }
        }
    }

    func deleteTask(_ task: CTask) {
        Task {
            do {
                try await SupabaseService.shared.deleteTask(id: task.id)
                tasks.removeAll { $0.id == task.id }
                checkTripOpportunities()
            } catch {
                errorMessage = "Failed to delete task"
            }
        }
    }

    func startRealtime() async {
        do {
            guard let userId = SupabaseService.shared.currentUser?.id else { return }
            realtimeChannel = try await SupabaseService.shared.subscribeToTasks(userId: userId) { [weak self] tasks in
                self?.tasks = tasks
                self?.checkTripOpportunities()
            }
        } catch {
            print("Realtime failed: \(error)")
        }
    }

    func stopRealtime() async {
        if let channel = realtimeChannel {
            await channel.unsubscribe()
        }
    }
}

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @State private var showAddTask = false
    @State private var selectedTask: CTask?
    @State private var showSettings = false
    @State private var showTrip = false

    var body: some View {
        NavigationStack {
            ZStack {
                List {
                    if viewModel.showTripBanner {
                        Section {
                            TripBannerView(tasks: viewModel.tripTasks) {
                                showTrip = true
                            }
                        }
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                    }

                    ForEach(TaskContextGroup.allCases, id: \.self) { group in
                        let groupTasks = tasks(for: group)
                        if !groupTasks.isEmpty {
                            Section {
                                ForEach(groupTasks) { task in
                                    TaskRow(task: task, onComplete: {
                                        viewModel.completeTask(task)
                                    }, onTap: {
                                        selectedTask = task
                                    })
                                }
                                .onDelete { indexSet in
                                    indexSet.forEach { index in
                                        viewModel.deleteTask(groupTasks[index])
                                    }
                                }
                            } header: {
                                Text(group.rawValue.uppercased())
                                    .font(.caption.weight(.medium))
                                    .tracking(2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }

                    if viewModel.tasks.isEmpty && !viewModel.isLoading {
                        EmptyStateView()
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                    }
                }
                .listStyle(.insetGrouped)
                .refreshable {
                    await viewModel.loadTasks()
                }
                .overlay(alignment: .top) {
                    if let error = viewModel.errorMessage {
                        ErrorBanner(message: error) {
                            viewModel.errorMessage = nil
                        }
                    }
                }

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: { showAddTask = true }) {
                            Image(systemName: "plus")
                                .font(.title2.weight(.semibold))
                                .foregroundStyle(.white)
                                .frame(width: 56, height: 56)
                                .background(Color.accentColor)
                                .clipShape(Circle())
                        }
                        .padding(.trailing, 16)
                        .padding(.bottom, 16)
                    }
                }
            }
            .navigationTitle("Contextual")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: { showSettings = true }) {
                        Image(systemName: "gearshape")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: { showAddTask = true }) {
                        Image(systemName: "mic")
                    }
                }
            }
            .sheet(item: $selectedTask) { task in
                TaskDetailView(task: task)
            }
            .sheet(isPresented: $showAddTask) {
                AddTaskView()
            }
            .sheet(isPresented: $showSettings) {
                SettingsView()
            }
            .sheet(isPresented: $showTrip) {
                TripView(tasks: viewModel.tripTasks)
            }
        }
        .task {
            await viewModel.loadTasks()
            await viewModel.startRealtime()
        }
        .onDisappear {
            Task {
                await viewModel.stopRealtime()
            }
        }
    }

    private func tasks(for group: TaskContextGroup) -> [CTask] {
        switch group {
        case .hereNow:
            // In production, compare against current location
            return viewModel.tasks.filter { $0.status == .active }.prefix(2).map { $0 }
        case .onYourWay:
            return viewModel.tasks.filter { $0.status == .active }.dropFirst(2).prefix(3).map { $0 }
        case .later:
            return viewModel.tasks.filter { $0.status == .active }.dropFirst(5).map { $0 }
        }
    }
}

struct TaskRow: View {
    let task: CTask
    let onComplete: () -> Void
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onComplete) {
                Image(systemName: task.status == .completed ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(task.status == .completed ? .green : .accentColor)
                    .frame(width: 44, height: 44)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(task.title)
                    .font(.body)
                    .strikethrough(task.status == .completed)
                    .foregroundStyle(task.status == .completed ? .secondary : .primary)

                if let notes = task.notes {
                    Text(notes)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

struct TripBannerView: View {
    let tasks: [CTask]
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(tasks.count) tasks near you")
                    .font(.subheadline.weight(.semibold))
                Text("Save 20 min by threading them")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(action: onTap) {
                Text("View trip")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }
        }
        .padding()
        .background(Color(.secondarySystemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

struct EmptyStateView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)

            Text("Nothing here yet")
                .font(.title3.weight(.semibold))

            Text("Add your first task — just say it")
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.vertical, 60)
        .frame(maxWidth: .infinity)
    }
}

struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(message)
                .font(.subheadline)
            Spacer()
            Button("Retry", action: onDismiss)
                .font(.subheadline.weight(.semibold))
        }
        .padding()
        .background(Color(.systemBackground))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundStyle(.separator),
            alignment: .bottom
        )
    }
}
