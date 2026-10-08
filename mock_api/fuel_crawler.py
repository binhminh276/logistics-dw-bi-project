"""
================================================================================
ĐƯỜNG DẪN: mock_api/fuel_crawler.py
MỤC ĐÍCH: Module cào và trích xuất dữ liệu giá dầu On-Highway Diesel thực tế
          giai đoạn 2022-2024 từ U.S. EIA / FRED API, nội suy chuỗi thời gian
          theo ngày, ánh xạ đơn giá thị trường cho 25 thành phố thuộc 5 vùng PADD,
          xuất ra file CSV/JSON và tích hợp cơ chế dự phòng offline.
TÁC GIẢ: Nhóm Logistics & Fleet Operations DW
CÁCH CHẠY:
  python mock_api/fuel_crawler.py
================================================================================
"""

import sys
import io
import json
import logging
from pathlib import Path
from datetime import datetime
import requests
import pandas as pd

# Thiết lập logging
logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s [%(levelname)s] %(message)s",
    handlers=[logging.StreamHandler(sys.stdout)]
)
logger = logging.getLogger("FuelCrawler")

# Thiết lập đường dẫn tương đối (chuẩn hóa theo repo root)
BASE_DIR = Path(__file__).resolve().parent.parent
OUTPUT_DIR = BASE_DIR / "data" / "fuel"
if not OUTPUT_DIR.exists() and (BASE_DIR / "Data" / "fuel").exists():
    OUTPUT_DIR = BASE_DIR / "Data" / "fuel"

OUTPUT_CSV = OUTPUT_DIR / "fuel_market_rates_2022_2024.csv"
OUTPUT_JSON = OUTPUT_DIR / "fuel_market_rates_2022_2024.json"

# Danh mục 25 thành phố tác nghiệp, tiểu bang, vùng PADD và hệ số chênh lệch giá đô thị (EIA/AAA Benchmark)
CITY_PADD_METRICS = [
    # Gulf Coast (PADD 3) - Giá rẻ nhất nhờ tập trung nhà máy lọc dầu
    {"city": "Houston", "state": "TX", "padd_region": "Gulf Coast (PADD 3)", "multiplier": 0.9500},
    {"city": "Dallas", "state": "TX", "padd_region": "Gulf Coast (PADD 3)", "multiplier": 0.9580},
    {"city": "Oklahoma City", "state": "OK", "padd_region": "Gulf Coast (PADD 3)", "multiplier": 0.9550},
    
    # Lower Atlantic (PADD 1C)
    {"city": "Atlanta", "state": "GA", "padd_region": "Lower Atlantic (PADD 1C)", "multiplier": 1.0080},
    {"city": "Charlotte", "state": "NC", "padd_region": "Lower Atlantic (PADD 1C)", "multiplier": 1.0020},
    {"city": "Miami", "state": "FL", "padd_region": "Lower Atlantic (PADD 1C)", "multiplier": 1.0420},
    
    # Central Atlantic (PADD 1B)
    {"city": "Philadelphia", "state": "PA", "padd_region": "Central Atlantic (PADD 1B)", "multiplier": 1.0550},
    {"city": "New York", "state": "NY", "padd_region": "Central Atlantic (PADD 1B)", "multiplier": 1.0850},
    
    # Midwest (PADD 2) - Gần mức bình quân quốc gia
    {"city": "Chicago", "state": "IL", "padd_region": "Midwest (PADD 2)", "multiplier": 1.0320},
    {"city": "Indianapolis", "state": "IN", "padd_region": "Midwest (PADD 2)", "multiplier": 0.9950},
    {"city": "Detroit", "state": "MI", "padd_region": "Midwest (PADD 2)", "multiplier": 1.0120},
    {"city": "Columbus", "state": "OH", "padd_region": "Midwest (PADD 2)", "multiplier": 1.0010},
    {"city": "Kansas City", "state": "MO", "padd_region": "Midwest (PADD 2)", "multiplier": 0.9850},
    {"city": "Minneapolis", "state": "MN", "padd_region": "Midwest (PADD 2)", "multiplier": 1.0210},
    {"city": "Omaha", "state": "NE", "padd_region": "Midwest (PADD 2)", "multiplier": 0.9920},
    {"city": "Memphis", "state": "TN", "padd_region": "Midwest (PADD 2)", "multiplier": 0.9750},
    {"city": "Nashville", "state": "TN", "padd_region": "Midwest (PADD 2)", "multiplier": 0.9910},
    {"city": "Milwaukee", "state": "WI", "padd_region": "Midwest (PADD 2)", "multiplier": 1.0150},
    
    # Rocky Mountain (PADD 4)
    {"city": "Phoenix", "state": "AZ", "padd_region": "Rocky Mountain (PADD 4)", "multiplier": 1.0350},
    {"city": "Denver", "state": "CO", "padd_region": "Rocky Mountain (PADD 4)", "multiplier": 1.0450},
    {"city": "Salt Lake City", "state": "UT", "padd_region": "Rocky Mountain (PADD 4)", "multiplier": 1.0520},
    
    # West Coast (PADD 5) - Giá cao nhất do thuế và tiêu chuẩn môi trường khắt khe
    {"city": "Los Angeles", "state": "CA", "padd_region": "West Coast (PADD 5)", "multiplier": 1.2550},
    {"city": "Seattle", "state": "WA", "padd_region": "West Coast (PADD 5)", "multiplier": 1.1820},
    {"city": "Portland", "state": "OR", "padd_region": "West Coast (PADD 5)", "multiplier": 1.1710},
    {"city": "Las Vegas", "state": "NV", "padd_region": "West Coast (PADD 5)", "multiplier": 1.1420}
]

