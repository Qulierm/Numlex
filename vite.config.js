import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

// Tauri expects a fixed dev server port and no auto-open.
export default defineConfig({
	plugins: [react()],
	test: {
		environment: 'node',
		include: ['src/**/*.test.js'],
	},
	clearScreen: false,
	server: {
		port: 1420,
		strictPort: true,
	},
	envPrefix: ['VITE_', 'TAURI_'],
	build: {
		// Tauri uses a modern webview target.
		target: ['es2022', 'chrome100', 'safari16'],
		minify: !process.env.TAURI_DEBUG ? 'esbuild' : false,
	},
})
