//
//  DiscoveryLocationStepView.swift
//  Sprung
//
//  Step 2 of Discovery onboarding: location, remote toggle, arrangement/size pickers.
//

import SwiftUI

struct DiscoveryLocationStepView: View {
    @Binding var location: String
    @Binding var remoteAcceptable: Bool
    @Binding var preferredArrangement: WorkArrangement
    @Binding var companySizePreference: CompanySizePreference

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Where are you looking for work?")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("This helps us find local job sources and networking events.")
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Primary Location")
                    .font(.headline)

                TextField("e.g., San Francisco Bay Area, Austin TX, Remote", text: $location)
                    .textFieldStyle(.roundedBorder)
            }

            Toggle(isOn: $remoteAcceptable) {
                VStack(alignment: .leading) {
                    Text("Open to remote positions")
                    Text("Include remote-only opportunities in search")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Work Arrangement Preference")
                    .font(.headline)

                Picker("Arrangement", selection: $preferredArrangement) {
                    ForEach(WorkArrangement.allCases, id: \.self) { arrangement in
                        Text(arrangement.rawValue).tag(arrangement)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 12) {
                Text("Company Size Preference")
                    .font(.headline)

                Picker("Size", selection: $companySizePreference) {
                    ForEach(CompanySizePreference.allCases, id: \.self) { size in
                        Text(size.rawValue).tag(size)
                    }
                }
                .pickerStyle(.menu)
            }
        }
    }
}
