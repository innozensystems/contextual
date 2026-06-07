import Foundation
import Supabase
import Combine

@MainActor
final class SupabaseService: ObservableObject {
    static let shared = SupabaseService()

    let client: SupabaseClient

    @Published var currentUser: User?
    @Published var isAuthenticated = false

    private init() {
        let rawUrl = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String
        let rawKey = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_ANON_KEY") as? String

        let urlString: String
        let supabaseKey: String

        #if DEBUG
        // Debug builds may use placeholder values if Info.plist is not configured.
        urlString = rawUrl?.isEmpty == false ? rawUrl! : "https://your-project.supabase.co"
        supabaseKey = rawKey?.isEmpty == false ? rawKey! : "your-anon-key"
        #else
        // Release builds must have real secrets injected at build time.
        guard let u = rawUrl, !u.isEmpty else {
            fatalError("SUPABASE_URL must be configured in Info.plist for release builds. Do not commit real credentials.")
        }
        guard let k = rawKey, !k.isEmpty else {
            fatalError("SUPABASE_ANON_KEY must be configured in Info.plist for release builds. Do not commit real credentials.")
        }
        urlString = u
        supabaseKey = k
        #endif

        guard let supabaseURL = URL(string: urlString) else {
            fatalError("Invalid SUPABASE_URL in Info.plist: \(urlString)")
        }

        self.client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: supabaseKey
        )
    }

    func initializeSession() async {
        do {
            let session = try await client.auth.session
            self.currentUser = session.user
            self.isAuthenticated = true
        } catch {
            self.isAuthenticated = false
        }
    }

    func signIn(email: String, password: String) async throws {
        let session = try await client.auth.signIn(email: email, password: password)
        self.currentUser = session.user
        self.isAuthenticated = true
    }

    func signUp(email: String, password: String) async throws {
        let session = try await client.auth.signUp(email: email, password: password)
        self.currentUser = session.user
        self.isAuthenticated = true
    }

    func signOut() async throws {
        try await client.auth.signOut()
        self.currentUser = nil
        self.isAuthenticated = false
    }

    // MARK: - Tasks

    func fetchTasks(for userId: UUID) async throws -> [CTask] {
        return try await client.database
            .from("tasks")
            .select("""
                *,
                locations:location_id (*)
            """)
            .eq("user_id", value: userId)
            .neq("status", value: "archived")
            .order("created_at", ascending: false)
            .execute()
            .value
    }

    func fetchSharedTasks(for userId: UUID) async throws -> [CTask] {
        return try await client.database
            .from("tasks")
            .select("""
                *,
                locations:location_id (*),
                lists:list_id (*)
            """)
            .eq("list_id", value: userId) // via RLS, user sees lists they're members of
            .neq("status", value: "archived")
            .execute()
            .value
    }

    func createTask(_ task: CTask) async throws -> CTask {
        return try await client.database
            .from("tasks")
            .insert(task)
            .single()
            .execute()
            .value
    }

    func updateTask(_ task: CTask) async throws {
        try await client.database
            .from("tasks")
            .update(task)
            .eq("id", value: task.id)
            .execute()
    }

    func deleteTask(id: UUID) async throws {
        try await client.database
            .from("tasks")
            .delete()
            .eq("id", value: id)
            .execute()
    }

    func completeTask(id: UUID) async throws {
        try await client.database
            .from("tasks")
            .update(["status": "completed", "completed_at": Date().iso8601])
            .eq("id", value: id)
            .execute()
    }

    // MARK: - Locations

    func createLocation(_ location: CLocation) async throws -> CLocation {
        return try await client.database
            .from("locations")
            .insert(location)
            .single()
            .execute()
            .value
    }

    // MARK: - Lists

    func fetchLists(for userId: UUID) async throws -> [CList] {
        return try await client.database
            .from("lists")
            .select("*")
            .or("owner_id.eq.\(userId), list_members!inner(user_id.eq.\(userId))")
            .execute()
            .value
    }

    // MARK: - Realtime

    func subscribeToTasks(userId: UUID, onUpdate: @escaping ([CTask]) -> Void) async throws -> RealtimeChannel {
        let channel = client.realtime.channel("public:tasks")

        await channel.on(.postgresChanges(event: .all, schema: "public", table: "tasks", filter: "user_id=eq.\(userId)")) { message in
            Task {
                let tasks = try await self.fetchTasks(for: userId)
                onUpdate(tasks)
            }
        }

        try await channel.subscribe()
        return channel
    }

    // MARK: - Nearby Tasks (RPC)

    func nearbyTasks(lat: Double, lng: Double, radiusMeters: Int = 5000) async throws -> [NearbyTaskResult] {
        return try await client.database
            .rpc("nearby_tasks", params: [
                "p_user_id": currentUser?.id.uuidString ?? "",
                "p_lat": lat,
                "p_lng": lng,
                "p_radius_meters": radiusMeters
            ])
            .execute()
            .value
    }
}

struct NearbyTaskResult: Codable {
    let taskId: UUID
    let title: String
    let locationName: String?
    let distanceMeters: Double
    let latitude: Double
    let longitude: Double

    enum CodingKeys: String, CodingKey {
        case taskId = "task_id"
        case title
        case locationName = "location_name"
        case distanceMeters = "distance_meters"
        case latitude
        case longitude
    }
}