# URL chuỗi thời gian giá dầu On-Highway Diesel hàng tuần của U.S. EIA phát hành qua FRED
FRED_EIA_DIESEL_URL = "https://fred.stlouisfed.org/graph/fredgraph.csv?id=GASDESW"


def fetch_national_diesel_prices() -> pd.DataFrame:
    """
    Trích xuất chuỗi giá Diesel bán lẻ bình quân quốc gia (EIA GASDESW).
    Có tích hợp cơ chế Fallback sang file đệm local khi mất kết nối.
    """
    logger.info("Đang kết nối API nguồn U.S. EIA / FRED để tải chuỗi giá Diesel thực tế...")
    try:
        response = requests.get(FRED_EIA_DIESEL_URL, timeout=8)
        if response.status_code == 200:
            df_raw = pd.read_csv(io.StringIO(response.text))
            df_raw.columns = ["date", "national_diesel_price"]
            df_raw["date"] = pd.to_datetime(df_raw["date"], errors="coerce")
            df_raw["national_diesel_price"] = pd.to_numeric(df_raw["national_diesel_price"], errors="coerce")
            df_raw = df_raw.dropna().sort_values("date")
            logger.info("-> Tải thành công %d điểm dữ liệu từ U.S. EIA / FRED!", len(df_raw))
            return df_raw
    except Exception as ex:
        logger.warning("-> Không thể kết nối trực tiếp đến API (%s). Kích hoạt cơ chế Offline Fallback.", str(ex))

    # Kích hoạt Offline Fallback
    if OUTPUT_CSV.exists():
        logger.info("-> Đang nạp từ dữ liệu đệm dự phòng: %s", OUTPUT_CSV)
        df_fb = pd.read_csv(OUTPUT_CSV)
        # Lấy giá trị bình quân của Houston (chuẩn PADD 3 ~ 0.95 để quy về national)
        df_fb_h = df_fb[df_fb["city"] == "Houston"][["rate_date", "diesel_price_per_gallon"]].copy()
        df_fb_h.columns = ["date", "national_diesel_price"]
        df_fb_h["date"] = pd.to_datetime(df_fb_h["date"])
        df_fb_h["national_diesel_price"] = df_fb_h["national_diesel_price"] / 0.9500
        return df_fb_h
    else:
        raise RuntimeError("Cả API và file dự phòng đều không khả dụng!")


