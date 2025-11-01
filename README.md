# Pyright LSP WebSocket Bridge

WebSocket bridge for Pyright language server with bundled Node.js runtime.

## Build

### Single Platform (Linux x64)
```bash
./build.sh
```
Output: `output/linux-x64.tar.gz` (~34 MB)

### All Platforms
```bash
./build-all.sh
```
Outputs:
- `linux-x64.tar.gz` / `linux-arm64.tar.gz`
- `darwin-x64.tar.gz` / `darwin-arm64.tar.gz`
- `win32-x64.zip`

## Deploy & Run

### Linux/macOS
```bash
# Extract
tar -xzf linux-x64.tar.gz

# Run
cd linux-x64
./start.sh \
  --port 9011 \
  --project-root /path/to/project \
  --jesse-relative-path jesse_folder_name \
  --bot-relative-path jesse-bot_folder_name
```

### Windows
```cmd
REM Extract linux-x64.zip, then:
cd linux-x64
start.bat --port 9011 --project-root C:\path\to\project --jesse-relative-path jesse_folder_name  --bot-relative-path jesse-bot_folder_nam
```

## Features

- ✅ Bundled Node.js runtime (no system dependencies)
- ✅ Optimized build (~70% size reduction)
- ✅ Cross-platform support (Linux, macOS, Windows)
- ✅ Production-ready dependencies only

## Development

```bash
npm install
npm start -- --port 9011 --project-root /path/to/project ...
```

