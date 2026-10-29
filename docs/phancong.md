# **KẾ HOẠCH TRIỂN KHAI, LUỒNG PIPELINE & PHÂN CÔNG CÔNG VIỆC DATA WAREHOUSE LOGISTICS**

## **(PHIÊN BẢN CHUẨN HÓA TOÀN DIỆN THEO THIẾT KẾ GALAXY SCHEMA & WEB CRAWLER THỰC TẾ)**

* **Chủ đề:** Hệ thống Kho dữ liệu Quản trị Vận tải, Tối ưu Chuỗi Giao nhận & Hiệu suất Đội xe (Logistics & Fleet Operations Enterprise Data Warehouse).
* **Mô hình kiến trúc:** **Galaxy Schema (Fact Constellation Schema - Mô hình Chòm sao)** chuẩn 4 bước của Ralph Kimball & Enterprise Bus Matrix.
* **Quy mô mô hình:** **4 Bảng Fact** (`Fact_Load`, `Fact_Trip`, `Fact_Delivery_Fulfillment`, `Fact_Maintenance`) liên kết với **9 Bảng Dimension** (bao gồm 2 Junk Dimensions và các Role-Playing Dimensions), triệt tiêu hoàn toàn rủi ro xung đột ngữ cảnh quan hệ và lỗi bẫy nhiều - nhiều.
* **Tập dữ liệu áp dụng:** Logistics and Fleet Operations Management Master Dataset (Giai đoạn 2022–2024; bao gồm các tệp nguồn: `loads`, `trips`, `delivery_events`, `maintenance`, `customers`, `facilities`, `drivers`, `trucks`, `trailers`, `routes`).
* **Cơ chế dữ liệu xăng dầu:** Script Python tự động cào và trích xuất dữ liệu giá nhiên liệu thực tế từ web (U.S. EIA / AAA Fuel Benchmarks) theo chuỗi thời gian 2022–2024 và danh mục 25 thành phố/tiểu bang tác nghiệp, cung cấp qua REST API và file đệm phục vụ tính toán phụ phí & chi phí vận hành (Fleet TCO).
* **Phân nhiệm 3 thành viên:**
  1. **Bình Minh (Trưởng nhóm):** Thiết kế Kiến trúc Galaxy Schema, Quản trị Staging/DWH, Khách hàng & Thương mại Đơn hàng (`Fact_Load`), Điều phối Báo cáo và Quản trị Dự án.
  2. **Phúc An:** Tích hợp Đa nguồn, Module Python Cào Dữ liệu Giá Xăng Dầu Thực tế & REST API, Kỹ thuật & Bảo dưỡng Đội xe (`Fact_Maintenance`), Cơ chế Incremental Load (CDC & High-Watermark).
  3. **Quang Duy:** Vận hành Chuyến xe (`Fact_Trip`), Chu trình Giao nhận Hai đầu bến (`Fact_Delivery_Fulfillment`), Tự động hóa Pipeline với Apache Airflow & Docker, Cấu hình SSAS Cube & Kịch bản phản biện Q&A.

---

## **PHẦN 1: LUỒNG DỰ ÁN CHI TIẾT & SẢN PHẨM ĐẦU RA (END-TO-END DATA PIPELINE)**

### **1.1. Danh mục sản phẩm đầu ra cuối cùng (Final Deliverables)**

Sau 4 tuần triển khai, nhóm sẽ hoàn tất và bàn giao hệ thống tích hợp khép kín gồm:

1. **Hệ thống Nguồn Dữ liệu Đa dạng (Multi-source Systems):**
   * **CSDL Nguồn OLTP (`Logistics_OLTP` trên SQL Server):** Lưu trữ các thực thể tác nghiệp cốt lõi (`Customers`, `Drivers`, `Trucks`, `Trailers`, `Loads`, `Trips`) được kích hoạt cơ chế **Change Data Capture (CDC)** để bắt biến động dữ liệu.
   * **Tập tin Nguồn Lịch sử (Flat Files CSV):** `facilities.csv`, `routes.csv`, `delivery_events.csv`, `maintenance_records.csv`.
   * **Module Python Web Crawler & REST API Giá Xăng Dầu Thực tế:** Kịch bản Python cào dữ liệu đơn giá nhiên liệu On-Highway Diesel & Gasoline thực tế từ cổng thông tin Năng lượng Hoa Kỳ (U.S. Energy Information Administration - EIA / AAA Fuel Gauge) giai đoạn 2022–2024 theo 25 thành phố/tiểu bang, đóng gói thành dịch vụ REST API (FastAPI) phục vụ ETL.
2. **Hệ thống Lưu trữ Kho dữ liệu (Storage Layers):**
   * **CSDL Vùng đệm `Logistics_Staging` (SQL Server):** Tối ưu hóa nạp dữ liệu tốc độ cao (Bulk Insert, vô hiệu hóa ràng buộc khóa ngoại), chứa các bảng đệm CDC, bảng tạm CSV và bảng giá nhiên liệu thị trường.
   * **CSDL Kho dữ liệu `Logistics_DW` (SQL Server):** Thiết kế chuẩn hóa theo mô hình **Galaxy Schema** gồm **4 Fact Tables** và **9 Dimensions** với hệ thống Surrogate Key đồng bộ.
3. **Pipeline Tích hợp Dữ liệu (ETL & Orchestration Pipeline):**
   * Bộ **SSIS Packages (.dtsx)** xử lý trích xuất, làm sạch chuỗi, Lookup Surrogate Keys, xử lý SCD Type 1 / Type 2, Accumulating Snapshot In-Flight Milestone Update và Incremental Load qua CDC / High-Watermark.
   * Môi trường **Apache Airflow** được đóng gói hoàn chỉnh bằng **Docker Compose**, tự động điều phối toàn trình: Kích hoạt Python Crawler $\rightarrow$ Nạp Staging $\rightarrow$ Kích hoạt SSIS Master Package $\rightarrow$ Process SSAS Cube $\rightarrow$ Ghi log kiểm toán.
