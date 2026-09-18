# Make Maybe a little less uncertain

Use Swift 6, iOS 17+ / macOS 14+, and Xcode for the sample app. The package has no
external dependencies. Start with `swift test` and `swift run maybe demo`.

Small improvements with a clear example are welcome. Before adding syntax, consider
whether it belongs in the provider or host app: the language's size is a feature.

## Checks

```sh
swift test
swift build -c release
xcodebuild -project Examples/MaybePlayground/MaybePlayground.xcodeproj \
  -scheme MaybePlayground -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

For UI tests, follow `docs/demo.md`. Edit `project.yml` and regenerate with XcodeGen
if changing the sample's project structure; keep the generated project checked in.

Use comments to explain why, especially around probability gates, replay, and
cancellation. Keep the examples funny and the failure behavior unsurprising.
Tests should catch a behavior change, not recite the implementation.

Never commit provider tokens or recordings of real personal input. Use synthetic
fixtures and injected transports. Live tests must be explicitly opted into.

If updating compatibility fixtures, use the optional oracle generator described in
`docs/architecture.md`, and explain intended differences from the original language.

Keep raw build logs, simulator result bundles, and personal recordings in ignored `work/`.
Public screenshots belong in `docs/assets/` and must use synthetic input.
