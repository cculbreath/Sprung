//
//  DocumentTranscriptionPrompts.swift
//  Sprung
//
//  Prompts and structured-output schema for the ONE-TIME multimodal PDF
//  transcription pass. The model sees the ACTUAL PDF (one pass per chunk) and
//  produces a high-fidelity `DocumentTranscription` — verbatim text, faithfully
//  described visuals (with their data), rendered tables, and a production-quality
//  signal — so downstream extraction can read the transcription instead of
//  re-uploading the PDF.
//
//  This is deliberately NOT a summary: nothing is condensed. The output may be
//  long. See `DocumentTranscription` in IntermediateRepresentation.swift for the
//  contract this pass produces.
//

import Foundation

enum DocumentTranscriptionPrompts {

    /// Prompt/schema version stamped into `IRProvenance.promptVersion`. Bump when
    /// the instructions or schema change in a way that alters the transcription.
    static let promptVersion = "pdf-transcription-v1"

    // MARK: - Instructions

    /// Standing transcription instruction for one chunk. The chunk covers the
    /// ABSOLUTE pages `pageRange` of a `totalPages`-page document; the model must
    /// use those absolute page numbers in `visualElements[].page` and
    /// `tables[].page` so multi-chunk merges keep correct page anchors.
    static func transcriptionInstructions(
        filename: String,
        pageRange: ClosedRange<Int>,
        totalPages: Int
    ) -> String {
        let lower = pageRange.lowerBound
        let upper = pageRange.upperBound
        return """
        You are transcribing "\(filename)". The pages you can see are ABSOLUTE \
        pages \(lower)–\(upper) of a \(totalPages)-page document. Whenever you cite \
        a page — in `visualElements[].page` and `tables[].page` — use these ABSOLUTE \
        page numbers (\(lower)…\(upper)), NOT a 1-based offset within this slice.

        This is a TRANSCRIPTION, not a summary. LOSE NOTHING. Do not condense, \
        paraphrase, abridge, or "clean up" the content. The output is expected to \
        be long, and that is correct.

        Produce a faithful, high-fidelity `DocumentTranscription` for these pages:

        1. fullText — Transcribe ALL text VERBATIM in natural reading order as \
        Markdown. Preserve headings, subheadings, lists, numbering, block quotes, \
        emphasis, and the overall structure. For multi-column layouts, read each \
        column in the correct order. Keep footnotes, captions, headers/footers, and \
        page numbers where they appear. Do NOT summarize or drop anything.

        2. visualElements — Describe EVERY chart, figure, diagram, image, or photo \
        COMPLETELY, including the ACTUAL DATA and VALUES it conveys, so the chart's \
        information survives even though the pixels do not. For a chart, give the \
        axes, series, and the concrete numbers/trends (use `dataPoints` for the \
        actual values, e.g. "2019: 42%", "Q3 revenue: $1.2M"). For a diagram, give \
        the nodes, edges, and what the flow means. Set `kind` to one of \
        chart | figure | diagram | image | photo, `page` to the ABSOLUTE page, and \
        `caption` to the printed caption when one exists.

        3. tables — Render EVERY table faithfully as Markdown in `markdown` \
        (header row, separator, all data rows, preserving cell order). Set `page` \
        to the ABSOLUTE page.

        4. productionQuality — Judge the document's production quality from what you \
        SEE — this is the support-skill signal (e.g. LaTeX authorship, graphic-design \
        chops). Guess the typesetting system (LaTeX | Word | InDesign | GoogleDocs | …) \
        in `typesettingSystemGuess` and back it with concrete visual evidence in \
        `typesettingEvidence` (ligatures, math typesetting, microtypography, section \
        styling, default templates, etc.). Describe `layoutSophistication`, the \
        `columns` count when discernible, `typography` (fonts, hierarchy, spacing), \
        `colorAndGraphicDesignSignals` (palette, custom graphics, iconography), and \
        `overallPolish`. Explain your reasoning in `rationale`.

        5. structure — Provide an accurate section outline / page map for these \
        pages (which sections/headings fall on which absolute pages).

        6. docMeta — `pageCount` is the count of pages YOU transcribed in this \
        slice (\(upper - lower + 1)); `language` is the primary language; \
        `docClassGuess` is the document class (resume | paper | portfolio | slides | …).

        Respond with JSON conforming exactly to the requested schema.
        """
    }

    // MARK: - Structured-output schema

