//
//  RemoteConnectionBadge.swift
//  Velvet Remote
//
//  Indicateur visuel de transport — conçu pour une lecture instantanée sur scène.
//

import SwiftUI

struct RemoteConnectionBadge: View {
    let transport: RemoteTransport

    var body: some View {
        Image(systemName: iconName)
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(color)
            .symbolRenderingMode(.hierarchical)
    }

    private var iconName: String {
        switch transport {
        case .wifi:         return "wifi"
        case .usb:          return "cable.connector"
        case .other:        return "wifi"
        case .disconnected: return "wifi.slash"
        }
    }

    private var color: Color {
        switch transport {
        case .wifi, .usb:   return .green
        case .other:        return .yellow
        case .disconnected: return .red
        }
    }
}
