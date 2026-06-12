# Creating Templates and Manifests

This guide explains how to create and configure resume templates in Sprung.

## Overview

A complete template consists of three files in `Sprung/Resources/TemplateDefaults/{slug}/`:

| File | Purpose |
|------|---------|
| `{slug}.html` | Mustache HTML template for PDF rendering |
| `{slug}.txt` | Plain text template for ATS-friendly export |
| `{slug}.manifest.json` | Configuration for editor behavior, styling, and defaults |

Templates must also be registered in `catalog.json`.

## Manifest Structure

The manifest controls how the template appears in the resume editor.

### Basic Example

```json
{
  "keys-in-editor": [
    "basics.summary",
    "work",
    "projects",
    "education",
    "skills",
    "custom.jobTitles",
    "custom.moreInfo",
    "styling"
  ],
  "section-visibility": {
    "work": true,
    "projects": true,
    "education": true,
    "skills": true
  },
  "section-visibility-labels": {
    "work": "Work Experience",
    "projects": "Projects",
    "education": "Education",
    "skills": "Skills"
  },
  "editorLabels": {
    "basics.summary": "Professional Summary",
    "custom.jobTitles": "Job Titles",
    "custom.moreInfo": "Additional Info"
  },
  "defaultAIFields": [
    "custom.objective",
    "work[].highlights",
    "skills.*.name",
    "skills[].keywords"
  ],
  "styling": {
    "fontSizes": {
      "name": "24pt",
      "sectionTitle": "14pt",
      "workHighlights": "10pt"
    }
  }
}
```

### Key Configuration Options

#### `keys-in-editor`

Controls which sections appear in the resume tree editor and their order.

```json
"keys-in-editor": [
  "basics.summary",    // Dot notation for nested fields
  "work",              // Top-level section
  "custom.jobTitles",  // Custom field promoted to top level
  "styling"            // Always include for font size controls
]
```

- Use dot notation (e.g., `basics.summary`) to show specific nested fields
- Sections listed here appear in the Content tree
- `styling` enables the Font Sizes panel

### Path Pattern Syntax (`defaultAIFields`)

`defaultAIFields` seeds the AI selection state when a resume tree is first built
from a template. Selection is a **single axis**: a node is editable by the
revision agent iff its status is `.aiToReplace`
(`TreeNode.isEditable == (status == .aiToReplace)`). Patterns are applied once
at tree-build time by `ExperienceDefaultsToTree.applyDefaultAIFields`
(`Sprung/ResumeTree/Utilities/ExperienceDefaultsToTree+AIFields.swift`); users
can change the selection afterward via the editor UI.

Patterns resolve to **attribute level**: a collection marker (`*` or `[]`) fans
out across the collection's entries and the remainder of the path is resolved
inside each entry. Only the node the pattern actually names is marked
`.aiToReplace` — never the whole section.

#### Core Symbols

| Symbol | Meaning |
|--------|---------|
| `.fieldName` | Navigate to the child node with that name |
| `.*.` or `[].` (mid-path) | Fan out across the collection's entries; resolve the rest of the path inside each entry |
| `field[]` (trailing) | The `field` list container itself is the named attribute |

`*` and `[]` are interchangeable: both fan out across entries. There is no
bundle-vs-iterate distinction anymore — the pattern only decides **which nodes
get marked**, and the revision agent works on the marked subtrees.

#### Understanding the Tree Structure

Consider this resume tree:

```
root
├── work
│   ├── Company A
│   │   ├── name: "Company A"
│   │   ├── position: "Engineer"
│   │   └── highlights
│   │       ├── "Built X"
│   │       ├── "Led Y"
│   │       └── "Improved Z"
│   └── Company B
│       ├── name: "Company B"
│       ├── position: "Developer"
│       └── highlights
│           ├── "Created W"
│           └── "Designed V"
├── skills
│   ├── Software Engineering
│   │   ├── name: "Software Engineering"
│   │   └── keywords
│   │       ├── "Swift"
│   │       ├── "Python"
│   │       └── "JavaScript"
│   └── Data Science
│       ├── name: "Data Science"
│       └── keywords
│           ├── "ML"
│           └── "Statistics"
└── custom
    └── jobTitles
        ├── "Engineer"
        ├── "Developer"
        └── "Architect"
```

