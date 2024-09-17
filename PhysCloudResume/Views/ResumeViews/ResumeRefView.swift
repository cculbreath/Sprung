import SwiftData
import SwiftUI

import SwiftData
import SwiftUI

struct ResRefView: View {
  @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
  @Environment(ResRefStore.self) private var resRefStore: ResRefStore
  @Binding var refPopup: Bool
  @State var isSourceExpanded: Bool = false
  @State var isSheetPresented: Bool = false
  @Binding var tab: TabList
  @State var newSourceName: String = ""
  @State var newSourceContent: String = ""
  @State var newSourceType: SourceType = SourceType.background
  @State var newEnabledByDefault: Bool = false

  var body: some View {
    @Bindable var jobAppStore = jobAppStore
    if let jobApp = jobAppStore.selectedApp {
      LazyVStack(alignment: .leading) {
        HStack {
          // Chevron icon with rotation based on isSourceExpanded
          Image(systemName: "chevron.right")
            .rotationEffect(.degrees(isSourceExpanded ? 90 : 0))
            .animation(.easeInOut(duration: 0.1), value: isSourceExpanded)
            .foregroundColor(.primary)
          Text("Résumé Source Documents")
            .font(.headline)
          Spacer()

          if jobApp.selectedRes != nil {
            if !(jobApp.selectedRes!.hasValidRefsEnabled) {
              HStack {
                Spacer().frame(minWidth: 10)
                Text("Choose one resume source and one JSON source")
                  .foregroundColor(.purple)
                  .font(.caption)
                  .multilineTextAlignment(.trailing)
                  .fontWeight(.light)
                  .frame(minWidth: 150)
                Image(systemName: "exclamationmark.triangle")
                  .foregroundColor(.purple)
                  .fontWeight(.light)
                  .font(.system(size: 20))
              }
              .padding(.horizontal, 10)
              .padding(.vertical, 5)
              .background(Color.gray.opacity(0.3))
              .cornerRadius(5)
            }
          }
        }
        // Attach the onTapGesture here to the HStack for expanding/collapsing the section
        .contentShape(Rectangle())  // Makes the whole HStack tappable
        .onTapGesture {
          withAnimation {
            isSourceExpanded.toggle()
          }
        }

        // Conditionally display the content based on isSourceExpanded
        if isSourceExpanded {
          LazyVStack(alignment: .leading, spacing: 0) {
            ForEach(resRefStore.resRefs, id: \.self) { child in
              Divider()
              SourceRowView(sourceNode: child, tab: $tab)
                .transition(.move(edge: .top))
            }
            HStack {
              Spacer()
              Button(action: {
                // Resetting states with @State properties
                newSourceName = ""
                newSourceContent = ""
                newEnabledByDefault = false
                newSourceType = .background
                isSheetPresented = true
              }) {
                Image(systemName: "plus.app")
                Text("Add Source")
              }
              .buttonStyle(.bordered)
              .padding()
            }
            .frame(maxWidth: .infinity)
            .sheet(isPresented: $isSheetPresented) {
              Form {
                Section(header: Text("Add New Source").font(.headline)) {
                  HStack(alignment: .top) {
                    Text("Source Name:")
                      .frame(width: 150, alignment: .trailing)
                    TextField("", text: $newSourceName)
                      .frame(maxWidth: .infinity)
                  }
                  HStack(alignment: .top) {
                    Text("Content:")
                      .frame(width: 150, alignment: .trailing)
                    TextField("", text: $newSourceContent, axis: .vertical)
                      .lineLimit(12)
                      .frame(maxWidth: .infinity)
                  }
                  .padding(.bottom, 10)

                  HStack(alignment: .top) {
                    Text("Source Type:")
                      .frame(width: 150, alignment: .trailing)
                    Picker("", selection: $newSourceType) {
                      ForEach(SourceType.allCases, id: \.self) { sourceType in
                        Text(sourceType.rawValue).tag(sourceType)
                      }
                    }
                    .pickerStyle(RadioGroupPickerStyle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                  }

                  HStack {
                    Text("Enabled by Default:")
                      .frame(width: 150, alignment: .trailing)
                    Toggle("", isOn: $newEnabledByDefault)
                      .toggleStyle(SwitchToggleStyle())
                  }

                  HStack {
                    Spacer()
                    Button("Cancel") {
                      isSheetPresented = false
                    }
                    .buttonStyle(.bordered)
                    Spacer()
                    Button("Save") {
                      let newSource = ResRef(
                        name: newSourceName,
                        content: newSourceContent,
                        type: newSourceType,
                        enabledByDefault: newEnabledByDefault
                      )
                      resRefStore.addResRef(newSource, res: jobApp.selectedRes)
                      isSheetPresented = false
                      if resRefStore.areRefsOk {
                        print("refs okay")
                        $refPopup.wrappedValue = false
                      } else {
                        print("refs not okay")
                      }
                    }
                    .buttonStyle(.borderedProminent)
                    Spacer()
                  }
                  .padding(.top)
                }
              }
              .padding()
              .frame(minWidth: 400, maxWidth: 600)
            }
          }
        }
      }
    }
  }
}

struct SourceRowView: View {
  @Environment(ResRefStore.self) private var resRefStore: ResRefStore
  @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
  @State var sourceNode: ResRef
  @State private var isButtonHovering = false
  @Binding var tab: TabList
  var isChecked: Bool {
    if let res = jobAppStore.selectedApp?.selectedRes {
      return res.enabledSources.contains(sourceNode)
    } else {
      return false
    }
  }

  var body: some View {
    if let res = jobAppStore.selectedApp?.selectedRes {
      @Bindable var res = res
      HStack {
        HStack(spacing: 15) {
          ToggleTextRow(
            leadingText: sourceNode.content,
            sourceNode: sourceNode
          )
          VStack(alignment: .leading) {
            Text(sourceNode.type.rawValue).font(.caption)
              .foregroundColor(isChecked ? .primary : .secondary)
            Text(sourceNode.name)
              .foregroundColor(isChecked ? .primary : .secondary)
          }
        }
        .padding(.vertical, 2).padding(.leading, 25)
        Spacer().frame(maxWidth: .infinity)

        Button(action: {
          resRefStore.deleteResRef(sourceNode)
        }) {
          Image(systemName: "trash.fill")
            .foregroundColor(isButtonHovering ? .red : .gray)
            .font(.system(size: 15))
            .padding(2)
            .background(isButtonHovering ? Color.red.opacity(0.3) : Color.gray.opacity(0.3))
            .cornerRadius(5)
        }
        .buttonStyle(PlainButtonStyle())
        .padding(4)
      }
      .background(Color.clear)
      .cornerRadius(5)
    }
  }
}

struct ToggleTextRow: View {
  @Environment(JobAppStore.self) private var jobAppStore: JobAppStore

  let leadingText: String
  @State var sourceNode: ResRef

  var body: some View {
    if let res = jobAppStore.selectedApp?.selectedRes {
      Toggle(
        "",
        isOn: Binding<Bool>(
          get: { res.enabledSources.contains(sourceNode) },
          set: { newValue in
            if newValue {
              if !res.enabledSources.contains(sourceNode) {
                res.enabledSources.append(sourceNode)
              }
            } else {
              if let index = res.enabledSources.firstIndex(of: sourceNode) {
                res.enabledSources.remove(at: index)
              }
            }
          }
        )
      )
      .toggleStyle(.switch)
    } else {
      EmptyView()
    }
  }
}
