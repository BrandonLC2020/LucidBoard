//
//  BoardBackgroundView.swift
//  LucidBoard
//
//  Created by Gemini CLI.
//

import SwiftUI

struct BoardBackgroundView: View {
    let layout: BackgroundLayout
    let color: Color
    
    var body: some View {
        ZStack {
            color
                .edgesIgnoringSafeArea(.all)
            
            switch layout {
            case .grid:
                InfiniteGridView(type: .grid)
            case .dotGrid:
                InfiniteGridView(type: .dotGrid)
            case .horizontalLines:
                InfiniteGridView(type: .horizontalLines)
            case .verticalLines:
                InfiniteGridView(type: .verticalLines)
            case .plain:
                EmptyView()
            }
        }
    }
}

struct InfiniteGridView: View {
    enum GridType {
        case grid
        case dotGrid
        case horizontalLines
        case verticalLines
    }
    
    let type: GridType
    let step: CGFloat = 50
    let range: CGFloat = 5000
    
    var body: some View {
        Canvas { context, size in
            let path = Path { p in
                switch type {
                case .grid:
                    for x in stride(from: -range, through: range, by: step) {
                        p.move(to: CGPoint(x: x, y: -range))
                        p.addLine(to: CGPoint(x: x, y: range))
                    }
                    for y in stride(from: -range, through: range, by: step) {
                        p.move(to: CGPoint(x: -range, y: y))
                        p.addLine(to: CGPoint(x: range, y: y))
                    }
                case .horizontalLines:
                    for y in stride(from: -range, through: range, by: step) {
                        p.move(to: CGPoint(x: -range, y: y))
                        p.addLine(to: CGPoint(x: range, y: y))
                    }
                case .verticalLines:
                    for x in stride(from: -range, through: range, by: step) {
                        p.move(to: CGPoint(x: x, y: -range))
                        p.addLine(to: CGPoint(x: x, y: range))
                    }
                case .dotGrid:
                    break // Dots are handled differently below
                }
            }
            
            if type == .dotGrid {
                for x in stride(from: -range, through: range, by: step) {
                    for y in stride(from: -range, through: range, by: step) {
                        context.fill(Path(ellipseIn: CGRect(x: x - 1, y: y - 1, width: 2, height: 2)), with: .color(Color.gray.opacity(0.3)))
                    }
                }
            } else {
                context.stroke(path, with: .color(Color.gray.opacity(0.15)), lineWidth: 1)
            }
        }
        .drawingGroup()
    }
}
