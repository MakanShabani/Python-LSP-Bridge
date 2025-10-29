import { spawn } from 'child_process'
import { WebSocketServer } from 'ws'
import { toSocket, WebSocketMessageReader, WebSocketMessageWriter } from 'vscode-ws-jsonrpc'
import { StreamMessageReader, StreamMessageWriter } from 'vscode-jsonrpc/node.js'
import { readFileSync, writeFileSync, existsSync } from 'fs'
import { join, dirname } from 'path'
import { fileURLToPath } from 'url'
import 'dotenv/config'

// Get the directory where this script is located
const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

// Production-ready configuration
const PYRIGHT_WS_PORT = Number(process.env.PYRIGHT_WS_PORT) || 3001
const PROJECT_ROOT = process.env.PROJECT_ROOT || '/fakeworkspace'
const PYRIGHT_PATH = process.env.PYRIGHT_PATH || 'node_modules/pyright/dist/pyright-langserver.js'

// Deploy pyrightconfig.json to the Jesse workspace on startup
function deployPyrightConfig() {
    const templatePath = join(__dirname, 'pyrightconfig.json')
    const targetPath = join(PROJECT_ROOT, 'pyrightconfig.json')
    
    if (!existsSync(templatePath)) {
        console.warn(`Warning: No pyrightconfig.json template found at ${templatePath}`)
        return
    }
    
    // Read template and replace variables
    let config = readFileSync(templatePath, 'utf-8')
    config = config.replace(/\$\{PROJECT_ROOT\}/g, PROJECT_ROOT)
    
    // Write to workspace
    writeFileSync(targetPath, config)
    console.log(`Deployed pyrightconfig.json to ${targetPath}`)
}



export function startPyrightBridge() {
        
        // Deploy config before starting the server
        deployPyrightConfig()
        
        const wss = new WebSocketServer({ port: PYRIGHT_WS_PORT })
        console.log(`Pyright WS bridge running on ws://localhost:${PYRIGHT_WS_PORT}`)
        console.log(`Ecosystem root: ${PROJECT_ROOT}`)

        wss.on('connection', (ws) => {
        console.log('Client connected, spawning Pyright...')

        // Spawn a new Pyright instance for THIS connection
        // Set cwd to the project root so Pyright can find pyrightconfig.json and .venv
        console.log(`Spawning Pyright with cwd: ${PROJECT_ROOT}`)

        const pyright = spawn('node', [PYRIGHT_PATH, '--stdio'], {
            cwd: PROJECT_ROOT,
            env: {
            ...process.env,
            PYTHONPATH: `${PROJECT_ROOT}/.venv/lib/python3.12/site-packages`
            }
        })

        console.log('Pyright spawned, setting up message readers/writers...')

        const reader = new StreamMessageReader(pyright.stdout)
        const writer = new StreamMessageWriter(pyright.stdin)

        const socket = toSocket(ws as any)
        const wsReader = new WebSocketMessageReader(socket)
        const wsWriter = new WebSocketMessageWriter(socket)

        // pipe WS -> Pyright
        wsReader.listen((msg) => {
            console.log('→ Client to Pyright:', JSON.stringify(msg).substring(0, 200))
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
