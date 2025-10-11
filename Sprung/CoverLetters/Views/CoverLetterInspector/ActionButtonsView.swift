//
//  ActionButtonsView.swift
//  Sprung
//
//  Created on 6/13/25.
//

import SwiftUI

struct ActionButtonsView: View {
    let coverLetter: CoverLetter
    @Binding var isEditing: Bool
    let namespace: Namespace.ID
    let onToggleChosen: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Actions")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .textCase(.uppercase)
            
            HStack(spacing: 12) {
                // Edit toggle button - blue when editing, orange on hover
                EditToggleButton(isEditing: $isEditing, namespace: namespace)
                
                // Star toggle button - yellow when chosen, can toggle on/off
                StarToggleButton(
                    coverLetter: coverLetter, 
                    action: onToggleChosen,
                    namespace: namespace
                )
                
                Spacer()
                
                // Delete button - red on hover only
                DeleteButton(
                    action: onDelete,
                    namespace: namespace
                )
            }
        }
    }
}