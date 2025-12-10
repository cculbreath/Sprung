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
  "transparentKeys": [
    "basics",
    "custom"
  ],
  "editorLabels": {
    "basics.summary": "Professional Summary",
    "custom.jobTitles": "Job Titles",
    "custom.moreInfo": "Additional Info"
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

#### `transparentKeys`

Keys listed here are "invisible containers" - their children are promoted to the parent level.

```json
"transparentKeys": [
  "basics",   // basics.summary appears without "basics" container
  "custom"    // custom.jobTitles appears without "custom" container
]
```

**Important**: If a key is in `transparentKeys`, don't list it directly in `keys-in-editor`. Instead, list the specific child paths you want to show.

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

2. **Use `transparentKeys` for containers** - Promotes a cleaner tree structure

3. **Provide meaningful `editorLabels`** - "Professional Summary" is better than "summary"

4. **Define section labels in seed data** - Allows per-template customization of headings

5. **Match `section-visibility` keys to actual sections** - Only include sections your template renders

6. **Test with real data** - Use a complete resume to verify all sections render correctly

## File Checklist

When creating a new template:

- [ ] `{slug}/{slug}.html` - HTML template
- [ ] `{slug}/{slug}.txt` - Plain text template
- [ ] `{slug}/{slug}.manifest.json` - Editor configuration and defaults
- [ ] Update `catalog.json` with new entry
- [ ] Rebuild app to include new template
