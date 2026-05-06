# Contributing

Thanks for helping improve V-Paste.

## Development Setup

1. Install Xcode.
2. Clone the repository.
3. Open `V-Paste.xcodeproj` or use the command line scripts.
4. Run the test suite before sending changes.

```bash
xcodebuild test \
  -project V-Paste.xcodeproj \
  -scheme V-Paste \
  -configuration Debug \
  -destination 'platform=macOS' \
  -derivedDataPath build/DerivedData
```

## Pull Request Guidelines

- Keep changes focused and easy to review.
- Include tests for model, persistence, parsing, and routing behavior where possible.
- Update README or docs when behavior, permissions, storage, or release steps change.
- Do not commit local build output, `dist/`, signing certificates, provisioning profiles, or user-specific Xcode state.

## Code Style

The project uses Swift, SwiftUI, AppKit, Carbon hotkeys, and SQLite3. Prefer small focused types, explicit dependencies for testability, and local-first behavior.
