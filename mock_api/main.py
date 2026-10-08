"""
================================================================================
ĐƯỜNG DẪN: mock_api/main.py
MỤC ĐÍCH: Dịch vụ REST API (FastAPI) cung cấp dữ liệu giá xăng dầu thực tế
          2022-2024 phục vụ SSIS Pipeline và Apache Airflow truy vấn theo ngày,
          thành phố và vùng PADD.
          Hỗ trợ đầy đủ các endpoint:
          - /api/fuel-rates (Chuẩn RESTful có phân trang và lọc khoảng ngày)
          - /api/fuel-prices/range (Truy vấn theo dải ngày)
          - /api/fuel-prices (Tương thích ngược với mock_api ban đầu)
          - /api/health (Kiểm tra trạng thái)
TÁC GIẢ: Nhóm Logistics & Fleet Operations DW
CÁCH CHẠY:
  uvicorn mock_api.main:app --reload --host 0.0.0.0 --port 8000
  Hoặc: python mock_api/main.py
================================================================================
"""

import sys
import logging
from pathlib import Path
from datetime import date
from typing import Optional, List, Dict, Any
from fastapi import FastAPI, Query, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel, Field
import pandas as pd
import uvicorn

# Thiết lập logging
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("FuelAPI")

# Định vị đường dẫn dữ liệu
BASE_DIR = Path(__file__).resolve().parent.parent
FUEL_CSV = BASE_DIR / "data" / "fuel" / "fuel_market_rates_2022_2024.csv"
if not FUEL_CSV.exists() and (BASE_DIR / "Data" / "fuel" / "fuel_market_rates_2022_2024.csv").exists():
    FUEL_CSV = BASE_DIR / "Data" / "fuel" / "fuel_market_rates_2022_2024.csv"

# Khởi tạo FastAPI App
app = FastAPI(
    title="Logistics Fleet Fuel Rates REST API",
    description="Dịch vụ tra cứu đơn giá dầu On-Highway Diesel & Xăng thực tế (2022–2024) từ U.S. EIA / AAA phục vụ tính toán phụ phí & chi phí vận hành Fleet TCO.",
    version="1.0.0",
    docs_url="/docs",
    redoc_url="/redoc"
)

# Cấu hình CORS
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# Mô hình dữ liệu Pydantic
class FuelRateItem(BaseModel):
    rate_date: str = Field(..., example="2023-05-19", description="Ngày ghi nhận đơn giá (YYYY-MM-DD)")
    city: str = Field(..., example="Houston", description="Tên thành phố tác nghiệp")
    state: str = Field(..., example="TX", description="Mã 2 ký tự của tiểu bang")
    padd_region: str = Field(..., example="Gulf Coast (PADD 3)", description="Phân vùng thị trường PADD của EIA")
    diesel_price_per_gallon: float = Field(..., example=3.8542, description="Đơn giá dầu Diesel ($/gallon)")

class FuelRateResponse(BaseModel):
    total_records: int
    returned_records: int
    limit: int
    offset: int
    data: List[FuelRateItem]

class HealthStatus(BaseModel):
    status: str
    total_dataset_rows: int
    cities_count: int
    date_range_start: str
    date_range_end: str
    source: str

class LegacyPriceResponse(BaseModel):
    price_date: str
    fuel_type: str
    price_per_gallon: float
    region: str
    city: Optional[str] = None
    state: Optional[str] = None


# Nạp dữ liệu vào bộ nhớ RAM khi khởi động để tối ưu tốc độ phản hồi (< 2ms)
df_fuel_cache: Optional[pd.DataFrame] = None

def load_dataset() -> pd.DataFrame:
    global df_fuel_cache
    if not FUEL_CSV.exists():
        logger.error("Không tìm thấy tệp dữ liệu giá dầu tại: %s", FUEL_CSV)
        raise FileNotFoundError(f"Không tìm thấy tệp dữ liệu giá dầu tại {FUEL_CSV}")
    
    logger.info("Đang nạp dữ liệu giá dầu từ %s vào bộ nhớ RAM...", FUEL_CSV)
    df = pd.read_csv(FUEL_CSV)
    df["city_lower"] = df["city"].str.strip().str.lower()
    df["state_upper"] = df["state"].str.strip().str.upper()
    df_fuel_cache = df
    logger.info("-> Nạp thành công %d bản ghi giá dầu vào RAM.", len(df))
    return df_fuel_cache


@app.on_event("startup")
def startup_event():
    load_dataset()


@app.get("/", tags=["Info"])
def root_info():
    """Endpoint giới thiệu và điều hướng nhanh tới tài liệu Swagger."""
    return {
        "service": "Logistics Fleet Fuel Rates REST API",
        "status": "ONLINE",
        "documentation": "/docs",
        "endpoints": [
            "/api/fuel-rates",
            "/api/fuel-prices/range",
            "/api/fuel-prices",
            "/api/health"
        ]
    }