#### Pattern Examples

| Pattern | Nodes marked `.aiToReplace` |
|---------|-----------------------------|
| `work[].highlights` | Each work entry's `highlights` container (2 nodes: Company A's and Company B's highlights lists) |
| `skills.*.name` | Each skill entry's `name` field (2 nodes) |
| `skills[].keywords` | Each skill entry's `keywords` container (2 nodes) |
| `custom.jobTitles[]` | The `jobTitles` container itself (1 node — trailing `[]` names the list) |
| `custom.objective` | The resolved `objective` node (1 node) |

Notes:
- Entries missing the named attribute contribute nothing (e.g., a work entry
  with no `highlights` is skipped).
- A pattern that matches no node logs a warning and is otherwise ignored.
- Marking a container makes its whole subtree editable by inheritance; users
  can opt individual children out (`.excludedFromGroup`) in the editor.

#### Typical Configuration

```json
"defaultAIFields": [
  "custom.objective",       // the objective node
  "work[].highlights",      // each job's highlights container
  "projects[].description", // each project's description field
  "skills.*.name",          // each skill category's name field
  "skills[].keywords",      // each skill category's keywords container
  "custom.jobTitles[]"      // the jobTitles container
]
```

#### `section-visibility`

Defines which sections can be toggled on/off in the "Show Sections" panel.

```json
"section-visibility": {
  "work": true,       // Default: visible
  "volunteer": false, // Default: hidden
  "education": true
}
```

#### `section-visibility-labels`

Human-readable labels for the visibility toggles.

```json
"section-visibility-labels": {
  "work": "Work Experience",
  "skills": "Skills & Expertise"
}
```

#### `editorLabels`

Display labels for tree nodes. Supports both simple keys and dot-notation paths.

```json
"editorLabels": {
  "basics.summary": "Professional Summary",
  "basics.label": "Job Title",
  "custom.jobTitles": "Job Titles",
  "custom.moreInfo": "Additional Info"
}
```

#### `styling.fontSizes`

Default font sizes for the template. These appear in the Font Sizes panel.

```json
"styling": {
  "fontSizes": {
    "name": "24pt",
    "sectionTitle": "14pt",
    "employerName": "12pt",
    "workDates": "10pt",
    "workHighlights": "10pt",
    "summary": "11pt"
  }
}
```

#### `sections.{sectionName}.hiddenFields`

Hide specific fields from the tree editor that your template doesn't use. This declutters the editor by only showing fields the template actually renders.

```json
"sections": {
  "work": {
    "type": "arrayOfObjects",
    "hiddenFields": ["description", "url", "location"]
  },
  "projects": {
    "type": "arrayOfObjects",
    "hiddenFields": ["highlights", "startDate", "endDate", "roles", "entity", "type"]
  }
}
```

**Common fields to consider hiding:**

| Section | Often Unused Fields |
|---------|---------------------|
| `work` | `description` (if using `highlights`), `summary` (if using `highlights`), `url`, `location` |
| `projects` | `highlights` (if using `description`), `startDate`, `endDate`, `roles`, `entity`, `type`, `keywords` |
| `education` | `url`, `score`, `courses` |
| `skills` | `level` |

**Why use `hiddenFields`:**
- Simplifies the editor UI for end users
- Prevents confusion when users edit fields that don't appear in their resume
- Template authors know exactly which fields their design uses

### Custom Section Fields

Define custom fields that aren't part of the standard JSON Resume schema.

```json
"custom": {
  "fields": [
    {
      "key": "jobTitles",
      "input": "text",
      "repeatable": true,
      "allowsManualMutations": true
    },
    {
      "key": "moreInfo",
      "input": "textarea"
    },
    {
      "key": "sectionLabels",
      "behavior": "sectionLabels",
      "children": [
        { "key": "work", "input": "text" },
        { "key": "education", "input": "text" }
      ]
    }
  ]
}
```

#### Field Descriptor Properties

