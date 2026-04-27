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
                // Infinite Background Layer
                BoardBackgroundView(
                    layout: viewModel.board.backgroundLayout,
                    color: backgroundColor
                )
                .offset(combinedOffset)
                .scaleEffect(combinedScale)
                
                // Canvas Layer (Notes)
                ZStack {
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
                    HStack {
                        Spacer()
                        Menu {
                            Section("Background Color") {
                                Button("Default (White)") { viewModel.updateBackgroundColor("#FFFFFF") }
                                Button("Light Gray") { viewModel.updateBackgroundColor("#F2F2F7") }
                                Button("Sepia") { viewModel.updateBackgroundColor("#F4ECD8") }
                                Button("Dark Blue") { viewModel.updateBackgroundColor("#1C1C1E") }
                            }
                            Section("Layout Pattern") {
                                Button("Grid") { viewModel.updateBackgroundLayout(.grid) }
                                Button("Dot Grid") { viewModel.updateBackgroundLayout(.dotGrid) }
                                Button("Horizontal Lines") { viewModel.updateBackgroundLayout(.horizontalLines) }
                                Button("Vertical Lines") { viewModel.updateBackgroundLayout(.verticalLines) }
                                Button("Plain") { viewModel.updateBackgroundLayout(.plain) }
                            }
                        } label: {
                            Image(systemName: "paintpalette.fill")
                                .font(.system(size: 20))
                                .padding(12)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                                .shadow(color: .black.opacity(0.1), radius: 5)
                        }
                        .padding(.top, 50)
                        .padding(.trailing, 20)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 20) {
                        Button(action: {
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
            .contentShape(Rectangle())
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
    }
    
    private var backgroundColor: Color {
        Color(hex: viewModel.board.backgroundColor)
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

#Preview {
    BoardView(viewModel: BoardViewModel(board: Board(
        id: UUID(),
        userId: UUID(),
        title: "Test Board",
        backgroundColor: "#FFFFFF",
        backgroundLayout: .grid,
        createdAt: Date(),
        updatedAt: Date()
    )))
}
