//
//  ThermalGlow.swift
//  LucidBoard
//

import SwiftUI

/// One contact event for `.thermalGlow`. A new `id` (via `ThermalPulse()`/`ThermalPulse(at:)`)
/// re-triggers the animation even if `location` is unchanged; `location` is in the modified
/// view's local coordinate space, or `nil` to center on the view itself (the common case for a
/// button, where the exact finger position isn't worth plumbing through).
struct ThermalPulse: Equatable {
    private let id = UUID()
    var location: CGPoint?

    init(at location: CGPoint? = nil) {
        self.location = location
    }
}

/// DESIGN.md's "Thermal Glow": a localized heat signature confirming the machine registered
/// touch. Two-phase physics per `.claude/context/llc-swift/thermal-glow.md` — 50ms excitation,
/// 300ms dissipation, `SPRING_STIFFNESS: 180` / `SPRING_DAMPING: 12` — reused verbatim here since
/// DESIGN.md calls strict adherence to these constants "not optional polish — it's the brand."
private struct ThermalGlowModifier: ViewModifier {
    @Binding var pulse: ThermalPulse?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var opacity: Double = 0
    @State private var scale: CGFloat = 0.5

    private static let core = Color(hex: "#FF3B30")
    private static let corona = Color(hex: "#FF9500")

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    let diameter = max(geo.size.width, geo.size.height) * 1.3
                    RadialGradient(
                        colors: [Self.core.opacity(0.55), Self.corona.opacity(0.35), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter / 2
                    )
                    .frame(width: diameter, height: diameter)
                    .scaleEffect(scale)
                    .opacity(opacity)
                    .position(pulse?.location ?? CGPoint(x: geo.size.width / 2, y: geo.size.height / 2))
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
                }
            )
            .onChange(of: pulse) { _, newValue in
                guard newValue != nil else { return }
                fire()
            }
    }

    private func fire() {
        scale = 0.5
        opacity = 0

        guard !reduceMotion else {
            // No expansion for reduced-motion users — a brief in-place flash carries the same
            // "the machine felt you" confirmation without the directional motion.
            withAnimation(.easeOut(duration: 0.15)) { opacity = 0.6 }
            withAnimation(.easeOut(duration: 0.15).delay(0.15)) { opacity = 0 }
            return
        }

        // Phase 1: Excitation (50ms) — rapid expansion from the contact point.
        withAnimation(.easeOut(duration: 0.05)) {
            opacity = 1.0
            scale = 1.2
        }
        // Phase 2: Dissipation (300ms) — cooling cycle, spring-driven continued expansion
        // while opacity eases out to baseline.
        withAnimation(.interpolatingSpring(stiffness: 180, damping: 12).delay(0.05)) {
            scale = 1.5
        }
        withAnimation(.easeOut(duration: 0.3).delay(0.05)) {
            opacity = 0
        }
    }
}

extension View {
    /// Triggers a Thermal Glow whenever `pulse`'s identity changes. Pass `ThermalPulse(at: point)`
    /// for a precise contact location (e.g. a drag's start location) or `ThermalPulse()` to center
    /// on the view.
    func thermalGlow(pulse: Binding<ThermalPulse?>) -> some View {
        modifier(ThermalGlowModifier(pulse: pulse))
    }
}
