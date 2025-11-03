#!/bin/bash

# Build script using esbuild + bundled Node.js runtime
# Bundles all TypeScript into one JavaScript file, downloads Node.js

set -e

PLATFORM="linux-x64"
NODE_VERSION="v20.11.0"
NODE_ARCH="linux-x64"

echo "╔════════════════════════════════════════════════════════╗"
echo "║  Building Pyright LSP Bridge (esbuild + Node.js)      ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""

# Clean previous builds
echo "🧹 Cleaning previous builds..."
rm -rf output
mkdir -p output/${PLATFORM}

# Step 1: Bundle TypeScript into one JavaScript file with esbuild
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📦 Bundling TypeScript with esbuild..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

npx esbuild index.ts \
  --bundle \
  --platform=node \
  --target=node18 \
  --format=esm \
  --outfile=output/${PLATFORM}/bundle.js \
  --external:ws \
  --external:vscode-ws-jsonrpc \
  --external:vscode-jsonrpc \
  --external:dotenv

if [ ! -f "output/${PLATFORM}/bundle.js" ]; then
    echo "❌ esbuild bundling failed!"
    exit 1
fi
echo "✓ Bundled: output/${PLATFORM}/bundle.js"
echo ""

# Step 2: Download and extract Node.js runtime
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📥 Downloading Node.js ${NODE_VERSION} for ${NODE_ARCH}..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

NODE_PKG="node-${NODE_VERSION}-${NODE_ARCH}"
NODE_URL="https://nodejs.org/dist/${NODE_VERSION}/${NODE_PKG}.tar.gz"
NODE_FILE="/tmp/${NODE_PKG}.tar.gz"

if [ ! -f "${NODE_FILE}" ]; then
    curl -L "${NODE_URL}" -o "${NODE_FILE}" || {
        echo "❌ Failed to download Node.js"
        exit 1
    }
else
    echo "✓ Using cached Node.js"
fi

echo "📂 Extracting Node.js..."
tar -xzf "${NODE_FILE}" -C /tmp/
mv "/tmp/${NODE_PKG}" "output/${PLATFORM}/node"
echo "✓ Node.js extracted to output/${PLATFORM}/node"

# Strip unnecessary files from Node.js to reduce size
echo "🧹 Stripping unnecessary files from Node.js..."
cd "output/${PLATFORM}/node"

# Remove npm, npx, corepack (we don't need package managers at runtime)
rm -rf lib/node_modules/npm 2>/dev/null || true
rm -rf lib/node_modules/corepack 2>/dev/null || true
rm -f bin/npm bin/npx bin/corepack 2>/dev/null || true

# Remove docs and other non-essential files
rm -rf share/doc 2>/dev/null || true
rm -rf share/man 2>/dev/null || true
rm -rf share/systemtap 2>/dev/null || true
rm -rf include 2>/dev/null || true
rm -f README.md CHANGELOG.md LICENSE 2>/dev/null || true
rm -f *.md 2>/dev/null || true

# Strip debug symbols from node binary (optional, reduces size significantly)
if command -v strip &> /dev/null; then
    strip bin/node 2>/dev/null || true
    echo "✓ Stripped debug symbols from node binary"
fi

cd ../../..
echo "✓ Stripped unnecessary files from Node.js"
echo ""

# Step 3: Install production dependencies
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "📥 Installing production node_modules..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

cp package.json output/${PLATFORM}/
cd output/${PLATFORM}
npm install --production --no-optional
rm package-lock.json
echo '{"type":"module"}' > package.json
echo "✓ Installed production dependencies"
echo ""

# Step 3.5: Prune unnecessary files from node_modules
echo "🧹 Pruning unnecessary files from node_modules..."
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
echo "✓ Pruned unnecessary files"

cd ../..
echo ""

# Step 4: Copy config template
echo "📋 Copying pyrightconfig.json..."
cp pyrightconfig.json output/${PLATFORM}/
echo "✓ Copied config template"
echo ""

# Step 5: Create start script
echo "📝 Creating start script..."
cat > "output/${PLATFORM}/start.sh" << 'EOF'
#!/bin/bash
# Pyright LSP WebSocket Bridge
# Usage: ./start.sh --port <PORT> --project-root <ROOT> --jesse-relative-path <JESSE> --bot-relative-path <BOT>

DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
"${DIR}/node/bin/node" "${DIR}/bundle.js" "$@"
EOF
chmod +x "output/${PLATFORM}/start.sh"
echo "✓ Created start.sh"
echo ""

# Step 6: Create compressed archive
echo "📦 Creating compressed archive..."
cd output
tar -czf "${PLATFORM}.tar.gz" "${PLATFORM}/"
echo "✓ Created ${PLATFORM}.tar.gz"

# Get sizes before cleanup
DIR_SIZE=$(du -sh "${PLATFORM}" | cut -f1)
ARCHIVE_SIZE=$(du -sh "${PLATFORM}.tar.gz" | cut -f1)

# Remove extracted folder
rm -rf "${PLATFORM}"
echo "✓ Removed extracted folder"
cd ..
echo ""

# Show summary

echo "╔════════════════════════════════════════════════════════╗"
echo "║  ✅ BUILD COMPLETE                                     ║"
echo "╚════════════════════════════════════════════════════════╝"
echo ""
echo "📦 Compressed archive: output/${PLATFORM}.tar.gz"
echo "   Original size: ${DIR_SIZE}"
echo "   Compressed: ${ARCHIVE_SIZE}"
echo ""
echo "📁 Archive contains:"
echo "   - bundle.js (all your bridge code bundled)"
echo "   - node/ (Node.js ${NODE_VERSION} runtime, optimized)"
echo "   - node_modules/ (Pyright + pruned dependencies)"
echo "   - pyrightconfig.json (config template)"
echo "   - start.sh (startup script)"
echo ""
echo "🚀 To deploy:"
echo "   1. Upload: scp output/${PLATFORM}.tar.gz server:/opt/"
echo "   2. Extract: tar -xzf ${PLATFORM}.tar.gz"
echo "   3. Run: cd ${PLATFORM} && ./start.sh --port 9011 --project-root /path/to/project ..."
echo ""

