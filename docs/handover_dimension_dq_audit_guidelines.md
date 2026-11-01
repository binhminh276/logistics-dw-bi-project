# QUY CHUẨN THIẾT KẾ DATA QUALITY, AUDIT LOG & ROLLBACK CHO TẦNG DIMENSION (NO STORED PROCEDURES)
**Dự án:** Logistics & Fleet Operations Data Warehouse  
**Người soạn thảo:** NGUYỄN PHÚC AN  
**Đối tượng bàn giao:** BÌNH MINH, QUANG DUY  
**Mục tiêu:** Đồng bộ hóa 100% cơ chế Quản trị chất lượng dữ liệu (Data Quality), Rẽ nhánh dòng bẩn (Dead-Letter Queue), Giao dịch đơn phiên (Native Transaction & Rollback) và Nhật ký kiểm toán (Audit Trail) cho toàn bộ **9 bảng Dimension** trên 3 package SSIS, đảm bảo tính nhất quán tuyệt đối với tầng Fact đã hoàn thiện.

---

## 1. TỔNG QUAN KIẾN TRÚC & NGUYÊN TẮC BẮT BUỘC

Sau khi nhóm đã chuẩn hóa thành công luồng Data Quality và Rollback cho 4 bảng Fact, tầng Dimension cần được áp dụng cơ chế tương tự. Nếu một Dimension bị nạp dở dang hoặc chứa dữ liệu rác, toàn bộ các bảng Fact phụ thuộc phía sau sẽ bị gán khóa Surrogate Key `-1` hoặc phát sinh lỗi quan hệ nghiêm trọng.

### 4 Nguyên tắc cốt tử:
1. **100% NATIVE SSIS COMPONENTS:** Tuyệt đối không dùng Stored Procedure. Toàn bộ logic Transaction, DQ, Redirection và Audit thực hiện bằng Execute SQL Task, Sequence Container, Conditional Split, Data Conversion Error Output, Derived Column và Event Handlers.
2. **KẾT NỐI ĐƠN PHIÊN (`RetainSameConnection = True`):** Quản lý Transaction qua một session SQL Server duy nhất, không dùng MSDTC, tự động Rollback sạch sẽ khi Data Flow hoặc SCD gặp lỗi.
3. **IN-FLIGHT ERROR REDIRECTION:** Không để dòng bẩn lọt vào Dimension rồi mới đi quét dọn. Mọi dòng vi phạm quy tắc phải bị rẽ nhánh ngay trong RAM Buffer vào bảng `audit.Data_Quality_Rejections`.
4. **BẢO TOÀN BẢN GHI KIMBALL KHÓA `-1`:** Bản ghi mặc định `key = -1` (Unknown / Unassigned) của 9 bảng Dimension tuyệt đối không bao giờ bị ghi đè bởi SCD Type 1 và không bị tạo version mới bởi SCD Type 2.

---

## 2. MA TRẬN PHÂN CÔNG KỸ THUẬT TẦNG DIMENSION (RACI MATRIX)

| Package SSIS | Bảng Dimension đảm nhiệm | Loại SCD áp dụng | Thành viên phụ trách | Trách nhiệm RACI |
| :--- | :--- | :---: | :---: | :---: |
| **`Dim_Commercial.dtsx`** | - `Dim_Customer`<br/>- `Dim_Route`<br/>- `Dim_Load_Profile` | SCD 1 & 2<br/>SCD 1<br/>Junk Static | **Bình Minh** | **A / R** |
| **`Dim_Fleet.dtsx`** | - `Dim_Truck`<br/>- `Dim_Trailer`<br/>- `Dim_Maintenance_Profile`<br/>- `Dim_Date` | SCD 1 & 2<br/>SCD 1<br/>Junk Static<br/>Static DWH | **Phúc An** | **A / R** |
| **`Dim_Driver_Facility.dtsx`** | - `Dim_Driver`<br/>- `Dim_Facility` | SCD 1 & 2<br/>SCD 1 | **Quang Duy** | **A / R** |

*(Ghi chú: **A** - Accountable / Chịu trách nhiệm nghiệm thu; **R** - Responsible / Trực tiếp cấu hình).*

