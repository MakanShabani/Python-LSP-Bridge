import { spawn } from 'child_process'
import { WebSocketServer } from 'ws'
import { toSocket, WebSocketMessageReader, WebSocketMessageWriter } from 'vscode-ws-jsonrpc'
import { StreamMessageReader, StreamMessageWriter } from 'vscode-jsonrpc/node.js'
import { readFileSync, writeFileSync, existsSync } from 'fs'
import path, { dirname, join } from 'path'
import { fileURLToPath } from 'url'

import 'dotenv/config'

// Get the directory where bundle.js is located (not cwd)
const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

// Parse command-line arguments
function parseArgs() {
    const args = process.argv.slice(2)
    const parsed: Record<string, string> = {}
    
    for (let i = 0; i < args.length; i++) {
        if (args[i].startsWith('--')) {
            const key = args[i].slice(2)
            const value = args[i + 1]
            if (value && !value.startsWith('--')) {
                parsed[key] = value
                i++
            }
        }
    }
    
    return parsed
}

// Production-ready configuration
// Usage: node index.js --port <PORT> --project-root <PROJECT_ROOT> --jesse-relative-path <JESSE_PATH> --bot-relative-path <BOT_PATH>
// Example: node index.js --port 9011 --project-root /home/king/jesse/jesse-ai --jesse-relative-path jesse/jesse --bot-relative-path jesse-bot
const args = parseArgs()
const PYRIGHT_WS_PORT = Number(args['port'])
const BOT_ROOT = args['bot-root']
const JESSE_ROOT = args['jesse-root']
const PYRIGHT_PATH = join(__dirname, 'node_modules/pyright/dist/pyright-langserver.js')

// Deploy pyrightconfig.json to the Jesse workspace on startup
function deployPyrightConfig() {
    const templatePath = join(__dirname, 'pyrightconfig.json')
    const targetPath = join(BOT_ROOT, 'pyrightconfig.json')
    
    if (!existsSync(templatePath)) {
        console.warn(`Warning: No pyrightconfig.json template found at ${templatePath}`)
        return
    }
    
    // Read template and replace variables
    let config = readFileSync(templatePath, 'utf-8')
    config = config.replace(/\$\{BOT_ROOT\}/g, BOT_ROOT)
    config = config.replace(/\$\{JESSE_ROOT\}/g, JESSE_ROOT || '')
    
    // Write to workspace
    writeFileSync(targetPath, config)
    console.log(`Deployed pyrightconfig.json to ${targetPath}`)
}



export function startPyrightBridge() {
        

        if (!PYRIGHT_WS_PORT || !BOT_ROOT || !JESSE_ROOT) {
            console.error('Error: --port and --bot-root and --jesse-root are required')
            console.error('Usage: npx tsx index.ts --port <PORT> --bot-root <BOT_ROOT> --jesse-root <JESSE_ROOT>')
            process.exit(1)
        }

        // Deploy config before starting the server
        deployPyrightConfig()
        
        const wss = new WebSocketServer({ port: PYRIGHT_WS_PORT, path: '/lsp'})
        console.log(`Pyright WS bridge running on ws://localhost:${PYRIGHT_WS_PORT}/lsp`)
        console.log(`Execution root: ${BOT_ROOT}`)

        wss.on('connection', (ws) => {
        console.log('Client connected, spawning Pyright...')

        // Spawn a new Pyright instance for THIS connection
        // Set cwd to the project root so Pyright can find pyrightconfig.json and .venv
        console.log(`Spawning Pyright with cwd: ${BOT_ROOT}`)

        const pyright = spawn('node', [PYRIGHT_PATH, '--stdio'], {
            cwd: BOT_ROOT,
            env: process.env
        })

        console.log('Pyright spawned, setting up message readers/writers...')

        const reader = new StreamMessageReader(pyright.stdout)
        const writer = new StreamMessageWriter(pyright.stdin)

        const socket = toSocket(ws as any)
        const wsReader = new WebSocketMessageReader(socket)
        const wsWriter = new WebSocketMessageWriter(socket)

        // pipe WS -> Pyright
        wsReader.listen((msg: any) => {
            console.log('→ Client to Pyright:', JSON.stringify(msg).substring(0, 200))
            
            // Auto-inject rootUri in initialize request
        if (msg.method === 'initialize') {
                console.log('🔧 Auto-injecting project configuration')
                
                msg.params = msg.params || {}
                msg.params.rootUri = `file://${BOT_ROOT}`
                msg.params.workspaceFolders = [
                {
                    uri: `file://${BOT_ROOT}`,
                    name: 'jesse-ai'
                }
                ]
                
                console.log('✓ rootUri:', msg.params.rootUri)
            }
      
        // Auto-convert relative file URIs to absolute
        if (msg.params?.textDocument?.uri) {
            const uri = msg.params.textDocument.uri
            
            // If not already absolute, make it absolute
            if (!uri.startsWith('file://')) {
                msg.params.textDocument.uri = `file://${path.join(BOT_ROOT, uri)}`
                }
            }

            writer.write(msg)
        })

        // pipe Pyright -> WS
        reader.listen((msg: any) => {
            console.log('← Pyright to Client:', JSON.stringify(msg).substring(0, 200))
            wsWriter.write(msg)
        })

        // Cleanup on disconnect
        ws.on('close', () => {
            console.log('Client disconnected, killing Pyright...')
            pyright.kill()
        })

        // Handle errors
        pyright.on('error', (err) => {
            console.error('Pyright process error:', err)
            ws.close()
        })

        pyright.stderr.on('data', (data) => {
            console.error('Pyright stderr:', data.toString())
        })
    })

}
