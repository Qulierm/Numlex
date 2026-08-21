// Rates via Tauri Rust backend (secure, cached, env-configured).
// When the app runs in a browser without Tauri, rates remain unavailable gracefully.

export function createRates(initial = { USD: null, EUR: null, EURUSD: null }) {
	const obj = {
		value: { ...initial },
		load: async () => {
			try {
				// Dynamic import so web preview without Tauri does not crash
				const { invoke } = await import('@tauri-apps/api/core')
				const data = await invoke('get_rates')
				obj.value = {
					USD: data.USD ?? null,
					EUR: data.EUR ?? null,
					EURUSD: data.EURUSD ?? null,
				}
			} catch {
				// Tauri not available (browser preview) or rates unavailable — keep nulls
				// Currency conversions will show "Rates unavailable" instead of silent wrong results.
			}
		},
	}
	return obj
}

export const RATES_INTERVAL_MS = 60 * 60 * 1000