4. **Mô hình Phân tích Đa chiều (OLAP Semantic Layer):**
   * Dự án **SSAS Multidimensional Cube** gồm 4 Measure Groups liên thông với 9 Dimensions, thiết lập Role-Playing Date Dimensions (`load_date_key`, `dispatch_date_key`, `pickup_date_key`, `delivery_date_key`, `maintenance_date_key`), phân cấp 2 nhánh độc lập cho `Dim_Route` và các Calculated Measures (DAX / MDX).
   * Bộ truy vấn đối soát và phân tích liên thông đa quy trình nghiệp vụ (**Cross-Fact Drill-Across**).
5. **Bộ Dashboard Trực quan hóa & Hồ sơ Nghiệm thu:**
   * Hệ thống **Power BI Dashboard** gồm 3 trang chuyên đề kết nối trực tiếp đến mô hình dữ liệu.
   * Báo cáo đồ án học thuật (Word/PDF), Sổ nhật ký phân công (Task Logbook) và Bảng tự đánh giá mức độ đóng góp công bằng ($33.3\%$ mỗi người), Slide thuyết trình và Bộ câu hỏi phản biện Q&A.

---

### **1.2. Luồng di chuyển dữ liệu (Data Lineage & Pipeline Flow)**

```
[Nguồn 1: SQL Server OLTP] (Loads, Trips, Drivers, Trucks, Trailers, Customers - Bật CDC)
[Nguồn 2: Flat Files CSV]   (Facilities, Routes, Delivery Events, Maintenance Records)
[Nguồn 3: Web Cào Thực tế] (Crawler Python cào giá xăng dầu EIA/AAA 2022-2024 -> REST API)
                                    │
                                    ▼
                     [TẦNG 1: TRÍCH XUẤT VÀO STAGING]
   - Cơ sở dữ liệu Logistics_Staging trên SQL Server
   - Bảng: Stg_CDC_Loads, Stg_CDC_Trips, Stg_External_CSV, Stg_Market_Fuel_Rates, ETL_Metadata
   - Không ràng buộc khóa ngoại, hỗ trợ Bulk Insert nạp nhanh song song
                                    │
                                    ▼
                     [TẦNG 2: BIẾN ĐỔI & NẠP VÀO DWH (SSIS)]
   - Chuẩn hóa text (TRIM, UPPER), phân giải xung đột địa lý bến bãi
   - Xử lý SCD Type 1 (Ghi đè) & SCD Type 2 (Tạo phiên bản dòng mới với Surrogate Key)
   - Lookup chuyển đổi Business Key thành Surrogate Key (Khóa mặc định -1 cho NULL/Pending)
   - Xử lý Accumulating Snapshot Fact_Delivery_Fulfillment (Cơ chế In-Flight: delivery_date_key = -1)
   - Nạp vào CSDL Logistics_DW (Galaxy Schema: 4 Fact Tables + 9 Dimensions)
                                    │
                                    ▼
                [TẦNG 3: ĐIỀU PHỐI TỰ ĐỘNG BẰNG APACHE AIRFLOW]
   - Docker Container vận hành Airflow Scheduler, Webserver, PostgreSQL
   - DAG tự động: Trigger Python Fuel Crawler -> Call SSIS Master -> Process Cube -> Alert Log
                                    │
                                    ▼
                 [TẦNG 4: MÔ HÌNH PHÂN TÍCH ĐA CHIỀU (SSAS CUBE)]
   - Galaxy Cube gồm 4 Measure Groups: Fact_Load, Fact_Trip, Fact_Fulfillment, Fact_Maintenance
   - Tách 2 nhánh User Hierarchies cho Dim_Route (Origin vs Destination) tránh lỗi N-N
   - Role-Playing Date Dimensions: Load Date, Dispatch Date, Pickup/Delivery Date, Maintenance Date
   - Calculated Measures: Net Revenue/lb, On-Time SLA Rate, Idle Time %, Trailer Health Check
                                    │
                                    ▼
                 [TẦNG 5: TRÌNH DIỄN & BÁO CÁO (POWER BI & SQL/MDX)]
   - 3 Trang Dashboard Power BI: Thương mại Đơn hàng, Vận hành Chuyến & SLA, Kỹ thuật & TCO Đội xe
   - Bộ truy vấn đối soát T-SQL và MDX Drill-Across liên kết Fact-to-Fact
```

---

## **PHẦN 2: MA TRẬN CÔNG CỤ & CHIẾN LƯỢC NẠP DỮ LIỆU**

### **2.1. Ma trận Công cụ Công nghệ theo từng Tầng Kiến trúc**

| Tầng kiến trúc / Quy trình | Công cụ / Công nghệ | Vai trò & Mục tiêu kỹ thuật |
| :--- | :--- | :--- |
| **1. Tầng Nguồn (Source Systems)** | Microsoft SQL Server 2019/2022 | CSDL giao dịch nghiệp vụ (`Logistics_OLTP`), kích hoạt **Change Data Capture (CDC)** trên bảng `Loads`, `Trips`, `Drivers`. |
| | Python 3.10+ (Requests, BeautifulSoup, FastAPI) | Script cào đơn giá nhiên liệu Diesel & Xăng thực tế theo ngày từ EIA/AAA (2022–2024) và đóng gói REST API. |
| | Flat Files (.csv) | Dữ liệu kho bãi (`facilities.csv`), tuyến đường (`routes.csv`), sự kiện dừng đỗ (`delivery_events.csv`), bảo dưỡng (`maintenance_records.csv`). |
| **2. Tầng Đệm (Staging Area)** | SQL Server (`Logistics_Staging`) | Chứa bảng trích xuất thô, bảng tạm CDC, bảng dữ liệu giá dầu cào từ web, bảng quản trị `ETL_Metadata` phục vụ Watermark tracking. |
| **3. Tầng Kho (Data Warehouse)** | SQL Server (`Logistics_DW`) | Lưu trữ **Galaxy Schema**: 4 Fact Tables (`Fact_Load`, `Fact_Trip`, `Fact_Delivery_Fulfillment`, `Fact_Maintenance`) và 9 Dimensions. Ràng buộc toàn vẹn $100\%$. |
| **4. Tầng Tích hợp (ETL Engine)** | SQL Server Integration Services (SSIS) | Pipeline ETL: SCD Transformation, CDC Splitter, Lookup Surrogate Keys, Derived Columns, In-Flight Accumulating Milestone Update. |
| **5. Tầng Điều phối (Orchestration)** | **Apache Airflow 2.x** trên **Docker Compose** | Tự động hóa lịch trình: kích hoạt Crawler/API, gọi SSIS qua `dtexec.exe`, ghi log kiểm toán và Process SSAS Cube. |
| **6. Tầng Đa chiều (OLAP Semantic)** | SSAS Multidimensional Cube | Xây dựng Galaxy Cube với 4 Measure Groups, Role-Playing Date Dimensions, User Hierarchies tách 2 nhánh độc lập cho Route. |
| **7. Báo cáo & Khai phá** | T-SQL Scripts & Truy vấn MDX | Trả lời các câu hỏi quản trị kinh doanh, tính toán chỉ số Drill-Across liên quy trình (Fleet TCO, Fulfillment Risk Ratio). |
| | Microsoft Power BI Desktop | Xây dựng 3 Dashboard chuyên đề kết nối Live / DirectQuery đến SSAS Cube và DW. |

