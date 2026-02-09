//
//  FontNodeView.swift
//  Sprung
//
//
import SwiftData
import SwiftUI
struct FontNodeView: View {
    @Environment(ResumeDetailVM.self) private var vm: ResumeDetailVM
    @State var node: FontSizeNode
    @State private var isEditing: Bool = false
    private static let fontFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.minimumFractionDigits = 0
        f.maximumFractionDigits = 1
        f.minimum = 1
        f.maximum = 100
        return f
    }()
    var body: some View {
        Stepper {
            HStack {
                Text(node.key)
                Spacer()
                if !isEditing {
                    Text(node.fontString).onTapGesture { isEditing = true }
                } else {
                    HStack(spacing: 0) {
                        TextField(
                            "",
                            value: $node.fontValue,
                            formatter: Self.fontFormatter
                        )
                        .frame(width: 50, alignment: .trailing).multilineTextAlignment(.trailing)
                        .onSubmit {
                            isEditing = false
                        }
                        .padding(.trailing, 0)
                        Text("pt")
                            .foregroundColor(.secondary).padding(.leading, 0)
                    }
                }
            }.frame(maxWidth: .infinity)
        } onIncrement: {
            node.fontValue += 0.5
        } onDecrement: {
            node.fontValue -= 0.5
        }
        .padding(.horizontal, 5)
        .onChange(of: node.fontValue) {
            vm.refreshPDF()
        }
        .cornerRadius(5)
    }
}
