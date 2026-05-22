//
//  PencilKitView.swift
//  LucidBoard
//
//  Created by Gemini CLI.
//

import SwiftUI
import PencilKit

struct PencilKitView: UIViewRepresentable {
    @Binding var drawing: PKDrawing
    var tool: PKTool = PKInkingTool(.pen, color: .black, width: 3)
    
    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawing = drawing
        canvasView.tool = tool
        canvasView.delegate = context.coordinator
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        
        #if targetEnvironment(simulator)
        canvasView.drawingPolicy = .anyInput
        #endif
        
        return canvasView
    }
    
    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        if uiView.drawing != drawing {
            uiView.drawing = drawing
        }
        
        // Ensure contentSize matches the view's bounds to allow drawing over the full area
        if uiView.contentSize != uiView.bounds.size {
            uiView.contentSize = uiView.bounds.size
        }
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(drawing: $drawing)
    }
    
    class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding var drawing: PKDrawing
        
        init(drawing: Binding<PKDrawing>) {
            _drawing = drawing
        }
        
        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawing = canvasView.drawing
        }
    }
}
