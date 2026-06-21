//
//  VelvetRemoteApp.swift
//  Velvet Remote
//
//  Companion iPad/iPhone app — read-only prompter for VELVET SHOW.
//

import SwiftUI

@main
struct VelvetRemoteApp: App {
    @State private var client = VelvetRemoteClient()

    var body: some Scene {
        WindowGroup {
            RemoteDiscoveryView()
                .environment(client)
        }
    }
}
