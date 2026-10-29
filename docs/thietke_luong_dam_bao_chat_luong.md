# **QUY TRÌNH KỸ THUẬT TRIỂN KHAI DATA QUALITY, AUDIT LOG & ROLLBACK BẰNG SSIS THUẦN TÚY (NO STORED PROCEDURES)**

## **HỆ THỐNG KHO DỮ LIỆU VẬN TẢI & QUẢN TRỊ ĐỘI XE (LOGISTICS & FLEET OPERATIONS DWH)**

*(Hệ sinh thái Microsoft: SSIS 2019/2022, SQL Server Agent, SSISDB Catalog, SSMS - Triển khai $100\%$ bằng SSIS Tasks & Components)*

---

## **1. TỔNG QUAN VẤN ĐỀ & CHIẾN LƯỢC KIẾN TRÚC THUẦN SSIS**

### **1.1. Bối cảnh & Yêu cầu Kỹ thuật**

Theo thiết kế Galaxy Schema (`thietke_dimfact.md`) và kế hoạch triển khai (`phancong.md`), nhóm đang hoàn thiện 4 bảng Fact (`Fact_Load`, `Fact_Trip`, `Fact_Delivery_Fulfillment`, `Fact_Maintenance`) và 9 Dimensions. Hiện tại, các package SSIS chỉ mới có luồng Happy Path (đọc nguồn và nạp đích). Khi vận hành thực tế, luồng này đối mặt với 4 lỗ hổng lớn:
1. **Dữ liệu thô chứa dòng bẩn (Dirty Rows):** Sai kiểu dữ liệu, chuỗi rỗng ép sang số, doanh thu/quãng đường mang giá trị âm, hoặc ngày giao hàng sớm hơn ngày nhận hàng khiến SSIS sập đột ngột (`Fail Component`).
2. **Không có cơ chế Rollback tự động:** Khi một package nạp được 50.000 dòng nhưng sập ở dòng 50.001, các dòng đã nạp dở dang vẫn nằm lại trong bảng Fact, gây trùng lặp (duplicate) hoặc lệch số liệu khi chạy lại pipeline.
3. **Mất dấu vết kiểm toán (Audit Trail):** Không ghi nhận được mỗi lượt ETL đọc bao nhiêu dòng từ CSV/CDC, nạp thành công bao nhiêu, loại bỏ bao nhiêu dòng lỗi, và nguyên nhân lỗi cụ thể là gì.
4. **Ràng buộc kiến trúc cốt lõi:** **TUYỆT ĐỐI KHÔNG DÙNG STORED PROCEDURES**. Toàn bộ logic quản trị giao dịch (Transaction), kiểm tra chất lượng (Data Quality), phân luồng rẽ nhánh (Redirection), đối soát số liệu (Reconciliation) và ghi nhận nhật ký (Audit Logging) phải được xây dựng bằng **chính các tác vụ, thành phần và cơ chế native của SSIS**.

---

### **1.2. Có cần tạo thêm bảng mới không?**

**CÓ, BẮT BUỘC TẠO THÊM BẢNG QUẢN TRỊ.**
Để SSIS có nơi lưu vết và cô lập dòng lỗi mà không làm biến dạng cấu trúc của các bảng Fact/Dimension, chúng ta khởi tạo một Schema chuyên biệt tên là `[audit]` đặt trong CSDL `Logistics_Staging` (hoặc `Logistics_DW`). 

Schema này gồm **6 bảng vật lý chuẩn công nghiệp** được thiết kế để các SSIS Tasks đọc/ghi trực tiếp qua OLE DB:
1. `audit.Batch_Log`: Theo dõi phiên chạy tổng thể của toàn bộ chu kỳ ETL (cấp Agent Job / Master Orchestrator).
2. `audit.Package_Log`: Ghi chi tiết từng package SSIS con (số dòng Extract, Insert, Update, Reject, thời gian thực thi).
3. `audit.Error_Log`: Ghi nhận mã lỗi kỹ thuật và thông điệp lỗi hệ thống khi có sự cố bất thường.
4. `audit.Data_Quality_Rejections`: Hàng đợi dữ liệu chết (Dead-Letter Queue) hứng các dòng vi phạm nghiệp vụ bị SSIS rẽ nhánh.
5. `audit.Reconciliation_Log`: Ghi nhận kết quả đối soát dòng và giá trị tiền tệ giữa Staging và DWH do SSIS thực hiện.
6. `audit.ETL_Metadata`: Quản lý mốc High-Watermark (`Last_Load_Date`) phục vụ Incremental Load.

---

### **1.3. Mô hình 4 Tầng Kiểm soát Tận dụng Tối đa Sức mạnh SSIS Native**

```
[LỚP 1: SQL Server Agent Job]
   └── Điều phối lịch trình, kiểm soát Step tuần tự, Retry và kích hoạt Cảnh báo.
            │
            ▼
[LỚP 2: SSIS Control Flow Orchestration]
   ├── Sequence Container (Cô lập ranh giới giao dịch Transaction Boundary)
   ├── Execute SQL Task (Inline Parameterized SQL: Mở phiên log, Khởi tạo/Commit/Rollback Transaction)
   ├── Precedence Constraints (Ràng buộc biểu thức Success / Failure / Expression @DiscrepancyCount == 0)
   └── Send Mail Task (Gửi email thông báo tự động chuẩn SSIS)
            │
            ▼
[LỚP 3: SSIS Data Flow Engine (DQ & Redirection)]
   ├── Data Conversion / Flat File Source Error Output (Bẫy lỗi Type Mismatch, Truncation)
   ├── Script Component (Transformation) (Phân giải ErrorCode SSIS thành chuỗi mô tả lỗi đọc hiểu được)
   ├── Conditional Split (Bẫy các quy tắc nghiệp vụ: Doanh thu âm, dặm âm, ngược logic thời gian)
   ├── Lookup Transformation (Cơ chế Kimball: Redirect No-Match -> Derived Column gán Key = -1)
   └── Row Count Transformation (Bắt chính xác số lượng dòng nạp mới, cập nhật, loại bỏ vào biến SSIS)
            │
            ▼
[LỚP 4: SSIS Global Event Handlers]
   └── Scope Package / Container -> Bắt sự kiện OnError / OnTaskFailed
         ├── Thực thi Inline T-SQL: IF @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
         ├── Ghi Error Description vào audit.Error_Log
         └── Cập nhật audit.Package_Log thành 'FAILED'
```

---

## **2. DDL HỆ THỐNG BẢNG QUẢN TRỊ AUDIT & METADATA (T-SQL)**

Thực thi kịch bản tạo Schema và các bảng kiểm toán trên CSDL `Logistics_Staging` (chỉ khởi tạo bảng, toàn bộ thao tác nạp/sửa/xóa đều do SSIS đảm nhiệm):

