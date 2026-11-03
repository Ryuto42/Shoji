# Contributing

Thanks for your interest in Shoji. Issues and pull requests are welcome in English or Japanese.

Shoji is the integration app. The features themselves live in their own repositories, so most changes belong there:

| Change | Repository |
|---|---|
| Dock, widgets, window previews, Option+Tab switcher | [GlassDock](https://github.com/Ryuto42/GlassDock) |
| Tabs, snapping, the split divider | [ShelfTabs](https://github.com/Ryuto42/ShelfTabs) |
| Window overview, desktops, four-finger gestures | [MissionView](https://github.com/Ryuto42/MissionView) |
| Menu, settings window, how the features are wired together | This repository |

## Getting started

1. Install Xcode 26 or later.
2. Clone this repository. To work on a feature at the same time, clone its repository next to this one (`../GlassDock`, `../ShelfTabs`, `../MissionView`); `Package.swift` then uses the local copy instead of the released version.
3. Run `./build.sh install` and grant Accessibility and Screen Recording on first launch.

Without an Apple Development certificate the app is signed ad hoc, which resets the Accessibility permission on every build.

## Guidelines

- **Stay lightweight**: Shoji runs all day. Avoid constant polling; update from notifications or events, and stop work while the screen is asleep or locked.
- **Respect privacy**: if you add a network destination or read or store new data, update the Privacy section of the README.
- **Private APIs**: make sure the app still works when they are unavailable.
- **Standalone apps**: each feature must keep working on its own, and Shoji must pause a feature while its standalone app is running.

## Pull requests

- Keep each pull request to one change.
- Attach a screenshot or video for UI changes.
- Make sure `./build.sh` succeeds without new warnings.
