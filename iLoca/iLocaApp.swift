//
//  iLocaApp.swift
//  iLoca
//
//  Created by Afrah Khan on 29/8/2026.
//

import SwiftUI

@main
struct iLocaApp: App {
    @AppStorage(AppearanceMode.storageKey) private var appearance = AppearanceMode.defaultMode.rawValue

    private var mode: AppearanceMode { AppearanceMode(rawValue: appearance) ?? .defaultMode }

    var body: some Scene {
        WindowGroup {
            RootScrollContainer()
                .frame(minWidth: 1280, minHeight: 800)
                .preferredColorScheme(mode.colorScheme)
                .onAppear { mode.apply() }
                .onChange(of: appearance) { mode.apply() }
        }
    }
}