---

### **2.2. Chi tiết các Chiến lược Nạp Dữ liệu (Load Strategies)**

Hệ thống thiết lập 4 chiến lược nạp dữ liệu chuyên biệt nhằm đáp ứng trọn vẹn điểm số tối đa của Rubric đánh giá ETL:

#### **A. Initial Load (Nạp Toàn bộ Lần đầu - Full Load)**
* **Đối tượng:** Bảng `Dim_Date` (sinh tự động 10 năm từ 2020 đến 2030), `Dim_Load_Profile` (Junk Dimension cố định), `Dim_Maintenance_Profile` (Junk Dimension) và toàn bộ các Dimension/Fact khi khởi tạo hệ thống.
* **Kỹ thuật:** Truncate Staging, sử dụng SSIS Fast Load (Bulk Insert), vô hiệu hóa Non-clustered Index trước khi nạp và Rebuild Index sau khi hoàn tất để tối ưu hóa IO.

#### **B. Incremental Load với CDC (Change Data Capture)**
* **Đối tượng:** Các bảng nghiệp vụ cốt lõi phát sinh biến động thường xuyên trên OLTP (`Loads`, `Trips`, `Drivers`).
* **Kỹ thuật:**
  1. Kích hoạt CDC cấp Database: `EXEC sys.sp_cdc_enable_db;`
  2. Kích hoạt CDC cấp Bảng: `EXEC sys.sp_cdc_enable_table @source_schema = 'dbo', @source_name = 'Loads', @role_name = NULL;`
  3. Dùng **CDC Control Task** trong SSIS để duy trì mốc LSN (Log Sequence Number).
  4. Sử dụng **CDC Source** và **CDC Splitter** để rẽ nhánh: Dòng INSERT chuyển nạp vào Fact/Dim, dòng UPDATE chuyển qua luồng xử lý SCD.

#### **C. Incremental Load dạng High-Watermark (Timestamp Tracking) & Accumulating Snapshot Update**
* **Đối tượng:** `Fact_Delivery_Fulfillment` và `Fact_Maintenance`.
* **Kỹ thuật High-Watermark:** Sử dụng bảng `ETL_Metadata` (`TableName`, `Last_Load_Date`, `Rows_Inserted`). SSIS chỉ trích xuất bản ghi có mốc thời gian lớn hơn `Last_Load_Date` của chu kỳ trước:
  ```sql
  SELECT * FROM Source_Maintenance WHERE maintenance_date > ?;
  ```
  Sau khi nạp xong, câu lệnh Execute SQL Task cập nhật lại `Last_Load_Date = MAX(maintenance_date)`.
* **Kỹ thuật Accumulating Snapshot Update (In-Flight Orders):**
  * Đối với các đơn hàng mới chỉ bốc nhưng chưa giao (`delivery_date_key = -1`): Pipeline nạp dòng mới vào Fact với trạng thái Pending.
  * Khi sự kiện `Delivery` hoàn tất, SSIS thực hiện Lookup đối chiếu `load_id`, cập nhật `delivery_date_key`, tính toán `transit_duration_hours`, `delivery_detention_minutes` và đổi cờ SLA tương ứng.

#### **D. Xử lý Thay đổi Chiều Chậm (Slowly Changing Dimensions - SCD)**
* **SCD Type 1 (Ghi đè - Overwrite):** Áp dụng cho các thông tin sửa lỗi dữ liệu hoặc thuộc tính vận hành hiện thời:
  * `Dim_Customer`: `customer_name`, `primary_freight_type`.
  * `Dim_Driver`: `first_name`, `last_name`, `full_name`, `license_number`, `years_experience`.
  * `Dim_Truck`: `unit_number`, `fuel_type`, `tank_capacity_gallons`.
  * `Dim_Trailer`: `trailer_number`, `trailer_type`.
  * `Dim_Route`: `typical_distance_miles`, `base_rate_per_mile`, `fuel_surcharge_rate`.
  * `Dim_Facility`: `facility_name`, `facility_type`, `city`, `state`, `latitude`, `longitude`.
  * *Cơ chế:* Cập nhật trực tiếp (`UPDATE`) vào bản ghi hiện hành dựa trên Business Key.
* **SCD Type 2 (Lưu vết Lịch sử - Versioning with Surrogate Key):** Áp dụng cho các thuộc tính quản trị quan trọng cần bảo lưu lịch sử phục vụ phân tích theo thời điểm:
  * `Dim_Driver`: `cdl_class`, `license_state`, `home_terminal`, `employment_status`.
  * `Dim_Customer`: `credit_terms_days`, `customer_type`, `account_status`, `annual_revenue_potential`.
  * `Dim_Truck`: `status`, `home_terminal`.
  * `Dim_Trailer`: `status`, `current_location`.
  * `Dim_Facility`: `dock_doors`, `operating_hours`.
  * *Cơ chế:* Đóng bản ghi cũ (`is_current = 0`, `expiration_date = GETDATE()`), chèn bản ghi mới (`is_current = 1`, `effective_date = GETDATE()`, `expiration_date = NULL`, cấp Surrogate Key mới).

