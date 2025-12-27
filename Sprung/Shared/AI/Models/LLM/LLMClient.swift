//
//  LLMClient.swift
//  Sprung
//
//  A small, stable protocol and DTOs that decouple the app from vendor SDK types.
//
import Foundation
import SwiftOpenAI

protocol LLMClient {
    // Text
    func executeText(prompt: String, modelId: String, temperature: Double?) async throws -> String
    func executeTextWithImages(prompt: String, modelId: String, images: [Data], temperature: Double?) async throws -> String
    func executeTextWithPDF(prompt: String, modelId: String, pdfData: Data, temperature: Double?, maxTokens: Int?) async throws -> String
    // Structured
    func executeStructured<T: Codable & Sendable>(prompt: String, modelId: String, as: T.Type, temperature: Double?) async throws -> T
    func executeStructuredWithImages<T: Codable & Sendable>(prompt: String, modelId: String, images: [Data], as: T.Type, temperature: Double?) async throws -> T
    // Structured with explicit schema (for providers that require it)
    func executeStructuredWithSchema<T: Codable & Sendable>(prompt: String, modelId: String, as: T.Type, schema: JSONSchema, schemaName: String, temperature: Double?) async throws -> T
}
