# Contributing

Small, focused issues and pull requests are welcome. Start from `main`, describe the user-visible change, and explain how you checked it.

For code changes, run `zsh tools/test.sh` and `zsh tools/build.sh`. Changes to rendering or desktop behavior should also be exercised in a graphical macOS session with the native review command in [development notes](docs/DEVELOPMENT.md). Prefer behavioral tests that catch user-visible failures.

Keep the aquarium calm, controls native, and all runtime assets local. Avoid adding analytics, external services, or unnecessary dependencies. Do not commit `build/`, `dist/`, credentials, signing identities, or personal desktop captures.

New artwork needs documented provenance and permission to distribute it under the project’s MIT license. See [artwork notes](docs/ARTWORK.md).

By contributing, you agree that your contribution is provided under the [MIT license](LICENSE).