---

## **PHẦN 3: LỘ TRÌNH 4 TUẦN & PHÂN CHIA NHIỆM VỤ KỸ THUẬT CHI TIẾT**

```
Tuần 1: Thiết kế Galaxy Schema Chuẩn hóa, Cào Giá Dầu Thực tế, DDL Staging/DWH (30% điểm)
Tuần 2: Xây dựng SSIS Packages (CDC/SCD/Lookup/In-Flight), Tự động hóa Airflow & Docker (20% điểm)
Tuần 3: Xây dựng SSAS Galaxy Cube (4 Measure Groups), Phân cấp 1:N, Truy vấn MDX/SQL (15% điểm)
Tuần 4: Xây dựng Dashboard Power BI, Test Demo Incremental, Báo cáo & Luyện Phản biện Q&A (35% điểm)
```

---

### **TUẦN 1: THIẾT KẾ GALAXY SCHEMA, WEB CRAWLER GIÁ XĂNG DẦU & DDL CSDL**
*(Mục tiêu: Đạt trọn 30% điểm Thiết kế Kho dữ liệu & Chuẩn bị hạ tầng cho 20% điểm ETL)*

#### **1. Bình Minh (Trưởng nhóm - Thiết kế Kiến trúc & Quản trị DWH):**
* **Đầu việc:**
  * Hoàn thiện tài liệu thiết kế Galaxy Schema mức logic và vật lý gồm **4 Fact Tables** (`Fact_Load`, `Fact_Trip`, `Fact_Delivery_Fulfillment`, `Fact_Maintenance`) và **9 Dimensions** chuẩn hóa theo Ralph Kimball.
  * Xây dựng ma trận **Enterprise Bus Matrix**, xác định rõ tính chất Conformed của các chiều dùng chung và vai trò Role-Playing của `Dim_Date` và `Dim_Facility`.
  * Thiết kế chi tiết bảng Junk Dimension `Dim_Load_Profile` (tổ hợp từ `load_status`, `booking_type`, `load_type`) và `Dim_Maintenance_Profile` (tổ hợp `maintenance_type` và cờ phái sinh `service_urgency` kèm khóa `-1`).
  * Quy hoạch phân cấp 2 nhánh độc lập cho `Dim_Route` (`Origin` và `Destination`) để triệt tiêu lỗi quan hệ nhiều - nhiều trên SSAS.
  * Soạn thảo tài liệu chuẩn hóa quy tắc SCD Type 1 & Type 2 cho toàn bộ các thuộc tính để các thành viên đồng bộ logic.
* **Sản phẩm bàn giao:** Tài liệu thiết kế kiến trúc hoàn chỉnh (`thietke_dimfact_2.md`), Sơ đồ ERD Galaxy Schema, Ma trận Enterprise Bus Matrix.

#### **2. Phúc An (Module Web Crawler Giá Xăng Dầu Thực tế & CSDL Nguồn OLTP):**
* **Đầu việc:**
  * Cài đặt CSDL `Logistics_OLTP` trên SQL Server. Bóc tách dữ liệu nguồn từ các file CSV thành các bảng quan hệ chuẩn hóa: `Customers`, `Drivers`, `Trucks`, `Trailers`, `Loads`, `Trips`, `Maintenance_Records`.
  * Kích hoạt cơ chế Change Data Capture (CDC) trên các bảng giao dịch nguồn (`Loads`, `Trips`, `Drivers`).
  * **Phát triển Module Python Web Crawler & REST API Giá Xăng Dầu Thực tế:**
    * Viết script Python (`fuel_price_crawler_api.py`) kết nối cào/trích xuất dữ liệu giá dầu Diesel & Xăng thực tế theo tuần và tháng từ cổng thông tin Năng lượng Hoa Kỳ (U.S. EIA / AAA Fuel Gauge) giai đoạn 2022–2024.
    * Ánh xạ tự động đơn giá thị trường cho 25 thành phố tác nghiệp thuộc các vùng PADD (Gulf Coast, Midwest, West Coast, Central Atlantic, Rocky Mountain).
    * Xuất dữ liệu ra file lưu trữ đệm `fuel_market_rates_2022_2024.csv` / `.json` và dựng service REST API bằng FastAPI (`http://localhost:8000/api/fuel-rates`) cho phép SSIS/Airflow truy vấn đơn giá theo ngày và địa phương.
* **Sản phẩm bàn giao:** CSDL `Logistics_OLTP` đã bật CDC và nạp dữ liệu; Mã nguồn Python Crawler & REST API hoàn chỉnh, tập dữ liệu giá nhiên liệu thực tế 2022–2024.

#### **3. Quang Duy (Khởi tạo DDL Staging, DWH & Môi trường Docker Airflow):**
* **Đầu việc:**
  * Dựa trên bản thiết kế của Bình Minh, viết toàn bộ script SQL DDL (`CREATE DATABASE`, `CREATE TABLE`, chỉ mục Clustered/Non-clustered Index, ràng buộc toàn vẹn) cho 2 CSDL: `Logistics_Staging` và `Logistics_DW`.
  * Viết script SQL sinh tự động $100\%$ dữ liệu cho bảng `Dim_Date` từ 2020 đến 2030 (đầy đủ các thuộc tính: `day_name`, `calendar_quarter`, `fiscal_quarter`, `fiscal_year`, `is_weekend`, `holiday_flag`), chèn bản ghi mặc định `date_key = -1` (*In-Flight / Pending*).
  * Thiết lập bảng kiểm soát `ETL_Metadata` trên Staging để ghi log watermark (`Last_Load_Date`, `Rows_Inserted`, `Execution_Status`).
  * Khởi tạo file cấu hình `docker-compose.yml` để đóng gói Apache Airflow (gồm Webserver, Scheduler, PostgreSQL metadata) chạy sẵn sàng trên môi trường nhóm.
