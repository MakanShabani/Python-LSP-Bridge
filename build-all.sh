#!/bin/bash

# Multi-platform build script with optimizations
# Builds for all major platforms: Linux, macOS, Windows (x64 and ARM64)

set -e

NODE_VERSION="v20.11.0"

# Define all platforms
PLATFORMS=(
    "linux:x64"
    "linux:arm64"
    "darwin:x64"
    "darwin:arm64"
    "win32:x64"
)

echo "╔════════════════════════════════════════════════════════╗"
echo "║  Building Pyright LSP for ALL Platforms               ║"
echo "║  Node.js: ${NODE_VERSION}                             ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

# Clean previous builds
rm -rf output
mkdir -p output

# Function to build for a specific platform
build_platform() {
    local os=$1
    local arch=$2
    local platform="${os}-${arch}"
    
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "📦 Building for: ${platform}"
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    mkdir -p "output/${platform}"
    
    # Step 1: Bundle TypeScript with esbuild (same for all platforms)
    echo "📝 Bundling TypeScript..."
    npx esbuild index.ts \
      --bundle \
      --platform=node \
      --target=node18 \
      --format=esm \
      --outfile=output/${platform}/bundle.js \
      --external:ws \
      --external:vscode-ws-jsonrpc \
      --external:vscode-jsonrpc \
      --external:dotenv \
      --log-level=error
    
    if [ ! -f "output/${platform}/bundle.js" ]; then
        echo "❌ esbuild bundling failed for ${platform}!"
        return 1
    fi
    echo "✓ Bundled: bundle.js"
    
    # Step 2: Download and extract Node.js runtime
    echo "📥 Downloading Node.js ${NODE_VERSION} for ${platform}..."
    
    local node_pkg="node-${NODE_VERSION}-${os}-${arch}"
    local node_url="https://nodejs.org/dist/${NODE_VERSION}/${node_pkg}"
    
    if [ "$os" = "win32" ]; then
        # Windows uses .zip
        node_url="${node_url}.zip"
        local node_file="/tmp/${node_pkg}.zip"
        
        if [ ! -f "${node_file}" ]; then
            curl -L "${node_url}" -o "${node_file}" || {
                echo "❌ Failed to download Node.js for ${platform}"
                return 1
            }
        else
            echo "✓ Using cached Node.js"
        fi
        
        unzip -q "${node_file}" -d /tmp/
        mv "/tmp/${node_pkg}" "output/${platform}/node"
    else
        # Linux/macOS use .tar.gz
        node_url="${node_url}.tar.gz"
        local node_file="/tmp/${node_pkg}.tar.gz"
        
        if [ ! -f "${node_file}" ]; then
            curl -L "${node_url}" -o "${node_file}" || {
                echo "❌ Failed to download Node.js for ${platform}"
                return 1
            }
        else
            echo "✓ Using cached Node.js"
        fi
        
        tar -xzf "${node_file}" -C /tmp/
        mv "/tmp/${node_pkg}" "output/${platform}/node"
    fi
    echo "✓ Node.js extracted"
    
    # Step 3: Strip unnecessary files from Node.js
    echo "🧹 Optimizing Node.js runtime..."
    cd "output/${platform}/node"
    
    if [ "$os" = "win32" ]; then
        # Windows paths
        rm -rf node_modules/npm 2>/dev/null || true
        rm -rf node_modules/corepack 2>/dev/null || true
        rm -f npm npm.cmd npx npx.cmd corepack corepack.cmd 2>/dev/null || true
        rm -f *.md LICENSE 2>/dev/null || true
    else
        # Unix paths
        rm -rf lib/node_modules/npm 2>/dev/null || true
        rm -rf lib/node_modules/corepack 2>/dev/null || true
        rm -f bin/npm bin/npx bin/corepack 2>/dev/null || true
        rm -rf share/doc share/man share/systemtap 2>/dev/null || true
        rm -rf include 2>/dev/null || true
        rm -f *.md LICENSE 2>/dev/null || true
        
        # Strip debug symbols (Linux/macOS only)
        if command -v strip &> /dev/null; then
            strip bin/node 2>/dev/null || true
            echo "✓ Stripped debug symbols"
        fi
    fi
    
    cd ../../..
    echo "✓ Node.js optimized"
    
    # Step 4: Install production dependencies
    echo "📥 Installing production node_modules..."
    cp package.json output/${platform}/
    cd output/${platform}
    npm install --production --no-optional --silent
    rm package-lock.json
    echo '{"type":"module"}' > package.json
    echo "✓ Installed dependencies"
    
    # Step 5: Prune unnecessary files from node_modules
    echo "🧹 Pruning node_modules..."
    find node_modules -type d -name "test" -exec rm -rf {} + 2>/dev/null || true
    find node_modules -type d -name "tests" -exec rm -rf {} + 2>/dev/null || true
    find node_modules -type d -name "docs" -exec rm -rf {} + 2>/dev/null || true
    find node_modules -type d -name "examples" -exec rm -rf {} + 2>/dev/null || true
    find node_modules -type d -name "example" -exec rm -rf {} + 2>/dev/null || true
    find node_modules -type d -name ".github" -exec rm -rf {} + 2>/dev/null || true
    find node_modules -type d -name "coverage" -exec rm -rf {} + 2>/dev/null || true
    find node_modules -type d -name "benchmark" -exec rm -rf {} + 2>/dev/null || true
    find node_modules -type f -name "*.md" -delete 2>/dev/null || true
    find node_modules -type f -name "*.ts" ! -name "*.d.ts" -delete 2>/dev/null || true
    find node_modules -type f -name "*.map" -delete 2>/dev/null || true
    find node_modules -type f -name "LICENSE*" -delete 2>/dev/null || true
    find node_modules -type f -name "CHANGELOG*" -delete 2>/dev/null || true
    find node_modules -type f -name ".npmignore" -delete 2>/dev/null || true
    find node_modules -type f -name ".eslintrc*" -delete 2>/dev/null || true
    find node_modules -type f -name ".prettierrc*" -delete 2>/dev/null || true
    find node_modules -type f -name "tsconfig.json" -delete 2>/dev/null || true
    echo "✓ Pruned node_modules"
    
    cd ../..
    
    # Step 6: Copy config template
    cp pyrightconfig.json output/${platform}/
    
    # Step 7: Create platform-specific start script
    if [ "$os" = "win32" ]; then
        # Windows .bat script
        cat > "output/${platform}/start.bat" << 'EOF'
@echo off
REM Pyright LSP WebSocket Bridge - Windows
REM Usage: start.bat --port <PORT> --project-root <ROOT> --jesse-relative-path <JESSE> --bot-relative-path <BOT>

set DIR=%~dp0
"%DIR%node\node.exe" "%DIR%bundle.js" %*
EOF
        echo "✓ Created start.bat"
    else
        # Unix/Mac bash script
        cat > "output/${platform}/start.sh" << 'EOF'
#!/bin/bash
# Pyright LSP WebSocket Bridge - Unix/Mac
# Usage: ./start.sh --port <PORT> --project-root <ROOT> --jesse-relative-path <JESSE> --bot-relative-path <BOT>

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
"${DIR}/node/bin/node" "${DIR}/bundle.js" "$@"
EOF
        chmod +x "output/${platform}/start.sh"
        echo "✓ Created start.sh"
    fi
    
    # Step 8: Create compressed archive
    echo "📦 Creating compressed archive..."
    cd output
    
    # Get size before compression
    local dir_size=$(du -sh "${platform}" | cut -f1)
    
    if [ "$os" = "win32" ]; then
        # Create .zip for Windows
        if command -v zip &> /dev/null; then
            zip -rq "${platform}.zip" "${platform}/"
            echo "✓ Created ${platform}.zip"
            local archive_size=$(du -sh "${platform}.zip" | cut -f1)
        else
            tar -czf "${platform}.tar.gz" "${platform}/"
            echo "✓ Created ${platform}.tar.gz (zip not available)"
            local archive_size=$(du -sh "${platform}.tar.gz" | cut -f1)
        fi
    else
        # Create .tar.gz for Unix/Mac
        tar -czf "${platform}.tar.gz" "${platform}/"
        echo "✓ Created ${platform}.tar.gz"
        local archive_size=$(du -sh "${platform}.tar.gz" | cut -f1)
    fi
    
    # Remove extracted folder
    rm -rf "${platform}"
    echo "✓ Removed extracted folder"
    
    cd ..
    
    echo "✅ Build complete for ${platform}"
    echo "   Original: ${dir_size} → Compressed: ${archive_size}"
    echo ""
}

