//
//  NoteView.swift
//  LucidBoard
//
//  Created by Gemini CLI.
//

import SwiftUI

struct NoteView: View {
    @ObservedObject var viewModel: NoteViewModel
    @State private var mode: NoteMode = .text
    var onDelete: () -> Void = {}
    var onBringToFront: () -> Void = {}

    enum NoteMode {
        case text, drawing
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Button(action: { mode = .text }) {
                    Image(systemName: "text.alignleft")
                        .foregroundStyle(mode == .text ? .primary : .secondary)
                }
                Button(action: { mode = .drawing }) {
                    Image(systemName: "pencil.tip")
                        .foregroundStyle(mode == .drawing ? .primary : .secondary)
                }
                Spacer()
                Image(systemName: "hand.tap")
                    .foregroundStyle(viewModel.isDragging ? .blue : .secondary)
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(0.8))
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
            
            ZStack {
                if mode == .text {
                    TextEditor(text: Binding(
                        get: { viewModel.note.contentText ?? "" },
                        set: { 
                            viewModel.note.contentText = $0 
                            viewModel.syncNote() // Basic debounced or direct sync
                        }
                    ))
                    .font(.system(size: 14, weight: .medium, design: .default))
                    .scrollContentBackground(.hidden)
                } else {
                    PencilKitView(drawing: $viewModel.drawing)
                }
            }
            .frame(width: 200, height: 200)
        }
        .padding(8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(hex: viewModel.note.color).opacity(0.8))
                .background(.ultraThinMaterial)
        )
        .cornerRadius(12)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        .position(x: CGFloat(viewModel.note.posX), y: CGFloat(viewModel.note.posY))
        .scaleEffect(viewModel.isDragging ? 1.05 : 1.0)
        .animation(.spring(response: 0.3, dampingFraction: 0.6, blendDuration: 0), value: viewModel.isDragging)
        .gesture(
            DragGesture()
                .onChanged { value in
                    if !viewModel.isDragging {
                        onBringToFront()
                    }
                    viewModel.isDragging = true
                    viewModel.updatePosition(to: CGPoint(
                        x: CGFloat(viewModel.note.posX) + value.translation.width,
                        y: CGFloat(viewModel.note.posY) + value.translation.height
                    ))
                }
                .onEnded { _ in
                    viewModel.isDragging = false
                    viewModel.finalizePosition()
                }
        )
    }
}

// Color Helper
extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (1, 1, 1, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