* **Sản phẩm bàn giao:** Script SQL tạo toàn bộ bảng cho Staging và DWH; Dữ liệu hoàn chỉnh cho `Dim_Date`; Môi trường Docker Airflow vận hành ổn định.

---

### **TUẦN 2: XÂY DỰNG PIPELINE SSIS, XỬ LÝ SCD, INCREMENTAL LOAD & AIRFLOW**
*(Mục tiêu: Đạt trọn 20% điểm Kỹ năng Tích hợp Dữ liệu ETL)*

#### **1. Bình Minh (ETL Khách hàng, Tuyến đường, Junk Profile & Fact_Load):**
* **Đầu việc:**
  * Xây dựng SSIS Package: `Dim_Commercial.dtsx` và `Fact_Load.dtsx`.
  * Thiết kế luồng nạp và xử lý SCD cho `Dim_Customer` (**100% Native SSIS SCD Transformation trong Data Flow**):
    * SCD Type 1: `customer_name`, `primary_freight_type` (Cập nhật đè).
    * SCD Type 2: `credit_terms_days`, `customer_type`, `account_status`, `annual_revenue_potential` (Đóng dòng cũ `is_current = 0`, sinh dòng mới với Surrogate Key mới).
  * Xây dựng luồng nạp dữ liệu cho `Dim_Route` (đồng bộ cột nguồn `typical_distance_miles`) và nạp tĩnh cho Junk Dimension `Dim_Load_Profile`.
  * Xây dựng luồng nạp cho `Fact_Load`:
    * Sử dụng Lookup Transformations để chuyển đổi Business Keys thành Surrogate Keys (`customer_key`, `route_key`, `load_profile_key`, `load_date_key`).
    * Tính toán thuộc tính dẫn xuất `total_revenue = revenue + fuel_surcharge + accessorial_charges` và gán hằng số `load_count = 1`.
    * Áp dụng cơ chế Incremental CDC để bắt các đơn hàng mới/thay đổi từ `Logistics_OLTP`.
* **Sản phẩm bàn giao:** File package `Dim_Commercial.dtsx` và `Fact_Load.dtsx` chạy thông suốt từ Staging sang DWH.

#### **2. Phúc An (ETL Tài sản Đội xe, Kỹ thuật Bảo dưỡng, Tích hợp Giá Dầu & High-Watermark):**
* **Đầu việc:**
  * Xây dựng SSIS Package: `Dim_Fleet.dtsx` và `Fact_Maintenance.dtsx` để nạp dữ liệu cho `Dim_Truck`, `Dim_Trailer`, `Dim_Maintenance_Profile` và `Fact_Maintenance`.
  * Xử lý SCD Type 2 cho `Dim_Truck` (`status`, `home_terminal`) và `Dim_Trailer` (`status`, `current_location`). Xử lý SCD Type 1 cho các thuộc tính kỹ thuật. **Quy chuẩn 100% dùng Native SSIS SCD Transformation trong Data Flow** (đã kiểm chứng chạy pass trên localhost).
  * Triển khai nạp bảng `Dim_Maintenance_Profile`: Áp dụng từ điển quy tắc phân loại `service_urgency` và gán bản ghi mặc định `-1` cho các mã ngoại lệ.
  * Tích hợp dữ liệu giá dầu thực tế: Xây dựng package `Stg_Fuel_Rates.dtsx` nạp dữ liệu giá dầu từ Web Crawler / REST API `http://localhost:8000/api/fuel-rates` (hoặc file `fuel_market_rates_2022_2024.csv`) vào bảng Staging **`Stg_Market_Fuel_Rates`**.
    * *Làm rõ vai trò kiến trúc:* Bảng `Stg_Market_Fuel_Rates` không phải bảng mồ côi; đây là bảng tham chiếu đơn giá thị trường (External Market Benchmark) cung cấp dữ liệu cho phân tích **Fleet TCO (Total Cost of Ownership)** và hiệu quả bù đắp phụ phí cước (`fuel_surcharge` trong `Fact_Load` đối chiếu tiêu hao `fuel_gallons_used` trong `Fact_Trip` và chi phí bảo dưỡng trong `Fact_Maintenance`) trên SSAS Galaxy Cube và Power BI.
  * Xây dựng luồng nạp Incremental Load cho `Fact_Maintenance`:
    * Lưu vị trí trạm sửa chữa bằng Degenerate Dimension `facility_location` (loại bỏ hoàn toàn việc tạo Surrogate Key ảo làm ô nhiễm `Dim_Facility`).
    * Lookup Surrogate Keys (`truck_key`, `maintenance_profile_key`, `maintenance_date_key`).
    * Áp dụng High-Watermark theo cột `maintenance_date` đối chiếu bảng `ETL_Metadata`.
* **Sản phẩm bàn giao:** File package `Dim_Fleet.dtsx`, `Fact_Maintenance.dtsx`, `Stg_Fuel_Rates.dtsx` kèm logic tích hợp REST API và cơ chế High-Watermark đã kiểm thử.

