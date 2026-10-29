# QUY CHUẨN THIẾT KẾ SSIS & HƯỚNG DẪN KỸ THUẬT TOÀN DIỆN CHO TEAM
**Dự án:** Logistics & Fleet Operations Data Warehouse  
**Người soạn thảo:** PHÚC AN 
**Đối tượng sử dụng:** Bình Minh, Quang Duy 
**Mục tiêu:** Cung cấp tài liệu quy chuẩn kỹ thuật, quy tắc đặt tên, cấu trúc thư mục, quy trình khởi tạo CSDL và các bước xây dựng package chuẩn hóa để các thành viên và AI Agent của họ đọc vào là có thể tự động triển khai chính xác $100\%$, đồng bộ toàn hệ thống, triệt tiêu mọi mâu thuẫn dữ liệu và phương pháp kỹ thuật.

---

## 1. CẤU TRÚC THƯ MỤC DỰ ÁN (PROJECT DIRECTORY STRUCTURE)

Hệ thống được tổ chức chuẩn hóa tại thư mục gốc repository để mọi thành viên và AI Agent dễ dàng định vị tài nguyên:

```
d:\Kho\Project\ (Repo Root)
│
├── Data/                             
│   ├── customers.csv, drivers.csv, trucks.csv, trailers.csv...
│   ├── facilities.csv, routes.csv, delivery_events.csv, maintenance_records.csv
│   └── fuel/                         <-- Dữ liệu giá xăng dầu thị trường từ Web Crawler
│       ├── fuel_market_rates_2022_2024.csv
│       └── fuel_market_rates_2022_2024.json
│
├── sql/                              
│   ├── 01_restore_oltp.sql           
│   ├── 02_enable_cdc.sql             
│   ├── 03_create_staging.sql         
│   ├── 04_create_dwh.sql             
│   ├── 05_populate_dim_date.sql      
│   ├── 06_create_etl_metadata.sql    
│   └── 07_create_delivery_events_mapping.sql 
│
├── docs/                             
│   ├── handover_ssis_guidelines_to_team.md  <-- TÀI LIỆU NÀY
│   └── 
│
└── SSIS_Logistics/                   
    ├── SSIS_Logistics.dtproj         
    ├── Project.params                <-- Tham số cấp Project (ServerName = localhost)
    ├── Conn_OLTP.conmgr              <-- Connection chung tới CSDL Logistics_OLTP
    ├── Conn_Staging.conmgr           <-- Connection chung tới CSDL Logistics_Staging
    ├── Conn_DW.conmgr                <-- Connection chung tới CSDL Logistics_DW
    └── *.dtsx                        <-- Các gói ETL Packages của từng thành viên
```

---

## 2. HƯỚNG DẪN KHỞI TẠO HẠ TẦNG CSDL (CHẠY CÁC FILE SQL CHUNG)

Trước khi mở Visual Studio để thiết kế SSIS, bất kỳ thành viên nào (hoặc AI Agent) sau khi clone repository về đều bắt buộc phải chạy bộ script SQL trong thư mục `sql/` theo đúng thứ tự từ `01` đến `07` để thiết lập hoàn chỉnh 3 CSDL (`Logistics_OLTP`, `Logistics_Staging`, `Logistics_DW`) và chuẩn bị sẵn các bảng từ điển ánh xạ.

### A. Danh mục các Script SQL & Thứ tự thực thi bắt buộc:

| Thứ tự | Tên File Script | Nhiệm vụ kỹ thuật & Lưu ý quan trọng |
| :---: | :--- | :--- |
| **01** | `sql/01_restore_oltp.sql` | **Khôi phục CSDL `Logistics_OLTP`** từ file sao lưu `LogisticsOLTP_v2.bak`.<br/>*Lưu ý:* Mở file kiểm tra dòng 15 đường dẫn file `.bak` (mặc định đã trỏ đúng `D:\Kho\Project\LogisticsOLTP_v2.bak`). Script này đã tích hợp sẵn lệnh chuẩn hóa $100\%$ cột chuỗi sang `NVARCHAR` (Unicode). |
| **02** | `sql/02_enable_cdc.sql` | **Bật Change Data Capture (CDC)** cho CSDL `Logistics_OLTP` và 3 bảng: `Loads`, `Trips`, `Drivers`.<br/>*Lưu ý:* Bắt buộc dịch vụ **SQL Server Agent** trên máy phải đang ở trạng thái **Running** (trong SSMS $\rightarrow$ chuột phải vào biểu tượng `SQL Server Agent` $\rightarrow$ chọn `Start`). |
| **03** | `sql/03_create_staging.sql` | **Tạo CSDL `Logistics_Staging`** chứa các bảng đệm CDC (`Stg_CDC_...`), bảng đệm CSV (`Stg_External_...`) và bảng giá dầu chuẩn hóa (`Stg_Market_Fuel_Rates`). Toàn bộ chuỗi là `NVARCHAR`, không ràng buộc khóa ngoại để nạp Bulk Insert tốc độ cao. |
| **04** | `sql/04_create_dwh.sql` | **Tạo CSDL `Logistics_DW`** theo mô hình Galaxy Schema gồm 9 Dimensions và 4 Facts. Đã đồng bộ kiểu dữ liệu số và chuỗi Unicode $100\%$, đồng thời tự động chèn sẵn bản ghi khóa mặc định `-1` (Unknown / Unassigned) cho tất cả các chiều. |
| **05** | `sql/05_populate_dim_date.sql` | **Nạp sẵn 4,018 ngày** từ năm 2020 đến 2030 vào bảng `Dim_Date` trong `Logistics_DW` với định dạng khóa số nguyên thông minh `YYYYMMDD`. |
| **06** | `sql/06_create_etl_metadata.sql` | **Khởi tạo bảng quản trị mốc gia tăng `dbo.ETL_Metadata`** trong `Logistics_Staging` cho cả 4 bảng Fact. Cột chuẩn hóa: `table_name`, `last_load_date`, `rows_inserted`, `execution_status`. |
| **07** | `sql/07_create_delivery_events_mapping.sql` | **BẮT BUỘC CHO FACT_DELIVERY_FULFILLMENT:** Tạo bảng từ điển cơ sở ưu tiên `dbo.Ref_City_Facility_Mapping`, bảng ánh xạ `dbo.Stg_Delivery_Events_Mapping` và thủ tục nạp dữ liệu thật `dbo.usp_Populate_Delivery_Events_Mapping` trên `Logistics_Staging`. Giải quyết dứt điểm sai lệch 96.55% của `facility_id` gốc. |

