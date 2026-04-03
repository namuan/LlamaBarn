#!/bin/bash
set -euo pipefail

# Migrate standalone GGUF files from llama.cpp cache to HF cache layout
# so LlamaBarn discovers them via dynamic model scanning.

LLAMA_CACHE="/Users/nnn/Library/Caches/llama.cpp"
HF_CACHE="$HOME/.cache/huggingface/hub"

echo "=== LlamaBarn HF Cache Migration ==="
echo ""

# Check source directory
if [ ! -d "$LLAMA_CACHE" ]; then
  echo "Error: llama.cpp cache not found at $LLAMA_CACHE"
  exit 1
fi

# Find GGUF files
gguf_files=("$LLAMA_CACHE"/*.gguf)
if [ ! -e "${gguf_files[0]}" ]; then
  echo "No .gguf files found in $LLAMA_CACHE"
  exit 0
fi

echo "Found ${#gguf_files[@]} GGUF file(s) to migrate:"
for gguf in "${gguf_files[@]}"; do
  echo "  - $(basename "$gguf")"
done
echo ""

# Create HF cache if needed
mkdir -p "$HF_CACHE"

migrated=0
for gguf in "${gguf_files[@]}"; do
  filename=$(basename "$gguf")
  stem="${filename%.gguf}"
  
  # Derive repo name by stripping quantization suffix
  # e.g. Qwen3.5-2B-Q4_K_M → Qwen3.5-2B
  repo_name=$(echo "$stem" | sed -E 's/-[A-Z0-9_]+$//')
  repo_dir="models--local--${repo_name}"
  
  # Generate commit hash from file content
  commit=$(shasum -a 256 "$gguf" | cut -c1-40)
  
  dest_dir="$HF_CACHE/$repo_dir/snapshots/$commit"
  
  # Skip if already imported
  if [ -L "$dest_dir/$filename" ]; then
    existing=$(readlink "$dest_dir/$filename")
    if [ "$existing" = "$(realpath "$gguf")" ]; then
      echo "⏭  $filename (already imported)"
      continue
    fi
  fi
  
  # Create HF cache layout
  mkdir -p "$dest_dir"
  mkdir -p "$HF_CACHE/$repo_dir/refs"
  
  # Create refs/main
  echo "$commit" > "$HF_CACHE/$repo_dir/refs/main"
  
  # Create symlink to actual file (force overwrite)
  rm -f "$dest_dir/$filename"
  ln -s "$(realpath "$gguf")" "$dest_dir/$filename"
  
  echo "✓  $filename → $repo_dir/snapshots/$commit/"
  migrated=$((migrated + 1))
done

echo ""
echo "Migration complete: $migrated file(s) imported."
echo "Restart LlamaBarn to see the new models."
