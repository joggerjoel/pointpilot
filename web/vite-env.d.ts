/// <reference types="vite/client" />

interface ImportMetaEnv {
  readonly VITE_ELEVENLABS_BACKEND_URL: string
  readonly VITE_ELEVENLABS_AGENT_ID: string
}

interface ImportMeta {
  readonly env: ImportMetaEnv
}
