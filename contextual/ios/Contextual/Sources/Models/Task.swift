import Foundation
import Supabase

enum TaskStatus: String, Codable, CaseIterable {
    case active = "active"
    case completed = "completed"
    case archived = "archived"
}

enum TaskPriority: String, Codable, CaseIterable {
    case low = "low"
    case normal = "normal"
    case high = "high"
    case urgent = "urgent"
}

struct CTask: Identifiable, Codable, Equatable {
    let id: UUID
    let userId: UUID
    var title: String
    var notes: String?
    var locationId: UUID?
    var status: TaskStatus
    var priority: TaskPriority
    var dueDate: Date?
    var completedAt: Date?
    var reminderRadiusMeters: Int
    var isHardToGet: Bool
    var listId: UUID?
    let createdAt: Date
    var updatedAt: Date
    var location: CLocation? = nil

    enum CodingKeys: String, CodingKey {
        case id
        case userId = "user_id"
        case title
        case notes
        case locationId = "location_id"
        case status
        case priority
        case dueDate = "due_date"
        case completedAt = "completed_at"
        case reminderRadiusMeters = "reminder_radius_meters"
        case isHardToGet = "is_hard_to_get"
        case listId = "list_id"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case location = "locations"
    }
}

struct CLocation: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    var address: String?
    var latitude: Double
    var longitude: Double
    var placeId: String?
    let createdBy: UUID?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case address
        case latitude
        case longitude
        case placeId = "place_id"
        case createdBy = "created_by"
        case createdAt = "created_at"
    }
}

struct CList: Identifiable, Codable, Equatable {
    let id: UUID
    var name: String
    let ownerId: UUID
    var isShared: Bool
    var syncPolicy: String
    let createdAt: Date
    var updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case name
        case ownerId = "owner_id"
        case isShared = "is_shared"
        case syncPolicy = "sync_policy"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }
}

struct CListMember: Identifiable, Codable, Equatable {
    let id: UUID
    let listId: UUID
    let userId: UUID
    var role: String
    let invitedBy: UUID?
    let invitedAt: Date
    let acceptedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id
        case listId = "list_id"
        case userId = "user_id"
        case role
        case invitedBy = "invited_by"
        case invitedAt = "invited_at"
        case acceptedAt = "accepted_at"
    }
}

struct CInvitation: Identifiable, Codable, Equatable {
    let id: UUID
    let listId: UUID
    let invitedBy: UUID
    var inviteeEmail: String?
    var inviteePhone: String?
    let token: String
    var status: String
    let createdAt: Date
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case listId = "list_id"
        case invitedBy = "invited_by"
        case inviteeEmail = "invitee_email"
        case inviteePhone = "invitee_phone"
        case token
        case status
        case createdAt = "created_at"
        case expiresAt = "expires_at"
    }
}
