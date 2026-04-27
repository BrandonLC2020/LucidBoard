//
//  BoardView.swift
//  LucidBoard
//
//  Created by Gemini CLI.
//

import SwiftUI

struct BoardView: View {
    @StateObject var viewModel: BoardViewModel
    
    @State private var currentOffset: CGSize = .zero
    @State private var currentScale: CGFloat = 1.0
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Infinite Grid Background
                InfiniteGrid()
                    .stroke(Color.gray.opacity(0.15), lineWidth: 1)
                    .offset(combinedOffset)
                    .scaleEffect(combinedScale)
                    .drawingGroup() // Optimize grid rendering
                
                // Canvas Layer
                ZStack {
                    // Filter and Sort can be expensive, but needed for Z-index
                    ForEach(Array(viewModel.noteViewModels.values).sorted { $0.note.zIndex < $1.note.zIndex }) { noteVM in
                        NoteView(viewModel: noteVM) {
                            viewModel.deleteNote(id: noteVM.id)
                        } onBringToFront: {
                            viewModel.bringToFront(id: noteVM.id)
                        }
                    }
                }
                .offset(combinedOffset)
                .scaleEffect(combinedScale)
                
                // UI Layer (Floating Toolbars)
                VStack {
                    Spacer()
                    HStack(spacing: 20) {
                        Button(action: {
                            // Add note relative to viewport center
                            let center = CGPoint(
                                x: (geometry.size.width / 2 - viewModel.offset.width - currentOffset.width) / combinedScale,
                                y: (geometry.size.height / 2 - viewModel.offset.height - currentOffset.height) / combinedScale
                            )
                            viewModel.addNote(at: center)
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
            .contentShape(Rectangle()) // Make the whole area tappable for gestures
            .gesture(
                SimultaneousGesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            currentOffset = value.translation
                        }
                        .onEnded { value in
                            viewModel.handlePanGesture(value.translation)
                            viewModel.finalizePanGesture()
                            currentOffset = .zero
                        },
                    MagnificationGesture()
                        .onChanged { value in
                            currentScale = value
                        }
                        .onEnded { value in
                            viewModel.handleZoomGesture(value)
                            viewModel.finalizeZoomGesture()
                            currentScale = 1.0
                        }
                )
            )
        }
        .edgesIgnoringSafeArea(.all)
        .background(Color(UIColor.systemBackground))
    }
    
    private var combinedOffset: CGSize {
        CGSize(
            width: viewModel.offset.width + currentOffset.width,
            height: viewModel.offset.height + currentOffset.height
        )
    }
    
    private var combinedScale: CGFloat {
        viewModel.scale * currentScale
    }
}

// Simple Grid helper
struct InfiniteGrid: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let step: CGFloat = 50
        
        // Extend drawing range to cover common movement areas
        let range: CGFloat = 5000
        
        for x in stride(from: -range, through: range, by: step) {
            path.move(to: CGPoint(x: x, y: -range))
            path.addLine(to: CGPoint(x: x, y: range))
        }
        
        for y in stride(from: -range, through: range, by: step) {
            path.move(to: CGPoint(x: -range, y: y))
            path.addLine(to: CGPoint(x: range, y: y))
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