```sql
USE Logistics_Staging;
GO

-- 1. Tạo Schema chuyên biệt audit
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'audit')
BEGIN
    EXEC('CREATE SCHEMA audit');
END
GO

-- 2. Bảng theo dõi phiên chạy cấp Batch (Job Master)
IF OBJECT_ID('audit.Batch_Log', 'U') IS NOT NULL DROP TABLE audit.Batch_Log;
CREATE TABLE audit.Batch_Log (
    batch_id            BIGINT IDENTITY(1,1) PRIMARY KEY,
    batch_name          VARCHAR(100) NOT NULL,
    triggered_by        VARCHAR(50) NOT NULL DEFAULT SUSER_SNAME(),
    start_time          DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    end_time            DATETIME2 NULL,
    status              VARCHAR(20) NOT NULL DEFAULT 'RUNNING', -- 'RUNNING', 'SUCCESS', 'FAILED'
    total_packages      INT NULL DEFAULT 0,
    error_summary       NVARCHAR(MAX) NULL
);
GO

-- 3. Bảng theo dõi tiến trình chi tiết của từng Package SSIS
IF OBJECT_ID('audit.Package_Log', 'U') IS NOT NULL DROP TABLE audit.Package_Log;
CREATE TABLE audit.Package_Log (
    package_log_id      BIGINT IDENTITY(1,1) PRIMARY KEY,
    batch_id            BIGINT NOT NULL FOREIGN KEY REFERENCES audit.Batch_Log(batch_id),
    package_name        VARCHAR(100) NOT NULL,
    start_time          DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    end_time            DATETIME2 NULL,
    source_row_count    BIGINT NULL DEFAULT 0,
    inserted_row_count  BIGINT NULL DEFAULT 0,
    updated_row_count   BIGINT NULL DEFAULT 0,
    rejected_row_count  BIGINT NULL DEFAULT 0,
    status              VARCHAR(20) NOT NULL DEFAULT 'RUNNING', -- 'RUNNING', 'SUCCESS', 'FAILED'
    error_message       NVARCHAR(MAX) NULL
);
GO

-- 4. Bảng ghi nhận ngoại lệ kỹ thuật toàn cục (SSIS Exception Log)
IF OBJECT_ID('audit.Error_Log', 'U') IS NOT NULL DROP TABLE audit.Error_Log;
CREATE TABLE audit.Error_Log (
    error_id            BIGINT IDENTITY(1,1) PRIMARY KEY,
    batch_id            BIGINT NULL,
    package_name        VARCHAR(100) NOT NULL,
    task_name           VARCHAR(100) NOT NULL,
    error_code          INT NULL,
    error_description   NVARCHAR(MAX) NOT NULL,
    logged_time         DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
GO

-- 5. Bảng Dead-Letter Queue (Chứa dòng bẩn bị rẽ nhánh ở cấp Data Flow)
IF OBJECT_ID('audit.Data_Quality_Rejections', 'U') IS NOT NULL DROP TABLE audit.Data_Quality_Rejections;
CREATE TABLE audit.Data_Quality_Rejections (
    rejection_id        BIGINT IDENTITY(1,1) PRIMARY KEY,
    batch_id            BIGINT NULL,
    package_name        VARCHAR(100) NOT NULL,
    source_table        VARCHAR(50) NOT NULL,       -- 'loads_sample.csv', 'trips', etc.
    business_key        VARCHAR(100) NULL,          -- 'LOAD00123', 'TRIP00000067'
    rule_name           VARCHAR(100) NOT NULL,      -- 'Negative Value', 'Invalid Date Order', 'Type Conversion'
    rejected_raw_data   NVARCHAR(MAX) NOT NULL,     -- Lưu chuỗi dữ liệu gốc dạng JSON hoặc Delimited text
    rejection_reason    NVARCHAR(500) NOT NULL,
    created_at          DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
GO

-- 6. Bảng kiểm tra đối soát số liệu liên tầng (Reconciliation Log)
IF OBJECT_ID('audit.Reconciliation_Log', 'U') IS NOT NULL DROP TABLE audit.Reconciliation_Log;
CREATE TABLE audit.Reconciliation_Log (
    check_id            BIGINT IDENTITY(1,1) PRIMARY KEY,
    batch_id            BIGINT NOT NULL,
    fact_table_name     VARCHAR(50) NOT NULL,
    source_row_count    BIGINT NOT NULL,
    dwh_row_count       BIGINT NOT NULL,
    difference_count    BIGINT NOT NULL,
    source_total_value  DECIMAL(18,2) NULL,
    dwh_total_value     DECIMAL(18,2) NULL,
    is_balanced         BIT NOT NULL,               -- 1 = Khớp, 0 = Lệch
    checked_time        DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
GO

-- 7. Bảng Metadata phục vụ High-Watermark Tracking
IF OBJECT_ID('audit.ETL_Metadata', 'U') IS NOT NULL DROP TABLE audit.ETL_Metadata;
CREATE TABLE audit.ETL_Metadata (
    table_name          VARCHAR(50) PRIMARY KEY,
    last_load_date      DATETIME2 NOT NULL,
    rows_inserted       BIGINT NULL DEFAULT 0,
    execution_status    VARCHAR(20) NOT NULL,
    updated_at          DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
GO

-- Khởi tạo mốc Watermark ban đầu
INSERT INTO audit.ETL_Metadata (table_name, last_load_date, rows_inserted, execution_status)
VALUES 
('Fact_Load', '2020-01-01 00:00:00', 0, 'INITIALIZED'),
('Fact_Trip', '2020-01-01 00:00:00', 0, 'INITIALIZED'),
('Fact_Maintenance', '2020-01-01 00:00:00', 0, 'INITIALIZED'),
('Fact_Delivery_Fulfillment', '2020-01-01 00:00:00', 0, 'INITIALIZED');
GO
```

---

## **3. QUY TRÌNH 5 BƯỚC THIẾT KẾ THUẦN TÚY TRÊN SSIS**

---

### **BƯỚC 1: XÂY DỰNG KHUNG AUDIT TRƯỚC VÀ SAU THỰC THI (PRE/POST AUDIT LOGGING)**

Thay vì gọi Stored Procedure, chúng ta sử dụng **Execute SQL Task** với câu lệnh T-SQL tham số hóa trực tiếp để quản lý vòng đời log của từng Package SSIS.

```
[Execute SQL Task: Start_Package_Audit]
                 │ (Success)
                 ▼
     [Sequence Container: Main ETL]
                 │ (Success)
                 ▼
[Execute SQL Task: Finish_Package_Audit]
```

