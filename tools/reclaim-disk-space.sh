#!/usr/bin/env bash
set -euo pipefail

MODE="dry-run"
INCLUDE_CONDITIONAL_OLLAMA=0
INCLUDE_LEGACY_SMALL_OLLAMA=0

usage() {
  cat <<'USAGE'
Usage:
  tools/reclaim-disk-space.sh [--dry-run] [--execute]
                              [--include-conditional-ollama]
                              [--include-legacy-small-ollama]

Default mode is --dry-run. Nothing is removed unless --execute is passed.

Recommended default targets:
  - Optional / experimental Hugging Face image and TTS caches
  - Goose local model cache with no ~/code project reference found
  - Braid VibeVoice audition weights
  - LivePortrait / SadTalker probe folders
  - Rebuildable project and package-manager caches

Extra flags:
  --include-conditional-ollama
      Also remove Ollama models that are not in current Braid production TOML
      but are still referenced by local/older Braid paths:
        gemma4:26b, gemma4:31b

  --include-legacy-small-ollama
      Also remove older/small Ollama models that appear to be historical
      benchmark/fallback installs:
        gemma3:4b, qwen2.5:3b, qwen3:4b
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run)
      MODE="dry-run"
      ;;
    --execute)
      MODE="execute"
      ;;
    --include-conditional-ollama)
      INCLUDE_CONDITIONAL_OLLAMA=1
      ;;
    --include-legacy-small-ollama)
      INCLUDE_LEGACY_SMALL_OLLAMA=1
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
  shift
done

PATH_TARGETS=()
PATH_REASONS=()
OLLAMA_TARGETS=()
OLLAMA_REASONS=()

add_path() {
  PATH_TARGETS+=("$1")
  PATH_REASONS+=("$2")
}

add_ollama() {
  OLLAMA_TARGETS+=("$1")
  OLLAMA_REASONS+=("$2")
}

# High-confidence model/cache targets from the review.
add_path "$HOME/.cache/huggingface/hub/models--Qwen--Qwen-Image-Edit-2509" \
  "optional experiments/closer qwen-edit cache, not Braid production"
add_path "$HOME/.local/share/goose/models/gemma-4-26B-A4B-it-UD-Q4_K_M.gguf" \
  "Goose local assistant model, no ~/code project reference found"
add_path "$HOME/code/braid/state/dev/toolchains/tts/vibevoice-models" \
  "Braid VibeVoice audition weights; publish path rolled back to mlx-audio"
add_path "$HOME/.cache/huggingface/hub/models--filipstrand--Z-Image-Turbo-mflux-4bit" \
  "optional experiments/closer z-image engine"
add_path "$HOME/.cache/huggingface/hub/models--mlx-community--Qwen3-TTS-12Hz-0.6B-CustomVoice-bf16" \
  "Braid Qwen3 TTS experiment cache, not current publish path"
add_path "$HOME/.cache/huggingface/hub/models--mlx-community--Qwen3-TTS-12Hz-1.7B-Base-8bit" \
  "Braid Qwen3 TTS experiment cache, not current publish path"
add_path "$HOME/code/experiments/liveportrait-braid-probe" \
  "LivePortrait probe project and weights"
add_path "$HOME/code/experiments/sadtalker-braid-probe" \
  "SadTalker probe project and weights"

# Rebuildable / cache targets.
add_path "$HOME/code/muse/app/src-tauri/target" \
  "Rust build output"
add_path "$HOME/code/muse-sync-server/target" \
  "Rust build output"
add_path "$HOME/code/braid/dist-site" \
  "Braid generated static site output"
add_path "$HOME/code/perch/.tmp" \
  "Perch temporary proof/workspace data"
add_path "$HOME/go/pkg/mod" \
  "Go module cache"
add_path "$HOME/.npm" \
  "npm package cache"
add_path "$HOME/Library/Developer/Xcode/DerivedData" \
  "Xcode derived data"
add_path "$HOME/Library/Caches/pip" \
  "pip download/build cache"
