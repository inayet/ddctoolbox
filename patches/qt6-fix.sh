#!/usr/bin/env bash
# Apply a set of mechanical source edits to make the upstream DDCToolbox source more Qt6-friendly.
# This script is best-effort and idempotent. It performs in-place edits under the `upstream/src/` tree.
#
# Usage:
#   cd ddctoolbox
#   ./patches/qt6-fix.sh
#
# Notes:
# - The edits are conservative and focused on the common Qt5->Qt6 API breakpoints:
#   * QWheelEvent: delta() -> angleDelta().y(), pos() -> position()
#   * QPainter render hint: HighQualityAntialiasing -> Antialiasing
#   * QWeakPointer::data() usage -> toStrongRef().data()
#   * QMap::unite(...) -> explicit insert loop
#   * QSet::toList() (in plot code) -> values()
#   * insertMulti -> insert (best-effort; check semantics)
# - The script limits some replacements to files under src/plot to avoid touching unrelated
#   code like model classes which may implement their own toList() methods.
# - After running, manually inspect changes and run the build. Additional fixes will likely be needed.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="$REPO_ROOT/upstream/src"

if [ ! -d "$SRC_DIR" ]; then
  echo "Error: source directory not found: $SRC_DIR"
  exit 1
fi

echo "Working from repo root: $REPO_ROOT"
echo "Patching sources under: $SRC_DIR"
echo

# Helper: run a safe sed replacement and print a summary
sedi() {
  # usage: sedi <file> <sed-expression>
  local file=$1
  shift
  local expr="$*"
  if [ ! -f "$file" ]; then
    return 0
  fi
  # Create a lightweight backup only if not present (idempotence)
  if [ ! -f "${file}.orig-for-qt6patch" ]; then
    cp -a "$file" "${file}.orig-for-qt6patch" || true
  fi
  # Run sed -i (POSIX-friendly); support extended regex with -E via argument if needed
  sed -i "$expr" "$file"
}

# 1) QWheelEvent: delta() -> angleDelta().y(), pos() -> position()
echo "1) Replacing QWheelEvent delta()/pos() usages (plot files)..."
grep -R --line-number -E "event->delta\\(|event->pos\\(" "$SRC_DIR/plot" 2>/dev/null | cut -d: -f1 | sort -u | while read -r f; do
  echo " - patching $f"
  # Replace plain delta() -> angleDelta().y()
  sedi "$f" "s/event->delta()/event->angleDelta().y()/g"
  # Replace event->pos() -> event->position()
  # Also handle common .pos().x() / .pos().y() patterns
  sedi "$f" "s/event->pos().x()/event->position().x()/g"
  sedi "$f" "s/event->pos().y()/event->position().y()/g"
  sedi "$f" "s/event->pos()/event->position()/g"
done

# 2) QPainter render hint: HighQualityAntialiasing -> Antialiasing (plot)
echo
echo "2) Replacing QPainter::HighQualityAntialiasing -> QPainter::Antialiasing (plot files)..."
grep -R --line-number -E "HighQualityAntialiasing" "$SRC_DIR/plot" 2>/dev/null | cut -d: -f1 | sort -u | while read -r f; do
  echo " - patching $f"
  sedi "$f" "s/HighQualityAntialiasing/Antialiasing/g"
done

# 3) QWeakPointer::data() -> toStrongRef().data() (best-effort)
# We target the common pattern "something.data()->" found in plot code; convert to toStrongRef().data()
echo
echo "3) Replacing <something>.data()-> -> <something>.toStrongRef().data()-> (plot files)..."
grep -R --line-number -E "\\.data\\(\\)\\s*->" "$SRC_DIR/plot" 2>/dev/null | cut -d: -f1 | sort -u | while read -r f; do
  echo " - patching $f"
  # Replace occurrences like "mPaintBuffer.data()->" with "mPaintBuffer.toStrongRef().data()->"
  # This preserves the following "->" usage while using the public toStrongRef() API.
  sedi "$f" "s/\\([A-Za-z0-9_]*\\)\\.data()\\s*->/\\1.toStrongRef().data()->/g"
