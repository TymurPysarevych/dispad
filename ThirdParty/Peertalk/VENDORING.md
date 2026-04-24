# Peertalk Vendoring

- **Upstream:** https://github.com/rsms/peertalk
- **Vendored commit SHA:** `c75cd68cf5ba682de355161aa84f9d23b0d4d491`
- **Branch at time of vendoring:** master
- **Date vendored:** 2026-04-24
- **License:** MIT (see `LICENSE.md`), Copyright (c) 2012 Rasmus Andersson

## Why vendored

Upstream is effectively unmaintained, so we pin a specific commit to guarantee
a reproducible build. Peertalk is required for the usbmuxd transport on the
macOS side of dispad.

## How to update

1. Download a fresh archive of the desired upstream commit from
   https://github.com/rsms/peertalk.
2. Replace the contents of `ThirdParty/Peertalk/peertalk/` with the new
   sources. Do not edit files under that directory by hand.
3. Run `./scripts/bootstrap.sh` from the repo root to regenerate any
   derived artifacts.
4. Build the project and run the test suite.
5. Update the **Vendored commit SHA** and **Date vendored** fields above.