#### **3. Quang Duy (ETL Tài xế, Vận hành Chuyến, Chu trình Giao nhận & Tự động hóa Airflow):**
* **Đầu việc:**
  * Xây dựng SSIS Package: `Dim_Driver_Facility.dtsx`, `Fact_Trip.dtsx` và `Fact_Delivery_Fulfillment.dtsx` để nạp `Dim_Driver`, `Dim_Facility`, `Fact_Trip` và `Fact_Delivery_Fulfillment`.
  * Xử lý SCD Type 2 cho `Dim_Driver` (`cdl_class`, `license_state`, `home_terminal`, `employment_status`) và tạo thuộc tính dẫn xuất `full_name`. Xử lý SCD cho `Dim_Facility` (**100% Native SSIS SCD Transformation trong Data Flow**).
  * Xây dựng luồng nạp `Fact_Trip`:
    * Nạp trực tiếp $100\%$ từ `trips.csv` (không join gián tiếp qua `loads.csv`).
    * Lưu `trip_status` dưới dạng Degenerate Dimension.
    * Gán Surrogate Key `-1` cho các chuyến xe thiếu tài xế hoặc đầu kéo.
  * Xây dựng luồng nạp `Fact_Delivery_Fulfillment` (Accumulating Snapshot):
    * Pivot cặp sự kiện Pickup - Delivery từ `delivery_events.csv` theo từng `load_id`.
    * **Chuẩn hóa địa chỉ lấy Master Location (BẮT BUỘC):** Chạy `sql/07_create_delivery_events_mapping.sql` trước khi dựng package. **TUYỆT ĐỐI KHÔNG dùng trực tiếp `facility_id` gốc từ CSV** vì chỉ khớp $3.45\%$, sai lệch tới $96.55\%$ vị trí thực tế! Bắt buộc dùng cặp `(location_city, location_state)` là **Master Ground Truth** (khớp $100.00\%$ với `routes.csv` — xem phân tích định lượng tại [docs/profiling_facility_conflict_report.md](file:///d:/Kho/Project/docs/profiling_facility_conflict_report.md)) để tra cứu `corrected_facility_id` từ `Ref_City_Facility_Mapping`, sau đó mới Lookup `Dim_Facility`. Đối với 4 thành phố thiếu cơ sở (Columbus OH, Seattle WA, Memphis TN, Minneapolis MN), gán `facility_key = -1`.
    * Xử lý cơ chế In-Flight: Nếu đơn hàng chưa giao xong, gán `delivery_date_key = -1` và `completed_fulfillment_count = 0`. Cập nhật bản ghi khi có mốc giao hàng thực tế.
  * Xây dựng package tổng hợp `Master_Orchestrator.dtsx` liên kết các package tuần tự.
  * Viết Airflow DAG (`dags/logistics_dwh_pipeline.py`) tự động hóa toàn trình: Kích hoạt Python Fuel Crawler $\rightarrow$ Gọi `Master_Orchestrator.dtsx` qua `dtexec.exe` $\rightarrow$ Process Cube SSAS $\rightarrow$ Ghi log kiểm toán.
* **Sản phẩm bàn giao:** Bộ SSIS Packages, `Master_Orchestrator.dtsx`, bộ script SQL chuẩn hóa `01` $\rightarrow$ `07` và Airflow DAG chạy tự động.

---

### **TUẦN 3: XÂY DỰNG SSAS CUBE (GALAXY SCHEMA), HIERARCHIES & TRUY VẤN MDX/SQL**
*(Mục tiêu: Đạt trọn 15% điểm Trả lời câu hỏi phân tích kinh doanh bằng SQL và MDX)*

#### **1. Bình Minh (Cấu trúc SSAS Galaxy Project, Phân cấp Hierarchy & Phân tích Doanh thu):**
* **Đầu việc:**
  * Khởi tạo dự án SSAS Multidimensional, kết nối CSDL `Logistics_DW`, tạo Data Source View (DSV) hiển thị rõ cấu trúc Galaxy Schema (4 Fact Tables liên kết với 9 Dimensions dùng chung).
  * Cấu hình các cây phân cấp User Hierarchies chuẩn quan hệ $1 - N$:
    * `Dim_Date`: *Calendar Hierarchy* (Year $\rightarrow$ Quarter $\rightarrow$ Month $\rightarrow$ Date) và *Fiscal Hierarchy*.
    * `Dim_Customer`: Customer Type $\rightarrow$ Customer Name.
    * `Dim_Route`: Thiết lập 2 nhánh phân cấp riêng biệt (*Origin State $\rightarrow$ Origin City $\rightarrow$ Route* và *Destination State $\rightarrow$ Destination City $\rightarrow$ Route*) nhằm triệt tiêu hoàn toàn lỗi *Attribute Relationship Violation*.
  * Cấu hình Measure Group cho `Fact_Load` và thực hiện 2 câu truy vấn chuyên sâu:
    * **MDX 1:** Thống kê Top 10 khách hàng đem lại tổng doanh thu thực tế (`total_revenue`) cao nhất trong từng quý của năm 2023.
    * **T-SQL 1:** Đánh giá tính sinh lời và hiệu suất cước trên từng pound tải trọng (`revenue_per_pound = SUM(total_revenue) / SUM(weight_lbs)`) theo từng hành lang tuyến (`Dim_Route`), phân tách tỷ trọng cước cơ bản và phụ phí xăng dầu.
* **Sản phẩm bàn giao:** Dự án SSAS cơ sở với cấu trúc DSV và Hierarchies hoàn chỉnh; 2 đoạn mã MDX/T-SQL phân tích doanh thu kèm diễn giải insight.

#### **2. Phúc An (Cấu hình Measure Group Bảo dưỡng & Phân tích Chi phí Sở hữu Đội xe):**
* **Đầu việc:**
  * Cấu hình Measure Group `Fact_Maintenance` trong SSAS Cube, thiết lập liên kết với `Dim_Truck`, `Dim_Maintenance_Profile` và Role-Playing Date `maintenance_date_key`.
  * Cấu hình Semi-Additive Measure `odometer_reading` (áp dụng hàm $LAST\_NON\_EMPTY$ hoặc $MAX$ theo từng đầu xe).
  * Cấu hình Calculated Measure quản trị sức khỏe rơ-moóc `low_utilization_trailer_count` bằng DAX/MDX (duyệt danh mục `Dim_Trailer` và tính lũy kế dặm từ `Fact_Trip` để phát hiện các rơ-moóc chạy dưới 500 dặm/tháng hoặc đắp chiếu 0 dặm).
  * Xây dựng truy vấn phân tích liên thông đa quy trình (**Cross-Fact Drill-Across**):
    * **MDX 2:** Tính toán Tổng Chi phí Sở hữu Đội xe (Fleet TCO) bằng cách kết hợp dặm chạy và nhiên liệu từ `Fact_Trip`, đơn giá dầu cào từ web và chi phí bảo dưỡng từ `Fact_Maintenance` theo từng Model Year và Make của đầu kéo (`Dim_Truck`):
      $$Total\_Truck\_Operating\_Cost = \sum(Fuel\_Gallons\_Used \times Average\_Fuel\_Price) + \sum(Total\_Maintenance\_Cost)$$
    * **T-SQL 2:** Xác định danh sách các đầu xe có chi phí bảo dưỡng bình quân trên mỗi dặm lăn bánh ($Cost\_per\_Mile$) vượt ngưỡng cảnh báo kinh tế để đề xuất thanh lý hoặc đại tu.
* **Sản phẩm bàn giao:** Measure Group Bảo dưỡng trên SSAS; 2 đoạn mã MDX/T-SQL phân tích TCO và sức khỏe tài sản đội xe.

#### **3. Quang Duy (Cấu hình Measure Groups Vận hành & Phân tích Giao nhận SLA):**
* **Đầu việc:**
  * Cấu hình 2 Measure Groups `Fact_Trip` và `Fact_Delivery_Fulfillment` trong SSAS Cube.
  * Cấu hình Role-Playing Dimensions cho `Dim_Date`: `dispatch_date_key`, `pickup_date_key`, `delivery_date_key`.
  * Cấu hình các Calculated Measures trọng yếu (đã khử lỗi mẫu số In-Flight):
    * Tỷ lệ giao hàng đúng hẹn SLA:
      $$on\_time\_delivery\_rate = \frac{\sum(delivery\_on\_time\_count)}{CALCULATE(\sum(total\_fulfillment\_count), delivery\_date\_key <> -1)} \times 100\%$$
    * Độ lệch thời gian vận chuyển thực tế so với tiêu chuẩn:
      $$transit\_variance\_hours = CALCULATE(\sum(transit\_duration\_hours) - SUMX(Fact\_Delivery\_Fulfillment, RELATED(Dim\_Route[typical\_transit\_days]) \times 24), delivery\_date\_key <> -1)$$
    * Tỷ lệ nổ máy dừng chờ lãng phí:
      $$idle\_time\_percentage = \frac{\sum(idle\_time\_hours)}{\sum(actual\_duration\_hours + idle\_time\_hours)} \times 100\%$$
  * Viết 2 câu truy vấn chuyên sâu:
    * **MDX 3:** Phân tích tỷ lệ giao hàng đúng hẹn (`on_time_delivery_rate`) và thời gian giam bãi chờ dỡ hàng (`delivery_detention_minutes`) theo từng cơ sở bến bãi đích (`Dim_Facility`) qua các tháng.
    * **T-SQL 3 (Drill-Across Unit Economics & Friction):** Tính toán Chỉ số Rủi ro Giao nhận trên Doanh thu Tuyến (`Fulfillment_Risk_Ratio = SUM(total_detention_minutes) / SUM(total_revenue)`) kết hợp giữa `Fact_Load` và `Fact_Delivery_Fulfillment` theo từng đối tác khách hàng.
* **Sản phẩm bàn giao:** Measure Groups Vận hành và Giao nhận trên SSAS; 2 đoạn mã MDX/T-SQL phân tích SLA và hiệu suất chuỗi bến bãi.

---

### **TUẦN 4: POWER BI TRỰC QUAN, KIỂM THỬ DEMO, BÁO CÁO & LUYỆN TẬP PHẢN BIỆN**
*(Mục tiêu: Đạt trọn 35% điểm Báo cáo, Đánh giá nhóm & Trả lời câu hỏi phản biện)*

#### **1. Bình Minh (Tổng hợp Báo cáo Học thuật, Quản trị Logbook & Dashboard Thương mại):**
* **Đầu việc:**
  * Soạn thảo và tổng hợp toàn bộ tài liệu thành Báo cáo Đồ án hoàn chỉnh (Word/PDF) theo mẫu chuẩn học thuật gồm 5 chương:
    * *Chương 1: Giới thiệu bài toán nghiệp vụ logistics, hạ tầng dữ liệu và module Python cào giá xăng dầu thực tế.*
    * *Chương 2: Thiết kế Kiến trúc Kho dữ liệu Chuẩn hóa (Chu trình 4 bước Kimball, Bus Matrix, 4 Fact Tables, 9 Dimensions, Xử lý SCD Type 1 & 2, Junk Dimensions, Phân cấp 2 nhánh Route).*
    * *Chương 3: Quy trình Tích hợp Dữ liệu ETL & Tự động hóa Pipeline (Staging, SSIS Packages, CDC, High-Watermark, In-Flight Accumulating Update, Airflow Docker).*
    * *Chương 4: Mô hình Phân tích Đa chiều SSAS Galaxy Cube & Các truy vấn chuyên sâu MDX/T-SQL Cross-Fact Drill-Across.*
    * *Chương 5: Trình diễn Báo cáo Power BI, Đánh giá Kết quả Dự án và Khuyến nghị Quản trị Vận tải.*
  * Thiết lập bảng **Nhật ký Phân công Công việc (Task Logbook)** và **Bảng Tự đánh giá Mức độ Đóng góp** có xác nhận của cả 3 thành viên ($33.3\%$ mỗi người).
  * Xây dựng Dashboard Power BI - **Trang 1: Quản trị Doanh thu & Khách hàng Thương mại** (Doanh thu theo Tuyến đường, Top khách hàng, Cơ cấu loại hình dịch vụ từ Junk Profile, Đơn giá doanh thu thực tế `revenue_per_pound`).
* **Sản phẩm bàn giao:** Báo cáo đồ án chính thức (Word/PDF); Task Logbook và Bảng tự đánh giá; File Power BI Trang 1.

#### **2. Phúc An (Kịch bản Test Demo & Dashboard Kỹ thuật Bảo dưỡng Đội xe):**
* **Đầu việc:**
  * Xây dựng bộ **Script SQL Test Demo** chứng minh hoạt động thực tế của hệ thống:
    * *Kịch bản 1 (Test CDC):* Thêm mới 5 đơn hàng vào `Logistics_OLTP`, kích hoạt SSIS để chứng minh CDC bắt chính xác dòng mới đẩy vào `Fact_Load`.
    * *Kịch bản 2 (Test SCD Type 2):* Cập nhật hạng bằng lái của một tài xế từ 'Class B' lên 'Class A', chạy ETL để chứng minh dòng cũ hết hiệu lực (`is_current = 0`) và dòng mới được cấp Surrogate Key mới.
    * *Kịch bản 3 (Test SCD Type 1):* Sửa lỗi chính tả tên công ty của 1 khách hàng trên nguồn để chứng minh cơ chế `UPDATE` đè tức thời.
    * *Kịch bản 4 (Test Python Crawler & REST API):* Kích hoạt script cào dữ liệu giá dầu ngày mới, gọi REST API và kiểm chứng dữ liệu nạp thành công vào Staging.
  * Xây dựng Dashboard Power BI - **Trang 2: Quản trị Kỹ thuật, Bảo dưỡng & Chi phí Sở hữu Đội xe (Fleet TCO)** (Chi phí vật tư và nhân công theo hãng xe, Thời gian ngưng hoạt động nằm xưởng Downtime, Biến động giá dầu thị trường, Giám sát rơ-moóc nhàn rỗi `low_utilization_trailer_count`).
* **Sản phẩm bàn giao:** Script SQL test kịch bản demo; File Power BI Trang 2.

#### **3. Quang Duy (Slide Thuyết trình, Dashboard Vận hành & Tài liệu Phản biện Q&A):**
* **Đầu việc:**
  * Thiết kế bộ **Slide thuyết trình bảo vệ đồ án** (PowerPoint/Canva) chuyên nghiệp, làm nổi bật sơ đồ kiến trúc Galaxy Schema, Bus Matrix, pipeline ETL và các biểu đồ KPI cốt lõi.
  * Xây dựng Dashboard Power BI - **Trang 3: Giám sát Vận hành Chuyến xe & Chu trình Giao nhận SLA** (Tỷ lệ giao đúng hẹn SLA theo khách hàng và bến bãi, Thời gian giam bãi chờ bốc dỡ Detention Minutes, Mức độ nổ máy chờ lãng phí của tài xế Idle Time %, Độ lệch hành trình Transit Variance).
  * Biên soạn **Bộ tài liệu ôn tập và câu hỏi phản biện Q&A**, tổ chức buổi phản biện thử nghiệm nội bộ tập trung vào các câu hỏi thường gặp:
    * *Tại sao chọn Galaxy Schema với 4 Fact Tables thay vì Star Schema đơn lẻ?*
    * *Bản chất của Accumulating Snapshot Fact Table trong việc xử lý đơn hàng In-Flight là gì?*
    * *Tại sao phải tách 2 nhánh độc lập cho Dim_Route trong SSAS Cube?*
    * *Cơ chế hoạt động của CDC so với High-Watermark khác nhau ở điểm nào?*
    * *Tại sao không đưa thông tin trạm bảo dưỡng vào Dim_Facility mà lưu Degenerate Dimension?*
* **Sản phẩm bàn giao:** File Slide thuyết trình; File Power BI Trang 3; Tài liệu ôn tập bộ câu hỏi Q&A phản biện.

---

## **PHẦN 4: BẢNG MA TRẬN ĐỐI SOÁT CÔNG VIỆC VÀ TIÊU CHÍ CHẤM ĐIỂM**

Bảng ma trận đảm bảo mọi tiêu chí của Rubric đều được phân công rõ ràng và tỷ lệ đóng góp của 3 thành viên đạt mức cân bằng tuyệt đối ($33.3\%$ mỗi người):

| Tiêu chuẩn chấm điểm theo Rubric | Trọng số | Phụ trách chính | Đầu việc kỹ thuật đã phân công | Thành viên phối hợp |
| :--- | :---: | :--- | :--- | :--- |
| **1. Thiết kế Kho dữ liệu (DWH Modeling)** | **30%** | **Bình Minh** | Thiết kế Galaxy Schema (4 Facts + 9 Dims), Bus Matrix, Junk Dimensions (`Dim_Load_Profile`, `Dim_Maintenance_Profile`), phân cấp 2 nhánh Route $1-N$, giải quyết triệt để rủi ro Surrogate Key. | Phúc An, Quang Duy |
| **2. Tích hợp Dữ liệu (ETL & Pipelines)** | **20%** | **Phúc An** | Pipeline SSIS, Incremental CDC, High-Watermark, Module Python Crawler cào giá xăng dầu thực tế & REST API, SCD Type 1 & 2, In-Flight Milestone Update. | Bình Minh, Quang Duy |
| **3. Tự động hóa Pipeline (Orchestration)** | *(Điểm cộng)* | **Quang Duy** | Triển khai Apache Airflow trên Docker Compose, tự động hóa kịch bản trích xuất Crawler/API và kích hoạt SSIS `dtexec.exe`. | Phúc An |
| **4. Phân tích Đa chiều (SSAS & MDX/SQL)** | **15%** | **Cả 3 bạn** | Xây dựng 4 Measure Groups, Role-Playing Dims, viết 6 câu truy vấn MDX và T-SQL chuyên sâu phân tích Cross-Fact Drill-Across (Fleet TCO, Fulfillment Friction). | Bình Minh, Phúc An, Quang Duy |
| **5. Trực quan hóa (Power BI Dashboard)** | **20%** | **Cả 3 bạn** | Xây dựng 3 trang Dashboard chuyên đề (Doanh thu & Thương mại, Kỹ thuật & TCO Đội xe, Vận hành Chuyến & SLA) kết nối trực tiếp với SSAS Cube/DW. | Bình Minh, Phúc An, Quang Duy |
| **6. Báo cáo, Kịch bản Demo & Phản biện** | **15%** | **Bình Minh & Quang Duy** | Soạn Báo cáo đồ án 5 chương, Script SQL test demo (CDC/SCD), Slide thuyết trình và Bộ câu hỏi Q&A phản biện. | Phúc An |
| **TỔNG CỘNG ĐÓNG GÓP TOÀN DỰ ÁN** | **100%** | **Bình Minh: 33.3%** | **Phúc An: 33.3%** | **Quang Duy: 33.3%** |