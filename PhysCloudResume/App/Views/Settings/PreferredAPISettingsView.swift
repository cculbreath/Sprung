//
//  PreferredAPISettingsView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 4/24/25.
//

import SwiftUI

// Enum for API choices

enum apis: String, Identifiable, CaseIterable {
    var id: Self { self }
    case scrapingDog = "Scraping Dog"
    case proxycurl = "Proxycurl (Deprecated)"
}

struct PreferredAPISettingsView: View {
    // AppStorage property specific to this view
    @AppStorage("preferredApi") private var preferredApi: apis = .scrapingDog

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Preferred Job Scraping API")
                .font(.headline)
                .padding(.bottom, 5)

            // Radio group for selecting the preferred API
            Picker("Preferred API", selection: $preferredApi) {
                ForEach(apis.allCases) { api in
                    HStack {
                        Text(api.rawValue)
                        if api == .proxycurl {
                            Text("(Service Discontinued)")
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                    .tag(api)
                }
            }
            .pickerStyle(.radioGroup) // Use radio buttons for clear selection
            .horizontalRadioGroupLayout() // Arrange horizontally if desired

            VStack(alignment: .leading, spacing: 5) {
                Text("Select the default API service for scraping job details from LinkedIn URLs.")
                    .font(.caption)
                    .foregroundColor(.secondary)
                if preferredApi == .proxycurl {
                    Text("⚠️ Proxycurl has been discontinued. Please switch to Scraping Dog.")
                        .font(.caption)
                        .foregroundColor(.red)
                }
            }
        }
        .padding(10)
        .background(Color(NSColor.windowBackgroundColor).opacity(0.9))
        .cornerRadius(8)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.gray.opacity(0.7), lineWidth: 1)
        )
    }
}
