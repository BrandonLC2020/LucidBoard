//
//  BoardView.swift
//  LucidBoard
//
//  Created by Gemini CLI.
//

import SwiftUI

struct BoardView: View {
    @StateObject var viewModel: BoardViewModel
    
    var body: some View {
        ZStack {
            // Infinite Grid Background (Optional but helpful for spatial sense)
            InfiniteGrid()
                .stroke(Color.gray.opacity(0.1), lineWidth: 1)
            
            // Canvas Layer
            ZStack {
                ForEach(Array(viewModel.noteViewModels.values).sorted { $0.note.zIndex < $1.note.zIndex }) { noteVM in
                    NoteView(viewModel: noteVM) {
                        viewModel.deleteNote(id: noteVM.id)
                    } onBringToFront: {
                        viewModel.bringToFront(id: noteVM.id)
                    }
                }
            }
            .offset(viewModel.offset)
            .scaleEffect(viewModel.scale)
            
            // UI Layer (Floating Toolbars)
            VStack {
                Spacer()
                HStack(spacing: 20) {
                    Button(action: {
                        viewModel.addNote(at: CGPoint(x: 400, y: 400)) // Simple fixed center for now
                    }) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.primary)
                    }
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                    
                    Button(action: {
                        Task {
                            await viewModel.triggerAutoOrganize()
                        }
                    }) {
                        ZStack {
                            if viewModel.isOrganizing {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                    .tint(.purple)
                                    .frame(width: 32, height: 32)
                            } else {
                                Image(systemName: "sparkles.circle.fill")
                                    .font(.system(size: 32))
                                    .foregroundStyle(.purple)
                            }
                        }
                        .frame(width: 32, height: 32)
                    }
                    .disabled(viewModel.isOrganizing)
                    .padding()
                    .background(.ultraThinMaterial)
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                }
                .padding(.bottom, 40)
            }
        }
        .edgesIgnoringSafeArea(.all)
        .gesture(
            SimultaneousGesture(
                DragGesture()
                    .onChanged { value in
                        viewModel.handlePanGesture(value.translation)
                    }
                    .onEnded { _ in
                        viewModel.finalizePanGesture()
                    },
                MagnificationGesture()
                    .onChanged { value in
                        viewModel.handleZoomGesture(value)
                    }
                    .onEnded { _ in
                        viewModel.finalizeZoomGesture()
                    }
            )
        )
        .background(Color(UIColor.systemBackground))
    }
}

// Simple Grid helper
struct InfiniteGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 50
        
        for x in stride(from: 0, through: rect.width, by: step) {
            path.move(to: CGPoint(x: x, y: 0))
            path.addLine(to: CGPoint(x: x, y: rect.height))
        }
        
        for y in stride(from: 0, through: rect.height, by: step) {
            path.move(to: CGPoint(x: 0, y: y))
            path.addLine(to: CGPoint(x: rect.width, y: y))
        }
        
        return path
    }
}

#Preview {
    BoardView(viewModel: BoardViewModel(board: Board(
        id: UUID(),
        userId: UUID(),
        title: "Test Board",
        createdAt: Date(),
        updatedAt: Date()
    )))
}
