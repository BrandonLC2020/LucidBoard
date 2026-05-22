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
    var contentForegroundColor: Color
    
    var body: some View {
        ZStack {
            // Background Patterns
            if viewModel.note.template == .lined {
                LinedPatternView()
            }
            
            // Main Content
            if viewModel.note.template == .checklist && mode == .text {
                ChecklistContentView(viewModel: viewModel, contentForegroundColor: contentForegroundColor)
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
    var contentForegroundColor: Color
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.note.checklistItems ?? []) { item in
                    HStack {
                        Button(action: { viewModel.toggleChecklistItem(id: item.id) }) {
                            Image(systemName: item.isCompleted ? "checkmark.square.fill" : "square")
                                .foregroundStyle(item.isCompleted ? .green : contentForegroundColor.opacity(0.7))
                        }
                        
                        TextField("Item", text: Binding(
                            get: { item.text },
                            set: { viewModel.updateChecklistItemText(id: item.id, text: $0) }
                        ))
                        .strikethrough(item.isCompleted)
                        .foregroundStyle(item.isCompleted ? contentForegroundColor.opacity(0.5) : contentForegroundColor)
                        
                        Button(action: { viewModel.deleteChecklistItem(id: item.id) }) {
                            Image(systemName: "xmark.circle")
                                .foregroundStyle(.red.opacity(0.5))
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
                    .foregroundStyle(.blue)
                    .padding(.top, 4)
                }
            }
            .padding(8)
        }
    }
}

// Shapes
struct DiamondShape: InsettableShape {
    var insetAmount: CGFloat = 0

    func path(in rect: CGRect) -> Path {
        let insetRect = rect.insetBy(dx: insetAmount, dy: insetAmount)
        var path = Path()
        path.move(to: CGPoint(x: insetRect.midX, y: insetRect.minY))
        path.addLine(to: CGPoint(x: insetRect.maxX, y: insetRect.midY))
        path.addLine(to: CGPoint(x: insetRect.midX, y: insetRect.maxY))
        path.addLine(to: CGPoint(x: insetRect.minY, y: insetRect.midY))
        path.closeSubpath()
        return path
    }

    func inset(by amount: CGFloat) -> some InsettableShape {
        var diamond = self
        diamond.insetAmount += amount
        return diamond
    }
}