| Property | Type | Description |
|----------|------|-------------|
| `key` | string | Field identifier |
| `input` | string | Input type: `text`, `textarea`, `date`, `url`, `email`, `phone`, `toggle`, `chips` |
| `required` | bool | Whether field is required |
| `repeatable` | bool | Allow multiple values (creates array) |
| `allowsManualMutations` | bool | User can add/remove items |
| `behavior` | string | Special handling: `sectionLabels`, `fontSizes`, `includeFonts` |
| `children` | array | Nested field descriptors |
| `placeholder` | string | Placeholder text for input |

#### Special Behaviors

- **`sectionLabels`**: Stores values in `resume.keyLabels` for customizable section headings. Field is hidden from tree.
- **`fontSizes`**: Populates the Font Sizes panel
- **`includeFonts`**: Boolean toggle for embedding fonts in PDF

## Data Sources

Resume data comes from multiple sources, merged in priority order:

| Source | Data | Priority |
|--------|------|----------|
| ApplicantProfile | Name, email, phone, address, picture | Highest |
| ExperienceDefaults | Work, education, skills, projects, summary | Medium |
| Manifest defaults | Styling, font sizes, section labels | Lowest |

### What Goes Where

| Data Type | Source | Notes |
|-----------|--------|-------|
| Contact info (name, email, phone) | ApplicantProfile | Set in Profile editor |
| Work experience, education, skills | ExperienceDefaults | Set in Experience editor |
| Professional summary | ExperienceDefaults | AI-editable per resume |
| Section heading labels | Manifest `custom.sectionLabels` | Template-specific customization |
| Font sizes | Manifest `styling.fontSizes` | Per-resume overrides allowed |

## Catalog Registration

Add your template to `catalog.json`:

```json
{
  "templates": [
    {
      "slug": "mytemplate",
      "name": "My Template",
      "isDefault": false,
      "paths": {
        "html": "mytemplate/mytemplate.html",
        "text": "mytemplate/mytemplate.txt",
        "manifest": "mytemplate/mytemplate.manifest.json"
      }
    }
  ]
}
```

Set `"isDefault": true` for the template that should be selected by default.

## HTML Template (Mustache)

Templates use Mustache syntax with custom filters.

### Basic Structure

```html
<!DOCTYPE html>
<html>
<head>
  <style>
    .name { font-size: {{styling.fontSizes.name}}; }
    .section-title { font-size: {{styling.fontSizes.sectionTitle}}; }
  </style>
</head>
<body>
  <h1 class="name">{{basics.name}}</h1>

  {{#basics.summary}}
  <p class="summary">{{basics.summary}}</p>
  {{/basics.summary}}

  {{#work}}
  <section class="work">
    <h2 class="section-title">{{custom.sectionLabels.work}}</h2>
    {{#work}}
    <div class="job">
      <strong>{{position}}</strong> at {{name}}
      <ul>
        {{#highlights}}
        <li>{{.}}</li>
        {{/highlights}}
      </ul>
    </div>
    {{/work}}
  </section>
  {{/work}}
</body>
</html>
```

### Custom Filters

| Filter | Usage | Description |
|--------|-------|-------------|
| `sectionLine` | `{{{sectionLine(custom.sectionLabels.work, 80)}}}` | Creates a section header line |
| `uppercase` | `{{uppercase(basics.name)}}` | Converts to uppercase |
| `formatDate` | `{{formatDate(startDate)}}` | Formats date values |

### Section Visibility

Wrap sections in conditionals that check visibility:

```html
{{#work}}
<section class="work">
  <!-- Content only renders if work section is visible -->
</section>
{{/work}}
```

## Best Practices

1. **Always include `styling` in `keys-in-editor`** - Users expect font size controls

2. **Provide meaningful `editorLabels`** - "Professional Summary" is better than "summary"

3. **Define section labels in manifest** - Use `custom.sectionLabels` for template-specific headings

4. **Match `section-visibility` keys to actual sections** - Only include sections your template renders

6. **Use `hiddenFields` to declutter the editor** - Hide fields your template doesn't render (e.g., hide `description` if you only use `highlights`)

7. **Test with real data** - Use a complete resume to verify all sections render correctly

## File Checklist

When creating a new template:

- [ ] `{slug}/{slug}.html` - HTML template
- [ ] `{slug}/{slug}.txt` - Plain text template
- [ ] `{slug}/{slug}.manifest.json` - Editor configuration and defaults
- [ ] Update `catalog.json` with new entry
- [ ] Rebuild app to include new template
