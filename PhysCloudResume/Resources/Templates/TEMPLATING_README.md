# Resume Template System Documentation

This document describes the native template system for generating resumes in both HTML/PDF and text formats using GRMustache templating engine.

## Overview

The resume generation system uses:
- **GRMustache.swift** for template rendering (Mustache/Handlebars syntax)
- **WKWebView** for HTML-to-PDF conversion
- **Swift text formatting helpers** for plain text output
- **Bundle-embedded templates** for consistent styling

## Template Locations

```
PhysCloudResume/Resources/Templates/
├── archer/
│   ├── archer-template.html    # HTML template for PDF generation
│   └── archer-template.txt     # Plain text template
├── typewriter/
│   ├── typewriter-template.html # HTML template for PDF generation  
│   └── typewriter-template.txt  # Plain text template
└── TEMPLATING_README.md        # This documentation
```

## Data Context Structure

Templates receive a preprocessed JSON context with the following structure:

### Core Resume Data
```json
{
  "contact": {
    "name": "Full Name",
    "email": "email@domain.com", 
    "phone": "(555) 123-4567",
    "website": "https://website.com",
    "location": {
      "city": "City",
      "state": "State"
    }
  },
  "jobTitles": ["Title 1", "Title 2"],
  "summary": "Professional summary text...",
  "sectionLabels": {
    "skillsAndExpertise": "Skills & Expertise",
    "employment": "Professional Experience", 
    "education": "Education",
    "hobbies": "Projects & Interests"
  },
  "skillsAndExpertise": [
    {
      "title": "Skill Category",
      "description": "Detailed description..."
    }
  ],
  "employment": [
    {
      "employer": "Company Name",
      "location": "City, State",
      "position": "Job Title", 
      "start": "2020-01",
      "end": "2023-12",
      "highlights": ["Achievement 1", "Achievement 2"]
    }
  ],
  "education": [
    {
      "institution": "University Name",
      "title": "Degree Title",
      "end": "2020"
    }
  ],
  "projectsHighlights": [
    {
      "name": "Project Name",
      "description": "Project description..."
    }
  ]
}
```

### Preprocessed Helper Data

For convenience, the system adds preprocessed formatting:

#### HTML Templates
- `jobTitlesJoined`: Job titles joined with `&nbsp;&middot;&nbsp;`
- Font size variables: `fontSizes.name`, `fontSizes.jobTitles`, etc.

#### Text Templates  
- `contact.name`, `job-titles`, `summary`: core resume fields from the SwiftData tree  
- `contactItems`: array of contact strings (location, phone, email, website)  
- `employment`: ordered array of dictionaries containing employer, location, position, start/end, highlights  
- `education`: ordered array of dictionaries with institution, title, start/end  
- `projects-highlights`: array of project dictionaries (name, description)  
- `section-labels`: dictionary of localized section labels (access with `section-labels.skills-and-expertise`)  
- `more-info`: free-form footer text  
- Other resume properties exposed by `ResumeTemplateDataBuilder` are also available (see manifests)

### Built-in Mustache Filters
These filters are registered automatically for plain-text templates:

| Filter | Usage | Description |
| --- | --- | --- |
| `center(text, width)` | `{{{ center(contact.name, 80) }}}` | Centers text within a width |
| `wrap(text, width, leftMargin, rightMargin)` | `{{{ wrap(summary, 80, 6, 6) }}}` | Wraps text with optional margins |
| `sectionLine(label, width)` | `{{{ sectionLine(section-labels.employment, 80) }}}` | Renders a decorative section header |
| `join(array, separator)` | `{{{ center(join(job-titles), 80) }}}` | Joins array elements using the optional separator (defaults to " · ") |
| `bulletList(array, width, indent, bullet, valueKey)` | `{{{ bulletList(highlights, 80, 2, "•") }}}` | Formats bullet items; optional `valueKey` for dictionaries |
| `formatDate(date, outputFormat, inputFormat)` | `{{ formatDate(start) }}` | Formats dates using an optional output format (default `MMM yyyy`) |
| `uppercase(text)` | `{{ uppercase(more-info) }}` | Uppercases text (returns nothing if empty) |

## Template Syntax

### Basic Variable Substitution
```handlebars
{{variable}}           <!-- HTML-escaped output -->
{{{variable}}}         <!-- Raw/unescaped output -->
```

### Conditional Blocks
```handlebars
{{#variable}}
  Content shown if variable exists and is truthy
{{/variable}}

{{^variable}}
  Content shown if variable is falsy or doesn't exist  
{{/variable}}
```

### Array Iteration
```handlebars
{{#arrayName}}
  <li>{{propertyName}}</li>
{{/arrayName}}
```