#### **1. Danh mục Biến SSIS (Variables) cần tạo tại mỗi Package:**
* `User::BatchID` (Int64): Nhận giá trị ID phiên tổng thể truyền từ Master Orchestrator (mặc định đặt là `1` khi debug độc lập).
* `User::PackageLogID` (Int64): Lưu khóa định danh phiên chạy của package hiện tại.
* `User::SourceRowCount` (Int64): Số dòng đọc từ nguồn Staging/CSV.
* `User::InsertedRowCount` (Int64): Số dòng Fact mới được nạp.
* `User::UpdatedRowCount` (Int64): Số dòng cập nhật (SCD1 hoặc In-Flight Milestone).
* `User::RejectedRowCount` (Int64): Số dòng bẩn bị rẽ nhánh.

#### **2. Cấu hình Task Bắt đầu (`Start_Package_Audit`):**
* **Loại Task:** `Execute SQL Task`.
* **Connection:** Kết nối OLE DB đến `Logistics_Staging`.
* **SQLStatement:**
  ```sql
  INSERT INTO audit.Package_Log (batch_id, package_name, start_time, status)
  VALUES (?, ?, SYSDATETIME(), 'RUNNING');
  
  SELECT CAST(SCOPE_IDENTITY() AS BIGINT) AS package_log_id;
  ```
* **Parameter Mapping:**
  * Param 0 $\rightarrow$ `User::BatchID` (Input, Long)
  * Param 1 $\rightarrow$ `System::PackageName` (Input, String)
* **Result Set:**
  * Chọn `ResultSet = Single row`.
  * Tại tab *Result Set*, ánh xạ Result Name `0` vào biến `User::PackageLogID`.

#### **3. Cấu hình Task Kết thúc Thành công (`Finish_Package_Audit`):**
* **Loại Task:** `Execute SQL Task`.
* **SQLStatement:**
  ```sql
  UPDATE audit.Package_Log
  SET end_time = SYSDATETIME(),
      source_row_count = ?,
      inserted_row_count = ?,
      updated_row_count = ?,
      rejected_row_count = ?,
      status = 'SUCCESS'
  WHERE package_log_id = ?;
  ```
* **Parameter Mapping:**
  * Param 0 $\rightarrow$ `User::SourceRowCount` (Input, Long)
  * Param 1 $\rightarrow$ `User::InsertedRowCount` (Input, Long)
  * Param 2 $\rightarrow$ `User::UpdatedRowCount` (Input, Long)
  * Param 3 $\rightarrow$ `User::RejectedRowCount` (Input, Long)
  * Param 4 $\rightarrow$ `User::PackageLogID` (Input, Long)

---

### **BƯỚC 2: CƠ CHẾ ĐẢM BẢO CHẤT LƯỢNG DỮ LIỆU & RẼ NHÁNH DÒNG BẨN (DATA QUALITY & REDIRECTION)**

Không để pipeline sập vì một vài dòng sai lệch định dạng hoặc vi phạm ràng buộc nghiệp vụ. Chúng ta áp dụng luồng lọc 3 lớp trong **Data Flow Task**:

```
[Nguồn Dữ Liệu]
       │
       ▼ (Đếm dòng đọc)
[Row Count: SourceRowCount]
       │
       ▼
[Data Conversion] ──(Lỗi kiểu / Cắt chuỗi)──> [Script Component: Decode Error] ──> [audit.Data_Quality_Rejections]
       │ (Hợp lệ)
       ▼
[Conditional Split: Business DQ Rules]
       ├── (Doanh thu âm / Dặm âm / Sai logic ngày) ─────────────────────────────> [audit.Data_Quality_Rejections]
       └── (Hợp lệ: Default Output)
                 │
                 ▼
      [Lookup Surrogate Keys]
                 ├── Match ──────────────────────────────────────────────────────> [Row Count: InsertedRowCount] ──> [Bảng Fact Đích]
                 └── No Match ──> [Derived Column: Key = -1] ──> [Union All] ──┘ (Chuẩn Kimball)
```

#### **1. Bẫy lỗi kiểu dữ liệu và Truncation tại Data Conversion:**
* Mở thuộc tính của **Data Conversion Transformation** (hoặc **Flat File Source**):
  * Nhấp nút **Configure Error Output** ở góc dưới.
  * Với các cột số lượng, ngày tháng, tiền tệ: Chuyển thiết lập ở cả 2 cột `Error` và `Truncation` từ mặc định *Fail component* thành **Redirect row**.
* Kéo nhánh mũi tên đỏ (Error Output) vào một **Script Component** (chọn kiểu *Transformation*):
  * Tại tab *Input Columns*, chọn `ErrorCode` và `ErrorColumn`.
  * Tại tab *Inputs and Outputs*, thêm một cột đầu ra mới tên là `ErrorDescription` (kiểu dữ liệu `DT_WSTR`, chiều dài `500`).
  * Nhấp *Edit Script*, thêm đoạn mã C# tự động giải mã lỗi của SSIS:
    ```csharp
    public override void Input0_ProcessInputRow(Input0Buffer Row)
    {
        // Lấy thông điệp lỗi chính xác từ SSIS Engine dựa trên ErrorCode
        Row.ErrorDescription = this.ComponentMetaData.GetErrorDescription(Row.ErrorCode);
    }
    ```
* Sau Script Component, dùng một **Derived Column** để gán thêm các thông tin kiểm toán:
  * `RuleName`: `'Data Type Conversion or Truncation Error'`
  * `SourceTable`: `@[System::PackageName]`
  * `BatchID`: `@[User::BatchID]`
* Kéo tiếp vào **Row Count Transformation** (gán vào biến `User::RejectedRowCount`) rồi nạp thẳng vào bảng `audit.Data_Quality_Rejections` qua **OLE DB Destination**.

#### **2. Thiết lập Quy tắc Nghiệp vụ bằng Conditional Split Transformation:**
Căn cứ vào nghiệp vụ trong `thietke_dimfact.md`, thiết lập các điều kiện lọc chi tiết cho từng gói Fact:

* **Package `ETL_Commercial_Fulfillment.dtsx` (`Fact_Load`):**
  * *Nhánh Lỗi 1 (`Bad_Revenue_Values`):*
    ```
    revenue < 0 || fuel_surcharge < 0 || accessorial_charges < 0
    ```
  * *Nhánh Lỗi 2 (`Invalid_Weight_Or_Pieces`):*
    ```
    ISNULL(weight_lbs) || weight_lbs <= 0 || ISNULL(pieces) || pieces < 0
    ```
  * *Nhánh Hợp lệ (`Default Output`):* Cho đi tiếp vào khâu Lookup khóa chiều.