add_path "$HOME/Library/Caches/Homebrew" \
  "Homebrew cache, if CleanMyMac left anything behind"

if [[ "$INCLUDE_CONDITIONAL_OLLAMA" -eq 1 ]]; then
  add_ollama "gemma4:26b" \
    "not in current Braid profile TOML; older docs/tests still reference it"
  add_ollama "gemma4:31b" \
    "current local-draft-cinematic only; not production/default publish"
fi

if [[ "$INCLUDE_LEGACY_SMALL_OLLAMA" -eq 1 ]]; then
  add_ollama "gemma3:4b" \
    "older relevance benchmark/fallback"
  add_ollama "qwen2.5:3b" \
    "older relevance benchmark/fallback"
  add_ollama "qwen3:4b" \
    "older batch/rerank benchmark"
fi

size_of_path() {
  local target="$1"
  if [[ -e "$target" ]]; then
    du -sh "$target" 2>/dev/null | awk '{print $1}'
  else
    echo "missing"
  fi
}

size_kib_of_path() {
  local target="$1"
  if [[ -e "$target" ]]; then
    du -sk "$target" 2>/dev/null | awk '{print $1}'
  else
    echo 0
  fi
}

ollama_size() {
  local model="$1"
  if ! command -v ollama >/dev/null 2>&1; then
    echo "ollama-not-found"
    return
  fi
  ollama list 2>/dev/null | awk -v model="$model" '$1 == model { print $3 " " $4; found=1 } END { if (!found) print "missing" }'
}

print_plan() {
  local total_kib=0

  echo "Mode: $MODE"
  echo
  echo "Path targets:"
  for i in "${!PATH_TARGETS[@]}"; do
    local target="${PATH_TARGETS[$i]}"
    local size
    size="$(size_of_path "$target")"
    total_kib=$((total_kib + $(size_kib_of_path "$target")))
    printf '  [%02d] %-8s %s\n' "$((i + 1))" "$size" "$target"
    printf '       %s\n' "${PATH_REASONS[$i]}"
  done

  echo
  echo "Estimated path reclaim: $(awk -v kib="$total_kib" 'BEGIN { printf "%.1f GiB", kib / 1024 / 1024 }')"

  if [[ "${#OLLAMA_TARGETS[@]}" -gt 0 ]]; then
    echo
    echo "Ollama targets:"
    for i in "${!OLLAMA_TARGETS[@]}"; do
      local model="${OLLAMA_TARGETS[$i]}"
      printf '  [%02d] %-8s %s\n' "$((i + 1))" "$(ollama_size "$model")" "$model"
      printf '       %s\n' "${OLLAMA_REASONS[$i]}"
    done
    echo
    echo "Note: Ollama models may share layers; exact reclaimed space can differ from listed model sizes."
  fi

  echo
  if [[ "$MODE" == "dry-run" ]]; then
    echo "Dry run only. Re-run with --execute to remove the listed targets."
  else
    echo "Execute mode. The listed targets will be removed."
  fi
}

remove_paths() {
  for target in "${PATH_TARGETS[@]}"; do
    if [[ -e "$target" ]]; then
      echo "Removing path: $target"
      rm -rf -- "$target"
    else
      echo "Skipping missing path: $target"
    fi
  done
}

remove_ollama_models() {
  if [[ "${#OLLAMA_TARGETS[@]}" -eq 0 ]]; then
    return
  fi
  if ! command -v ollama >/dev/null 2>&1; then
    echo "ollama command not found; skipping Ollama targets" >&2
    return
  fi
  for model in "${OLLAMA_TARGETS[@]}"; do
    if ollama list 2>/dev/null | awk -v model="$model" '$1 == model { found=1 } END { exit found ? 0 : 1 }'; then
      echo "Removing Ollama model: $model"
      ollama rm "$model"
    else
      echo "Skipping missing Ollama model: $model"
    fi
  done
}

print_plan

if [[ "$MODE" == "execute" ]]; then
  echo
  echo "Starting removal..."
  remove_paths
  remove_ollama_models
  echo "Done."
fi
