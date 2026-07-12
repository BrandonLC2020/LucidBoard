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
    @State private var thermalPulse: ThermalPulse?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var onDelete: () -> Void = {}
    var onBringToFront: () -> Void = {}

    /// iPhone's compact width makes the iPad/Mac default note (200pt) span more than half the
    /// screen; nil (Mac, visionOS) falls back to the regular-width size.
    private var noteSize: CGFloat {
        horizontalSizeClass == .compact ? 160 : 200
    }

    private var adaptiveOpacity: Double {
        let baseColor = Color(hex: viewModel.note.color)
        return baseColor.luminance > 0.5 ? 0.35 : 0.55
    }

    private var contentForegroundColor: Color {
        let baseColor = Color(hex: viewModel.note.color)
        // If note is dark, use white text. If note is light, use primary (which adapts to dark/light mode background)
        return baseColor.luminance < 0.4 ? .white : .primary
    }

    private var colorBinding: Binding<Color> {
        Binding(
            get: { Color(hex: viewModel.note.color) },
            set: { newColor in
                viewModel.note.color = PlatformColor(newColor).hexString
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
                        .foregroundStyle(mode == .text ? contentForegroundColor : contentForegroundColor.opacity(0.8))
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Text mode")
                .accessibilityAddTraits(mode == .text ? .isSelected : [])

                #if os(iOS) || os(visionOS)
                Button(action: { mode = .drawing }) {
                    Image(systemName: "pencil.tip")
                        .foregroundStyle(mode == .drawing ? contentForegroundColor : contentForegroundColor.opacity(0.8))
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Drawing mode")
                .accessibilityAddTraits(mode == .drawing ? .isSelected : [])
                #endif

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
                        .foregroundStyle(contentForegroundColor.opacity(0.8))
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Note template")

                Spacer()
                ColorPicker("", selection: colorBinding, supportsOpacity: false)
                    .labelsHidden()
                    .frame(width: 28, height: 28)
                    .accessibilityLabel("Note color")
                Image(systemName: "hand.tap")
                    .foregroundStyle(viewModel.isDragging ? .blue : contentForegroundColor.opacity(0.8))
                    .accessibilityHidden(true)
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .foregroundStyle(.red.opacity(0.8))
                        .padding(6)
                        .contentShape(Rectangle())
                }
                .accessibilityLabel("Delete note")
            }
            .padding(.horizontal, 4)
            .padding(.top, 4)
            
            ZStack {
                // Background Layer (Templates & Patterns)
                NoteTemplateView(viewModel: viewModel, mode: mode, contentForegroundColor: contentForegroundColor)
                
                // Content Layer
                if viewModel.note.template == .checklist && mode == .text {
                    // Handled inside NoteTemplateView for checklists
                } else {
                    if mode == .drawing {
                        #if os(iOS) || os(visionOS)
                        PencilKitView(drawingData: $viewModel.drawingData)
                            .allowsHitTesting(mode == .drawing)
                        #endif
                    } else {
                        TextEditor(text: Binding(
                            get: { viewModel.note.contentText ?? "" },
                            set: {
                                viewModel.note.contentText = $0
                                viewModel.syncNote()
                            }
                        ))
                        .font(.lucidNoteContent)
                        .foregroundStyle(contentForegroundColor)
                        .scrollContentBackground(.hidden)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: noteSize, height: noteSize)
        .padding(8)
        .background(
            ZStack {
                noteShape
                    .fill(.ultraThinMaterial)
                noteShape
                    .fill(Color(hex: viewModel.note.color).opacity(adaptiveOpacity))
            }
        )
        .clipShape(noteShape)
        .overlay(
            noteShape
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            .white.opacity(adaptiveOpacity > 0.4 ? 0.3 : 0.1),
                            .black.opacity(0.1)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.08), radius: 12, x: 0, y: 6)
        .thermalGlow(pulse: $thermalPulse)
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
                        thermalPulse = ThermalPulse(at: value.startLocation)
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
    
    private var noteShape: AnyInsettableShape {
        switch viewModel.note.template {
        case .circle:
            return AnyInsettableShape(Circle())
        case .diamond:
            return AnyInsettableShape(DiamondShape())
        default:
            return AnyInsettableShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// Insettable Shape Eraser
struct AnyInsettableShape: InsettableShape {
    private var _path: (CGRect) -> Path
    private var _inset: (CGFloat) -> AnyInsettableShape

    init<S: InsettableShape>(_ shape: S) {
        self._path = { rect in shape.path(in: rect) }
        self._inset = { amount in AnyInsettableShape(shape.inset(by: amount)) }
    }

    func path(in rect: CGRect) -> Path {
        _path(rect)
    }

    func inset(by amount: CGFloat) -> AnyInsettableShape {
        _inset(amount)
    }
}

// Color Helpers
//
// UIKit isn't available on native macOS, and AppKit's NSColor isn't available on iOS, so the
// hex/luminance math below bridges through whichever platform color type actually exists rather
// than hard-coding UIColor.
#if canImport(UIKit)
import UIKit
typealias PlatformColor = UIColor
#elseif canImport(AppKit)
import AppKit
typealias PlatformColor = NSColor
#endif

extension PlatformColor {
    var hexString: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(AppKit) && !canImport(UIKit)
        let rgbColor = usingColorSpace(.deviceRGB) ?? self
        rgbColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif
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
        PlatformColor(self).hexString
    }

    var luminance: Double {
        let platformColor = PlatformColor(self)
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        #if canImport(AppKit) && !canImport(UIKit)
        let rgbColor = platformColor.usingColorSpace(.deviceRGB) ?? platformColor
        rgbColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        #else
        platformColor.getRed(&r, green: &g, blue: &b, alpha: &a)
        #endif

        // standard relative luminance formula
        return 0.2126 * Double(r) + 0.7152 * Double(g) + 0.0722 * Double(b)
    }
}
