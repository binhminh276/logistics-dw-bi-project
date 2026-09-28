from fastapi import FastAPI
from datetime import date

app = FastAPI(title="Fuel Price Mock API")

@app.get("/api/fuel-prices")
def get_fuel_price(query_date: str = str(date.today())):
    return {
        "price_date": query_date,
        "fuel_type": "Diesel",
        "price_per_gallon": 3.85,
        "region": "US-National"
    }