    /// JSON Schema for `TranscriptionPayload`. Every object — root and every
    /// nested object (including objects inside array `items`) — carries
    /// `additionalProperties: false` and a `required` array listing its required
    /// keys; optional keys (caption, dataPoints, columns) are omitted from
    /// `required`. Provenance is NOT in the schema — the service supplies it.
    static let transcriptionJsonSchema: [String: Any] = [
        "type": "object",
        "additionalProperties": false,
        "properties": [
            "fullText": [
                "type": "string",
                "description": "ALL text transcribed verbatim in reading order as Markdown — structure preserved, nothing condensed or summarized."
            ],
            "visualElements": [
                "type": "array",
                "description": "Every chart/figure/diagram/image/photo, described completely including the actual data it conveys.",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "properties": [
                        "page": [
                            "type": "integer",
                            "description": "ABSOLUTE page number of the visual within the whole document."
                        ],
                        "kind": [
                            "type": "string",
                            "description": "chart | figure | diagram | image | photo"
                        ],
                        "caption": [
                            "type": "string",
                            "description": "Printed caption, if any."
                        ],
                        "faithfulDescription": [
                            "type": "string",
                            "description": "What it depicts plus the actual data/values it conveys, so the information survives without the pixels."
                        ],
                        "dataPoints": [
                            "type": "array",
                            "items": ["type": "string"],
                            "description": "The concrete values the visual conveys, e.g. '2019: 42%', 'Q3 revenue: $1.2M'."
                        ]
                    ],
                    "required": ["page", "kind", "faithfulDescription"]
                ]
            ],
            "tables": [
                "type": "array",
                "description": "Every table rendered faithfully as Markdown.",
                "items": [
                    "type": "object",
                    "additionalProperties": false,
                    "properties": [
                        "page": [
                            "type": "integer",
                            "description": "ABSOLUTE page number of the table within the whole document."
                        ],
                        "markdown": [
                            "type": "string",
                            "description": "Faithful Markdown rendering of the table (header, separator, all data rows in order)."
                        ]
                    ],
                    "required": ["page", "markdown"]
                ]
            ],
            "productionQuality": [
                "type": "object",
                "additionalProperties": false,
                "description": "Production-quality signal judged from the rendered document — the support-skill axis (typesetting, layout, typography, polish).",
                "properties": [
                    "typesettingSystemGuess": [
                        "type": "string",
                        "description": "LaTeX | Word | InDesign | GoogleDocs | …"
                    ],
                    "typesettingEvidence": [
                        "type": "string",
                        "description": "Concrete visual evidence for the typesetting-system guess."
                    ],
                    "layoutSophistication": [
                        "type": "string",
                        "description": "How sophisticated the layout is and why."
                    ],
                    "columns": [
                        "type": "integer",
                        "description": "Number of text columns, when discernible."
                    ],
                    "typography": [
                        "type": "string",
                        "description": "Fonts, hierarchy, spacing, and other type signals."
                    ],
                    "colorAndGraphicDesignSignals": [
                        "type": "string",
                        "description": "Palette, custom graphics, iconography, and other design signals."
                    ],
                    "overallPolish": [
                        "type": "string",
                        "description": "Overall production polish assessment."
                    ],
                    "rationale": [
                        "type": "string",
                        "description": "Reasoning tying the evidence to the conclusions."
                    ]
                ],
                "required": ["typesettingSystemGuess", "typesettingEvidence", "layoutSophistication", "typography", "colorAndGraphicDesignSignals", "overallPolish", "rationale"]
            ],
            "structure": [
                "type": "string",
                "description": "Section outline / page map for the transcribed pages."
            ],
            "docMeta": [
                "type": "object",
                "additionalProperties": false,
                "description": "Document-level metadata for the transcribed pages.",
                "properties": [
                    "pageCount": [
                        "type": "integer",
                        "description": "Number of pages transcribed in this slice."
                    ],
                    "language": [
                        "type": "string",
                        "description": "Primary language of the document."
                    ],
                    "docClassGuess": [
                        "type": "string",
                        "description": "resume | paper | portfolio | slides | …"
                    ]
                ],
                "required": ["pageCount", "language", "docClassGuess"]
            ]
        ],
        "required": ["fullText", "visualElements", "tables", "productionQuality", "structure", "docMeta"]
    ]
}

// MARK: - TranscriptionPayload

/// The model's per-chunk transcription output: a `DocumentTranscription` WITHOUT
/// provenance (the service supplies provenance, not the model). The service maps
/// payload + provenance → `DocumentTranscription`. Reuses the contract's value
/// types verbatim so decoding lands directly on the shared shapes.
struct TranscriptionPayload: Codable, Sendable {
    var fullText: String
    var visualElements: [VisualElement]
    var tables: [TranscribedTable]
    var productionQuality: TranscriptionProductionQuality
    var structure: String
    var docMeta: DocMeta
}
