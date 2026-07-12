//
//  SidebarView.swift
//  LucidBoard
//
//  Created by Gemini CLI.
//

import SwiftUI

struct SidebarView: View {
    @Binding var isShowing: Bool
    @Binding var navigationPath: NavigationPath
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                if isShowing {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                        .onTapGesture { isShowing = false }

                    HStack {
                        VStack(alignment: .leading, spacing: 20) {
                            Text("LucidBoard")
                                .font(.lucidHeadline(28))
                                .padding(.top, geometry.safeAreaInsets.top + 52)

                            Divider()

                            Button(action: { isShowing = false }) {
                                Label("Board Canvas", systemImage: "square.grid.2x2")
                                    .font(.lucidBody())
                            }

                            Button(action: {
                                isShowing = false
                                navigationPath.append("settings")
                            }) {
                                Label("App Settings", systemImage: "gearshape.fill")
                                    .font(.lucidBody())
                            }

                            Spacer()
                        }
                        .padding()
                        .frame(width: sidebarWidth(in: geometry.size.width))
                        .background(.ultraThinMaterial)
                        .transition(.move(edge: .leading))

                        Spacer()
                    }
                }
            }
        }
        .animation(.easeInOut, value: isShowing)
    }

    /// iPhone-width contexts get a wide-but-not-full drawer sized off the actual window instead
    /// of a fixed 280pt that would otherwise swallow most of a compact-width screen; iPad, Mac,
    /// and visionOS (nil size class) keep the fixed 280pt tuned for a regular-width window.
    private func sidebarWidth(in availableWidth: CGFloat) -> CGFloat {
        guard horizontalSizeClass == .compact else { return 280 }
        return min(320, availableWidth * 0.85)
    }
}

#Preview {
    SidebarView(isShowing: .constant(true), navigationPath: .constant(NavigationPath()))
}