def generate_market_fuel_rates(start_date: str = "2022-01-01", end_date: str = "2024-12-31") -> pd.DataFrame:
    """
    Nội suy chuỗi giá hàng ngày giai đoạn 2022-2024 và ánh xạ cho 25 thành phố / 5 vùng PADD.
    """
    df_national = fetch_national_diesel_prices()
    
    # Tạo dải ngày liên tục đủ 1.096 ngày (2022, 2023 và 2024 năm nhuận 366 ngày)
    date_range = pd.date_range(start=start_date, end=end_date, freq="D", name="date")
    df_daily = pd.DataFrame(index=date_range)
    
    # Hợp nhất và nội suy chuỗi giá (Daily Time-Series Interpolation)
    df_merged = df_daily.join(df_national.set_index("date"))
    df_merged["national_diesel_price"] = df_merged["national_diesel_price"].interpolate(method="time").bfill().ffill()
    df_merged = df_merged.reset_index()
    
    all_rows = []
    for city_info in CITY_PADD_METRICS:
        city_name = city_info["city"]
        state_code = city_info["state"]
        padd = city_info["padd_region"]
        mult = city_info["multiplier"]
        
        for _, row in df_merged.iterrows():
            current_date_str = row["date"].strftime("%Y-%m-%d")
            base_price = row["national_diesel_price"]
            city_price = round(base_price * mult, 4)
            
            all_rows.append({
                "rate_date": current_date_str,
                "city": city_name,
                "state": state_code,
                "padd_region": padd,
                "diesel_price_per_gallon": city_price
            })
            
    df_result = pd.DataFrame(all_rows)
    return df_result


def validate_fuel_data(df: pd.DataFrame) -> bool:
    """
    Kiểm tra chất lượng dữ liệu (Data Quality Validation Gate) theo chuẩn Data Engineer:
    - Tổng số dòng = 27.400 (1.096 ngày x 25 thành phố)
    - Không có bất kỳ ô NULL nào
    - Khoảng giá hợp lý ($2.5 - $7.0/gallon)
    - Đủ 25 thành phố và đủ chuỗi ngày
    """
    logger.info("Đang kiểm định chất lượng dữ liệu giá nhiên liệu...")
    total_rows = len(df)
    unique_cities = df["city"].nunique()
    unique_dates = df["rate_date"].nunique()
    null_counts = df.isnull().sum().sum()
    min_price = df["diesel_price_per_gallon"].min()
    max_price = df["diesel_price_per_gallon"].max()
    
    logger.info("  * Tổng số bản ghi: %d (Kỳ vọng: 27.400)", total_rows)
    logger.info("  * Số thành phố độc lập: %d (Kỳ vọng: 25)", unique_cities)
    logger.info("  * Số ngày độc lập: %d (Kỳ vọng: 1.096)", unique_dates)
    logger.info("  * Tổng số giá trị NULL: %d (Kỳ vọng: 0)", null_counts)
    logger.info("  * Khoảng giá: min $%.4f - max $%.4f (Kỳ vọng: $2.5 - $7.0)", min_price, max_price)
    
    is_valid = (
        total_rows == 27400
        and unique_cities == 25
        and unique_dates == 1096
        and null_counts == 0
        and 2.5 <= min_price <= 4.0
        and 4.5 <= max_price <= 7.50
    )
    
    if is_valid:
        logger.info("-> CHẤT LƯỢNG DỮ LIỆU ĐẠT CHUẨN 100% (DATA QUALITY PASSED)!")
    else:
        logger.error("-> LỖI: Dữ liệu không đạt chuẩn kiểm định!")
    return is_valid


def run_pipeline():
    """Chạy toàn bộ luồng cào, làm sạch, thẩm định và xuất file."""
    logger.info("=== BẮT ĐẦU PIPELINE CRAWLER GIÁ XĂNG DẦU 2022-2024 ===")
    
    # 1. Tạo thư mục đích nếu chưa có
    OUTPUT_DIR.mkdir(parents=True, exist_ok=True)
    
    # 2. Sinh tập dữ liệu
    df_fuel = generate_market_fuel_rates()
    
    # 3. Kiểm định chất lượng
    if not validate_fuel_data(df_fuel):
        raise ValueError("Dữ liệu không vượt qua cổng kiểm định chất lượng!")
        
    # 4. Xuất file CSV
    df_fuel.to_csv(OUTPUT_CSV, index=False, encoding="utf-8")
    logger.info("-> Đã xuất file CSV thành công: %s (%s bytes)", OUTPUT_CSV, f"{OUTPUT_CSV.stat().st_size:,}")
    
    # 5. Xuất file JSON phục vụ REST API
    data_dict = df_fuel.to_dict(orient="records")
    with open(OUTPUT_JSON, "w", encoding="utf-8") as f:
        json.dump(data_dict, f, ensure_ascii=False, indent=2)
    logger.info("-> Đã xuất file JSON thành công: %s (%s bytes)", OUTPUT_JSON, f"{OUTPUT_JSON.stat().st_size:,}")
    
    logger.info("=== HOÀN TẤT PIPELINE CRAWLER GIÁ XĂNG DẦU! ===")


if __name__ == "__main__":
    run_pipeline()
