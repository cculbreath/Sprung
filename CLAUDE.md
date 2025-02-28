# PhysCloudResume Development Guide

## Build/Run Commands
- Open project in Xcode and use standard build process (⌘+B)
- Run application in Xcode (⌘+R)
- Use `./PhysCloudResume/makeText.bash` to concatenate Swift files for text processing
- Use `./PhysCloudResume/modelcomb.bash` to combine @Model files
- PDF generation: `./PhysCloudResume/scripts/reshack.sh`

## Code Style Guidelines
- **Architecture**: SwiftUI with SwiftData persistence (@Model pattern)
- **Imports**: Group system imports first, then third-party packages
- **Naming**: Use clear descriptive names following Apple conventions (camelCase for variables/functions, PascalCase for types)
- **Organization**: Models in Models/, Views in Views/, organized by feature
- **Types**: Use strong typing with appropriate Swift types (avoid Any)
- **SwiftUI Patterns**: Use environment injection (@Environment) for dependencies
- **Error Handling**: Use Swift's Result type or throw/catch pattern
- **Dependencies**: Managed through Swift Package Manager (SwiftOpenAI, SwiftCollections, SwiftSoup, SwiftyJSON)
- **Target**: macOS 15.0+
- **Minimum Requirements**: Follow documented @Model relationships for SwiftData persistence