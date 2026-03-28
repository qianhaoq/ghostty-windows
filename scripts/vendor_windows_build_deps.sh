#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VENDOR_DIR="$ROOT/vendor/zig-deps"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$VENDOR_DIR"

download_and_extract() {
  local name="$1"
  local url="$2"
  local archive="$TMP_DIR/$name.archive"
  local extract_dir="$TMP_DIR/$name.extract"
  local dest="$VENDOR_DIR/$name"

  echo "vendoring $name from $url"
  rm -rf "$archive" "$extract_dir" "$dest"
  mkdir -p "$extract_dir" "$dest"

  curl -fL --retry 3 --retry-delay 2 "$url" -o "$archive"

  case "$url" in
    *.zip)
      unzip -q "$archive" -d "$extract_dir"
      ;;
    *)
      tar -xf "$archive" -C "$extract_dir"
      ;;
  esac

  local first
  first="$(find "$extract_dir" -mindepth 1 -maxdepth 1 | head -n 1)"
  if [[ -n "${first:-}" && -d "$first" ]]; then
    cp -a "$first"/. "$dest"/
  else
    cp -a "$extract_dir"/. "$dest"/
  fi
}

copy_themes() {
  local src="$ROOT/zig-out/share/ghostty/themes"
  local dest="$VENDOR_DIR/iterm2_themes"

  if [[ ! -d "$src" ]]; then
    echo "missing local themes source: $src" >&2
    return 1
  fi

  rm -rf "$dest"
  mkdir -p "$dest"
  cp -a "$src"/. "$dest"/
}

prepare_fonts() {
  local src="$ROOT/src/font/res"
  local jetbrains="$VENDOR_DIR/jetbrains_mono"
  local nerd="$VENDOR_DIR/nerd_fonts_symbols_only"

  rm -rf "$jetbrains" "$nerd"
  mkdir -p \
    "$jetbrains/fonts/ttf" \
    "$jetbrains/fonts/variable" \
    "$nerd"

  cp "$src/JetBrainsMonoNoNF-Regular.ttf" \
    "$jetbrains/fonts/ttf/JetBrainsMono-Regular.ttf"
  cp "$src/JetBrainsMonoNerdFont-Bold.ttf" \
    "$jetbrains/fonts/ttf/JetBrainsMono-Bold.ttf"
  cp "$src/JetBrainsMonoNerdFont-Italic.ttf" \
    "$jetbrains/fonts/ttf/JetBrainsMono-Italic.ttf"
  cp "$src/JetBrainsMonoNerdFont-BoldItalic.ttf" \
    "$jetbrains/fonts/ttf/JetBrainsMono-BoldItalic.ttf"

  cp "$src/JetBrainsMonoNoNF-Regular.ttf" \
    "$jetbrains/fonts/variable/JetBrainsMono[wght].ttf"
  cp "$src/JetBrainsMonoNerdFont-Italic.ttf" \
    "$jetbrains/fonts/variable/JetBrainsMono-Italic[wght].ttf"

  cp "$src/JetBrainsMonoNerdFont-Regular.ttf" \
    "$nerd/SymbolsNerdFont-Regular.ttf"
}

prepare_dearbindings() {
  local src="$VENDOR_DIR/dearbindings-src"
  local pydeps="$TMP_DIR/dearbindings-pydeps"

  if ! command -v python3 >/dev/null 2>&1; then
    echo "missing python3 for dear bindings generation" >&2
    return 1
  fi

  python3 -m pip install \
    --disable-pip-version-check \
    --no-input \
    --target "$pydeps" \
    -r "$src/requirements.txt"

  (
    cd "$src"
    PYTHONPATH="$pydeps" python3 dear_bindings.py \
      -o dcimgui \
      ../imgui-src/imgui.h
    PYTHONPATH="$pydeps" python3 dear_bindings.py \
      -o dcimgui_internal \
      --include ../imgui-src/imgui.h \
      ../imgui-src/imgui_internal.h
  )
}

