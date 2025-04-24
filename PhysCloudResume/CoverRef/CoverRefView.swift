import SwiftData
import SwiftUI

struct CoverRefView: View {
    @Environment(CoverRefStore.self) var coverRefStore: CoverRefStore
    @Environment(CoverLetterStore.self) var coverLetterStore: CoverLetterStore

    var body: some View {
        // Only show the wrapped view if we have a cL
        if let letter = coverLetterStore.cL {
            CoverRefViewWrapped(coverRefStore: coverRefStore, cL: letter)
        }
    }
}

struct CoverRefViewWrapped: View {
    @Environment(CoverLetterStore.self) var coverLetterStore: CoverLetterStore

    // Using `@Bindable` from SwiftData/SwiftUI so that
    // we can do `$coverRefStore` updates if needed.
    @Bindable var coverRefStore: CoverRefStore
    @Bindable var cL: CoverLetter

    // Live SwiftData query to automatically refresh on model changes
    @Query(sort: \CoverRef.name) private var allCoverRefs: [CoverRef]

    private var backgroundFacts: [CoverRef] {
        allCoverRefs.filter { $0.type == .backgroundFact }
    }

    private var writingSamples: [CoverRef] {
        allCoverRefs.filter { $0.type == .writingSample }
    }

    @State private var showAddBackgroundFactSheet = false
    @State private var showAddWritingSampleSheet = false

    var body: some View {
        List {
            // ======= Background section =======
            Text("Resume Background Documents")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.vertical, 5)
                .background(Color.clear)

            // Instead of directly binding to $cL.includeResumeRefs,
            // use a custom Binding that either:
            // (a) sets `cL.includeResumeRefs` if `generated == false`
            // (b) or creates a new cL with `includeResumeRefs` changed
            Toggle(isOn: includeResumeBinding) {
                Text("Include Resume Background")
            }

            Text("Cover Letter Background Facts")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.vertical, 5)
                .background(Color.clear)
                .sheet(isPresented: $showAddBackgroundFactSheet) {
                    AddCoverRefForm(
                        coverRefStore: coverRefStore,
                        type: .backgroundFact,
                        cL: cL,
                        showMe: $showAddBackgroundFactSheet
                    )
                }

            // Show existing background facts
            ForEach(backgroundFacts) { fact in
                RefRow(
                    cL: cL,
                    element: fact,
                    coverRefStore: coverRefStore,
                    showPreview: true
                )
                .listRowBackground(Color.clear)
            }

            Button(action: {
                showAddBackgroundFactSheet.toggle()
            }) {
                Label("Add Background Fact", systemImage: "plus")
            }
            .listRowBackground(Color.clear)

            // ======= Writing Samples section =======
            Text("Writing Samples")
                .font(.headline)
                .foregroundColor(.primary)
                .padding(.vertical, 5)
                .background(Color.clear)
                .sheet(isPresented: $showAddWritingSampleSheet) {
                    AddCoverRefForm(
                        coverRefStore: coverRefStore,
                        type: .writingSample,
                        cL: cL,
                        showMe: $showAddWritingSampleSheet
                    )
                }

            ForEach(writingSamples) { sample in
                RefRow(
                    cL: cL,
                    element: sample,
                    coverRefStore: coverRefStore,
                    showPreview: false
                )
                .listRowBackground(Color.clear)
            }

            Button(action: {
                showAddWritingSampleSheet.toggle()
            }) {
                Label("Add Writing Sample", systemImage: "plus")
            }
            .listRowBackground(Color.clear)
        }
        // If you want a plain look
        .listStyle(PlainListStyle())
        .scrollContentBackground(.hidden)
        .background(Color.clear)
    }

    // MARK: - Custom Binding for `includeResumeRefs`

    private var includeResumeBinding: Binding<Bool> {
        Binding<Bool>(
            get: { cL.includeResumeRefs },
            set: { newValue in
                guard let oldCL = coverLetterStore.cL else { return }
                if oldCL.generated {
                    // If it's generated, create a *new* copy with updated value
                    let newCL = coverLetterStore.createDuplicate(letter: oldCL)
                    newCL.includeResumeRefs = newValue
                    coverLetterStore.cL = newCL
                } else {
                    // Otherwise, just mutate the existing cL
                    cL.includeResumeRefs = newValue
                }
            }
        )
    }
}
