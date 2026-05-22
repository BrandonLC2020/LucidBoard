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
    
    var body: some View {
        ZStack {
            if isShowing {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                    .onTapGesture { isShowing = false }
                
                HStack {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("LucidBoard")
                            .font(.title.bold())
                            .padding(.top, 60)
                        
                        Divider()
                        
                        Button(action: { isShowing = false }) {
                            Label("Board Canvas", systemImage: "square.grid.2x2")
                        }
                        
                        Button(action: { 
                            isShowing = false
                            navigationPath.append("settings")
                        }) {
                            Label("App Settings", systemImage: "gearshape.fill")
                        }
                        
                        Spacer()
                    }
                    .padding()
                    .frame(width: 280)
                    .background(.ultraThinMaterial)
                    .transition(.move(edge: .leading))
                    
                    Spacer()
                }
            }
        }
        .animation(.easeInOut, value: isShowing)
    }
}

#Preview {
    SidebarView(isShowing: .constant(true), navigationPath: .constant(NavigationPath()))
}
