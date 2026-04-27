//
//  SupabaseService.swift
//  LucidBoard
//
//  Created by Gemini CLI.
//

import Foundation
import Supabase

enum SupabaseError: Error {
    case notConfigured
}

class SupabaseService {
    static let shared = SupabaseService()
    
    private let _client: SupabaseClient?
    
    var client: SupabaseClient {
        get throws {
            guard let client = _client else {
                throw SupabaseError.notConfigured
            }
            return client
        }
    }
    
    private init() {
        let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? ""
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_KEY") as? String ?? ""
        
        if let url = URL(string: urlString), !key.isEmpty {
            _client = SupabaseClient(
                supabaseURL: url,
                supabaseKey: key
            )
        } else {
            _client = nil
        }
    }
    
    // Auth
    func signInAnonymously() async throws {
        try await client.auth.signInAnonymously()
    }
    
    // Boards
    func fetchBoards() async throws -> [Board] {
        return try await client.from("boards")
            .select()
            .execute()
            .value
    }
    
    func updateBoard(_ board: Board) async throws {
        try await client.from("boards")
            .update(board)
            .eq("id", value: board.id)
            .execute()
    }
    
    // Notes
    func fetchNotes(boardId: UUID) async throws -> [Note] {
        return try await client.from("notes")
            .select()
            .eq("board_id", value: boardId)
            .execute()
            .value
    }
    
    func upsertNote(_ note: Note) async throws {
        try await client.from("notes")
            .upsert(note)
            .execute()
    }

    func deleteNote(id: UUID) async throws {
        try await client.from("notes")
            .delete()
            .eq("id", value: id)
            .execute()
    }
    
    // AI Clustering (Phase 4)
    func autoOrganize(boardId: UUID) async throws -> [UUID: (Float, Float)] {
        // This calls a Postgres RPC named 'match_notes'
        // Which should be defined in Supabase SQL:
        // CREATE OR REPLACE FUNCTION match_notes(board_uuid uuid) ...
        
        let result: [NoteClusterResult] = try await client.rpc("match_notes", params: ["board_uuid": boardId.uuidString])
            .execute()
            .value
            
        var positions: [UUID: (Float, Float)] = [:]
        for res in result {
            positions[res.id] = (res.new_x, res.new_y)
        }
        return positions
    }
}

struct NoteClusterResult: Codable {
    let id: UUID
    let new_x: Float
    let new_y: Float
}
