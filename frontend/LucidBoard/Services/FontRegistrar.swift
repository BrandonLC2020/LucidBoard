//
//  FontRegistrar.swift
//  LucidBoard
//

import CoreText
import Foundation

/// Registers the bundled Montserrat/Open Sans variable fonts with CoreText at launch.
///
/// iOS's declarative `UIAppFonts` Info.plist key has no equivalent that works identically across
/// iOS, macOS, and visionOS in a `GENERATE_INFOPLIST_FILE = YES` project, so registration happens
/// once at process start via `CTFontManagerRegisterFontsForURL` instead — the one mechanism common
/// to every Apple platform this app ships on.
enum FontRegistrar {
    private static let bundledFontResources = ["Montserrat", "OpenSans"]

    static func registerBundledFonts() {
        for resource in bundledFontResources {
            guard let url = Bundle.main.url(forResource: resource, withExtension: "ttf") else {
                assertionFailure("Missing bundled font resource: \(resource).ttf")
                continue
            }
            // Re-registering an already-registered font (e.g. repeated SwiftUI preview runs in
            // the same process) reports failure harmlessly; only the URL lookup above is fatal.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
