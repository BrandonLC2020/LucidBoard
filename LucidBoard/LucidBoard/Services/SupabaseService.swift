//
//  SupabaseService.swift
//  LucidBoard
//
//  Created by Gemini CLI.
//

import Foundation
import Supabase

class SupabaseService {
    static let shared = SupabaseService()
    
    let client: SupabaseClient
    
    private init() {
        let urlString = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_URL") as? String ?? ""
        let key = Bundle.main.object(forInfoDictionaryKey: "SUPABASE_KEY") as? String ?? ""
        
        client = SupabaseClient(
            supabaseURL: URL(string: urlString)!,
            supabaseKey: key
        )
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
