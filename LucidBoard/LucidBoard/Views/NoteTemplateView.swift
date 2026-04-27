//
//  NoteTemplateView.swift
//  LucidBoard
//
//  Created by Gemini CLI.
//

import SwiftUI

struct NoteTemplateView: View {
    @ObservedObject var viewModel: NoteViewModel
    var mode: NoteView.NoteMode
    
    var body: some View {
        ZStack {
            // Background Patterns
            if viewModel.note.template == .lined {
                LinedPatternView()
            }
            
            // Main Content
            if viewModel.note.template == .checklist && mode == .text {
                ChecklistContentView(viewModel: viewModel)
            } else if viewModel.note.template == .checklist && mode == .drawing {
                // Drawing mode checklist shows a large checkbox outline
                HandwrittenChecklistBackground()
            }
        }
    }
}

struct LinedPatternView: View {
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 25
            for y in stride(from: step, to: size.height, by: step) {
                var path = Path()
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(path, with: .color(.gray.opacity(0.2)), lineWidth: 1)
            }
        }
    }
}

struct HandwrittenChecklistBackground: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ForEach(0..<5) { _ in
                RoundedRectangle(cornerRadius: 4)
                    .stroke(Color.gray.opacity(0.3), lineWidth: 2)
                    .frame(width: 24, height: 24)
            }
            Spacer()
        }
        .padding(.leading, 10)
        .padding(.top, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct ChecklistContentView: View {
    @ObservedObject var viewModel: NoteViewModel
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.note.checklistItems ?? []) { item in
                    HStack {
                        Button(action: { viewModel.toggleChecklistItem(id: item.id) }) {
                            Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                                .foregroundColor(item.isCompleted ? .green : .secondary)
                        }
                        
                        TextField("Item", text: Binding(
                            get: { item.text },
                            set: { viewModel.updateChecklistItemText(id: item.id, text: $0) }
                        ))
                        .strikethrough(item.isCompleted)
                        .foregroundColor(item.isCompleted ? .secondary : .primary)
                        
                        Button(action: { viewModel.deleteChecklistItem(id: item.id) }) {
                            Image(systemName: "xmark.circle")
                                .foregroundColor(.red.opacity(0.5))
                                .font(.caption)
                        }
                    }
                }
                
                Button(action: { viewModel.addChecklistItem() }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Item")
                    }
                    .font(.caption)
                    .foregroundColor(.blue)
                    .padding(.top, 4)
                }
            }
            .padding(8)
        }
    }
}

// Shapes
struct DiamondShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minY, y: rect.midY))
        path.closeSubpath()
        return path
    }
}
