//
//  InsetGroupStyle.swift
//  Sprung
//
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
