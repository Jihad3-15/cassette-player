#!/usr/bin/env bash
# Generates the android/ and ios/ platform folders (they are not committed) and
# applies Cassette's platform configuration on top of the Flutter templates.
#
# Safe to run repeatedly: `flutter create` only runs when a platform folder is
# missing, and tool/patch_platforms.py is idempotent.
#
# Usage (from anywhere): bash tool/bootstrap_platforms.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

if [[ ! -f pubspec.yaml || ! -d lib ]]; then
  echo "bootstrap: expected pubspec.yaml and lib/ in $ROOT" >&2
  exit 1
fi

if [[ ! -d android || ! -d ios ]]; then
  echo "bootstrap: generating platform folders with flutter create"

  # `flutter create` on an existing project skips files that already exist
  # (Template.render with overwriteExisting=false unless --overwrite is passed),
  # so lib/ and pubspec.yaml should be untouched. Back them up anyway and
  # restore afterwards so app code can never be clobbered.
  BACKUP="$(mktemp -d)"
  trap 'rm -rf "$BACKUP"' EXIT
  cp -a lib "$BACKUP/lib"
  cp -a pubspec.yaml "$BACKUP/pubspec.yaml"

  # flutter create also writes analysis_options.yaml (including
  # package:flutter_lints) if it is missing. flutter_lints is not a dev
  # dependency here, so an unresolvable include would make `flutter analyze`
  # report a warning. Only remove the file if flutter create added it.
  HAD_ANALYSIS_OPTIONS=0
  [[ -f analysis_options.yaml ]] && HAD_ANALYSIS_OPTIONS=1

  flutter create \
    --platforms=android,ios \
    --org com.jihad3_15 \
    --project-name cassette_player \
    .

  rm -rf lib
  cp -a "$BACKUP/lib" lib
  cp -a "$BACKUP/pubspec.yaml" pubspec.yaml

  if [[ "$HAD_ANALYSIS_OPTIONS" == 0 && -f analysis_options.yaml ]]; then
    echo "bootstrap: removing generated analysis_options.yaml (flutter_lints is not a dependency)"
    rm -f analysis_options.yaml
  fi
else
  echo "bootstrap: android/ and ios/ already exist, skipping flutter create"
fi

# The template's widget test references MyApp, which does not exist here.
if [[ -f test/widget_test.dart ]] && grep -q 'MyApp' test/widget_test.dart; then
  echo "bootstrap: removing generated test/widget_test.dart"
  rm -f test/widget_test.dart
fi

python3 tool/patch_platforms.py

# App icon (assets/icon/): generate every Android and iOS size from the
# 1024px source. Config lives under flutter_launcher_icons in pubspec.yaml.
flutter pub get
dart run flutter_launcher_icons
echo "bootstrap: done"
