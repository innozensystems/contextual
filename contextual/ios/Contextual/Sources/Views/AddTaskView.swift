import SwiftUI
import Speech

@MainActor
class AddTaskViewModel: ObservableObject {
    @Published var taskTitle = ""
    @Published var locationQuery = ""
    @Published var notes = ""
    @Published var priority: TaskPriority = .normal
    @Published var reminderRadius = 200
    @Published var isHardToGet = false

    @Published var isListening = false
    @Published var recognizedText = ""
    @Published var transcript = ""
    @Published var geocodeResults: [ProxyService.GeocodeResult] = []
    @Published var isGeocoding = false
    @Published var selectedLocation: ProxyService.GeocodeResult?

    @Published var errorMessage: String?
    @Published var isSaving = false

    private var speechRecognizer: SFSpeechRecognizer?
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioEngine = AVAudioEngine()

    init() {
        speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    }

    func requestSpeechAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status == .authorized)
            }
        }
    }

    func startListening() async {
        let authorized = await requestSpeechAuthorization()
        guard authorized else {
            errorMessage = "Microphone access needed for voice entry"
            return
        }

        do {
            try AVAudioSession.sharedInstance().setCategory(.record, mode: .measurement, options: .duckOthers)
            try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)

            recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
            guard let request = recognitionRequest else { return }
            request.shouldReportPartialResults = true

            recognitionTask = speechRecognizer?.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }
                if let result = result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.parseVoiceInput(result.bestTranscription.formattedString)
                    }
                }
                if error != nil {
                    self.stopListening()
                }
            }

            let inputNode = audioEngine.inputNode
            let recordingFormat = inputNode.outputFormat(forBus: 0)
            inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
                self.recognitionRequest?.append(buffer)
            }

            audioEngine.prepare()
            try audioEngine.start()
            isListening = true
        } catch {
            errorMessage = "Speech recognition failed — try typing"
            stopListening()
        }
    }

    func stopListening() {
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionRequest = nil
        recognitionTask = nil
        isListening = false
    }

    func parseVoiceInput(_ text: String) {
        // Naive parsing: "Buy milk at Whole Foods" → task="Buy milk", location="Whole Foods"
        let patterns = [
            " at ",
            " near ",
            " from ",
            " in ",
        ]
        var foundLocation: String?
        var taskPart = text
        for pattern in patterns {
            if let range = text.lowercased().range(of: pattern) {
                taskPart = String(text[..<range.lowerBound])
                foundLocation = String(text[range.upperBound...]).trimmingCharacters(in: .whitespaces)
                break
            }
        }

        self.taskTitle = taskPart.trimmingCharacters(in: .whitespaces)
        if let loc = foundLocation {
            self.locationQuery = loc
            geocodeLocation()
        }
    }

    func geocodeLocation() {
        guard !locationQuery.isEmpty else { return }
        isGeocoding = true
        Task {
            do {
                let results = try await ProxyService.shared.geocode(query: locationQuery)
                self.geocodeResults = results
                if let first = results.first {
                    self.selectedLocation = first
                }
            } catch {
                errorMessage = "Location not found — try a different name"
            }
            isGeocoding = false
        }
    }

    func saveTask() async -> Bool {
        guard !taskTitle.isEmpty else {
            errorMessage = "Task name is required"
            return false
        }
        isSaving = true
        defer { isSaving = false }

        do {
            let userId = SupabaseService.shared.currentUser?.id ?? UUID()
            var locationId: UUID?

            if let loc = selectedLocation {
                let location = CLocation(
                    id: UUID(),
                    name: loc.name,
                    address: loc.address,
                    latitude: loc.latitude,
                    longitude: loc.longitude,
                    placeId: loc.placeId,
                    createdBy: userId,
                    createdAt: Date()
                )
                let saved = try await SupabaseService.shared.createLocation(location)
                locationId = saved.id
            }

            let task = CTask(
                id: UUID(),
                userId: userId,
                title: taskTitle,
                notes: notes.isEmpty ? nil : notes,
                locationId: locationId,
                status: .active,
                priority: priority,
                dueDate: nil,
                completedAt: nil,
                reminderRadiusMeters: reminderRadius,
                isHardToGet: isHardToGet,
                listId: nil,
                createdAt: Date(),
                updatedAt: Date()
            )

            _ = try await SupabaseService.shared.createTask(task)
            return true
        } catch {
            errorMessage = "Failed to save task — will retry when online"
            return false
        }
    }
}

