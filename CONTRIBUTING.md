# Contributing to coscene

Thanks for helping. Bug reports, new levels, translations and fixes are all welcome.

## Setup

You need Flutter 3.44 or newer. For iOS builds, Xcode with CocoaPods; for Android, the Android SDK and JDK 17.

```bash
git clone https://github.com/vecvel/coscene.git
cd coscene
flutter pub get
cd apps/coscene-mobile && flutter run
```

The repo is a pub workspace, so one `flutter pub get` at the root sets up every package.

## Before you open a pull request

Run the same checks CI runs:

```bash
dart format apps packages
flutter analyze
```

```bash
for p in coscene-core coscene-content coscene-i18n; do (cd packages/$p && dart test); done
(cd packages/coscene-render && flutter test)
(cd apps/coscene-mobile && flutter test)
```

Lines are 120 characters wide; `dart format` reads that from each package's `analysis_options.yaml`.

## Where things live

- Puzzle rules, validators and solvers: `packages/coscene-core`. Keep it pure Dart and deterministic: the same input must give the same result on every device.
- Levels: `packages/coscene-content/levels/base/`. After editing, run `dart run tool/generate_levels.dart --embed` in `packages/coscene-content`. The tool refuses to write a level that has no solution.
- Text: `packages/coscene-i18n/locales/<code>.json`, then `dart run tool/embed_locales.dart` in `packages/coscene-i18n`. English is the fallback, so a new key only has to exist in `en.json` to work; native speakers are very welcome to fill in the rest.
- Drawing, logo and icons: `packages/coscene-render`.
- Screens, sound and saving: `apps/coscene-mobile`.

## Pull requests

1. Fork the repo and branch from `main`.
2. Keep each pull request to one change. Add or update tests for engine and content changes.
3. Write commit messages in the imperative, short and plain: `Fix gear ratio rounding`, `Add Tamil hints for the harbour`.
4. Describe what changed and how you checked it. Screenshots help for anything visual.

## Releases

Maintainers release by bumping `version:` in `apps/coscene-mobile/pubspec.yaml` (both the name and the `+build` number) and `appVersion` in `apps/coscene-mobile/lib/screens/settings_screen.dart`, adding a section to `CHANGELOG.md`, and merging to `main`. The release workflow builds and signs the Android app, tags `v<version>` and publishes the GitHub release.

## Reporting bugs

Open an issue with the device, OS version, app version (shown in Settings) and the steps to reproduce. For security problems, follow [SECURITY.md](SECURITY.md) instead.

By contributing you agree that your work is released under the [MIT License](LICENSE), and to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
