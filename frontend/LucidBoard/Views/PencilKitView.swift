//
//  PencilKitView.swift
//  LucidBoard
//
//  Created by Gemini CLI.
//

import SwiftUI

// PencilKit only ships on iOS/iPadOS and visionOS; this whole view is unavailable on native
// macOS, where the "Drawing mode" toggle in NoteView is compiled out entirely (see NoteView.swift).
#if os(iOS) || os(visionOS)
import PencilKit

struct PencilKitView: UIViewRepresentable {
    @Binding var drawingData: Data?
    var tool: PKTool = PKInkingTool(.pen, color: .black, width: 3)

    func makeUIView(context: Context) -> PKCanvasView {
        let canvasView = PKCanvasView()
        canvasView.drawing = decodedDrawing
        canvasView.tool = tool
        canvasView.delegate = context.coordinator
        canvasView.backgroundColor = .clear
        canvasView.isOpaque = false
        canvasView.accessibilityLabel = "Drawing canvas"

        #if targetEnvironment(simulator)
        canvasView.drawingPolicy = .anyInput
        #endif

        return canvasView
    }

    func updateUIView(_ uiView: PKCanvasView, context: Context) {
        let latest = decodedDrawing
        if uiView.drawing != latest {
            uiView.drawing = latest
        }

        // Ensure contentSize matches the view's bounds to allow drawing over the full area
        if uiView.contentSize != uiView.bounds.size {
            uiView.contentSize = uiView.bounds.size
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(drawingData: $drawingData)
    }

    private var decodedDrawing: PKDrawing {
        guard let drawingData else { return PKDrawing() }
        return (try? PKDrawing(data: drawingData)) ?? PKDrawing()
    }

    class Coordinator: NSObject, PKCanvasViewDelegate {
        @Binding var drawingData: Data?

        init(drawingData: Binding<Data?>) {
            _drawingData = drawingData
        }

        func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
            drawingData = canvasView.drawing.dataRepresentation()
        }
    }
}
#endif
