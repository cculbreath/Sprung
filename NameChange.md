# Name Change Worklist: PhysCloudResume → Sprung

This checklist captures every place where the current PhysCloudResume branding appears so the app can be renamed to **Sprung** without leaving residual references. Update or replace each item before shipping the new name.

## 1. Repository & Project Structure
- Rename the top-level source directory `PhysCloudResume/` → `Sprung/` and move `Sprung.icon/` with it. Update any tool configs or scripts that assume the old path.
- Rename `PhysCloudResume.xcodeproj` → `Sprung.xcodeproj` and adjust references inside the project file (`PhysCloudResume.xcodeproj/project.pbxproj`) so project, target, and group entries use the new name.
- Rename the primary target, product, and Swift module names from `PhysCloudResume` to `Sprung` inside `project.pbxproj` (native target declaration, build configuration lists, `PRODUCT_NAME`, `SWIFT_MODULE_NAME`, etc.).
- Rename the shared scheme file `PhysCloudResume.xcodeproj/xcshareddata/xcschemes/PhysCloudResume.xcscheme` and update its XML (`BlueprintName`, `BuildableName`, `BuildableIdentifier`) to reference `Sprung`.
- Rename configuration artifacts that match the old name: `PhysCloudResume.entitlements`, `PhysCloudResume/PhysCloudResume.entitlements`, and any other `.xcconfig` or plist files if added later.

## 2. Build & Bundle Settings
- Update bundle identifiers in `project.pbxproj` (`PRODUCT_BUNDLE_IDENTIFIER = "Physics-Cloud.PhysCloudResume"`) to a Sprung-specific reverse-DNS string. Align related build settings such as `ASSETCATALOG_COMPILER_BUNDLE_IDENTIFIER`, `DOCC_CATALOG_IDENTIFIER`, and `LM_BUNDLE_IDENTIFIER`.
- Change generated Info.plist values in build settings: `INFOPLIST_KEY_CFBundleDisplayName = "Physics Cloud Résumé"` and ensure `CFBundleName`, `CFBundleExecutable`, and any marketing version metadata reflect Sprung.
- If Xcode build configurations or derived Info.plist keys embed `PhysCloudResume`, update them and regenerate `PhysCloudResume/Info.plist` if it gains static content.
- Regenerate or edit `build.log`/`.build` artifacts after the rename so automated tooling doesn’t keep the old product name.

## 3. App Entrypoint & Runtime Code
- Rename `PhysCloudResume/App/PhysicsCloudResumeApp.swift` to something like `SprungApp.swift`; update the `PhysicsCloudResumeApp` type declaration, logger diagnostics (`"PhysicsCloudResumeApp init …"`), and any `private extension PhysicsCloudResumeApp` blocks.
- Update `AppDelegate` menu/title strings in `PhysCloudResume/App/AppDelegate.swift` (`"About PhysCloudResume"` and `"About Physics Cloud Résumé"`); ensure macOS application menu shows “Sprung”.
- Review `PhysCloudResume/App/Views/ContentViewLaunch.swift` and other views for user-facing strings such as *“relaunch PhysCloudResume”* and `restoreStatus` messages; switch them to Sprung and adjust backup path text.
- Update notification or analytics identifiers that include the old name (e.g., `Logger` statements, debug categories, `@MainActor` logs) so diagnostics remain consistent with the new brand.
- Change any hard-coded paths or fallback defaults: e.g., `PhysCloudResume_Backups`, `AppConfig.X-Title = "Physics Cloud Resume"`, `APIKeyManager.service = Bundle.main.bundleIdentifier ?? "Physics-Cloud.PhysCloudResume"`, and `Logger` subsystems defaulting to `"PhysCloudResume"`.

## 4. Storage Paths, File System Touchpoints, and Data Artifacts
- Update `PhysCloudResume/Shared/Utilities/SwiftDataBackupManager.swift`, `ContentViewLaunch.swift`, and related helpers to use a `Sprung_Backups` folder (and migrate existing backups if needed).
- Replace `.appendingPathComponent("PhysCloudResume")` occurrences in template, export, and resume utilities (`TemplateImporter`, `TemplateEditorView`, `ResumeTemplateProcessor`, `NativePDFGenerator`, `TextResumeGenerator`) with the new application support directory name.
- Adjust PDF/export metadata such as `kCGPDFContextCreator: "Physics Cloud Resume"` in `CoverLetterPDFGenerator` and any template metadata referencing the old brand.

## 5. Resources, Icons, and Asset Catalogs
- Verify `Assets.xcassets/AppIcon.appiconset` filenames and marketing artwork match the Sprung branding (rename exported PNGs if they embed the old name).
- Ensure `.icns` or `.iconset` bundles (`PhysCloudResume/Sprung.icon/Assets`) reflect the new product name in filenames or metadata if required by marketing materials.
- Replace any old-name text in resource manifests or template metadata (`PhysCloudResume/Resources/Templates/**`, resume manifests, JSON descriptors, HTML fragments).

## 6. Documentation, Notes, and Build Guides
- Update README (`README.md`) headings, clone/build instructions, and text that currently say “Physics Cloud Résumé” or reference the `PhysCloudResume` repository.
- Refresh agent/developer docs (`agents.md`, `CLAUDE.md`, `LLM_Passoff.md`, `Docs/**`, `Notes/**`, `LLM Design Intent Docs/**`, etc.) to use Sprung in examples, file paths, and explanatory text.
- Search for `"PhysCloudResume"` / `"Physics Cloud Résumé"` across the repo (including `Notes` and `Docs`) and update any canonical resume content that markets the app by name.
- Update quickstart commands in docs to reference the new project file (`open Sprung.xcodeproj`, `xcodebuild -project Sprung.xcodeproj -scheme Sprung …`).

## 7. Scripts, Tooling, and Automation
- Adjust scripts under `PhysCloudResume/Resources/Scripts/` (e.g., `resume_data.json`, `canonical *.json`, output HTML/TXT files) that mention Physics Cloud Résumé to the new name.
- Update any CI, lint, or build scripts that assume the `PhysCloudResume` scheme/target names (check `.github`, fastlane, or local automation if introduced later).
- Review packaged logs (`periphery_log.txt`, `build.log`) and regenerate them after the rename so automation baselines don’t keep the old identifiers.

## 8. External Touchpoints
- Update bundle signing and provisioning profiles to match the new bundle identifier (Apple Developer portal, notarization, Sparkle updates if applicable).
- Refresh marketing assets (website copy, release notes, metadata published with the app) to use Sprung.
- If distributing via Sparkle or the Mac App Store, ensure feed URLs, appcast titles, and installer package names adopt the new branding.

## 9. Post-Rename Cleanup & Verification
- Clear DerivedData, rebuild, and rerun tests (`xcodebuild -project Sprung.xcodeproj -scheme Sprung test`) to confirm no build settings still reference PhysCloudResume.
- Run a repo-wide search for legacy strings (`rg 'Phys'`, `rg 'Physics Cloud'`, `rg 'PhysCloudResume'`) to ensure nothing remains.
- Validate backup/export directories, template imports, and PDF metadata on a clean install to confirm runtime paths now point to Sprung locations.
- Update any cached user defaults, keychain entries, or migration logic that depended on the old bundle identifier so existing users transition cleanly.

Document progress in version control as you complete each section to keep the rename auditable.