* **Package `ETL_Trip_Operations_Delivery.dtsx` (`Fact_Trip` & `Fact_Delivery_Fulfillment`):**
  * *Nhánh Lỗi `Fact_Trip` (`Bad_Trip_Metrics`):*
    ```
    actual_distance_miles < 0 || fuel_gallons_used < 0 || actual_duration_hours < 0
    ```
  * *Nhánh Lỗi `Fact_Delivery_Fulfillment` (`Timeline_Logic_Violation`):*
    ```
    pickup_actual_datetime > delivery_actual_datetime
    ```
    *(Thời điểm giao hàng thực tế không thể xảy ra trước thời điểm nhận hàng).*

* **Package `ETL_Fleet_Maintenance_Fuel.dtsx` (`Fact_Maintenance`):**
  * *Nhánh Lỗi (`Bad_Maintenance_Cost`):*
    ```
    labor_cost < 0 || parts_cost < 0 || downtime_hours < 0 || labor_hours < 0
    ```

Tất cả các nhánh sai phạm đều được nối vào luồng ghi nhận của bảng `audit.Data_Quality_Rejections`, giúp bảo toàn nguyên vẹn dòng dữ liệu nguồn sạch sẽ để nạp vào Fact.

#### **3. Xử lý Lookup No-Match chuẩn Kimball (Surrogate Key = -1):**
* Tại các component **Lookup Transformation** (`Lookup Customer`, `Lookup Driver`, `Lookup Truck`):
  * Trong tab *General*, tại mục *"Specify how to handle rows with no matching entries"*, chọn **Redirect rows to no match output** (KHÔNG CHỌN *Fail component*).
* Tại nhánh **No Match Output**:
  * Kéo vào một **Derived Column Transformation**.
  * Ghi đè hoặc gán khóa Surrogate Key bằng giá trị **`-1`** (Ví dụ: `customer_key = -1`, `driver_key = -1` đại diện cho *Unassigned / Unknown* theo đúng quy hoạch trong `thietke_dimfact.md`).
* Sử dụng **Union All Transformation** để gộp nhánh Match và nhánh No Match đã gán khóa `-1` trước khi ghi vào OLE DB Destination. Nhờ đó, pipeline không bao giờ bị đứt gãy vì thiếu dữ liệu chiều.

---

### **BƯỚC 3: CHIẾN LƯỢC ROLLBACK & QUẢN LÝ GIAO DỊCH NATIVE (100% SSIS - NO STORED PROCEDURES)**

Không sử dụng Stored Procedure, SSIS cung cấp **2 phương pháp chuẩn công nghiệp** để đảm bảo tính trọn vẹn dữ liệu (ACID) và khả năng Rollback tự động khi có sự cố:

#### **PHƯƠNG PHÁP: KẾT NỐI ĐƠN PHIÊN (`RetainSameConnection = True`) + INLINE TRANSACTION**

Đây là phương thức kiểm soát giao dịch mạnh mẽ nhất của SSIS trên một máy chủ SQL Server mà **hoàn toàn không cần bật dịch vụ MSDTC** (tránh được mọi lỗi mạng/firewall cổng 135 RPC).

##### **Nguyên lý hoạt động:**
Bình thường, mỗi Task trong SSIS sẽ mở một kết nối vật lý độc lập rồi đóng lại. Nếu ta bật thuộc tính `RetainSameConnection = True` trên OLE DB Connection Manager, toàn bộ các Task trong package sẽ **dùng chung duy nhất một session SQL Server**. Nhờ đó, một lệnh `BEGIN TRANSACTION` ở đầu Container sẽ bao bọc toàn bộ Data Flow Task và chỉ được chốt lại khi gặp lệnh `COMMIT`.

```
[Sequence Container: Fact_Load_Transaction_Scope]
   │
   ├── 1. Execute SQL Task: BEGIN_TRANSACTION
   │           │ (Success)
   │           ▼
   ├── 2. Execute SQL Task: PRE_CLEAN_EXISTING_BATCH (Idempotent DELETE)
   │           │ (Success)
   │           ▼
   ├── 3. Data Flow Task: LOAD_FACT_LOAD (Extract -> DQ -> Lookup -> OLE DB Dest)
   │           │ (Success)
   │           ▼
   ├── 4. Execute SQL Task: UPDATE_WATERMARK_METADATA
   │           │ (Success)
   │           ▼
   └── 5. Execute SQL Task: COMMIT_TRANSACTION
```

##### **Chi tiết cấu hình từng bước:**

1. **Cấu hình Connection Manager:**
   * Trong cửa sổ *Connection Managers*, nhấp đúp vào kết nối `Logistics_DW` (và `Logistics_Staging`).
   * Trong cửa sổ *Properties* (F4), tìm thuộc tính **`RetainSameConnection`** và chuyển từ `False` sang **`True`**.

2. **Cấu hình Task 1: `BEGIN_TRANSACTION` (`Execute SQL Task`):**
   * **Connection:** `Logistics_DW`
   * **SQLStatement:**
     ```sql
     BEGIN TRANSACTION;
     ```

3. **Cấu hình Task 2: `PRE_CLEAN_EXISTING_BATCH` (`Execute SQL Task`):**
   * **Mục đích:** Đảm bảo tính Idempotent (chạy lại bao nhiêu lần cũng không duplicate dữ liệu).
   * **SQLStatement:**
     ```sql
     -- Xóa các bản ghi đã tồn tại trong đợt nạp này dựa trên Staging CDC Keys
     DELETE target
     FROM dbo.Fact_Load target
     WHERE EXISTS (
         SELECT 1 
         FROM Logistics_Staging.dbo.Stg_CDC_Loads stg
         WHERE target.load_id = stg.load_id
     );
     ```

4. **Cấu hình Task 3: `LOAD_FACT_LOAD` (`Data Flow Task`):**
   * Thực hiện toàn bộ khâu Extract, Data Quality Conditional Split, Lookup khóa Dimension.
   * **OLE DB Destination:**
     * Trỏ vào `dbo.Fact_Load`.
     * Data access mode: Chọn **`Table or view - fast load`**.
     * **BỎ CHỌN** cờ *Table lock* (để tránh xung đột lock với session transaction hiện hành).
     * Đặt *Rows per batch* và *Maximum insert commit size* bằng `10000`.

5. **Cấu hình Task 4: `UPDATE_WATERMARK_METADATA` (`Execute SQL Task`):**
   * **SQLStatement:**
     ```sql
     UPDATE Logistics_Staging.audit.ETL_Metadata
     SET last_load_date = SYSDATETIME(),
         rows_inserted = ?,
         execution_status = 'SUCCESS',
         updated_at = SYSDATETIME()
     WHERE table_name = 'Fact_Load';
     ```
   * **Parameter Mapping:** Param 0 $\rightarrow$ `User::InsertedRowCount` (Input, Long).

