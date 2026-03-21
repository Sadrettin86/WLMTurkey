//
//  WLMTurkeyApp.swift
//  WLMTurkey
//
//  Created by adem özcan on 15.03.2026.
//

import SwiftUI

@main
struct WLMTurkeyApp: App {
    @State private var settings = AppSettings.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(settings)
                .preferredColorScheme(settings.colorScheme)
        }
    }
}
