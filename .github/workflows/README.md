# GitHub Actions Workflows

## Release and Publish to CocoaPods

This workflow automates the release process for the PassageSDK Swift package, including:

- Version bumping
- Git tagging
- GitHub release creation
- CocoaPods publication
- XCFramework generation

### Setup Requirements

Before using this workflow, you need to set up the following repository secret:

#### `COCOAPODS_TRUNK_TOKEN`

1. Get your CocoaPods trunk token by running:

   ```bash
   pod trunk me
   ```

2. Copy the token from the output

3. In your GitHub repository, go to:
   - Settings → Secrets and variables → Actions
   - Click "New repository secret"
   - Name: `COCOAPODS_TRUNK_TOKEN`
   - Value: Your trunk token

### Usage

1. Go to the "Actions" tab in your GitHub repository
2. Select "Release and Publish to CocoaPods"
3. Click "Run workflow"
4. Choose:
   - **Version bump type**: `patch`, `minor`, or `major`
   - **Release notes**: Optional markdown description of changes

### What the Workflow Does

1. **Validation**: Validates Swift Package and podspec syntax
2. **Version Bump**: Updates version in `PassageSDK.podspec`
3. **Git Operations**: Commits changes, creates and pushes git tag
4. **GitHub Release**: Creates a GitHub release with release notes
5. **CocoaPods**: Publishes the new version to CocoaPods
6. **XCFramework**: Builds and attaches XCFramework as release asset

### Manual Release Process

If you prefer to release manually, you can still use the existing script:

```bash
# Dry run to test
./publish-cocoapods-source.sh --dry-run

# Actual release
./publish-cocoapods-source.sh
```

### Troubleshooting

- **Podspec validation fails**: Check that all dependencies are correctly specified
- **CocoaPods push fails**: Ensure `COCOAPODS_TRUNK_TOKEN` is correctly set
- **XCFramework build fails**: Verify Xcode scheme is properly configured
- **Tag already exists**: The workflow will skip creating duplicate tags

### Version Numbering

The workflow follows semantic versioning:

- **Patch** (x.x.X): Bug fixes and small improvements
- **Minor** (x.X.0): New features, backwards compatible
- **Major** (X.0.0): Breaking changes
