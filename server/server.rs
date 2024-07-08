use actix_web::{web, App, HttpServer, Responder};
use reqwest;
use serde::{Deserialize, Serialize};
use std::sync::Mutex;
use tokio::time::{self, Duration};
use std::sync::Arc;

#[derive(Deserialize, Clone)]
struct ExchangeRateResponse {
    conversion_rates: ConversionRates,
}

#[derive(Deserialize, Clone)]
struct ConversionRates {
    RUB: f64,
    EUR: Option<f64>, // Optional because we only need this for EURUSD
}

#[derive(Clone, Serialize)]
struct Cache {
    USD: Option<f64>,
    EUR: Option<f64>,
    EURUSD: Option<f64>,
    last_update: Option<std::time::SystemTime>,
}

impl Cache {
    fn new() -> Self {
        Cache {
            USD: None,
            EUR: None,
            EURUSD: None,
            last_update: None,
        }
    }
}

struct AppState {
    cache: Mutex<Cache>,
}

async fn fetch_rates(data: web::Data<Arc<AppState>>) -> Result<(), reqwest::Error> {
    let response_usd = reqwest::get("https://v6.exchangerate-api.com/v6/{API}/latest/USD").await?;
    let data_usd: ExchangeRateResponse = response_usd.json().await?;
    let exchange_rate_usd = data_usd.conversion_rates.RUB;

    let response_eur = reqwest::get("https://v6.exchangerate-api.com/v6/{API}/latest/EUR").await?;
    let data_eur: ExchangeRateResponse = response_eur.json().await?;
    let exchange_rate_eur = data_eur.conversion_rates.RUB;

    let response_eur_usd = reqwest::get("https://v6.exchangerate-api.com/v6/{API}/latest/USD").await?;
    let data_eur_usd: ExchangeRateResponse = response_eur_usd.json().await?;
    let exchange_rate_eur_usd = data_eur_usd.conversion_rates.EUR.unwrap();

    let mut cache = data.cache.lock().unwrap();
    cache.USD = Some(exchange_rate_usd);
    cache.EUR = Some(exchange_rate_eur);
    cache.EURUSD = Some(exchange_rate_eur_usd);
    cache.last_update = Some(std::time::SystemTime::now());

    Ok(())
}

async fn rates(data: web::Data<Arc<AppState>>) -> impl Responder {
    let cache = data.cache.lock().unwrap();
    web::Json(cache.clone())
}

#[actix_web::main]
async fn main() -> std::io::Result<()> {
    let cache = Cache::new();
    let data = Arc::new(AppState {
        cache: Mutex::new(cache),
    });

    // Fetch rates initially
    fetch_rates(web::Data::new(data.clone())).await.unwrap();

    // Schedule rate fetching every 24 hours
    let data_clone = data.clone();
    tokio::spawn(async move {
        let mut interval = time::interval(Duration::from_secs(24 * 60 * 60));
        loop {
            interval.tick().await;
            fetch_rates(web::Data::new(data_clone.clone())).await.unwrap();
        }
    });

    HttpServer::new(move || {
        App::new()
            .app_data(web::Data::new(data.clone()))
            .route("/rates", web::get().to(rates))
    })
        .bind(("127.0.0.1", 3000))?
        .run()
        .await
}
