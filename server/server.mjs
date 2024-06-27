import express from 'express'
import fetch from 'node-fetch'

const app = express()
const port = 3000

let cache = {
	USD: null,
	EUR: null,
	EURUSD: null,
	lastUpdate: null,
}

const fetchRates = async () => {
	const responseUSD = await fetch(
		'https://v6.exchangerate-api.com/v6/{API}/latest/USD'
	)
	const dataUSD = await responseUSD.json()
	const exchangeRateUSD = dataUSD.conversion_rates.RUB

	const responseEUR = await fetch(
		'https://v6.exchangerate-api.com/v6/{API}/latest/EUR'
	)
	const dataEUR = await responseEUR.json()
	const exchangeRateEUR = dataEUR.conversion_rates.RUB

	const responseEURUSD = await fetch(
		'https://v6.exchangerate-api.com/v6/{API}/latest/USD'
	)
	const dataEURUSD = await responseEURUSD.json()
	const exchangeRateEURUSD = dataEURUSD.conversion_rates.EUR

	cache = {
		USD: exchangeRateUSD,
		EUR: exchangeRateEUR,
		EURUSD: exchangeRateEURUSD,
		lastUpdate: new Date(),
	}
}

//update data
fetchRates()

setInterval(fetchRates, 24 * 60 * 60 * 1000)

app.get('/rates', (req, res) => {
	res.json(cache)
})

app.listen(port, () => {
	console.log(`Server is running on http://localhost:${port}`)
})
