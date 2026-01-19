#!/bin/bash
set -e

# ============================================
# Antigravity Tools - 打包构建脚本
# ============================================

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 配置
APP_NAME="Antigravity Tools"
VERSION=$(grep '"version":' package.json | head -n 1 | awk -F: '{ print $2 }' | sed 's/[", ]//g')
BUILD_DIR="src-tauri/target/release/bundle"
DIST_DIR="dist_release"

# 打印带颜色的消息
info() { echo -e "${BLUE}ℹ️  $1${NC}"; }
success() { echo -e "${GREEN}✅ $1${NC}"; }
warn() { echo -e "${YELLOW}⚠️  $1${NC}"; }
error() { echo -e "${RED}❌ $1${NC}"; exit 1; }

# 显示帮助
show_help() {
    echo "用法: $0 [选项]"
    echo ""
    echo "选项:"
    echo "  --debug, -d       Debug 模式构建"
    echo "  --release, -r     Release 模式构建 (默认)"
    echo "  --skip-frontend   跳过前端构建"
    echo "  --clean           清理构建目录"
    echo "  --dmg             构建后打包 DMG"
    echo "  --aarch64         仅构建 ARM64 (Apple Silicon)"
    echo "  --x86_64          仅构建 x86_64 (Intel)"
    echo "  --universal       构建 Universal 二进制"
    echo "  -h, --help        显示帮助"
    exit 0
}

# 默认参数
BUILD_MODE="release"
SKIP_FRONTEND=false
CLEAN_BUILD=false
CREATE_DMG=false
TARGET_ARCH=""

# 解析参数
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug|-d)
            BUILD_MODE="debug"
            shift
            ;;
        --release|-r)
            BUILD_MODE="release"
            shift
            ;;
        --skip-frontend)
            SKIP_FRONTEND=true
            shift
            ;;
        --clean)
            CLEAN_BUILD=true
            shift
            ;;
        --dmg)
            CREATE_DMG=true
            shift
            ;;
        --aarch64)
            TARGET_ARCH="aarch64-apple-darwin"
            shift
            ;;
        --x86_64)
            TARGET_ARCH="x86_64-apple-darwin"
            shift
            ;;
        --universal)
            TARGET_ARCH="universal-apple-darwin"
            shift
            ;;
        -h|--help)
            show_help
            ;;
        *)
            error "未知参数: $1"
            ;;
    esac
done

# 显示构建信息
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║         Antigravity Tools - 打包构建脚本                    ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
info "应用名称:   $APP_NAME"
info "版本:       $VERSION"
info "构建模式:   $BUILD_MODE"
info "目标架构:   ${TARGET_ARCH:-$(uname -m)}"
echo ""

# 检查依赖
info "检查依赖..."
command -v node >/dev/null 2>&1 || error "未找到 Node.js，请先安装"
command -v npm >/dev/null 2>&1 || error "未找到 npm，请先安装"
command -v cargo >/dev/null 2>&1 || error "未找到 Cargo，请先安装 Rust"
success "依赖检查通过"

# 清理构建目录
if [ "$CLEAN_BUILD" = true ]; then
    info "清理构建目录..."
    rm -rf "$DIST_DIR"
    rm -rf src-tauri/target
    rm -rf dist
    rm -rf node_modules/.cache
    success "清理完成"
fi

# 安装 npm 依赖
if [ ! -d "node_modules" ] || [ ! -f "node_modules/.package-lock.json" ]; then
    info "安装 npm 依赖..."
    npm ci
    success "npm 依赖安装完成"
fi

# 构建前端
if [ "$SKIP_FRONTEND" = false ]; then
    info "构建前端 (Vite + React)..."
    npm run build
    success "前端构建完成"
fi

# 构建 Tauri 应用
info "构建 Tauri 应用..."

TAURI_CMD="npm run tauri build"

if [ "$BUILD_MODE" = "debug" ]; then
    TAURI_CMD="npm run tauri build -- --debug"
fi

if [ -n "$TARGET_ARCH" ]; then
    TAURI_CMD="$TAURI_CMD -- --target $TARGET_ARCH"
fi

echo "执行: $TAURI_CMD"
eval $TAURI_CMD

success "Tauri 应用构建完成"

# 创建发布目录
info "整理发布文件..."
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

# 复制构建产物
if [ "$BUILD_MODE" = "release" ]; then
    # macOS .app
    if [ -d "$BUILD_DIR/macos/${APP_NAME}.app" ]; then
        cp -R "$BUILD_DIR/macos/${APP_NAME}.app" "$DIST_DIR/"
        success "已复制: ${APP_NAME}.app"
    fi
    
    # macOS .dmg
    if ls "$BUILD_DIR/dmg/"*.dmg 1> /dev/null 2>&1; then
        cp "$BUILD_DIR/dmg/"*.dmg "$DIST_DIR/"
        success "已复制: DMG 安装包"
    fi
    
    # Windows .msi / .exe (如果存在)
    if ls "$BUILD_DIR/msi/"*.msi 1> /dev/null 2>&1; then
        cp "$BUILD_DIR/msi/"*.msi "$DIST_DIR/"
        success "已复制: MSI 安装包"
    fi
    
    if ls "$BUILD_DIR/nsis/"*.exe 1> /dev/null 2>&1; then
        cp "$BUILD_DIR/nsis/"*.exe "$DIST_DIR/"
        success "已复制: NSIS 安装包"
    fi
fi

# 打包 DMG (带修复脚本)
if [ "$CREATE_DMG" = true ]; then
    info "创建自定义 DMG..."
    DMG_NAME="Antigravity_Tools_${VERSION}.dmg"
    DMG_STAGING="$DIST_DIR/dmg_staging"
    
    mkdir -p "$DMG_STAGING"
    cp -R "$BUILD_DIR/macos/${APP_NAME}.app" "$DMG_STAGING/"
    cp "scripts/Fix_Damaged.command" "$DMG_STAGING/"
    chmod +x "$DMG_STAGING/Fix_Damaged.command"
    ln -s /Applications "$DMG_STAGING/Applications"
    
    rm -f "$DIST_DIR/$DMG_NAME"
    hdiutil create -volname "${APP_NAME}" -srcfolder "$DMG_STAGING" -ov -format UDZO "$DIST_DIR/$DMG_NAME"
    
    rm -rf "$DMG_STAGING"
    success "已创建: $DMG_NAME"
fi

# 显示结果
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                     构建完成!                               ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
info "构建产物位置: $PWD/$DIST_DIR"
echo ""
ls -lah "$DIST_DIR"
echo ""
success "All done! 🎉"