struct AddTaskView: View {
    @StateObject private var viewModel = AddTaskViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    if viewModel.isListening {
                        VStack(spacing: 16) {
                            VoiceWaveformView()
                                .frame(height: 60)
                            Text(viewModel.transcript)
                                .font(.body)
                                .foregroundStyle(.secondary)
                                .animation(.easeInOut, value: viewModel.transcript)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 20)
                    } else {
                        TextField("Task name", text: $viewModel.taskTitle)
                        TextField("Notes", text: $viewModel.notes, axis: .vertical)
                            .lineLimit(3...6)
                    }
                } header: {
                    Text("What do you need to do?")
                } footer: {
                    if !viewModel.isListening {
                        Text("Voice stays on-device until parsed")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Where") {
                    TextField("Location (e.g., Whole Foods)", text: $viewModel.locationQuery)
                        .onSubmit { viewModel.geocodeLocation() }

                    if viewModel.isGeocoding {
                        ProgressView()
                            .frame(maxWidth: .infinity)
                    }

                    if !viewModel.geocodeResults.isEmpty {
                        ForEach(viewModel.geocodeResults, id: \.placeId) { result in
                            Button(action: { viewModel.selectedLocation = result }) {
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(result.name)
                                            .font(.body)
                                        if let address = result.address {
                                            Text(address)
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                    Spacer()
                                    if viewModel.selectedLocation?.placeId == result.placeId {
                                        Image(systemName: "checkmark")
                                            .foregroundStyle(.accent)
                                    }
                                }
                            }
                        }
                    }
                }

                Section("Details") {
                    Picker("Priority", selection: $viewModel.priority) {
                        ForEach(TaskPriority.allCases, id: \.self) { p in
                            Text(p.rawValue.capitalized).tag(p)
                        }
                    }

                    Stepper("Reminder radius: \(viewModel.reminderRadius)m", value: $viewModel.reminderRadius, in: 50...1000, step: 50)

                    Toggle("Hard to get item", isOn: $viewModel.isHardToGet)
                }

                if let error = viewModel.errorMessage {
                    Section {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.subheadline)
                    }
                }
            }
            .navigationTitle("Add Task")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            let success = await viewModel.saveTask()
                            if success { dismiss() }
                        }
                    }
                    .disabled(viewModel.taskTitle.isEmpty || viewModel.isSaving)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(action: {
                        if viewModel.isListening {
                            viewModel.stopListening()
                        } else {
                            Task { await viewModel.startListening() }
                        }
                    }) {
                        Image(systemName: viewModel.isListening ? "mic.fill" : "mic")
                            .foregroundStyle(viewModel.isListening ? .red : .accent)
                    }
                }
            }
        }
    }
}

struct VoiceWaveformView: View {
    @State private var phase: Double = 0

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.05)) { _ in
            Canvas { context, size in
                let barCount = 20
                let barWidth = size.width / CGFloat(barCount * 2)
                let maxHeight = size.height

                for i in 0..<barCount {
                    let x = CGFloat(i * 2 + 1) * barWidth
                    let normalizedIndex = Double(i) / Double(barCount)
                    let wave = sin(normalizedIndex * .pi * 4 + phase)
                    let height = maxHeight * CGFloat(0.3 + 0.7 * abs(wave))
                    let rect = CGRect(
                        x: x - barWidth / 2,
                        y: (size.height - height) / 2,
                        width: barWidth,
                        height: height
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: barWidth / 2),
                        with: .color(.accentColor)
                    )
                }
            }
            .onAppear {
                withAnimation(.linear(duration: 1).repeatForever(autoreverses: false)) {
                    phase += .pi * 2
                }
            }
        }
    }
}
