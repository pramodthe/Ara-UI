//
//  Message.swift
//  nova
//
//  Defines chat message types used across the app.
//

import Foundation

enum MessageRole: String, Codable, CaseIterable {
    case user
    case model
}

struct Message: Identifiable, Equatable, Codable {
    let id: UUID
    let role: MessageRole
    var text: String
    let createdAt: Date

    init(id: UUID = UUID(), role: MessageRole, text: String, createdAt: Date = Date()) {
        self.id = id
        self.role = role
        self.text = text
        self.createdAt = createdAt
    }
}