---

## 3. MÔ HÌNH KIẾN TRÚC CONTROL FLOW CHUẨN CHO MỖI PACKAGE DIMENSION

Mỗi file package Dimension (`Dim_Commercial.dtsx`, `Dim_Fleet.dtsx`, `Dim_Driver_Facility.dtsx`) bắt buộc phải tuân thủ đúng sơ đồ Control Flow sau:

```
[Execute SQL: Start_Package_Audit]
                 │ (Success)
                 ▼
[Sequence Container: SEQ_Dimension_Transaction_Scope] ──(Failure)──┐
   ├── 1. Execute SQL: BEGIN_TRANSACTION                           │
   │        │ (Success)                                            │
   │        ▼                                                      │
   ├── 2. Data Flow: DFT_Dim_Table_1 (Extract -> DQ -> SCD) ───(Fail)───┤
   │        │ (Success)                                            │
   │        ▼                                                      │
   ├── 3. Data Flow: DFT_Dim_Table_2 (Extract -> DQ -> SCD) ───(Fail)───┼──▶ [Execute SQL: ROLLBACK_ON_FAILURE]
   │        │ (Success)                                            │
   │        ▼                                                      │
   └── 4. Execute SQL: COMMIT_TRANSACTION                          │
                 │ (Success)                                       │
                 ▼                                                 │
[Execute SQL: Finish_Package_Audit]                                │
                                                                   │
* Lưu ý: Đường nối đỏ từ các Data Flow / Container sang Rollback ──┘
         phải đặt thuộc tính Multiple constraints = Logical OR (đường nét đứt).
```

---

## 4. BỘ THÔNG SỐ & CÂU LỆNH T-SQL CHUẨN HÓA CHO TỪNG TASK

### 4.1. Khởi tạo 6 Biến Chuẩn (Variables) tại cấp Package
Tất cả thành viên đặt đúng tên biến để đảm bảo tính đồng bộ toàn hệ thống:

| Tên biến (Variable Name) | Kiểu dữ liệu | Giá trị mặc định | Mục đích sử dụng |
| :--- | :---: | :---: | :--- |
| `User::vBatchID` | `Int64` | `1` | ID phiên tổng thể nhận từ Master Orchestrator |
| `User::vPackageLogID` | `Int64` | `0` | Khóa định danh của chính package trong `audit.Package_Log` |
| `User::vSourceRowCount` | `Int64` | `0` | Tổng số dòng đọc từ Staging/OLTP |
| `User::vInsertedRowCount` | `Int64` | `0` | Số dòng mới nạp (New SCD records) |
| `User::vUpdatedRowCount` | `Int64` | `0` | Số dòng cập nhật (SCD Type 1 hoặc đóng mốc SCD Type 2) |
| `User::vRejectedRowCount` | `Int64` | `0` | Số dòng bẩn vi phạm DQ bị rẽ nhánh |

---

### 4.2. Cấu hình Task `Start_Package_Audit`
- **Loại Task:** `Execute SQL Task`
- **Connection:** `Conn_Staging`
- **ResultSet:** `Single row`
- **SQLStatement:**
  ```sql
  INSERT INTO audit.Package_Log (batch_id, package_name, start_time, status)
  VALUES (?, ?, SYSDATETIME(), 'RUNNING');

  SELECT CAST(SCOPE_IDENTITY() AS BIGINT) AS package_log_id;
  ```
- **Parameter Mapping:**
  - Param `0` $\rightarrow$ `User::vBatchID` (Input, Long)
  - Param `1` $\rightarrow$ `System::PackageName` (Input, NVARCHAR)
- **Result Set:**
  - Result Name `0` $\rightarrow$ `User::vPackageLogID`

---

### 4.3. Cấu hình Task `BEGIN_TRANSACTION`
- **Loại Task:** `Execute SQL Task`
- **Connection:** `Conn_DW` *(Bắt buộc bật `RetainSameConnection = True` trong Properties)*
- **SQLStatement:**
  ```sql
  BEGIN TRANSACTION;
  ```

---

