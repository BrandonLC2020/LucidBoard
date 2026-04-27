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
    @State private var dragOffset: CGSize = .zero
    
    var onDelete: () -> Void = {}
    var onBringToFront: () -> Void = {}

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: viewModel.note.color) },
            set: { newColor in
                viewModel.note.color = UIColor(newColor).hexString
                viewModel.syncNote()
            }
        )
    }

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
                
                Menu {
                    Section("Templates") {
                        Button("Plain") { viewModel.updateTemplate(.plain) }
                        Button("Checklist") { viewModel.updateTemplate(.checklist) }
                        Button("Lined") { viewModel.updateTemplate(.lined) }
                        Button("Circle") { viewModel.updateTemplate(.circle) }
                        Button("Diamond") { viewModel.updateTemplate(.diamond) }
                    }
                } label: {
                    Image(systemName: "doc.richtext.fill")
                        .foregroundStyle(.secondary)
                }
                
                Spacer()
                ColorPicker("", selection: colorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 28, height: 28)
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
                // Background Layer (Templates & Patterns)
                NoteTemplateView(viewModel: viewModel, mode: mode)
                
                // Content Layer
                if viewModel.note.template == .checklist && mode == .text {
                    // Handled inside NoteTemplateView for checklists
                } else {
                    if mode == .text {
                        TextEditor(text: Binding(
                            get: { viewModel.note.contentText ?? "" },
                            set: { 
                                viewModel.note.contentText = $0 
                                viewModel.syncNote() 
                            }
                        ))
                        .font(.system(size: 14, weight: .medium, design: .default))
                        .scrollContentBackground(.hidden)
                    } else {
                        PencilKitView(drawing: $viewModel.drawing)
                            .allowsHitTesting(mode == .drawing)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 200, height: 200)
        .padding(8)
        .background(
            noteShape
                .fill(Color(hex: viewModel.note.color).opacity(0.8))
                .background(.ultraThinMaterial)
        )
        .clipShape(noteShape)
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        .offset(
            x: CGFloat(viewModel.note.posX) + dragOffset.width,
            y: CGFloat(viewModel.note.posY) + dragOffset.height
        )
        .scaleEffect(viewModel.isDragging ? 1.05 : 1.0)
        .animation(.interactiveSpring(), value: dragOffset)
        .animation(.spring(response: 0.3, dampingFraction: 0.6), value: viewModel.isDragging)
        .gesture(
            DragGesture(minimumDistance: 5)
                .onChanged { value in
                    if !viewModel.isDragging {
                        onBringToFront()
                        viewModel.isDragging = true
                    }
                    dragOffset = value.translation
                }
                .onEnded { value in
                    viewModel.updatePosition(to: CGPoint(
                        x: CGFloat(viewModel.note.posX) + value.translation.width,
                        y: CGFloat(viewModel.note.posY) + value.translation.height
                    ))
                    dragOffset = .zero
                    viewModel.isDragging = false
                    viewModel.finalizePosition()
                }
        )
    }
    
    private var noteShape: AnyShape {
        switch viewModel.note.template {
        case .circle:
            return AnyShape(Circle())
        case .diamond:
            return AnyShape(DiamondShape())
        default:
            return AnyShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// Color Helpers
extension UIColor {
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return String(format: "#%02X%02X%02X", Int(r * 255), Int(g * 255), Int(b * 255))
    }
}

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

    func toHex() -> String? {
        let uiColor = UIColor(self)
        return uiColor.hexString
    }
}
