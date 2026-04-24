# Contributing to dispad

Thanks for your interest. This is a small open-source project; contributions are welcome.

## Getting set up

1. Clone the repo.
2. Open `DispadProtocol/Package.swift` in Xcode to work on the shared protocol code.
3. Open `DispadHost/DispadHost.xcodeproj` for the macOS app.
4. Open `DispadClient/DispadClient.xcodeproj` for the iPadOS app.

You need Xcode 15 or newer and macOS 13 or newer to build.

## Running tests

```bash
cd DispadProtocol
swift test
```

The two apps are manually tested end-to-end. There is no headless integration test harness.

## Pull requests

- One logical change per PR.
- Run `swift-format` before committing (there is a pre-commit hook).
- No CLA or DCO — just submit the PR.
- Keep commit messages professional and descriptive. No bot signatures, no emoji in commit subjects.

## Architecture

See [`docs/architecture.md`](docs/architecture.md) for how the pieces fit together.

## Scope

`dispad` intentionally solves one narrow problem: iPad-as-display for a headless Mac mini, over USB-C. We will say no to scope creep that doesn't serve that goal. Features like Wi-Fi transport, input forwarding, and audio are all on the roadmap but are v2 territory.
