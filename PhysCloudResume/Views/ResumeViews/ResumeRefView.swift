import SwiftData
import SwiftUI

struct ResRefView: View {
  @Environment(JobAppStore.self) private var jobAppStore: JobAppStore
  @Environment(ResRefStore.self) private var resRefStore: ResRefStore
  @Binding var refPopup: Bool
  @State var isSourceExpanded: Bool
  @State var isSheetPresented: Bool = false
  var isSourceHovering = false
  var buttonHover: Bool = false
  @Binding var selRes: Resume?
  @Binding var tab: TabList
  @State var newSourceName: String = ""
  @State var newSourceContent: String = ""
  @State var newSourceType: SourceType = SourceType.background
  @State var newEnabledByDefault: Bool = false

  var body: some View {

    LazyVStack(alignment: .leading) {
      HStack {
        Image(systemName: "chevron.right")
          .rotationEffect(.degrees(isSourceExpanded ? 90 : 0))
          .animation(
            .easeInOut(duration: 0.1), value: isSourceExpanded
          )
          .foregroundColor(.primary)
        Text("Résumé Source Documents")
          .font(.headline)
        Spacer()
        if let selRes = selRes {
          if !(selRes.hasValidRefsEnabled) {
            HStack {
              Spacer().frame(minWidth: 10)
              Text("Choose one resume source and one JSON source")
                .foregroundColor(.purple)
                .font(.caption)
                .multilineTextAlignment(.trailing).fontWeight(.light).frame(minWidth: 150)
              Image(systemName: "exclamationmark.triangle").foregroundColor(.purple).fontWeight(
                .light
              ).font(.system(size: 20))
            }
          }
        }
      }
      .padding(.horizontal, 10)
      .padding(.vertical, 5)
      .background(
        isSourceHovering ? Color.gray.opacity(0.3) : Color.clear
      )
      .cornerRadius(5)
      //            .onHover { hovering in
      //                isSourceHovering = hovering
      //            }
      .contentShape(Rectangle())
      .onTapGesture {
        withAnimation {
          isSourceExpanded.toggle()
        }
      }

      if isSourceExpanded {
        LazyVStack(alignment: .leading, spacing: 0) {
          ForEach(resRefStore.resRefs, id: \.self) { child in
            Divider()
            SourceRowView(sourceNode: child, res: $selRes, tab: $tab)
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
            //                        .onHover { hovering in buttonHover = hovering }
            .padding()
          }.frame(maxWidth: .infinity)
            .sheet(isPresented: $isSheetPresented) {
              Form {
                Section(
                  header: Text("Add New Source").font(.headline)
                ) {
                  HStack(alignment: .top) {
                    Text("Source Name:")
                      .frame(width: 150, alignment: .trailing)
                    TextField(
                      "",
                      text: $newSourceName
                    )  // Use $ to pass a Binding
                    .frame(maxWidth: .infinity)
                  }
                  HStack(alignment: .top) {
                    Text("Content:")
                      .frame(width: 150, alignment: .trailing)
                    TextField(
                      "", text: $newSourceContent,
                      axis: .vertical
                    )  // Use $ to pass a Binding
                    .lineLimit(12)
                    .frame(maxWidth: .infinity)
                  }
                  .padding(.bottom, 10)

                  HStack(alignment: .top) {
                    Text("Source Type:")
                      .frame(width: 150, alignment: .trailing)
                    Picker(
                      "",
                      selection: $newSourceType
                    ) {  // Use $ to pass a Binding
                      ForEach(SourceType.allCases, id: \.self) { sourceType in
                        Text(sourceType.rawValue).tag(
                          sourceType)
                      }
                    }
                    .pickerStyle(RadioGroupPickerStyle())
                    .frame(
                      maxWidth: .infinity, alignment: .leading
                    )
                  }

                  HStack {
                    Text("Enabled by Default:")
                      .frame(width: 150, alignment: .trailing)
                    Toggle(
                      "",
                      isOn: $newEnabledByDefault
                    )  // Use $ to pass a Binding
                    .toggleStyle(SwitchToggleStyle())  // Standard switch toggle style
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
                        enabledByDefault:
                          newEnabledByDefault
                      )
                      resRefStore
                        .addResRef(newSource, res: selRes)
                      isSheetPresented = false
                      if (resRefStore.areRefsOk) {
                        print("refs okay")
                        $refPopup.wrappedValue = false
                      }
                      else {
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
struct SourceRowView: View {
  @Environment(ResRefStore.self) private var resRefStore: ResRefStore

  @State var sourceNode: ResRef
  @State private var isButtonHovering = false
  @State private var isRowHovering = false
  @Binding var res: Resume?
  //    @Query var sourceNodes: [ResRef]
  @Binding var tab: TabList
  var isChecked: Bool {
    if res == nil {
      return false
    }
    else {
      return res!.enabledSources.contains(sourceNode)
    }
  }

  var body: some View {
    HStack {
      HStack(spacing: 15) {
        ToggleTextRow(
          leadingText: sourceNode.content,
          res: $res,
          sourceNode: sourceNode
        )
        VStack(alignment: .leading) {
          Text(sourceNode.type.rawValue).font(.caption)
            .foregroundColor(isChecked ? .primary : .secondary)
          Text(sourceNode.name).foregroundColor(isChecked ? .primary : .secondary)

        }

      }
      .padding(.vertical, 2).padding(.leading, 25)
      //            .onHover { hovering in
      //                isRowHovering = hovering
      //            }
      Spacer().frame(maxWidth: .infinity)

      Button(action: {
        resRefStore.deleteResRef(sourceNode)
      }) {
        Image(systemName: "trash.fill")
          .foregroundColor(isButtonHovering ? .red : .gray)
          .font(.system(size: 15))
          .padding(2)
          .background(
            isButtonHovering
              ? Color.red.opacity(0.3) : Color.gray.opacity(0.3)
          )
          .cornerRadius(5)

      }
      .buttonStyle(PlainButtonStyle())
      //            .onHover { hovering in
      //                isButtonHovering = hovering
      //            }
      .padding(4)
    }.background(Color.clear)
      .cornerRadius(5)
    //            .onHover { hovering in
    //                isRowHovering = hovering
    //            }
  }
}

struct ToggleTextRow: View {
  let leadingText: String
  @Binding var res: Resume?
  @State var sourceNode: ResRef

  var body: some View {
    if let res = res {
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
            //          res.enabledSources.forEach { print($0.name + $0.type.rawValue) }  // This should now run when the toggle is changed
          }
        )
      )
      .toggleStyle(.switch)
    }
    
    else{
      EmptyView()
    }
  }
}

