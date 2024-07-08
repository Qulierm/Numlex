// conversions.ts

export function kmToMeter(km: number): number {
	return parseFloat((km * 1000).toFixed(4))
}

export function meterToKm(meter: number): number {
	return parseFloat((meter / 1000).toFixed(4))
}

export function mileToKm(mile: number): number {
	return parseFloat((mile * 1.60934).toFixed(4))
}

export function kmToMile(km: number): number {
	return parseFloat((km / 1.60934).toFixed(4))
}

export function cmToMeter(cm: number): number {
	return parseFloat((cm / 100).toFixed(4))
}

export function meterToCm(meter: number): number {
	return parseFloat((meter * 100).toFixed(4))
}

export function cmToKm(cm: number): number {
	return parseFloat((cm / 100000).toFixed(4))
}

export function kmToCm(km: number): number {
	return parseFloat((km * 100000).toFixed(4))
}

export function kgToTon(kg: number): number {
	return parseFloat((kg / 1000).toFixed(4))
}

export function tonToKg(ton: number): number {
	return parseFloat((ton * 1000).toFixed(4))
}

export function mgToKg(mg: number): number {
	return parseFloat((mg / 1000).toFixed(4))
}

export function kgToMg(kg: number): number {
	return parseFloat((kg * 1000).toFixed(4))
}

export function mlToTeaspoon(ml: number): number {
	return parseFloat((ml / 5).toFixed(4))
}

export function teaspoonToMl(teaspoon: number): number {
	return parseFloat((teaspoon * 5).toFixed(4))
}

export function literToMl(liters: number): number {
	return parseFloat((liters * 1000).toFixed(4))
}

export function mlToLiter(ml: number): number {
	return parseFloat((ml / 1000).toFixed(4))
}

export function fahrenheitToCelsius(F: number): number {
	return parseFloat((((F - 32) * 5) / 9).toFixed(4))
}

export function celsiusToFahrenheit(C: number): number {
	return parseFloat((C * 1.8 + 32).toFixed(4))
}

export function kelvinToCelsius(K: number): number {
	return parseFloat((K - 273.15).toFixed(4))
}

export function celsiusToKelvin(C: number): number {
	return parseFloat((C + 273.15).toFixed(4))
}