### Nested Array Iteration
```handlebars
{{#employment}}
  <h3>{{employer}}</h3>
  {{#highlights}}
    {{#.}}
      <li>{{.}}</li>
    {{/.}}
  {{/highlights}}
{{/employment}}
```

## Template Examples

### HTML Template Structure
```html
<!DOCTYPE html>
<html>
<head>
    <title>{{{contact.name}}}</title>
    <style>
        /* CSS styles with system font references */
        @font-face {
            font-family: "ArcherLight";
            src: local("Archer Pro Light");
        }
    </style>
</head>
<body>
    <div class="header">
        <h1>{{{contact.name}}}</h1>
        <div class="subheader">{{{jobTitlesJoined}}}</div>
    </div>
    
    <div class="contact">
        {{contact.location.city}}, {{contact.location.state}} • 
        {{contact.phone}} • {{contact.email}}
    </div>
    
    <div class="summary">{{{summary}}}</div>
    
    <section class="skills">
        <h2>{{sectionLabels.skillsAndExpertise}}</h2>
        <ul>
            {{#skillsAndExpertise}}
            <li><strong>{{{title}}}</strong><br>{{{description}}}</li>
            {{/skillsAndExpertise}}
        </ul>
    </section>
</body>
</html>
```

### Text Template Structure
```
{{{ center(contact.name, 80) }}}

{{{ center(join(job-titles), 80) }}}

{{#contactLine}}
{{{ center(contactLine, 80) }}}
{{/contactLine}}

{{{ wrap(summary, 80, 6, 6) }}}

{{#section-labels.skills-and-expertise}}
{{{ sectionLine(section-labels.skills-and-expertise, 80) }}}
{{/section-labels.skills-and-expertise}}

{{#skills-and-expertise}}
{{ title }}
{{{ wrap(description, 80, 3, 0) }}}

{{/skills-and-expertise}}

{{#section-labels.employment}}
{{{ sectionLine(section-labels.employment, 80) }}}
{{/section-labels.employment}}

{{#employment}}
{{ employer }}{{#location}} | {{{.}}}{{/location}}
{{#position}}
{{ position }}
{{/position}}
{{ formatDate(start) }} – {{ formatDate(end) }}
{{{ bulletList(highlights, 80, 2, "•") }}}

{{/employment}}

{{#more-info}}
{{{ wrap(uppercase(more-info), 80, 0, 0) }}}
{{/more-info}}
```

## System Font References

### Archer Theme Fonts
- `local("Archer Pro Hairline")` - Ultra-light weight
- `local("Archer Pro Light")` - Light weight  
- `local("Archer Pro Book")` - Regular weight
- `local("Archer Pro Medium")` - Medium weight
- `local("Archer Pro Semibold")` - Semi-bold weight
- `local("Archer Pro Bold")` - Bold weight

### Typewriter Theme Fonts
- `local("Courier New")` - Standard monospace
- `local("Courier New Bold")` - Bold monospace
- `local("Cooper Black")` - Display font for headers

## Debug Features

### HTML Debug Output
When generating PDFs, debug HTML is automatically saved to:
```
~/Downloads/debug_resume_{template}_{format}_{timestamp}.html
```

### Error Handling
- Missing templates trigger file picker dialogs
- Font fallbacks ensure compatibility across systems
- Graceful degradation for missing data fields

## Best Practices

### Template Development
1. **Test both HTML and text outputs** - Ensure consistency across formats
2. **Use semantic CSS classes** - Avoid inline styles when possible  
3. **Handle missing data gracefully** - Use conditional blocks
4. **Follow existing naming conventions** - Match current template patterns
5. **Validate on different screen sizes** - PDFs should be print-ready

### Performance Considerations
- Templates are cached in bundle - no network requests
- Swift text helpers are more efficient than JavaScript equivalents
- WKWebView reuses instances for better memory management

### Customization
- Custom templates can be loaded via file picker
- CSS can reference any system-installed fonts
- Text formatting width defaults to 80 characters (customizable)

## Migration from HackMyResume

Key differences from the previous API-based system:

1. **No JavaScript helpers** - Swift functions replace JS formatting
2. **System fonts only** - No bundled font files
3. **Simplified syntax** - Standard Mustache instead of complex helpers
4. **Local generation** - No network dependencies
5. **Debug output** - HTML saved locally for troubleshooting

## Troubleshooting

### Common Issues
- **Parse errors**: Check for unclosed Mustache tags `{{#section}} ... {{/section}}`
- **Missing fonts**: Verify font names match system installation
- **Layout issues**: Check CSS margin/padding calculations for print media
- **Data not showing**: Verify JSON key names match template variables

### Debugging Steps
1. Check debug HTML output in Downloads folder
2. Verify data structure in generated JSON  
3. Test template syntax with minimal data
4. Compare with working template examples
