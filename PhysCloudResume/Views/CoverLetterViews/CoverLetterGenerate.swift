//
//  SwiftUIView.swift
//  PhysCloudResume
//
//  Created by Christopher Culbreath on 9/10/24.
//

//import SwiftUI
//
//struct CoverLetterGenerate: View {
//  @Bindable var jobApp: JobApp
//  let applicant = Applicant()
//  let chosenResume: Resume
//  let backgroundItemsString = ""
//  let writingSamplesString = ""
//  let cannedResponseString = ""
//  let messageHistory = [chatMessage]
//  var body: some View {
//    var generationPrompt = """
//  Please compose a cover letter to accompany \(applicant.name)'s application to be hired as a \(jobApp.job_position) at \(jobApp.company_name). The full job listing and \(applicant.name)'s résumé for this position are included below. 
//
//    \(applicant.name) has provided the folllowing background information regarding his current job search that may be useful in composing the draft cover letter:
//
//    \(backgroundItemsString)
//
//    Full Job Listing:
//    \(jobApp.jobListingString)
//
//    Text version of Résumé to be submitted with application:
//    \(chosenResume.textRes)
//
//    \(applicant.name) has also included a few samples of cover letters he wrote for earlier applications that he is particularly satisfied with. Use these writing samples to as a guide to the writing style and voice of your cover letter draft.
//    \(writingSamplesString)
//
//"""
//    var revisePrompt = //[System, User, Assistant].append.init() or something
//    """
//    [Messsage History]
//    Upon reading your latest draft, \(applicant.name) has requested that you prepare a revised draft that incorporates each of the feedback items below:
//
//        \(cannedResponseString)
//"""
//    var editorPrompt = """
//    My initial draft of a cover letter to accompany my application to be hired as a  \(jobApp.job_position) at \(jobApp.company_name) is included below. \(chosenEditorPrompt)
//        \(freshFeedback)
//
//"""
//
//    }
//}
//
//enum EditorPrompts: String {
//  case improve = "Please carefully read the draft and indentify at least three ways the content and quality of the writing can be improved. Provde a new draft that incorporates the identified improvements."
//  case zissner = "Carefully read the letter as a professional editor, specifically William Zissner incorporating the writing techniques and style he advocates in \"On Writing Well\" Provide a new draft that incorporates Zissner's edits to improve the quality of the writing. "
//}
