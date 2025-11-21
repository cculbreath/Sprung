//
//  InsetGroupStyle.swift
//  Sprung
//
//  Created by Christopher Culbreath on 9/1/24.
//
import SwiftUI
extension View {
    func insetGroupedStyle<V: View>(header: V) -> some View {
        return GroupBox(label: header.padding(.top).padding(.bottom, 6)) {
            Form {
                self.padding(.vertical, 3).padding(.horizontal, 5)
            }.padding(.horizontal).padding(.vertical)
        }
    }
}
