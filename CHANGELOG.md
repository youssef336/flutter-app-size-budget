# Changelog

## 0.1.0

First release.

- Composite action `youssef336/flutter-app-size-budget@v1`: builds the app with `--analyze-size`
  (`apk`, `appbundle` or `ios --no-codesign`), with flavor, target, `--dart-define-from-file` and
  extra build arguments.
- Baseline on pushes to the default branch, saved to `actions/cache` (keyed by commit) and as an
  artifact. Pull requests restore the baseline of their base commit, fall back to the latest one of
  the base branch, or build the base commit in a git worktree with `build-base: true`.
- Diff of the artifact size, per category (Dart AOT, Flutter engine, other native libs, assets, dex,
  resources, other), per Dart package, new / removed packages and the biggest movers.
- Budgets: `max-size`, `max-increase` (bytes or %), and per-category / per-package limits in
  `size-budget.yaml`. The `size-increase-approved` label (configurable) accepts an over-budget PR.
- One sticky PR comment (found by a hidden marker and updated in place) and the job summary.
- Outputs: `status`, `total-size`, `diff-bytes`, `base-size`, `baseline`, `report-path`, `snapshot-path`.
