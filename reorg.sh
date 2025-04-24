#!/usr/bin/env bash
set -euo pipefail

use_git=0
if command -v git >/dev/null 2>&1 && git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  use_git=1
fi

do_mv() {
  local src="$1" dest="$2"
  [[ -e "$src" ]] || { echo "⚠️  $src not found – skipping"; return; }
  mkdir -p "$(dirname "$dest")"
  if [[ $use_git -eq 1 ]]; then
    git mv "$src" "$dest"
  else
    mv "$src" "$dest"
  fi
}

do_rm() {
  local target="$1"
  [[ -e "$target" ]] || return
  if [[ $use_git -eq 1 ]]; then
    git rm "$target"
  else
    rm -f "$target"
  fi
}

echo "🔄 Moving files..."

while IFS="|" read -r src dest; do
  [[ -z "$src" || -z "$dest" ]] && continue
  do_mv "$src" "$dest"
done <<EOF
PhysCloudResume/Shared/Views/ResumeViews/ResumeViews/ResumeDetailView.swift|PhysCloudResume/Shared/Views/ResumeViews/ResumeDetailView.swift
PhysCloudResume/Shared/Views/ResumeViews/ResumeViews/FontSizePanelView.swift|PhysCloudResume/Shared/Views/ResumeViews/FontSizePanelView.swift
PhysCloudResume/Shared/Views/ResumeViews/ResumeViews/ResumeViewSetup.swift|PhysCloudResume/Shared/Views/ResumeViews/ResumeViewSetup.swift
PhysCloudResume/Shared/Views/ResumeViews/ResumeViews/ResumePDFView.swift|PhysCloudResume/Shared/Views/ResumeViews/ResumePDFView.swift
PhysCloudResume/Shared/Views/ResumeViews/ResumeViews/ResumeSplitView.swift|PhysCloudResume/Shared/Views/ResumeViews/ResumeSplitView.swift
PhysCloudResume/Shared/Views/ResumeViews/ResumeViews/CreateNewResumeView.swift|PhysCloudResume/Shared/Views/ResumeViews/CreateNewResumeView.swift
PhysCloudResume/Shared/Views/ResumeViews/ResumeViews/ResumeUtilityViews/SparkleButton.swift|PhysCloudResume/Shared/Views/ResumeViews/ResumeUtilityViews/SparkleButton.swift
PhysCloudResume/Shared/Views/ResumeViews/ResumeViews/ResumeUtilityViews/ResumeToolbar.swift|PhysCloudResume/Shared/Views/ResumeViews/ResumeUtilityViews/ResumeToolbar.swift
PhysCloudResume/Shared/Views/ResumeViews/ResumeViews/ResumeUtilityViews/DragInfo.swift|PhysCloudResume/Shared/Views/ResumeViews/ResumeUtilityViews/DragInfo.swift
PhysCloudResume/Shared/Views/ResumeViews/ResumeViews/ResumeUtilityViews/TextRowViews.swift|PhysCloudResume/Shared/Views/ResumeViews/ResumeUtilityViews/TextRowViews.swift
PhysCloudResume/Shared/Views/ResumeViews/ResumeViews/ResumeUtilityViews/ReorderableLeafRow.swift|PhysCloudResume/Shared/Views/ResumeViews/ResumeUtilityViews/ReorderableLeafRow.swift
PhysCloudResume/Shared/Views/ResumeViews/ResumeViews/ResumeUtilityViews/EditingControls.swift|PhysCloudResume/Shared/Views/ResumeViews/ResumeUtilityViews/EditingControls.swift
PhysCloudResume/Shared/Views/ResumeViews/ResInspectorViews/ResInspectorToggleView.swift|PhysCloudResume/Shared/Views/ResumeViews/ResInspectorViews/ResInspectorToggleView.swift
PhysCloudResume/Shared/Views/ResumeViews/ResumeViews/ResInspectorViews/ResumeInpectorListView.swift|PhysCloudResume/Shared/Views/ResumeViews/ResInspectorViews/ResumeInpectorListView.swift
PhysCloudResume/Shared/Views/ResumeViews/ResumeViews/ResInspectorViews/ResumeInspectorView.swift|PhysCloudResume/Shared/Views/ResumeViews/ResInspectorViews/ResumeInspectorView.swift
PhysCloudResume/Shared/Views/ResumeViews/ResumeViews/ResModelViews/ResModelFormView.swift|PhysCloudResume/Shared/Views/ResumeViews/ResModelViews/ResModelFormView.swift
PhysCloudResume/Shared/Views/ResumeViews/ResumeViews/ResModelViews/JsonValidatingTextEditor.swift|PhysCloudResume/Shared/Views/ResumeViews/ResModelViews/JsonValidatingTextEditor.swift
PhysCloudResume/Shared/Views/ResumeViews/ResumeViews/ResModelViews/ResModelView.swift|PhysCloudResume/Shared/Views/ResumeViews/ResModelViews/ResModelView.swift
PhysCloudResume/Shared/Views/ResumeViews/ResumeViews/ResModelViews/ResModelRowView.swift|PhysCloudResume/Shared/Views/ResumeViews/ResModelViews/ResModelRowView.swift
EOF

echo "🗑️ Deleting empty file..."
do_rm "PhysCloudResume/Scripts/File.swift"

echo "🧹 Removing empty directories..."
find "PhysCloudResume/Shared/Views/ResumeViews/ResumeViews" -type d -empty -delete

echo "✅ Done!"