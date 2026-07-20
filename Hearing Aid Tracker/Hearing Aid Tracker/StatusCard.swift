//
//  StatusCard.swift
//  Hearing Aid Tracker
//
//  Created by Sophia Bao on 2025-08-25.
//


import SwiftUI

struct StatusCard: View {
    let battery: Int?
    let connection: String
    let lastSeen: Date?

    private var isStale: Bool {
        guard let d = lastSeen else { return true }
        return Date().timeIntervalSince(d) > 30 // >30s turns red
    }

    private var lastSeenText: String {
        guard let d = lastSeen else { return "Never" }
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return df.string(from: d)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Battery / Connection / Last detection")
                .font(.system(size: 16, weight: .semibold))

            HStack {
                Text("Battery:").fontWeight(.medium)
                Spacer()
                Text(battery.map { "\($0)%" } ?? "—").monospacedDigit()
            }

            HStack {
                Text("Connection:").fontWeight(.medium)
                Spacer()
                Text(connection).monospacedDigit()
            }

            HStack {
                Text("Last detected:").fontWeight(.medium)
                Spacer()
                Text(lastSeenText)
                    .foregroundColor(isStale ? .red : .primary)
                    .fontWeight(isStale ? .bold : .regular)
                    .monospacedDigit()
            }
        }
        .padding(16)
        .background(Color.white)
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.black))
        .cornerRadius(8)
    }
}
