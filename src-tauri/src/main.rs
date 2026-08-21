#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use serde::{Deserialize, Serialize};
use std::sync::Mutex;
use std::time::Instant;

#[derive(Clone, Serialize, Deserialize, Default)]
struct Rates {
    USD: Option<f64>,
    EUR: Option<f64>,
    EURUSD: Option<f64>,
}

#[derive(Deserialize)]
struct ExchangeRateResponse {
    conversion_rates: ConversionRates,
}

#[derive(Deserialize)]
struct ConversionRates {
    RUB: f64,
    EUR: Option<f64>,
}

struct Cached {
    rates: Rates,
    fetched_at: Instant,
}

struct AppState {
    cache: Mutex<Option<Cached>>,
}

const CACHE_TTL_SECS: u64 = 60 * 60; // 1 hour

async fn fetch_rates_from_provider(api_key: &str) -> Result<Rates, String> {
    let client = reqwest::Client::builder()
        .timeout(std::time::Duration::from_secs(5))
        .build()
        .map_err(|e| e.to_string())?;

    // If the key looks like a full URL, use it directly; otherwise build exchangerate-api URL.
    // Environment variable NUMLEX_RATES_URL can be a full URL template with {API} placeholder.
    // NUMLEX_EXCHANGE_API_KEY is simpler: just the key.
    let url_template = std::env::var("NUMLEX_RATES_URL").unwrap_or_else(|_| "https://v6.exchangerate-api.com/v6/{API}/latest/USD".to_string());

    let fetch_one = |url: String, client: reqwest::Client| async move {
        let resp = client.get(&url).send().await.map_err(|e| e.to_string())?;
        let data: ExchangeRateResponse = resp.json().await.map_err(|e| e.to_string())?;
        Ok::<ExchangeRateResponse, String>(data)
    };

    // Build URLs for USD and EUR
    let usd_url = url_template.replace("{API}", api_key);
    let eur_url = if url_template.contains("USD") {
        url_template.replace("{API}", api_key).replace("USD", "EUR")
    } else {
        // Fallback: explicit EUR endpoint
        format!("https://v6.exchangerate-api.com/v6/{}/latest/EUR", api_key)
    };

    let data_usd = fetch_one(usd_url, client.clone()).await?;
    let data_eur = fetch_one(eur_url, client.clone()).await?;
    // EURUSD is EUR value when base is USD (converts USD->EUR)
    let eurusd = data_usd.conversion_rates.EUR;

    Ok(Rates {
        USD: Some(data_usd.conversion_rates.RUB),
        EUR: Some(data_eur.conversion_rates.RUB),
        EURUSD: eurusd,
    })
}

#[tauri::command]
async fn get_rates(state: tauri::State<'_, AppState>) -> Result<Rates, String> {
    // Return cached if fresh
    {
        let guard = state.cache.lock().map_err(|e| e.to_string())?;
        if let Some(cached) = guard.as_ref() {
            if cached.fetched_at.elapsed().as_secs() < CACHE_TTL_SECS {
                return Ok(cached.rates.clone());
            }
        }
    }

    // Try to fetch from provider if API key configured
    let api_key = std::env::var("NUMLEX_EXCHANGE_API_KEY")
        .or_else(|_| std::env::var("EXCHANGE_API_KEY"))
        .ok();

    let rates = if let Some(key) = api_key {
        if key.trim().is_empty() || key == "{API}" {
            Rates::default()
        } else {
            match fetch_rates_from_provider(&key).await {
                Ok(r) => r,
                Err(e) => {
                    eprintln!("[numlex] rates fetch failed: {}", e);
                    Rates::default()
                }
            }
        }
    } else {
        // No API key configured — rates unavailable gracefully. Frontend shows "Rates unavailable".
        Rates::default()
    };

    // Cache the result (even if unavailable, to avoid hammering)
    {
        let mut guard = state.cache.lock().map_err(|e| e.to_string())?;
        *guard = Some(Cached {
            rates: rates.clone(),
            fetched_at: Instant::now(),
        });
    }

    Ok(rates)
}

fn main() {
    tauri::Builder::default()
        .manage(AppState {
            cache: Mutex::new(None),
        })
        .invoke_handler(tauri::generate_handler![get_rates])
        .run(tauri::generate_context!())
        .expect("error while running Numlex");
}
