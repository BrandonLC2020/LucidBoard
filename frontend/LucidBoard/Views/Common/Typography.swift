//
//  Typography.swift
//  LucidBoard
//

import SwiftUI

/// Semantic type roles from DESIGN.md's "Brand-Font Rule": Montserrat carries anything
/// structural (headline weight), Open Sans carries everything read at length (body weight).
/// Unresolved PostScript names fall back to the system font automatically — Core Text's default
/// behavior — which mirrors DESIGN.md's own `-apple-system` fallback without extra code.
///
/// Every role uses `custom(_:size:relativeTo:)`, not the plain `custom(_:size:)` overload — the
/// plain overload is a fixed point size that ignores the user's Dynamic Type setting entirely.
/// The `relativeTo:` anchor keeps these scaling with system text size like everything else.
extension Font {
    /// Sidebar title, settings section headers, and other structural labels. Montserrat Bold.
    static func lucidHeadline(_ size: CGFloat) -> Font {
        .custom("Montserrat-Bold", size: size, relativeTo: .headline)
    }

    /// Sidebar nav labels, settings copy, and general UI text. Open Sans Regular.
    static func lucidBody(_ size: CGFloat = 17) -> Font {
        .custom("OpenSans-Regular", size: size, relativeTo: .body)
    }

    /// Text typed inside a note. Open Sans Medium, 14pt per DESIGN.md's `note-content` token.
    static let lucidNoteContent: Font = .custom("OpenSans-Regular", size: 14, relativeTo: .body).weight(.medium)
}
