# MODULE CRAWLER GIÁ XĂNG DẦU THỰC TẾ (2022–2024)

## 1. TỔNG QUAN
Thư mục này chứa mã nguồn trích xuất dữ liệu giá xăng dầu thực tế từ FRED / U.S. EIA phục vụ trực tiếp cho pipeline nạp Staging & DWH (SSIS và Power BI).

> **Lưu ý kiến trúc:** Luồng dữ liệu chạy trực tiếp theo chu trình:
> `FRED API / EIA` → `fuel_crawler.py` → xuất file `data/fuel/fuel_market_rates_2022_2024.csv` → SSIS nạp thẳng vào `Stg_Market_Fuel_Rates` (Logistics_Staging).
> Phần Web API localhost (FastAPI) đã được gỡ bỏ để tinh giản kiến trúc theo định hướng SSIS thuần túy.

### Thành phần:
* **`fuel_crawler.py`**: Module Python cào chuỗi thời gian giá dầu On-Highway Diesel từ U.S. EIA / FRED, mở rộng theo ngày bằng phương pháp Forward-Fill (giữ nguyên biểu giá Thứ 2 áp dụng cho cả tuần theo chuẩn logistics) cho 25 thành phố tác nghiệp (27.400 dòng, 2022–2024), xuất ra `data/fuel/fuel_market_rates_2022_2024.csv` và `.json`. Có cơ chế dự phòng offline.
* **`requirements.txt`**: Danh sách thư viện phụ thuộc (`pandas`, `requests`).

---

## 2. HƯỚNG DẪN CÀI ĐẶT & CHẠY

### Bước 1: Cài đặt thư viện
```bash
pip install -r mock_api/requirements.txt
```

### Bước 2: Chạy crawler làm mới dữ liệu
```bash
python mock_api/fuel_crawler.py
```
Dữ liệu được lưu trực tiếp vào thư mục `data/fuel/`. SSIS package `ETL_Fleet_Maintenance_Fuel.dtsx` sẽ tự động đọc file CSV này để nạp vào hệ thống.