### 4.4. Cấu hình Task `COMMIT_TRANSACTION`
- **Loại Task:** `Execute SQL Task`
- **Connection:** `Conn_DW`
- **SQLStatement:**
  ```sql
  COMMIT TRANSACTION;
  ```

---

### 4.5. Cấu hình Task `ROLLBACK_ON_FAILURE` (Kèm đánh dấu FAILED)
- **Loại Task:** `Execute SQL Task`
- **Connection:** `Conn_DW`
- **SQLStatement:**
  ```sql
  IF @@TRANCOUNT > 0
  BEGIN
      ROLLBACK TRANSACTION;
  END

  UPDATE Logistics_Staging.audit.Package_Log
  SET end_time = SYSDATETIME(),
      status = 'FAILED'
  WHERE package_log_id = ?;
  ```
- **Parameter Mapping:** Param `0` $\rightarrow$ `User::vPackageLogID` (Input, Long).

---

### 4.6. Cấu hình Task `Finish_Package_Audit`
- **Loại Task:** `Execute SQL Task`
- **Connection:** `Conn_Staging`
- **SQLStatement:**
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
- **Parameter Mapping:**
  - Param `0` $\rightarrow$ `User::vSourceRowCount`
  - Param `1` $\rightarrow$ `User::vInsertedRowCount`
  - Param `2` $\rightarrow$ `User::vUpdatedRowCount`
  - Param `3` $\rightarrow$ `User::vRejectedRowCount`
  - Param `4` $\rightarrow$ `User::vPackageLogID`

---

### 4.7. Cấu hình Event Handler `OnError` cấp Package
Chuyển sang tab **Event Handlers** $\rightarrow$ Chọn Executable là Package $\rightarrow$ Event **`OnError`**:
Thêm một Execute SQL Task tên là **`EH_Rollback_Dangling_Transaction`**:
- **Connection:** `Conn_DW`
- **SQLStatement:**
  ```sql
  IF @@TRANCOUNT > 0
  BEGIN
      ROLLBACK TRANSACTION;
  END
  ```

---

## 5. TỪ ĐIỂN QUY TẮC DATA QUALITY & REDIRECTION CHO TỪNG BẢNG DIMENSION

Trong **Data Flow Task** của từng Dimension, dữ liệu phải đi qua bộ lọc **Conditional Split** trước khi nạp vào SCD Component hoặc Destination. 
- **Nhánh Lỗi:** Nối sang `DER_Audit_Rejection_Info` (gán `RuleName`, `RejectionReason`) $\rightarrow$ Row Count (`User::vRejectedRowCount`) $\rightarrow$ OLE DB Destination `audit.Data_Quality_Rejections` (trên `Conn_Staging`).
- **Nhánh Sạch (Default Output):** Đi tiếp vào luồng xử lý SCD / Insert Dimension.

```
[Source] ──> [Data Conversion Error Output] ──────────────────────────────────────────┐
                 │ (Hợp lệ)                                                            │
                 ▼                                                                     │
[Conditional Split: DQ Rules] ──(Dòng lỗi nghiệp vụ)──> [DER_Audit_Info] ──> [Count] ──┴─▶ [audit.Data_Quality_Rejections]
                 │ (Nhánh sạch)
                 ▼
       [SCD Transformation] ──> [Bảng Dimension Đích]
```

### 5.1. Bảng phân bổ quy tắc lọc chi tiết cho 3 thành viên:

#### A. PHÂN HỆ `Dim_Commercial.dtsx` (Bình Minh phụ trách)
1. **`Dim_Customer`**:
   - *Tên nhánh lỗi:* `Invalid_Customer_Profile`
   - *Biểu thức SSIS Conditional Split:*
     ```csharp
     ISNULL(customer_name) || TRIM(customer_name) == "" || credit_terms_days < 0 || annual_revenue_potential < 0
     ```
   - *SCD Rule:* `customer_name`, `primary_freight_type` (SCD Type 1); `credit_terms_days`, `customer_type`, `account_status` (SCD Type 2).
