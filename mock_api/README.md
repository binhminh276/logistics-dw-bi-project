# MODULE CRAWLER & REST API GIÁ XĂNG DẦU THỰC TẾ (2022–2024)

## 1. TỔNG QUAN
Thư mục này chứa toàn bộ mã nguồn trích xuất dữ liệu giá xăng dầu và dịch vụ REST API (FastAPI) phục vụ toàn bộ pipeline của dự án (SSIS, Airflow và Power BI).

### Thành phần:
* **`fuel_crawler.py`**: Module Python cào chuỗi thời gian giá dầu On-Highway Diesel từ U.S. EIA / FRED, nội suy theo ngày cho 25 thành phố tác nghiệp (27.400 dòng, 2022–2024), xuất ra `data/fuel/fuel_market_rates_2022_2024.csv` và `.json`. Có cơ chế dự phòng offline.
* **`main.py`**: Web API service chạy trên nền FastAPI, tải dữ liệu vào RAM khi khởi động để phản hồi cực nhanh (< 2ms).
* **`requirements.txt`**: Danh sách thư viện phụ thuộc (`fastapi`, `uvicorn`, `pandas`, `requests`, `pydantic`).

---

## 2. HƯỚNG DẪN CÀI ĐẶT & CHẠY

### Bước 1: Cài đặt thư viện
```bash
pip install -r mock_api/requirements.txt
```

### Bước 2: Chạy crawler làm mới dữ liệu (tùy chọn)
```bash
python mock_api/fuel_crawler.py
```

### Bước 3: Khởi động REST API Server
```bash
uvicorn mock_api.main:app --reload --host 0.0.0.0 --port 8000
```
Hoặc:
```bash
python mock_api/main.py
```

Truy cập tài liệu Swagger UI tương tác tại:
* `http://localhost:8000/docs`
* `http://localhost:8000/redoc`

---

## 3. DANH SÁCH ENDPOINTS CHÍNH

1. **`GET /api/fuel-rates`** (Chuẩn RESTful):
   * Lọc theo `date`, `start_date`, `end_date`, `city`, `state`, `padd_region`.
   * Hỗ trợ phân trang: `limit`, `offset`.
2. **`GET /api/fuel-prices/range`**:
   * Truy vấn khoảng ngày phục vụ SSIS / Airflow ETL.
3. **`GET /api/fuel-prices`**:
   * Tương thích ngược với endpoint mock_api cũ. Trả về đơn giá thực tế từ dữ liệu 2022–2024.
4. **`GET /api/health`**:
   * Kiểm tra tình trạng server, tổng số dòng và dải ngày dữ liệu.
