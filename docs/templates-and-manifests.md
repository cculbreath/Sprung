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
  "listContainers": [
    "skills.*.keywords",
    "work.*.highlights"
  ],
  "reviewPhases": {
    "skills": [
      { "phase": 1, "field": "skills.*.name", "bundle": true },
      { "phase": 2, "field": "skills.*.keywords", "bundle": false }
    ]
  },
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

#### `listContainers` (Deprecated)

> **Note:** This field is deprecated. Use `*` vs `[]` notation in path patterns instead.
> - `skills.*.keywords` (bundle) → batch review
> - `skills[].keywords` (enumerate) → per-item review

Previously defined review behavior for list items:

```json
"listContainers": [
  "skills.*.keywords",
  "work.*.highlights"
]
```

#### `reviewPhases`

Configures multi-phase AI review for complex sections. Each phase targets a specific field path.

```json
"reviewPhases": {
  "skills": [
    { "phase": 1, "field": "skills.*.name" },
    { "phase": 2, "field": "skills[].keywords" }
  ]
}
```

### Path Pattern Syntax (defaultAIFields & reviewPhases)

Path patterns determine how resume tree nodes are exported for AI review. The syntax controls both **navigation** (which nodes to select) and **grouping** (how many RevNodes are created).

#### Core Symbols

| Symbol | Meaning | Grouping |
|--------|---------|----------|
| `.fieldName` | Navigate to exact field | — |
| `.*` | Enumerate children AND **bundle** | All matches → **1 RevNode** |
| `[]` | Enumerate children, **separate** | Each match → **1 RevNode** |

#### The Key Distinction: `*` vs `[]`

Both `*` and `[]` enumerate child nodes, but they differ in how results are grouped:

- **`*` bundles**: Collect the specified attribute from ALL children into a single RevNode
- **`[]` iterates**: Create separate RevNodes for each child

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

| Pattern | RevNodes | Content |
|---------|----------|---------|
| `work[].highlights` | 2 | RevNode 1: `["Built X", "Led Y", "Improved Z"]`<br>RevNode 2: `["Created W", "Designed V"]` |
| `work.*.highlights` | 1 | `["Built X", "Led Y", "Improved Z", "Created W", "Designed V"]` |
| `skills.*.name` | 1 | `["Software Engineering", "Data Science"]` |
| `skills[].name` | 2 | RevNode 1: `"Software Engineering"`<br>RevNode 2: `"Data Science"` |
| `skills[].keywords` | 2 | RevNode 1: `["Swift", "Python", "JavaScript"]`<br>RevNode 2: `["ML", "Statistics"]` |
| `skills.*.keywords` | 1 | `["Swift", "Python", "JavaScript", "ML", "Statistics"]` |
| `custom.jobTitles[]` | 3 | RevNode 1: `"Engineer"`<br>RevNode 2: `"Developer"`<br>RevNode 3: `"Architect"` |
| `projects[].description` | N | One RevNode per project, each containing a description string |

#### Double Iteration: `[]` + `[]`

For deep iteration, you can use `[]` multiple times:

| Pattern | RevNodes | Content |
|---------|----------|---------|
| `skills[].keywords[]` | 5 | One RevNode per keyword across all skills |
| `work[].highlights[]` | 5 | One RevNode per highlight bullet across all jobs |

#### When to Use Each

**Use `*` (bundle) when:**
- LLM needs holistic view of all items together
- Items should be reviewed/edited as a cohesive set
- Example: Skill category names should complement each other

**Use `[]` (iterate) when:**
- Each item should be reviewed independently
- Changes to one item don't affect others
- Example: Each job's highlights stand alone

#### Typical Configuration

```json
"defaultAIFields": [
  "custom.objective",      // 1 RevNode: scalar field
  "work[].highlights",     // N RevNodes: each job's bullets separately
  "projects[].description",// N RevNodes: each project description
  "skills.*.name",         // 1 RevNode: all category names bundled (Phase 1)
  "skills[].keywords",     // N RevNodes: each category's keywords (Phase 2)
  "custom.jobTitles[]"     // N RevNodes: each job title separately
]
```

#### Phase Configuration

Phases let you review certain fields first (e.g., skill category names) before reviewing dependent fields (e.g., keywords under those categories):

```json
"reviewPhases": {
  "skills": [
    { "phase": 1, "field": "skills.*.name" },
    { "phase": 2, "field": "skills[].keywords" }
  ]
}
```

In this example:
- **Phase 1**: Review all 5 skill category names together (1 bundled RevNode)
- **Phase 2**: After Phase 1 approvals are applied, review keywords for each category (5 RevNodes)

Phase 2 paths will reflect any name changes from Phase 1.

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