@app.get("/api/health", response_model=HealthStatus, tags=["Health Check"])
def get_health_status():
    """Kiểm tra tình trạng hoạt động của API và số lượng dữ liệu đã sẵn sàng."""
    global df_fuel_cache
    if df_fuel_cache is None:
        load_dataset()
        
    return HealthStatus(
        status="ONLINE",
        total_dataset_rows=len(df_fuel_cache),
        cities_count=df_fuel_cache["city"].nunique(),
        date_range_start=df_fuel_cache["rate_date"].min(),
        date_range_end=df_fuel_cache["rate_date"].max(),
        source="U.S. Energy Information Administration (EIA) / AAA Fuel Benchmarks"
    )


@app.get("/api/fuel-rates", response_model=FuelRateResponse, tags=["Fuel Rates Query"])
@app.get("/api/fuel-prices/range", response_model=FuelRateResponse, tags=["Fuel Rates Query"])
def query_fuel_rates(
    rate_date: Optional[str] = Query(None, alias="date", description="Lọc theo ngày (YYYY-MM-DD), ví dụ: 2023-05-19"),
    start_date: Optional[str] = Query(None, description="Lọc từ ngày (YYYY-MM-DD) khi truy vấn range"),
    end_date: Optional[str] = Query(None, description="Lọc đến ngày (YYYY-MM-DD) khi truy vấn range"),
    city: Optional[str] = Query(None, description="Lọc theo thành phố, ví dụ: Houston, Chicago, Los Angeles"),
    state: Optional[str] = Query(None, description="Lọc theo tiểu bang (2 ký tự), ví dụ: TX, IL, CA"),
    padd_region: Optional[str] = Query(None, description="Lọc theo vùng PADD, ví dụ: Gulf Coast (PADD 3)"),
    limit: int = Query(100, ge=1, le=5000, description="Giới hạn số bản ghi trả về mỗi trang (mặc định: 100, tối đa: 5000)"),
    offset: int = Query(0, ge=0, description="Vị trí bắt đầu lấy bản ghi (mặc định: 0)")
):
    """
    Truy vấn đơn giá nhiên liệu thị trường phục vụ tích hợp ETL (SSIS / Airflow):
    - Hỗ trợ cả 2 endpoint: /api/fuel-rates (chuẩn RESTful) và /api/fuel-prices/range.
    - Hỗ trợ lọc theo ngày cụ thể hoặc khoảng ngày (start_date -> end_date) và địa phương.
    - Hỗ trợ phân trang chuẩn RESTful (limit/offset).
    """
    global df_fuel_cache
    if df_fuel_cache is None:
        load_dataset()

    df_filtered = df_fuel_cache

    if rate_date:
        df_filtered = df_filtered[df_filtered["rate_date"] == rate_date.strip()]
    if start_date:
        df_filtered = df_filtered[df_filtered["rate_date"] >= start_date.strip()]
    if end_date:
        df_filtered = df_filtered[df_filtered["rate_date"] <= end_date.strip()]

    if city:
        city_clean = city.strip().lower()
        df_filtered = df_filtered[df_filtered["city_lower"] == city_clean]

    if state:
        state_clean = state.strip().upper()
        df_filtered = df_filtered[df_filtered["state_upper"] == state_clean]

    if padd_region:
        df_filtered = df_filtered[df_filtered["padd_region"].str.contains(padd_region.strip(), case=False, na=False)]

    total_matched = len(df_filtered)
    
    # Phân trang
    df_paged = df_filtered.iloc[offset : offset + limit]
    
    data_list = [
        FuelRateItem(
            rate_date=row["rate_date"],
            city=row["city"],
            state=row["state"],
            padd_region=row["padd_region"],
            diesel_price_per_gallon=float(row["diesel_price_per_gallon"])
        )
        for _, row in df_paged.iterrows()
    ]

    return FuelRateResponse(
        total_records=total_matched,
        returned_records=len(data_list),
        limit=limit,
        offset=offset,
        data=data_list
    )


@app.get("/api/fuel-prices", response_model=LegacyPriceResponse, tags=["Legacy Mock Compatibility"])
def get_fuel_price_legacy(
    query_date: str = Query(default=str(date.today()), description="Ngày cần tra cứu (YYYY-MM-DD)"),
    city: Optional[str] = Query(None, description="Tên thành phố (tùy chọn)")
):
    """
    Endpoint tương thích ngược với mock_api ban đầu.
    Trả về đơn giá thực tế từ dữ liệu 2022–2024 thay vì giá hardcode tĩnh.
    """
    global df_fuel_cache
    if df_fuel_cache is None:
        load_dataset()

    matched = df_fuel_cache[df_fuel_cache["rate_date"] == query_date.strip()]
    if matched.empty:
        # Nếu ngày ngoài phạm vi dataset, lấy ngày gần nhất
        matched = df_fuel_cache.tail(25)

    if city:
        city_matched = matched[matched["city_lower"] == city.strip().lower()]
        if not city_matched.empty:
            matched = city_matched

    row = matched.iloc[0]
    return LegacyPriceResponse(
        price_date=row["rate_date"],
        fuel_type="Diesel",
        price_per_gallon=float(row["diesel_price_per_gallon"]),
        region=row["padd_region"],
        city=row["city"],
        state=row["state"]
    )


if __name__ == "__main__":
    uvicorn.run("main:app", host="0.0.0.0", port=8000, reload=False)