---

### B. Hai cách thực thi bộ Script SQL:

#### Cách 1: Chạy tự động qua Command Line / PowerShell (Khuyên dùng cho AI Agent & Dev):
Mở PowerShell tại thư mục gốc dự án (`d:\Kho\Project\`) và copy chạy lần lượt các lệnh sau:
```powershell
sqlcmd -S localhost -E -i "sql\01_restore_oltp.sql"
sqlcmd -S localhost -E -i "sql\02_enable_cdc.sql"
sqlcmd -S localhost -E -i "sql\03_create_staging.sql"
sqlcmd -S localhost -E -i "sql\04_create_dwh.sql"
sqlcmd -S localhost -E -i "sql\05_populate_dim_date.sql"
sqlcmd -S localhost -E -i "sql\06_create_etl_metadata.sql"
sqlcmd -S localhost -E -i "sql\07_create_delivery_events_mapping.sql"
```

#### Cách 2: Chạy thủ công trên SQL Server Management Studio (SSMS):
1. Mở SSMS, kết nối vào server `localhost` (hoặc dấu `.`).
2. Vào menu `File` $\rightarrow$ `Open` $\rightarrow$ `File...` mở lần lượt từng file từ `01` đến `07`.
3. Bấm phím **F5 (Execute)** để chạy từng file.
4. Sau khi chạy xong, Refresh lại Object Explorer sẽ thấy đủ 3 CSDL: `Logistics_OLTP`, `Logistics_Staging`, `Logistics_DW`.

---

## 3. QUY CHUẨN ĐẶT TÊN (NAMING CONVENTIONS)

Tất cả các thành viên và AI Agent khi tạo mới đối tượng trong SSIS bắt buộc phải tuân thủ nghiêm ngặt tiền tố và cấu trúc tên sau:

### A. Quy chuẩn đặt tên Package (`.dtsx`):
* Gói tầng Staging: `Stg_<Nguồn hoặc Thực thể>.dtsx` (Ví dụ: `Stg_OLTP_CDC.dtsx`, `Stg_CSV_Files.dtsx`, `Stg_Fuel_Rates.dtsx`).
* Gói nạp Dimension: `Dim_<Tên Chiều>.dtsx` (Ví dụ: `Dim_Commercial.dtsx`, `Dim_Driver_Facility.dtsx`, `Dim_Fleet.dtsx`).
* Gói nạp Fact Table: `Fact_<Tên Bảng Fact>.dtsx` (Ví dụ: `Fact_Load.dtsx`, `Fact_Trip.dtsx`, `Fact_Delivery_Fulfillment.dtsx`, `Fact_Maintenance.dtsx`).
* Gói điều phối tổng: `Master_Orchestrator.dtsx`.

### B. Quy chuẩn đặt tên Task trên Control Flow:
* **Execute SQL Task:** Tiền tố `SQL_` + `<Hành động>` + `_<Đối tượng>`  
  *(Ví dụ: `SQL_Truncate_Stg_Loads`, `SQL_Get_Watermark`, `SQL_Update_Watermark`).*
* **Data Flow Task:** Tiền tố `DFT_` + `<Hành động/Nạp>`  
  *(Ví dụ: `DFT_Stage_Maintenance`, `DFT_Load_Fact_Maintenance`, `DFT_Dim_Truck`).*
* **Sequence Container:** Tiền tố `Sequence_` + `<Tên nhóm logic>`  
  *(Ví dụ: `Sequence_Dim_Truck`, `Sequence_Dim_Trailer`).*
* **Execute Package Task:** Tiền tố `EPT_` + `<Tên Package được gọi>`  
  *(Ví dụ: `EPT_Stg_Fuel_Rates`, `EPT_Fact_Load`).*

### C. Quy chuẩn đặt tên Component trong Data Flow:
* **Nguồn dữ liệu:**
  * OLE DB Source: `OLE_SRC_<Tên bảng nguồn>` (Ví dụ: `OLE_SRC_Stg_Maintenance`, `OLE_SRC_Trucks`).
  * Flat File Source: `FLAT_SRC_<Tên thực thể>` (Ví dụ: `FLAT_SRC_Fuel`, `FLAT_SRC_Facilities`).
* **Đích nạp dữ liệu:**
  * OLE DB Destination: `OLE_DST_<Tên bảng đích>` (Ví dụ: `OLE_DST_Fact_Maintenance`, `OLE_DST_Dim_Customer`).
* **Các phép biến đổi (Transformations):**
  * Conditional Split: `SPL_<Mô tả điều kiện lọc>` (Ví dụ: `SPL_Incremental_Filter`, `SPL_CDC_Router`).
  * Derived Column: `DER_<Mô tả tính toán>` (Ví dụ: `DER_Calculations`, `DER_Default_Keys`).
  * Lookup: `LKP_<Tên bảng Dimension>` (Ví dụ: `LKP_Dim_Date`, `LKP_Dim_Truck`, `LKP_Dim_Customer`, `LKP_City_Facility_Mapping`).
  * Row Count: `CNT_<Tên bộ đếm>` hoặc `RC_<Tên>` (Ví dụ: `CNT_Rows_Inserted`).
  * Data Conversion: `DCNV_<Mô tả>` (Ví dụ: `DCNV_Data_Types`).
  * Aggregate: `AGG_<Mô tả nhóm>` (Ví dụ: `AGG_Distinct_Profile`).
  * Slowly Changing Dimension: `SCD_<Tên thực thể>` (Ví dụ: `SCD_Trucks`, `SCD_Customer`, `SCD_Driver`).

### D. Quy chuẩn đặt tên Biến (Variables):
* Tiền tố chữ thường `v` + tên theo quy tắc CamelCase (Ví dụ: `vLastLoadDate`, `vRowsInserted`, `vMaxDate`).
* **Phạm vi (Scope):** Luôn để ở cấp độ **Package** (chọn tên Package ở cột Scope trong cửa sổ Variables) để mọi Task trong package đều nhìn thấy biến.

---

## 4. QUY TRÌNH 5 BƯỚC CHUẨN ĐỂ XÂY DỰNG MỘT SSIS PACKAGE (GUIDE CHO AGENT & DEV)

Mỗi khi thành viên hoặc AI Agent nhận nhiệm vụ dựng một package (đặc biệt là Fact hoặc Dimension phức tạp), hãy tuân thủ tuần tự 5 bước kỹ thuật sau:

```
[Bước 1: Kết nối & Schema Check] ──> [Bước 2: Dựng Control Flow chuẩn 3 tầng]
                                                     │
                                                     ▼
[Bước 4: Xử lý Toàn vẹn Khóa -1] <── [Bước 3: Dựng Data Flow (Table or view)]
               │
               ▼
[Bước 5: Chốt Watermark & Chạy Kiểm thử (F5)]
```

### Bước 1: Kết nối & Kiểm tra Schema
1. Sử dụng 3 Connection Managers cấp Project có sẵn: `Conn_OLTP`, `Conn_Staging`, `Conn_DW` (Server name luôn là `localhost`).
2. Mở file script tương ứng trong thư mục `sql/` để kiểm tra chính xác tên bảng, tên cột và kiểu dữ liệu.

### Bước 2: Dựng Control Flow chuẩn 3 tầng
1. **Task nạp Staging (`DFT_Stage_...`):** Đọc dữ liệu thô từ nguồn $\rightarrow$ nạp nguyên trạng vào bảng `Logistics_Staging`.
2. **Task lấy mốc gia tăng (`SQL_Get_Watermark`):**
   * Connection: `Conn_Staging`, ResultSet: `Single row`.
   * SQLStatement: `SELECT ISNULL(last_load_date, '1900-01-01') FROM dbo.ETL_Metadata WHERE table_name = 'Tên_Bảng_Fact';`
   * Result Set: Map số `0` vào biến `User::vLastLoadDate`.
3. **Task nạp Kho DWH (`DFT_Load_...`):** Thực thi luồng xử lý chính.
4. **Task chốt mốc gia tăng (`SQL_Update_Watermark`):**
   * Cập nhật `last_load_date = MAX(ngày)`, `rows_inserted = ?`, `execution_status = 'SUCCESS'`.

### Bước 3: Dựng Data Flow - Nguyên tắc "Nói không với SQL Command"
1. **OLE DB Source:** 
   * Data access mode: Chọn **`Table or view`** (chọn bảng trực tiếp từ dropdown).
   * **Lợi ích sống còn:** Tránh hardcode SQL query, triệt tiêu lỗi thiếu Parameter `?`, tự động cập nhật metadata khi CSDL thêm cột.
2. **Lọc gia tăng (Incremental Filter):**
   * Đặt component **`Conditional Split`** ngay sau Source.
   * Điều kiện lọc: `event_date > @[User::vLastLoadDate]`.
   * Chọn nhánh Output để nối tiếp sang các khối biến đổi.
3. **Tính toán đo lường (`Derived Column`):**
   * Tính toán doanh thu, chi phí, hoặc cờ trạng thái bằng biểu thức SSIS.
   * Gán hằng số cộng dồn: `(DT_I4)1` cho các cột đếm (ví dụ `load_count`, `trip_count`, `maintenance_count`, `total_fulfillment_count`).
4. **Tra cứu khóa thay thế (`Lookup`):**
   * Luôn chọn Data access mode: **`Table or view`** trỏ tới bảng Dimension trong `Conn_DW`.
   * Mục *Specify how to handle rows with no matching entries*: Chọn **`Ignore failure`**.
   * Dữ liệu tiếp tục chảy qua cổng **`Lookup Match Output`**.

### Bước 4: Xử lý Toàn vẹn Khóa ngoại & Khóa mặc định `-1` (Kimball Standard)
* Đặt component **`Derived Column`** (đặt tên `DER_Default_Keys`) ngay sau chuỗi Lookups.
* Cấu hình thay thế giá trị `NULL` bằng khóa mặc định **`-1`**:
  * Cột kiểu `INT`: `ISNULL(foreign_key) ? -1 : foreign_key`
  * Cột kiểu `SMALLINT`: `ISNULL(foreign_key) ? (DT_I2)(-1) : foreign_key`
* *(Quy tắc này triệt tiêu hoàn toàn lỗi vi phạm Foreign Key Constraint khi gặp bản ghi chưa xác định hoặc Late-Arriving Data)*.

### Bước 5: Đếm số dòng & Ghi vào Destination
1. Kéo component **`Row Count`**, chọn VariableName: `User::vRowsInserted`.
2. Kéo **`OLE DB Destination`**:
   * Data access mode: Chọn **`Table or view - fast load`** *(để nạp khối lượng lớn tốc độ cao)*.
   * Tab Mappings: Nối các cột tương ứng vào bảng đích DWH.
3. Nhấn **F5 (Start)** để chạy thử và kiểm tra các task sáng đèn xanh lá cây ($\checkmark$).

---

## 5. CÁC QUY CHUẨN KỸ THUẬT BẮT BUỘC KHÁC

### A. Tiêu chuẩn Bảng mã & Kiểu chuỗi: 100% Unicode `NVARCHAR` (`DT_WSTR`)
* Toàn bộ hệ thống CSDL (`OLTP`, `Staging`, `DWH`) đã được chuẩn hóa cột chuỗi sang `NVARCHAR`.
* Trong SSIS, các cột chuỗi tương ứng là **`Unicode string [DT_WSTR]`**.
* **Cấm:** Không ép kiểu sang `DT_STR` (Code Page 1252/1258 non-unicode) để tránh lỗi lệch kiểu khi so sánh trong Lookup và OLE DB Command.

### B. Lưu ý sống còn về Locale ID khi đọc file CSV (Flat File Connection):
* Khi tạo Flat File Connection Manager đọc file CSV nguồn trong thư mục `Data/`:
  * Mở tab **General** $\rightarrow$ Mục **Locale**: Bắt buộc chọn **`English (United States)`** *(thay vì Vietnamese)*.
  * Mục **Code page**: Chọn **`65001 (UTF-8)`** hoặc `1252 (ANSI)`.
  * **Giải thích:** Trong tiếng Việt, dấu phẩy `,` là số thập phân, còn các file CSV dùng dấu chấm `.` (ví dụ: `3.4324`). Nếu để Locale là Vietnamese, component Data Conversion sẽ bị lỗi crash khi chuyển đổi sang số `numeric` hoặc `float`.

### C. Quy chuẩn duy nhất cho SCD: Sử dụng 100% Native SSIS SCD Transformation trong Data Flow
* **CHỐT PHƯƠNG PHÁP DUY NHẤT:** Toàn bộ 3 thành viên thống nhất sử dụng component **Slowly Changing Dimension (SCD Wizard)** trực quan ngay trong Data Flow của SSIS.
* **TUYỆT ĐỐI KHÔNG SỬ DỤNG STORED PROCEDURE** (`usp_Load_Dim_...`) như trong bản nháp sơ khai trước đây.
* **Lý do kỹ thuật & học thuật:**
  1. **Rubric đánh giá môn Kho Dữ liệu & SSIS:** Điểm số tối đa của đồ án yêu cầu trực quan hóa quy trình biến đổi ETL bằng giao diện SSIS Data Flow. Việc sử dụng Native SCD Transformation thể hiện rõ ràng 2 nhánh xử lý:
     * Nhánh **Changing Attribute Updates (SCD Type 1)**: Cập nhật đè dữ liệu cũ bằng OLE DB Command.
     * Nhánh **Historical Attribute Inserts (SCD Type 2)**: Đóng bản ghi cũ (`is_current = 0`, `expiration_date = GETDATE()`) và sinh dòng mới (`is_current = 1`, `effective_date = GETDATE()`, cấp Surrogate Key mới).
  2. **Tránh biến SSIS thành "Hộp đen":** Dùng Stored Procedure giấu toàn bộ logic vào T-SQL bên ngoài, vi phạm tiêu chí đánh giá năng lực công cụ ETL của môn học.
  3. **Đã kiểm chứng thực tế:** Package mẫu [Dim_Fleet.dtsx](file:///d:/Kho/Project/SSIS_Logistics/Dim_Fleet.dtsx) của Phúc An đã hoàn thành $100\%$ bằng Native SSIS SCD Transformation và đã chạy thực tế trên SQL Server `localhost` ra kết quả hoàn hảo. Toàn nhóm triển khai đồng bộ theo chuẩn này.

### D. Thống nhất Tên Bảng Staging & REST API Giá Dầu:
* **Tên bảng Staging chính thức:** **`Stg_Market_Fuel_Rates`** (khớp $100\%$ với file DDL [sql/03_create_staging.sql](file:///d:/Kho/Project/sql/03_create_staging.sql#L149), package [Stg_Fuel_Rates.dtsx](file:///d:/Kho/Project/SSIS_Logistics/Stg_Fuel_Rates.dtsx) và tệp dữ liệu gốc [fuel_market_rates_2022_2024.csv](file:///d:/Kho/Project/Data/fuel/fuel_market_rates_2022_2024.csv)).
  * *Lưu ý:* Tuyệt đối không dùng tên cũ `Stg_Daily_Fuel_Rates` để tránh xung đột script.
* **REST API Endpoint chính thức:** Dịch vụ FastAPI cung cấp 2 endpoint song song:
  * Endpoint chuẩn RESTful: `http://localhost:8000/api/fuel-rates`
  * Endpoint alias theo khoảng ngày: `http://localhost:8000/api/fuel-prices/range`
  * Fallback Flat File: `Data/fuel/fuel_market_rates_2022_2024.csv`.

### E. Kiến trúc & Vai trò của Bảng `Stg_Market_Fuel_Rates` (Khử rủi ro "Bảng mồ côi" khi phản biện):
* **Bản chất nghiệp vụ:** Bảng `Fact_Maintenance` chỉ ghi nhận chi phí bảo dưỡng kỹ thuật của xe (tiền công thợ `labor_cost`, vật tư thay thế `parts_cost`, số giờ nằm xưởng `downtime_hours`). Xe vào xưởng không lăn bánh trên đường nên không tiêu thụ nhiên liệu. Do đó, việc `Fact_Maintenance` không chứa khóa ngoại giá dầu là **hoàn toàn chính xác về mặt chuẩn mực thiết kế Fact Table của Ralph Kimball**.
* **Vai trò trong Kiến trúc Galaxy Schema:** Bảng `Stg_Market_Fuel_Rates` là **Bảng Tham chiếu Đơn giá Thị trường Ngoại sinh (External Market Benchmark Rate Table)**. Dữ liệu này được kết nối trực tiếp trong **SSAS Galaxy Cube và Power BI** để tính toán các chỉ số quản trị chiến lược:
  1. **Tổng Chi phí Sở hữu Đội xe (Fleet Total Cost of Ownership - TCO):** Truy vấn liên thông (*Cross-Fact Drill-Across*) giữa `Fact_Trip` và `Fact_Maintenance` qua conformed dimension `Dim_Truck`:
     $$Total\_Truck\_Operating\_Cost = \sum(Fact\_Trip.fuel\_gallons\_used \times Stg\_Market\_Fuel\_Rates.diesel\_price) + \sum(Fact\_Maintenance.total\_maintenance_cost)$$
  2. **Đánh giá Hiệu quả Bù đắp Phụ phí Nhiên liệu (Fuel Surcharge Efficiency):** Đối chiếu giữa doanh thu phụ phí xăng dầu thu từ khách hàng (`Fact_Load.fuel_surcharge`) với chi phí nhiên liệu thực tế xe chạy tiêu hao (`Fact_Trip.fuel_gallons_used \times Stg\_Market\_Fuel\_Rates.diesel\_price`) theo từng tuyến đường (`Dim_Route`).
* **Kịch bản phản biện Q&A:** Nếu giảng viên hỏi: *"Tại sao Fact_Maintenance không có cột giá dầu?"* $\rightarrow$ Trả lời: *"Bảo dưỡng xe ghi nhận chi phí sửa chữa tại xưởng, không tiêu hao dầu hành trình. Dữ liệu giá dầu được trích xuất vào Staging để phục vụ phân tích Fleet TCO và Phụ phí cước liên thông giữa Fact_Trip, Fact_Load và Fact_Maintenance trên tầng Semantic Layer SSAS Cube."*

---

## 6. MA TRẬN PHÂN CHIA GÓI CÔNG VIỆC & QUẢN TRỊ DWH (WORK BREAKDOWN MATRIX)

> [!IMPORTANT]
> ### **KHẲNG ĐỊNH VỀ NỀN TẢNG CSDL DWH ĐÃ ĐƯỢC TẠO SẴN:**
> * **Phúc An đã thiết kế chuẩn hóa và tạo sẵn 100% khung DDL** cho toàn bộ **9 Dimensions** và **4 Fact Tables** trong script [sql/04_create_dwh.sql](file:///d:/Kho/Project/sql/04_create_dwh.sql), cùng bảng `Dim_Date` (nạp sẵn 4.018 dòng qua [sql/05_populate_dim_date.sql](file:///d:/Kho/Project/sql/05_populate_dim_date.sql)), bảng quản trị `dbo.ETL_Metadata` ([sql/06_create_etl_metadata.sql](file:///d:/Kho/Project/sql/06_create_etl_metadata.sql)), và bảng từ điển chuẩn hóa bến bãi `Ref_City_Facility_Mapping` ([sql/07_create_delivery_events_mapping.sql](file:///d:/Kho/Project/sql/07_create_delivery_events_mapping.sql)).
> * **Các thành viên (Bình Minh, Quang Duy) KHÔNG CẦN TỰ TẠO BẢNG DWH**. Toàn bộ cấu trúc bảng đích (`Destination`) và Lookups đã có sẵn đầy đủ trên SQL Server, chỉ cần tập trung dựng các SSIS Packages để trích xuất, biến đổi và nạp dữ liệu vào schema có sẵn theo đúng phân công dưới đây.

### BẢNG TỔNG QUAN PHÂN BỔ TRÁCH NHIỆM TOÀN DỰ ÁN (9 DIMS & 4 FACTS):

| STT | Tên Bảng trong DWH | Mô hình / Loại thực thể | Tạo khung DDL bảng | Thành viên phụ trách ETL (SSIS) | Tên Package SSIS (.dtsx) | Tiến độ / Ghi chú kỹ thuật |
| :---: | :--- | :--- | :---: | :---: | :--- | :--- |
| **1** | **`Dim_Date`** | Conformed Dimension | **Phúc An** *(Script 04)* | **Phúc An** *(Script 05)* | `05_populate_dim_date.sql` | **Đã nạp sẵn 4.018 ngày** (2020–2030, Smart Key `YYYYMMDD`) |
| **2** | **`Dim_Customer`** | Core Dimension | **Phúc An** *(Script 04)* | **Bình Minh** | `Dim_Commercial.dtsx` | Dùng Native SSIS SCD Type 1 & Type 2 |
| **3** | **`Dim_Route`** | Core Dimension | **Phúc An** *(Script 04)* | **Bình Minh** | `Dim_Commercial.dtsx` | Nạp từ `Stg_External_Routes` (đồng bộ `INT`) |
| **4** | **`Dim_Load_Profile`** | Junk Dimension | **Phúc An** *(Script 04)* | **Bình Minh** | `Dim_Commercial.dtsx` | Tổ hợp trạng thái đơn hàng (`load_status`, `booking_type`) |
| **5** | **`Dim_Driver`** | Core Dimension | **Phúc An** *(Script 04)* | **Quang Duy** | `Dim_Driver_Facility.dtsx` | Dùng Native SSIS SCD Type 2 |
| **6** | **`Dim_Facility`** | Core Dimension | **Phúc An** *(Script 04)* | **Quang Duy** | `Dim_Driver_Facility.dtsx` | Dùng Native SSIS SCD Type 1 & Type 2 |
| **7** | **`Dim_Truck`** | Conformed Dimension | **Phúc An** *(Script 04)* | **Phúc An** | `Dim_Fleet.dtsx` | **ĐÃ HOÀN THÀNH 100%** (Native SCD Type 1 & Type 2) |
| **8** | **`Dim_Trailer`** | Core Dimension | **Phúc An** *(Script 04)* | **Phúc An** | `Dim_Fleet.dtsx` | **ĐÃ HOÀN THÀNH 100%** (Native SCD Type 1 & Type 2) |
| **9** | **`Dim_Maintenance_Profile`**| Junk Dimension | **Phúc An** *(Script 04)* | **Phúc An** | `Dim_Fleet.dtsx` | **ĐÃ HOÀN THÀNH 100%** (Phân loại bảo dưỡng + urgency) |
| **—** | ----------------------- | ----------------------- | :---: | :---: | ----------------------- | ---------------------------------------------------- |
| **I** | **`Fact_Load`** | Transaction Fact | **Phúc An** *(Script 04)* | **Bình Minh** | `Fact_Load.dtsx` | Nạp từ CDC Loads, tính doanh thu + phụ phí |
| **II** | **`Fact_Trip`** | Transaction Fact | **Phúc An** *(Script 04)* | **Quang Duy** | `Fact_Trip.dtsx` | Nạp từ CDC Trips, tính nhiên liệu & dặm bay |
| **III**| **`Fact_Delivery_Fulfillment`**| Accumulating Snapshot | **Phúc An** *(Script 04)* | **Quang Duy** | `Fact_Delivery_Fulfillment.dtsx` | Pivot Pickup/Delivery, **bắt buộc Lookup Ref_City_Facility_Mapping** |
| **IV** | **`Fact_Maintenance`** | Periodic / Transaction Fact | **Phúc An** *(Script 04)* | **Phúc An** | `Fact_Maintenance.dtsx` | **ĐÃ HOÀN THÀNH 100%** (Chuẩn 3 tầng, Incremental Watermark) |
| **—** | ----------------------- | ----------------------- | :---: | :---: | ----------------------- | ---------------------------------------------------- |
| **S1**| `Stg_Market_Fuel_Rates` | Staging External Table | **Phúc An** *(Script 03)* | **Phúc An** | `Stg_Fuel_Rates.dtsx` | **ĐÃ HOÀN THÀNH 100%** (27.400 dòng từ Web API / CSV) |
| **S2**| `Stg_CDC_...` (3 bảng)  | Staging CDC Tables | **Phúc An** *(Script 03)* | **Bình Minh** | `Stg_OLTP_CDC.dtsx` | Trích xuất CDC `Loads`, `Trips`, `Drivers` |
| **S3**| `Stg_External_...` (3 bảng)| Staging CSV Tables | **Phúc An** *(Script 03)* | **Quang Duy** | `Stg_CSV_Files.dtsx` | Nạp Flat Files `facilities`, `routes`, `delivery_events` |
| **M** | *Toàn bộ Pipeline* | Orchestration Workflow | **Cả nhóm** | **Quang Duy** | `Master_Orchestrator.dtsx` | Điều phối chuỗi Staging $\rightarrow$ Dim $\rightarrow$ Fact |

---

### A. Chi tiết phần việc của BÌNH MINH:
1. **`Stg_OLTP_CDC.dtsx`**:
   * Sử dụng CDC Source & CDC Splitter để trích xuất các bảng có kích hoạt CDC (`Loads`, `Trips`, `Drivers`) nạp vào các bảng `Stg_CDC_Loads`, `Stg_CDC_Trips`, `Stg_CDC_Drivers`.
2. **`Dim_Commercial.dtsx`**:
   * **`Dim_Customer`**: Dùng **Native SSIS SCD Transformation** (Type 1: `customer_name`, `primary_freight_type`; Type 2: `credit_terms_days`, `account_status`, `annual_revenue_potential`).
   * **`Dim_Route`**: Nạp tuyến đường từ `Stg_External_Routes` (đồng bộ `typical_distance_miles` INT).
   * **`Dim_Load_Profile`**: Nạp tổ hợp Junk Dimension (`load_status`, `booking_type`, `load_type`) kèm bản ghi mặc định `-1`.
3. **`Fact_Load.dtsx`**:
   * Nạp từ `Stg_CDC_Loads` sang `Logistics_DW.dbo.Fact_Load`.
   * Lookups: `customer_key`, `route_key`, `load_profile_key`, `load_date_key`.
   * Tính toán: `total_revenue = revenue + fuel_surcharge + accessorial_charges`, `load_count = 1`.

---

### B. Phần việc của QUANG DUY:
1. **`Stg_CSV_Files.dtsx`**:
   * Nạp các file CSV vào Staging: `facilities.csv` $\rightarrow$ `Stg_External_Facilities`, `routes.csv` $\rightarrow$ `Stg_External_Routes`, `delivery_events.csv` $\rightarrow$ `Stg_External_Delivery_Events`.
2. **`Dim_Driver_Facility.dtsx`**:
   * **`Dim_Driver`**: Dùng **Native SSIS SCD Transformation** (SCD Type 2: `cdl_class`, `license_state`, `home_terminal`, `employment_status`), ghép cột `full_name = first_name + " " + last_name`.
   * **`Dim_Facility`**: Dùng **Native SSIS SCD Transformation** (SCD Type 1 & Type 2: `dock_doors`, `operating_hours`).
3. **`Fact_Trip.dtsx`**:
   * Nạp từ `Stg_CDC_Trips` sang `Logistics_DW.dbo.Fact_Trip`.
   * Lookups: `truck_key`, `driver_key`, `dispatch_date_key`, `route_key`. Lưu `trip_status` dưới dạng Degenerate Dimension.
4. **`Fact_Delivery_Fulfillment.dtsx` (Accumulating Snapshot Fact)**:
   * Xử lý Pivot sự kiện Pickup & Delivery theo từng `load_id` từ `Stg_External_Delivery_Events`.
   * > [!CAUTION]
     > ### **CẢNH BÁO SỐNG CÒN VỀ SỰ THẬT NGUỒN (MASTER GROUND TRUTH):**
     > **TUYỆT ĐỐI KHÔNG DÙNG TRỰC TIẾP `facility_id` GỐC TỪ CSV ĐỂ LOOKUP `Dim_Facility`!**
     > * **Bằng chứng thực nghiệm:** Xem chi tiết báo cáo định lượng tại [docs/profiling_facility_conflict_report.md](file:///d:/Kho/Project/docs/profiling_facility_conflict_report.md). Mã `facility_id` gốc trong `delivery_events.csv` chỉ khớp đúng **$3.45\%$** so với địa chỉ thực tế, sai lệch tới **$96.55\%$**. Nếu tin theo `facility_id` gốc, bảng `Fact_Delivery_Fulfillment` sẽ **sai vị trí ở 96.55% số dòng**!
     > * **Master Ground Truth ($100.00\%$ khớp):** Ngược lại, cặp `(location_city, location_state)` của sự kiện Pickup & Delivery khớp chính xác **$100.00\%$** với `origin_city/state` và `destination_city/state` của tuyến đường (`routes.csv`).
     > * **QUY TRÌNH BẮT BUỘC QUANG DUY PHẢI THỰC HIỆN:**
     >   1. Bắt buộc chạy script [sql/07_create_delivery_events_mapping.sql](file:///d:/Kho/Project/sql/07_create_delivery_events_mapping.sql) trên `Logistics_Staging` để tạo bảng từ điển [Ref_City_Facility_Mapping](file:///d:/Kho/Project/sql/07_create_delivery_events_mapping.sql#L33), bảng [Stg_Delivery_Events_Mapping](file:///d:/Kho/Project/sql/07_create_delivery_events_mapping.sql#L105) và thủ tục `dbo.usp_Populate_Delivery_Events_Mapping`.
     >   2. Trong Data Flow, thực hiện Lookup theo `TRIM(UPPER(location_city))` và `TRIM(UPPER(location_state))` vào bảng `Ref_City_Facility_Mapping` để lấy **`corrected_facility_id`**.
     >   3. Dùng `corrected_facility_id` để Lookup tiếp vào `Dim_Facility` lấy `origin_facility_key` và `destination_facility_key`.
     >   4. Đối với 4 thành phố ngoại lệ không có cơ sở trong danh mục `facilities.csv` (*Columbus OH, Seattle WA, Memphis TN, Minneapolis MN* — chiếm $21.66\%$ sự kiện), giá trị `corrected_facility_id` là `NULL` $\rightarrow$ gán khóa mặc định **`facility_key = -1`** (*Missing / Unknown Facility*).
   * Cơ chế In-Flight: Đơn hàng chưa giao xong gán `delivery_date_key = -1` và `completed_fulfillment_count = 0`. Cập nhật bản ghi khi có mốc giao hàng thực tế.
5. **`Master_Orchestrator.dtsx`**:
   * Kéo các Execute Package Task nối tuần tự:
     `Staging Packages` $\longrightarrow$ `Dimension Packages` $\longrightarrow$ `Fact Packages`.

---

### C. Phần việc của PHÚC AN (Senior Data Engineer):
1. **`Stg_Fuel_Rates.dtsx`**:
   * Nạp dữ liệu giá xăng dầu thị trường từ Flat File [fuel_market_rates_2022_2024.csv](file:///d:/Kho/Project/Data/fuel/fuel_market_rates_2022_2024.csv) hoặc gọi REST API `http://localhost:8000/api/fuel-rates` vào bảng Staging **`Stg_Market_Fuel_Rates`**.
   * Cấu hình Flat File Connection với `Locale = English (United States)` và `CodePage = 65001 (UTF-8)`.
2. **`Dim_Fleet.dtsx` (ĐÃ HOÀN THÀNH $100\%$ & KIỂM THỬ THÀNH CÔNG)**:
   * **`Dim_Truck`**: Nạp từ `Logistics_OLTP.dbo.trucks` qua Native SCD Transformation (SCD Type 2: `status`, `home_terminal`; SCD Type 1: `unit_number`, `fuel_type`, `tank_capacity_gallons`).
   * **`Dim_Trailer`**: Nạp từ `Logistics_OLTP.dbo.trailers` qua Native SCD Transformation (SCD Type 2: `status`, `current_location`; SCD Type 1: `trailer_number`, `trailer_type`).
   * **`Dim_Maintenance_Profile`**: Nạp tĩnh từ điển phân loại `maintenance_type` kết hợp `service_urgency` kèm bản ghi mặc định `-1`.
3. **`Fact_Maintenance.dtsx` (ĐÃ HOÀN THÀNH $100\%$ THEO CHUẨN 3 TẦNG)**:
   * Control Flow 3 tầng: `DFT_Stage_Maintenance` $\rightarrow$ `SQL_Get_Watermark` $\rightarrow$ `DFT_Load_Fact_Maintenance` $\rightarrow$ `SQL_Update_Watermark`.
   * Data Flow 100% `Table or view` kết hợp `Conditional Split` incremental filter (`maintenance_date > vLastLoadDate`), Lookups gán Surrogate Keys (`truck_key`, `maintenance_profile_key`, `maintenance_date_key`), lưu Degenerate Dimension `facility_location` và xử lý khóa mặc định `-1`.

---

## 7. CHECKLIST KIỂM THỬ TRƯỚC KHI COMMIT (DEFINITION OF DONE)
* [ ] Đã chạy đủ **7 file script SQL** khởi tạo CSDL (`01` đến `07`).
* [ ] Đặt tên Package, Task, Component, Variable đúng chuẩn tiền tố quy định tại Mục 3.
* [ ] Tất cả OLE DB Connection Managers đều dùng chung ở cấp Project trỏ về `localhost`.
* [ ] $100\%$ chuỗi văn bản là Unicode `DT_WSTR`, không có cảnh báo vàng Code Page.
* [ ] Flat File Connection đọc CSV luôn đặt Locale là **`English (United States)`**.
* [ ] **Toàn bộ các bảng Dimension sử dụng $100\%$ Native SSIS SCD Transformation trong Data Flow (không dùng Stored Procedure)**.
* [ ] Bảng Staging giá dầu mang tên chuẩn **`Stg_Market_Fuel_Rates`**.
* [ ] **Quang Duy đã tích hợp `Ref_City_Facility_Mapping` từ script `07` để sửa `facility_id` trong `Fact_Delivery_Fulfillment` (không dùng `facility_id` gốc)**.
* [ ] Có bước `DER_Default_Keys` gán `-1` cho tất cả các cột khóa ngoại.
* [ ] Fact Table có bước đọc và cập nhật `last_load_date`, `rows_inserted` vào `dbo.ETL_Metadata`.
* [ ] Nhấn **F5 (Start)** trên Visual Studio: Toàn bộ các Task sáng **màu xanh lá cây (Success)**, không có cảnh báo đỏ hay vàng.