6. **Cấu hình Task 5: `COMMIT_TRANSACTION` (`Execute SQL Task`):**
   * **SQLStatement:**
     ```sql
     COMMIT TRANSACTION;
     ```

##### **Cơ chế Kích hoạt Rollback Tự động khi Gặp Lỗi:**
Để tự động hủy bỏ dữ liệu dở dang khi Data Flow hoặc bất kỳ Task nào bên trong Sequence Container gặp sự cố, ta cấu hình luồng **Precedence Constraint đỏ (Failure)**:
* Từ Sequence Container, kéo đường mũi tên Precedence Constraint ra ngoài một **Execute SQL Task** đặt tên là `ROLLBACK_ON_FAILURE`.
* Nhấp đúp vào đường nối, chuyển *Value* từ `Success` sang **`Failure`**.
* Cấu hình nội dung `ROLLBACK_ON_FAILURE`:
  * **Connection:** `Logistics_DW` (chung kết nối `RetainSameConnection = True`).
  * **SQLStatement:**
    ```sql
    IF @@TRANCOUNT > 0
    BEGIN
        ROLLBACK TRANSACTION;
    END
    ```
* **Kết quả:** Nếu Data Flow Task sập ở dòng thứ 50.001, lệnh `ROLLBACK` lập tức trả kho dữ liệu `Fact_Load` về trạng thái nguyên vẹn ban đầu. Không có bất kỳ dòng rác nào lọt lại trong DWH!


### **BƯỚC 4: BẮT LỖI TOÀN CỤC BẰNG SSIS EVENT HANDLERS (`OnError`)**

Để bắt trọn vẹn mọi lỗi runtime (mã lỗi, tên component bị hỏng, câu thông báo chi tiết) mà không cần viết try-catch thủ công:

1. Mở Package trong Visual Studio $\rightarrow$ Nhấp vào tab **Event Handlers**.
2. Tại khung **Executable**: Chọn mức cao nhất (chính tên Package).
3. Tại khung **Event handler**: Chọn sự kiện **`OnError`**.
4. Kéo thả 2 Task tuần tự vào màn hình Event Handler:

```
[Event Handler: OnError]
         │
         ├── 1. Execute SQL Task: Rollback_Dangling_Transaction
         │           │ (Completion)
         │           ▼
         └── 2. Execute SQL Task: Write_Global_Error_Log
```

#### **Task 1: `Rollback_Dangling_Transaction` (`Execute SQL Task`):**
* **Connection:** `Logistics_DW`
* **SQLStatement:**
  ```sql
  IF @@TRANCOUNT > 0
      ROLLBACK TRANSACTION;
  ```

#### **Task 2: `Write_Global_Error_Log` (`Execute SQL Task`):**
* **Connection:** `Logistics_Staging`
* **SQLStatement:**
  ```sql
  -- 1. Ghi vết chi tiết vào bảng Error_Log
  INSERT INTO audit.Error_Log (
      batch_id, 
      package_name, 
      task_name, 
      error_code, 
      error_description
  )
  VALUES (?, ?, ?, ?, ?);

  -- 2. Đánh dấu trạng thái thất bại cho Package_Log
  UPDATE audit.Package_Log
  SET end_time = SYSDATETIME(),
      status = 'FAILED',
      error_message = ?
  WHERE package_log_id = ?;
  ```
* **Parameter Mapping:**
  * Param 0 $\rightarrow$ `User::BatchID` (Input, Long)
  * Param 1 $\rightarrow$ `System::PackageName` (Input, String)
  * Param 2 $\rightarrow$ `System::SourceName` (Input, String - Tự động bắt tên Task cụ thể bị nổ lỗi)
  * Param 3 $\rightarrow$ `System::ErrorCode` (Input, Long)
  * Param 4 $\rightarrow$ `System::ErrorDescription` (Input, String - Thông điệp kỹ thuật chuẩn xác của SSIS)
  * Param 5 $\rightarrow$ `System::ErrorDescription` (Input, String)
  * Param 6 $\rightarrow$ `User::PackageLogID` (Input, Long)

---

### **BƯỚC 5: ĐỐI SOÁT DỮ LIỆU TỰ ĐỘNG & GỬI CẢNH BÁO BẰNG SSIS TASKS (NO STORED PROCEDURES)**

Sau khi nạp xong dữ liệu tầng DWH, package kiểm soát chất lượng sẽ tự động đối soát chéo số lượng dòng và giá trị tiền tệ giữa Staging và DWH để đảm bảo không bị thất thoát bản ghi.

```
[Execute SQL Task: Run_Reconciliation_Check]
         │
         ├── (Precedence Constraint: @DiscrepancyCount > 0 - CÓ LỆCH DỮ LIỆU)
         │           │
         │           ▼
         │    [Send Mail Task: Send_Failure_Alert] ──> [Script Task: Force_Task_Fail]
         │
         └── (Precedence Constraint: @DiscrepancyCount == 0 - KHỚP 100%)
                     │
                     ▼
              [Cho phép nạp tiếp SSAS Cube]
```

#### **1. Cấu hình `Run_Reconciliation_Check` (`Execute SQL Task`):**
* **Khai báo biến:** `User::DiscrepancyCount` (Int32).
* **Connection:** `Logistics_Staging`
* **SQLStatement:**
  ```sql
  -- Inline T-SQL đối soát trực tiếp Fact_Load
  DECLARE @StgCount BIGINT, @DwhCount BIGINT;
  DECLARE @StgRev DECIMAL(18,2), @DwhRev DECIMAL(18,2);
  DECLARE @DiffCount BIGINT, @IsBalanced BIT;

  SELECT 
      @StgCount = COUNT(*),
      @StgRev = COALESCE(SUM(revenue + fuel_surcharge + accessorial_charges), 0)
  FROM Logistics_Staging.dbo.Stg_CDC_Loads;

  SELECT 
      @DwhCount = COUNT(*),
      @DwhRev = COALESCE(SUM(total_revenue), 0)
  FROM Logistics_DW.dbo.Fact_Load
  WHERE load_id IN (SELECT load_id FROM Logistics_Staging.dbo.Stg_CDC_Loads);

  SET @DiffCount = ABS(@StgCount - @DwhCount);
  SET @IsBalanced = CASE WHEN @DiffCount = 0 AND ABS(@StgRev - @DwhRev) < 0.01 THEN 1 ELSE 0 END;

  -- Ghi nhận kết quả vào bảng kiểm toán
  INSERT INTO audit.Reconciliation_Log (
      batch_id, fact_table_name, source_row_count, dwh_row_count, difference_count,
      source_total_value, dwh_total_value, is_balanced
  )
  VALUES (?, 'Fact_Load', @StgCount, @DwhCount, @DiffCount, @StgRev, @DwhRev, @IsBalanced);

  -- Trả về số lượng dòng bị lệch (0 = Hoàn hảo, > 0 = Thất thoát dữ liệu)
  SELECT CAST(@DiffCount AS INT) AS discrepancy_count;
  ```
