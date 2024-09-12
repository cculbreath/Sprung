
//
//  swift
//  PhysicsCloudResume
//
//  Created by Christopher Culbreath on 8/30/24.
//

import Foundation
import SwiftData

@Observable
final class CoverLetterStore {
  var coverRefStore: CoverRefStore?

  private var modelContext: ModelContext?
  init() {}
  func initialize(context: ModelContext, refStore: CoverRefStore) {
    self.modelContext = context
    self.coverRefStore = refStore
  }

  @discardableResult
  func addLetter(letter: CoverLetter, to jobApp: JobApp) -> CoverLetter {
    jobApp.coverLetters.append(letter)
    modelContext!.insert(letter)
    saveContext()
    return letter
  }

  @discardableResult
  func create(jobApp: JobApp) -> CoverLetter {

      print("Model context available")
      print("Creating resume for job application: \(jobApp)")

      let letter = CoverLetter(
        enabledRefs: self.coverRefStore!.defaultSources,
        jobApp: jobApp
      )
      print("CoverLetter object created")

      modelContext!.insert(letter)
      try? modelContext!.save()
      return letter

  }
  func createDuplicate(letter: CoverLetter) -> CoverLetter {

    let newLetter = CoverLetter( enabledRefs: letter.enabledRefs,
                                 jobApp: letter.jobApp)
    self.addLetter(letter: newLetter, to: letter.jobApp)
    return newLetter

  }

  func deleteLetter(_ letter: CoverLetter) {
    let jobApp = letter.jobApp
    if let index = jobApp.coverLetters.firstIndex(of: letter){
      jobApp.coverLetters.remove(at: index)
      modelContext!.delete(letter)
      saveContext()
    }
    else {
      print("letter not attached to jobapp!")
    }


  }
 
  // Save changes to the database
  private func saveContext() {
    do {
      try modelContext!.save()
    } catch {
      print("Failed to save context: \(error)")
    }
  }
}
