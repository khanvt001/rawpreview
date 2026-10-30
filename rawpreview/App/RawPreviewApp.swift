//
//  RawPreviewApp.swift
//  rawpreview
//
//  Created by khanvt001 on 30/10/26.
//

import SwiftUI

@main
struct RawPreviewApp: App {
    @State private var library = LibraryViewModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(library)
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified)
    }
}