* **Parameter Mapping:** Param 0 $\rightarrow$ `User::BatchID`.
* **Result Set:** Chuyển `ResultSet = Single row`, gán Result Name `0` vào biến `User::DiscrepancyCount`.

#### **2. Cấu hình Precedence Constraints phân nhánh nghiệp vụ:**
* **Nhánh Báo Động (Lệch số liệu):**
  * Kéo đường nối từ `Run_Reconciliation_Check` sang `Send_Failure_Alert`.
  * Nhấp đúp chuột vào đường nối:
    * *Evaluation operation*: Chọn **`Expression and Constraint`**.
    * *Value*: Chọn `Success`.
    * *Expression*: Gõ `@User::DiscrepancyCount > 0`.
* **Nhánh Hợp Lệ (Khớp 100%):**
  * Kéo đường nối sang Task kế tiếp (hoặc SSAS Processing Task).
  * *Expression*: Gõ `@User::DiscrepancyCount == 0`.

#### **3. Cấu hình Gửi Cảnh báo Bằng `Send Mail Task` (Native SSIS):**
* Tạo một **SMTP Connection Manager** trỏ tới SMTP Server nội bộ của doanh nghiệp (hoặc `localhost` / Office 365 SMTP relay).
* Tại **Send Mail Task**:
  * *From*: `ssis_alert@logistics.com`
  * *To*: `binhminh_lead@logistics.com;phucan_data@logistics.com;quangduy_bi@logistics.com`
  * *Subject*: `[CẢNH BÁO KHẨN] Phát Hiện Thất Thoát Dữ Liệu Trong Chu Trình ETL`
  * *MessageSourceType*: `Direct Input`
  * *MessageSource*: `Tiến trình đối soát tự động phát hiện số liệu giữa Staging và DWH không khớp. Pipeline đã bị dừng khẩn cấp trước khi xử lý SSAS Cube. Vui lòng kiểm tra audit.Reconciliation_Log!`
* Sau task gửi mail, đặt một **Script Task** chứa mã `Dts.Events.FireError(0, "Reconciliation", "Số liệu bị lệch!", "", 0); Dts.TaskResult = (int)ScriptResults.Failure;` để chủ động đánh dấu Step này bị Fail, ngăn chặn SQL Server Agent chạy tiếp sang bước nạp Cube!

---

## **4. ĐIỀU PHỐI PIPELINE BẰNG SQL SERVER AGENT (THAY THẾ AIRFLOW)**

Hệ thống chuyển đổi từ DAG Airflow sang **Multi-step SQL Server Agent Job** (`Logistics_Daily_ETL_Orchestration`). Agent Job sẽ điều phối các SSIS Package đã được deploy lên **SSISDB Catalog**:

```
[SQL Server Agent: Logistics_Daily_ETL_Orchestration]
  │
  ├── Step 1: Initialize Batch Log (Inline T-SQL) ───────────────(Fail)──> [Step 7: Send Failure Mail]
  │        (Success)
  ├── Step 2: Run Fuel Crawler (CmdExec - Python) ───────────────(Fail)──> [Step 7: Send Failure Mail]
  │        (Success)
  ├── Step 3: Run SSIS Staging Ingestion (SSIS Package) ─────────(Fail)──> [Step 7: Send Failure Mail]
  │        (Success)
  ├── Step 4: Run SSIS Master Orchestrator (SSIS Package) ───────(Fail)──> [Step 7: Send Failure Mail]
  │        (Success)
  ├── Step 5: Run SSIS Data Reconciliation (SSIS Package) ───────(Fail)──> [Step 7: Send Failure Mail]
  │        (Success)
  ├── Step 6: Process SSAS Galaxy Cube (XMLA Command) ───────────(Fail)──> [Step 7: Send Failure Mail]
  │        (Success)
  └── Step 8: Finalize Batch Log (Inline T-SQL: SUCCESS)
```

### **Bảng Đặc tả Cấu hình Các Step trên SQL Server Agent:**

| Step | Tên Step | Loại (Type) | Lệnh thực thi chi tiết (Command) | On Success | On Failure |
| :---: | :--- | :--- | :--- | :--- | :--- |
| **1** | `Init_Batch_Log` | T-SQL Script | `INSERT INTO Logistics_Staging.audit.Batch_Log (batch_name, status) VALUES ('Daily_ETL', 'RUNNING');` | Go to next step | Go to Step 7 (`Alert_Failure`) |
| **2** | `Run_Fuel_Crawler` | Operating System (CmdExec) | Gọi script cào giá dầu của Phúc An:<br>`python "C:\Logistics_ETL\fuel_price_crawler_api.py"` | Go to next step | Go to Step 7 (`Alert_Failure`) |
| **3** | `SSIS_Load_Staging` | SSIS Package Execution | Chọn gói từ Catalog: `\SSISDB\Logistics_ETL\ETL_Staging_Ingestion.dtsx` | Go to next step | Go to Step 7 (`Alert_Failure`) |
| **4** | `SSIS_Load_DWH` | SSIS Package Execution | Chọn gói điều phối: `\SSISDB\Logistics_ETL\Master_Orchestrator.dtsx` (Điều phối tuần tự các package Fact và Dim có tích hợp transaction). | Go to next step | Go to Step 7 (`Alert_Failure`) |
| **5** | `SSIS_Reconciliation` | SSIS Package Execution | Chọn gói đối soát: `\SSISDB\Logistics_ETL\ETL_Data_Reconciliation.dtsx` (Chứa logic so sánh và Send Mail Task). | Go to next step | Go to Step 7 (`Alert_Failure`) |
| **6** | `Process_SSAS_Cube` | SSAS Command (XMLA) | Gửi lệnh xử lý Full Cube:<br>`<Process xmlns="http://schemas.microsoft.com/analysisservices/2003/engine"><Object><DatabaseID>Logistics_SSAS</DatabaseID></Object><Type>ProcessFull</Type></Process>` | Go to Step 8 | Go to Step 7 (`Alert_Failure`) |
| **7** | `Alert_Failure` | T-SQL Script | Cập nhật `audit.Batch_Log` = `'FAILED'`. Đồng thời gọi lệnh dự phòng `msdb.dbo.sp_send_dbmail` nếu package SSIS bị dừng đột ngột ngoài tầm kiểm soát. | Quit with failure | Quit with failure |
| **8** | `Finalize_Batch_Success` | T-SQL Script | `UPDATE Logistics_Staging.audit.Batch_Log SET end_time = SYSDATETIME(), status = 'SUCCESS' WHERE batch_id = (SELECT MAX(batch_id) FROM Logistics_Staging.audit.Batch_Log);` | Quit with success | Quit with failure |

