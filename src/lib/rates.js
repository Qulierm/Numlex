// Exchange rates polling, ported from the legacy src/script.js.
// The rate server is an optional standalone service (see server/About.md);
// when unreachable, currency conversions are silently skipped.

const RATES_URL = 'http://80.90.182.109:3000/rates'

export function createRates(initial = { USD: null, EUR: null, EURUSD: null }) {
	return {
		value: initial,
		load: async () => {
			try {
				const response = await fetch(RATES_URL, { signal: AbortSignal.timeout(5000) })
				const data = await response.json()
				this.value = { USD: data.USD, EUR: data.EUR, EURUSD: data.EURUSD }
			} catch {
				// API unavailable — currency conversions will be skipped
			}
		},
	}
}

export const RATES_INTERVAL_MS = 60 * 60 * 1000
