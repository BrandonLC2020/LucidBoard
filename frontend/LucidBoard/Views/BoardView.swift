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
    
    @State private var isShowingSidebar = false
    @State private var navigationPath = NavigationPath()
    @State private var lastAddNoteTap: Date?
    @State private var addNoteThermalPulse: ThermalPulse?
    @State private var autoOrganizeThermalPulse: ThermalPulse?

    private let addNoteDebounce: TimeInterval = 0.4

    private var canAddNote: Bool {
        guard let lastAddNoteTap else { return true }
        return Date().timeIntervalSince(lastAddNoteTap) > addNoteDebounce
    }

    var body: some View {
        NavigationStack(path: $navigationPath) {
            GeometryReader { geometry in
                ZStack {
                    // Infinite Background Layer
                    BoardBackgroundView(
                        layout: viewModel.board.backgroundLayout,
                        color: backgroundColor
                    )
                    .offset(combinedOffset)
                    .scaleEffect(combinedScale)
                    .ignoresSafeArea()

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
                    .ignoresSafeArea()
                    
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
                            .accessibilityLabel("Board appearance")
                            .padding(.top, geometry.safeAreaInsets.top + 12)
                            .padding(.trailing, geometry.safeAreaInsets.trailing + 20)
                        }
                        
                        Spacer()
                        
                        HStack(spacing: 20) {
                            Button(action: {
                                guard canAddNote else { return }
                                lastAddNoteTap = Date()
                                addNoteThermalPulse = ThermalPulse()
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
                            .accessibilityLabel("Add note")
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                            .thermalGlow(pulse: $addNoteThermalPulse)

                            Button(action: {
                                autoOrganizeThermalPulse = ThermalPulse()
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
                            .accessibilityLabel(viewModel.isOrganizing ? "Auto-organizing" : "Auto-organize")
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                            .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
                            .thermalGlow(pulse: $autoOrganizeThermalPulse)
                        }
                        .padding(.bottom, geometry.safeAreaInsets.bottom + 24)
                    }

                    // Hamburger Menu Button
                    VStack {
                        HStack {
                            Button(action: { isShowingSidebar.toggle() }) {
                                Image(systemName: "line.3.horizontal")
                                    .font(.system(size: 20, weight: .bold))
                                    .padding(12)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                                    .shadow(color: .black.opacity(0.1), radius: 5)
                            }
                            .accessibilityLabel("Menu")
                            .padding(.top, geometry.safeAreaInsets.top + 12)
                            .padding(.leading, geometry.safeAreaInsets.leading + 20)
                            Spacer()
                        }
                        Spacer()
                    }

                    // Sidebar Overlay
                    SidebarView(isShowing: $isShowingSidebar, navigationPath: $navigationPath)

                    // Sync error banner
                    if let syncError = viewModel.syncError {
                        VStack {
                            SyncErrorBanner(message: syncError) {
                                viewModel.dismissSyncError()
                            }
                            .padding(.top, geometry.safeAreaInsets.top + 12)
                            Spacer()
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: viewModel.syncError)
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
                .navigationDestination(for: String.self) { destination in
                    if destination == "settings" {
                        SettingsView()
                    }
                }
            }
        }
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
    ), repository: SupabaseRepository()))
}

/// Non-blocking notice for a failed sync — surfaces the "Notes-Are-User-Content"-adjacent
/// promise that changes are saved without gating the canvas behind a modal.
private struct SyncErrorBanner: View {
    let message: String
    var onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Color(hex: "#FF3B30"))

            Text(message)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.primary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(Color(hex: "#FF3B30").opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.1), radius: 10, x: 0, y: 5)
        .padding(.horizontal, 20)
        .accessibilityElement(children: .contain)
    }
}