---

## **5. PHÂN CÔNG TRÁCH NHIỆM & KẾ HOẠCH NƯỚC RÚT 5 NGÀY**

### **5.1. Nguyên tắc Phối hợp Kỹ thuật**

* **Mô hình Hybrid (Nối đuôi - Song song):**
  * *Nối đuôi (Sequential):* Ngày 1 phải hoàn tất toàn bộ DDL Schema `[audit]` và bảng log dùng chung trước khi các thành viên bắt tay vào cấu hình SSIS. Ngày 4 nối đuôi để ghép nối vào Master Orchestrator. Ngày 5 kiểm thử đồng loạt.
  * *Song song (Parallel):* Trong các Ngày 2 và 3, mỗi thành viên thao tác độc lập trên các file package `.dtsx` riêng biệt đã được phân bổ trong `phancong.md`, tuyệt đối không sửa chồng chéo để tránh xung đột mã nguồn.

---

### **5.2. Kế hoạch Hành động Chi tiết Từng Ngày (Từ Ngày 1 đến Ngày 5)**

#### **NGÀY 1: KHỞI TẠO DDL AUDIT & THIẾT LẬP KẾT NỐI `RetainSameConnection` TRÊN SSIS**
*Tính chất: Nối đuôi sáng (Tạo hạ tầng CSDL) $\rightarrow$ Song song chiều (Khởi tạo khung package SSIS).*

| Thành viên | File / Đối tượng thao tác | Đầu vào (Input) | Sản phẩm bàn giao (Deliverables) |
| :--- | :--- | :--- | :--- |
| **Bình Minh** *(Trưởng nhóm)* | `01_init_audit_schema.sql`<br>`ETL_Commercial_Fulfillment.dtsx` | - CSDL `Logistics_Staging` & `Logistics_DW`.<br>- Thiết kế `Fact_Load` từ `thietke_dimfact.md`. | - Schema `[audit]` và 6 bảng log tạo thành công trên SQL Server.<br>- Khởi tạo biến Audit và cấu hình `RetainSameConnection = True` trên kết nối `Logistics_DW`. |
| **Phúc An** | `ETL_Fleet_Maintenance_Fuel.dtsx`<br>`02_fuel_staging_table.sql` | - Script DDL schema `audit` của Bình Minh.<br>- Thiết kế `Fact_Maintenance`.<br>- Tệp `fuel_market_rates_2022_2024.csv`. | - Bảng đệm `Stg_Daily_Fuel_Rates`.<br>- Cấu hình `RetainSameConnection = True` và khung biến Audit cho gói bảo dưỡng. |
| **Quang Duy** | `ETL_Trip_Operations_Delivery.dtsx` | - Script DDL schema `audit` của Bình Minh.<br>- Cấu trúc `Fact_Trip` và `Fact_Delivery_Fulfillment`. | - Cấu hình biến Audit, kết nối đơn phiên và khung Sequence Container cho 2 luồng Trip và Fulfillment. |

---

#### **NGÀY 2: TRIỂN KHAI DATA QUALITY, CONDITIONAL SPLIT & ERROR REDIRECTION**
*Tính chất: Song song 100% trên 3 package SSIS riêng biệt.*

| Thành viên | File / Đối tượng thao tác | Quy tắc DQ & Logic SSIS cần cấu hình | Sản phẩm bàn giao |
| :--- | :--- | :--- | :--- |
| **Bình Minh** | `ETL_Commercial_Fulfillment.dtsx` | - Flat File/Data Conversion: Configure Error Output $\rightarrow$ Redirect row.<br>- Script Component phân giải lỗi SSIS Engine sang text.<br>- Conditional Split: Lọc doanh thu âm, trọng lượng $\le 0$.<br>- Lookup Dim gán Surrogate Key `-1`. | - Luồng Data Flow nạp `Fact_Load` sạch $100\%$, toàn bộ dòng lỗi rẽ nhánh vào `audit.Data_Quality_Rejections`. |
| **Phúc An** | `ETL_Fleet_Maintenance_Fuel.dtsx`<br>`fuel_price_crawler_api.py` | - Data Conversion: Bẫy lỗi parse kiểu ngày tháng và số tiền.<br>- Conditional Split: Lọc chi phí phụ tùng âm, downtime âm.<br>- Lookup `Dim_Maintenance_Profile`: Gán `-1` cho mã lạ.<br>- Script Python cào giá dầu có bẫy lỗi HTTP timeout. | - Luồng nạp `Fact_Maintenance` cô lập dòng bẩn.<br>- Script cào giá dầu chạy độc lập ổn định. |
| **Quang Duy** | `ETL_Trip_Operations_Delivery.dtsx` | - Data Conversion: Bẫy chuỗi rỗng sang số của quãng đường.<br>- Conditional Split: Lọc chuyến xe dặm âm, ngày giao < ngày nhận.<br>- Lookup `Dim_Driver`, `Dim_Truck`: Gán Surrogate Key `-1` cho chuyến thiếu tài xế/đầu kéo.<br>- Accumulating Snapshot: Gán `delivery_date_key = -1` cho đơn In-Flight. | - Hoàn tất khâu làm sạch và rẽ nhánh lỗi cho cả `Fact_Trip` và `Fact_Delivery_Fulfillment`. |

---

#### **NGÀY 3: TÍCH HỢP TRANSACTION NATIVE, EVENT HANDLERS & ROW COUNTERS**
*Tính chất: Song song cấu hình; Nối đuôi cuối ngày để test chạy độc lập từng package.*

| Thành viên | File / Đối tượng thao tác | Logic SSIS triển khai (Thuần túy SSIS) | Sản phẩm bàn giao |
| :--- | :--- | :--- | :--- |
| **Bình Minh** | `ETL_Commercial_Fulfillment.dtsx` | - Sequence Container chứa: `BEGIN TRAN` $\rightarrow$ Idempotent DELETE $\rightarrow$ Data Flow $\rightarrow$ `COMMIT TRAN`.<br>- Precedence Constraint Failure $\rightarrow$ `ROLLBACK TRAN`.<br>- Event Handler `OnError` $\rightarrow$ Ghi log vào `audit.Error_Log`.<br>- Row Count gắn vào `User::InsertedRowCount`, `RejectedRowCount`. | - Package thương mại hoàn chỉnh cơ chế tự động Rollback không cần Stored Procedure. |
| **Phúc An** | `ETL_Fleet_Maintenance_Fuel.dtsx` | - Sequence Container bọc giao dịch Transaction nạp `Fact_Maintenance`.<br>- Execute SQL Task cập nhật High-Watermark vào `audit.ETL_Metadata` đặt sau Data Flow.<br>- Event Handler `OnError` bắt lỗi toàn cục.<br>- Cơ chế rollback xóa dữ liệu dở dang khi nạp lỗi. | - Package bảo dưỡng hoàn tất cơ chế kiểm soát giao dịch và cập nhật mốc Watermark an toàn. |
| **Quang Duy** | `ETL_Trip_Operations_Delivery.dtsx` | - Cấu hình 2 Sequence Container độc lập bọc Transaction cho `Fact_Trip` và `Fact_Delivery_Fulfillment`.<br>- Xử lý cập nhật In-Flight bằng OLE DB Command / Staging Merge trong SSIS.<br>- Event Handler `OnError` cấp Package. | - Package vận hành hoàn chỉnh toàn bộ cơ chế quản lý giao dịch và bắt lỗi toàn cục. |