2. **`Dim_Route`**:
   - *Tên nhánh lỗi:* `Invalid_Route_Metrics`
   - *Biểu thức SSIS Conditional Split:*
     ```csharp
     typical_distance_miles <= 0 || typical_transit_days <= 0 || base_rate_per_mile <= 0 || fuel_surcharge_rate < 0
     ```
   - *SCD Rule:* SCD Type 1 cập nhật trực tiếp biến động đơn giá tuyến đường.

---

#### B. PHÂN HỆ `Dim_Fleet.dtsx` (Phúc An phụ trách)
1. **`Dim_Truck`**:
   - *Tên nhánh lỗi:* `Invalid_Truck_Specs`
   - *Biểu thức SSIS Conditional Split:*
     ```csharp
     ISNULL(vin) || LEN(TRIM(vin)) != 17 || tank_capacity_gallons <= 0 || model_year < 1990 || model_year > 2030
     ```
   - *SCD Rule:* `status`, `home_terminal` (SCD Type 1); `fuel_type`, `tank_capacity_gallons` (SCD Type 2 khi hoán cải động cơ).
2. **`Dim_Trailer`**:
   - *Tên nhánh lỗi:* `Invalid_Trailer_Specs`
   - *Biểu thức SSIS Conditional Split:*
     ```csharp
     ISNULL(trailer_number) || TRIM(trailer_number) == "" || capacity_lbs <= 0 || capacity_lbs > 100000
     ```
   - *SCD Rule:* `status`, `current_location` (SCD Type 1).

---

#### C. PHÂN HỆ `Dim_Driver_Facility.dtsx` (Quang Duy phụ trách)
1. **`Dim_Driver`**:
   - *Tên nhánh lỗi:* `Invalid_Driver_Profile`
   - *Biểu thức SSIS Conditional Split:*
     ```csharp
     ISNULL(license_number) || TRIM(license_number) == "" || years_experience < 0 || years_experience > 60 || ISNULL(first_name)
     ```
   - *SCD Rule:* `first_name`, `last_name`, `license_number` (SCD Type 1); `cdl_class`, `license_state`, `home_terminal`, `employment_status` (SCD Type 2).
2. **`Dim_Facility`**:
   - *Tên nhánh lỗi:* `Invalid_Facility_Location`
   - *Biểu thức SSIS Conditional Split:*
     ```csharp
     ISNULL(facility_name) || TRIM(facility_name) == "" || latitude < 20.0 || latitude > 55.0 || longitude < -130.0 || longitude > -65.0 || dock_doors < 0
     ```
     *(Tọa độ ngoài lãnh thổ tác nghiệp nước Mỹ hoặc số cửa dỡ hàng âm).*
   - *Lưu ý sống còn:* Áp dụng từ điển địa lý chuẩn hóa `Ref_City_Facility_Mapping` (`sql/07_create_delivery_events_mapping.sql`) trước khi nạp.

---

## 6. QUY TRÌNH KIỂM THỬ & NGHIỆM THU ĐỒNG BỘ 3 BƯỚC

Mỗi thành viên sau khi hoàn thiện package Dimension của mình phải tự kiểm thử 3 kịch bản:

1. **Test Case 1 (Happy Path):** Chạy package khi dữ liệu sạch $\rightarrow$ Tất cả các task chuyển **màu xanh lá cây**, bảng `audit.Package_Log` ghi nhận đúng `status = 'SUCCESS'`, `inserted_row_count > 0`, `rejected_row_count = 0`.
2. **Test Case 2 (Fault Injection - Dòng bẩn):** Cố tình giả lập 1 dòng có dung tích âm / số dặm âm / tên rỗng $\rightarrow$ Dữ liệu sạch vẫn nạp đủ vào Dimension, dòng lỗi nằm chính xác trong `audit.Data_Quality_Rejections` kèm lý do, package vẫn kết thúc `SUCCESS`.
3. **Test Case 3 (Crash & Rollback Simulation):** Ngắt kết nối mạng hoặc ép dừng tiến trình khi Data Flow đang nạp dở $\rightarrow$ Lệnh `ROLLBACK_ON_FAILURE` hoặc Event Handler `OnError` kích hoạt ngay lập tức, bảng Dimension trên `Logistics_DW` không bị rác dữ liệu, `audit.Package_Log` ghi nhận `status = 'FAILED'`.