# Build for all platforms
for platform_pair in "${PLATFORMS[@]}"; do
    IFS=':' read -r os arch <<< "$platform_pair"
    build_platform "$os" "$arch" || echo "⚠️  Skipped ${os}-${arch} due to errors"
done

# Show summary
echo "╔════════════════════════════════════════════════════════╗"
echo "║  ✅ BUILD COMPLETE - All Platforms                     ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
echo "📦 Compressed archives (output/):"
for platform_pair in "${PLATFORMS[@]}"; do
    IFS=':' read -r os arch <<< "$platform_pair"
    local platform="${os}-${arch}"
    if [ -f "output/${platform}.tar.gz" ]; then
        local size=$(du -sh "output/${platform}.tar.gz" 2>/dev/null | cut -f1)
        printf "   %-30s %s\n" "${platform}.tar.gz" "${size}"
    elif [ -f "output/${platform}.zip" ]; then
        local size=$(du -sh "output/${platform}.zip" 2>/dev/null | cut -f1)
        printf "   %-30s %s\n" "${platform}.zip" "${size}"
    fi
done
echo ""
echo "📁 Each archive contains:"
echo "   - bundle.js (your bridge code)"
echo "   - node/ (optimized Node.js runtime)"
echo "   - node_modules/ (Pyright + pruned dependencies)"
echo "   - pyrightconfig.json (config template)"
echo "   - start.sh or start.bat (startup script)"
echo ""
echo "🚀 To deploy (Linux/macOS):"
echo "   1. Upload: scp output/linux-x64.tar.gz server:/opt/"
echo "   2. Extract: tar -xzf linux-x64.tar.gz"
echo "   3. Run: cd linux-x64 && ./start.sh --port 9011 --project-root /path ..."
echo ""
echo "🚀 To deploy (Windows):"
echo "   1. Extract: win32-x64.zip"
echo "   2. Run: cd win32-x64 && start.bat --port 9011 --project-root C:\\path ..."
echo ""
echo "💡 Platform guide:"
echo "   linux-x64    → Linux Intel/AMD (most servers, WSL)"
echo "   linux-arm64  → Linux ARM (Raspberry Pi, AWS Graviton)"
echo "   darwin-x64   → macOS Intel (older Macs)"
echo "   darwin-arm64 → macOS Apple Silicon (M1/M2/M3/M4)"
echo "   win32-x64    → Windows Intel/AMD"
echo ""