---

#### **NGÀY 4: TÍCH HỢP MASTER ORCHESTRATOR, ĐỐI SOÁT & SQL SERVER AGENT**
*Tính chất: Nối đuôi liên hoàn (Phối hợp đồng bộ từ SSIS Master Package đến Agent Job).*

| Thành viên | File / Đối tượng thao tác | Đầu vào (Input) | Sản phẩm bàn giao |
| :--- | :--- | :--- | :--- |
| **Bình Minh** | `ETL_Data_Reconciliation.dtsx`<br>`SSISDB Catalog Configuration` | - Schema `[audit]`.<br>- Cấu trúc `Fact_Load` và `Stg_CDC_Loads`. | - Package SSIS đối soát tự động (`Run_Reconciliation_Check`) sử dụng Execute SQL Task và Send Mail Task.<br>- Thiết lập Parameters trên SSISDB Catalog. |
| **Phúc An** | `03_test_crawler_agent.bat`<br>`Test_Crawler_Agent.sql` | - Kịch bản Python `fuel_price_crawler_api.py`.<br>- Tài khoản thực thi Agent Service Account. | - Hoàn thiện Step 2 trên Agent Job gọi Python an toàn qua CmdExec.<br>- File bat kiểm tra mã thoát OS (`exit code`) của Python. |
| **Quang Duy** | `Master_Orchestrator.dtsx`<br>`04_create_sql_agent_job.sql` | - 3 package con đã hoàn thiện ở Ngày 3.<br>- Package đối soát của Bình Minh. | - Package `Master_Orchestrator.dtsx` liên kết tuần tự các package con qua Execute Package Task.<br>- Script tạo 8 Steps trên SQL Server Agent điều phối toàn trình. |

---

#### **NGÀY 5: KIỂM THỬ THỰC THI (FAULT INJECTION), CHỨNG MINH ROLLBACK & NGHIỆM THU**
*Tính chất: Nối đuôi thực nghiệm liên hoàn (Cả 3 thành viên cùng phối hợp trực tiếp trên server).*

| Thành viên | Kịch bản Kiểm thử / Nghiệm thu | Thao tác thực hiện | Bằng chứng nghiệm thu (Deliverables) |
| :--- | :--- | :--- | :--- |
| **Bình Minh** | **Test Case 1: Tiêm dòng bẩn (Fault Injection - Dirty Data)** | Cố tình chèn vào file nguồn CSV/Staging các dòng có doanh thu âm (`-5000`) và trọng lượng bằng `0`. Chạy package. | - Kiểm chứng: Package vẫn chạy `SUCCESS`.<br>- Dữ liệu sạch nạp đủ vào `Fact_Load`.<br>- Các dòng bẩn nằm chính xác trong bảng `audit.Data_Quality_Rejections` kèm nguyên nhân. |
| **Phúc An** | **Test Case 2: Kiểm chứng Rollback tự động (Crash Simulation)** | Chạy package nạp `Fact_Maintenance`. Khi Data Flow đang nạp dở dang, chủ động ngắt kết nối mạng hoặc ép dừng tiến trình. | - Kiểm chứng: Bảng `Fact_Maintenance` không có bất kỳ dòng rác nào (Rollback sạch sẽ $100\%$).<br>- Bảng `audit.ETL_Metadata` không bị nhảy mốc sai.<br>- Bảng `audit.Error_Log` ghi nhận thông tin sự cố. |
| **Quang Duy** | **Test Case 3: Đối soát thất thoát & Kích hoạt Cảnh báo** | Giả lập cố tình sửa lệch số đơn hàng giữa Staging và Fact. Chạy Job trên SQL Server Agent. | - Kiểm chứng: Step 5 đối soát phát hiện chênh lệch $\rightarrow$ Ngắt Job khẩn cấp, ngăn không cho nạp SSAS Cube.<br>- Nhận được email cảnh báo HTML qua Send Mail Task. |

---

### **5.3. Bảng Ma trận Phân nhiệm Kỹ thuật (RACI Matrix)**

* **R (Responsible):** Người trực tiếp cấu hình package SSIS / viết script DDL.
* **A (Accountable):** Người chịu trách nhiệm cao nhất về chất lượng và nghiệm thu.
* **C (Consulted):** Người được tham vấn chuyên môn, phối hợp giao tiếp interface.
* **I (Informed):** Người nhận thông báo kết quả.

| Phân hệ Kỹ thuật / Hạng mục Triển khai | Bình Minh | Phúc An | Quang Duy |
| :--- | :---: | :---: | :---: |
| **1. Thiết kế Schema `[audit]`, DDL Log & Metadata Tables** | **A / R** | C | C |
| **2. DQ & Error Redirection: `ETL_Commercial_Fulfillment.dtsx`** | **A / R** | I | C |
| **3. DQ, High-Watermark & Redirection: `ETL_Fleet_Maintenance_Fuel.dtsx`** | C | **A / R** | I |
| **4. DQ, In-Flight & Redirection: `ETL_Trip_Operations_Delivery.dtsx`** | C | I | **A / R** |
| **5. Cấu hình SSIS Event Handlers `OnError` toàn cục** | R | R | **A / R** |
| **6. Giao dịch Transaction & Rollback thuần túy SSIS (`RetainSameConnection`)** | **A / R** | R | R |
| **7. Package Đối soát Dữ liệu Tự động & Gửi Mail Cảnh báo** | **A / R** | C | C |
| **8. Tích hợp `Master_Orchestrator.dtsx` & SSISDB Catalog** | C | C | **A / R** |
| **9. Thiết lập Multi-step Job trên SQL Server Agent** | C | C | **A / R** |
| **10. Kịch bản Test Fault Injection, Kiểm chứng Rollback & Báo cáo** | **A / R** | R | R |