done

# 4) QSet::toList() -> values() (but limit to plot files to avoid model helpers)
echo
echo "4) Replacing .toList() -> .values() in plot files (avoid touching model classes)..."
grep -R --line-number -E "\\.toList\\(\\)" "$SRC_DIR/plot" 2>/dev/null | cut -d: -f1 | sort -u | while read -r f; do
  echo " - patching $f"
  sedi "$f" "s/\\.toList()/\\.values()/g"
done

# 5) QMap::unite usages -> explicit insertion loop (QCustomPlot)
echo
echo "5) Replacing mTicks.unite(ticks) -> explicit insert loop in QCustomPlot.cpp (best-effort)..."
QCP_FILE="$SRC_DIR/plot/QCustomPlot.cpp"
if [ -f "$QCP_FILE" ]; then
  # Only replace the simple unite call with a single-line loop (keeps formatting simple)
  if grep -q "mTicks.unite(ticks);" "$QCP_FILE"; then
    echo " - patching $QCP_FILE"
    # Note: replace exactly that call with a for-loop; keep it one-line to reduce accidental formatting issues.
    sedi "$QCP_FILE" "s/mTicks.unite(ticks);/for (auto it = ticks.constBegin(); it != ticks.constEnd(); ++it) mTicks.insert(it.key(), it.value());/g"
  else
    echo " - no mTicks.unite(ticks); occurrence found"
  fi
fi

# 6) insertMulti -> insert (best-effort)
# insertMulti semantics differ from insert (insertMulti keeps multiple values), so this is a heuristic.
echo
echo "6) Replacing insertMulti( -> insert( in plot files (best-effort; review semantics)..."
grep -R --line-number -E "insertMulti\\(" "$SRC_DIR/plot" 2>/dev/null | cut -d: -f1 | sort -u | while read -r f; do
  echo " - patching $f"
  sedi "$f" "s/insertMulti\\(/insert(/g"
done

# 7) Misc: QImage::mirrored deprecation - leave as-is but notify files for manual review
echo
echo "7) Listing occurrences of QImage::mirrored(...) for manual review (do not auto-change):"
grep -R --line-number -E "mirrored\\(" "$SRC_DIR" 2>/dev/null || true

# 8) Misc: document-style references (no code change) - list spots where event->pos()/delta() are mentioned in comments/docs
echo
echo "8) Listing comment or doc references to event->pos()/event->delta() for manual doc update:"
grep -R --line-number -E "event->pos\\(|event->delta\\(" "$SRC_DIR" 2>/dev/null || true

echo
echo "Patch pass complete. Rough summary of changed files (git-style):"
# Show files under upstream/src that were modified compared to original backups we made (.orig-for-qt6patch)
find "$SRC_DIR" -type f -name "*.orig-for-qt6patch" -print | while read -r b; do
  orig="$b"
  f="${b%.orig-for-qt6patch}"
  if [ -f "$f" ]; then
    echo " - $(realpath --relative-to="$REPO_ROOT" "$f")"
  fi
done

echo
echo "IMPORTANT next steps:"
echo " - Inspect the patched files (especially QCustomPlot.cpp, FrequencyPlot.cpp and other files under src/plot)."
echo " - Commit the patches you want to keep into the repository (or keep them in a 'patches' directory and apply in flake.nix's patchPhase)."
echo " - Run the nix build on the flake: 'nix build .#ddctoolbox' and iterate on remaining compiler errors."
echo
echo "Caveat: these edits are mechanical best-effort fixes. Some replacements (insertMulti -> insert, .toStrongRef().data()->) may change behavior or require null-checks; review runtime behavior in the app (mouse/zoom behavior and painting) once it runs."
echo
echo "Done."