patch_nested_zons() {
  cat > "$VENDOR_DIR/vaxis/build.zig.zon" <<'EOF'
.{
    .name = .vaxis,
    .fingerprint = 0x14fbbb94fc556305,
    .version = "0.5.1",
    .minimum_zig_version = "0.15.1",
    .dependencies = .{
        .zigimg = .{
            .path = "../../../vendor/zig-deps/zigimg",
        },
        .uucode = .{
            .path = "../../../vendor/zig-deps/uucode-vaxis",
        },
    },
    .paths = .{
        "LICENSE",
        "build.zig",
        "build.zig.zon",
        "src",
    },
}
EOF

  cat > "$VENDOR_DIR/zf/build.zig.zon" <<'EOF'
.{
    .name = .zf,
    .fingerprint = 0x30d847eef1728438,
    .description = "a commandline fuzzy finder designed for filtering filepaths",
    .version = "0.10.3",
    .minimum_zig_version = "0.15.2",
    .dependencies = .{
        .vaxis = .{
            .path = "../../../vendor/zig-deps/vaxis",
            .lazy = true,
        },
    },
    .paths = .{
        "src/zf",
        "build.zig",
        "build.zig.zon",
        "LICENSE",
    },
}
EOF
}

download_and_extract "libxev" \
  "https://codeload.github.com/mitchellh/libxev/tar.gz/34fa50878aec6e5fa8f532867001ab3c36fae23e"
download_and_extract "vaxis" \
  "https://codeload.github.com/rockorager/libvaxis/tar.gz/7dbb9fd3122e4ffad262dd7c151d80d863b68558"
download_and_extract "zigimg" \
  "https://github.com/ivanstepanovftw/zigimg/archive/d7b7ab0ba0899643831ef042bd73289510b39906.tar.gz"
download_and_extract "uucode-vaxis" \
  "https://codeload.github.com/jacobsandlund/uucode/tar.gz/5f05f8f83a75caea201f12cc8ea32a2d82ea9732"
download_and_extract "z2d" \
  "https://codeload.github.com/vancluever/z2d/tar.gz/refs/tags/v0.10.0"
download_and_extract "zf" \
  "https://codeload.github.com/natecraddock/zf/tar.gz/3c52637b7e937c5ae61fd679717da3e276765b23"

download_and_extract "freetype-src" \
  "https://download.savannah.gnu.org/releases/freetype/freetype-2.13.2.tar.gz"
download_and_extract "harfbuzz-src" \
  "https://github.com/harfbuzz/harfbuzz/releases/download/11.0.0/harfbuzz-11.0.0.tar.xz"
download_and_extract "libpng-src" \
  "https://codeload.github.com/glennrp/libpng/tar.gz/refs/tags/v1.6.43"
download_and_extract "zlib-src" \
  "https://zlib.net/fossils/zlib-1.3.1.tar.gz"
download_and_extract "oniguruma-src" \
  "https://codeload.github.com/kkos/oniguruma/tar.gz/refs/tags/v6.9.9"
download_and_extract "glslang-src" \
  "https://codeload.github.com/KhronosGroup/glslang/tar.gz/refs/tags/14.2.0"
download_and_extract "spirv-cross-src" \
  "https://codeload.github.com/KhronosGroup/SPIRV-Cross/tar.gz/refs/tags/vulkan-sdk-1.3.296.0"
download_and_extract "highway-src" \
  "https://codeload.github.com/google/highway/tar.gz/66486a10623fa0d72fe91260f96c892e41aceb06"
download_and_extract "utfcpp-src" \
  "https://codeload.github.com/nemtrif/utfcpp/tar.gz/refs/tags/v4.0.9"
download_and_extract "wuffs-src" \
  "https://codeload.github.com/google/wuffs/tar.gz/refs/tags/v0.4.0-alpha.9"
download_and_extract "pixels-src" \
  "https://codeload.github.com/make-github-pseudonymous-again/pixels/tar.gz/refs/heads/main"

download_and_extract "dearbindings-src" \
  "https://codeload.github.com/dearimgui/dear_bindings/tar.gz/refs/tags/DearBindings_v0.17_ImGui_v1.92.5-docking"
download_and_extract "imgui-src" \
  "https://github.com/ocornut/imgui/archive/refs/tags/v1.92.5-docking.tar.gz"

copy_themes
prepare_fonts
prepare_dearbindings
patch_nested_zons
