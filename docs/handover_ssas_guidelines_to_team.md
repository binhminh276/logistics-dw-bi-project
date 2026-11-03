# QUY CHUẨN THIẾT KẾ SSAS & HƯỚNG DẪN KỸ THUẬT TOÀN DIỆN CHO TEAM
**Dự án:** Logistics & Fleet Operations Enterprise Data Warehouse (SSAS Semantic Layer)  
**Người soạn thảo:** Quang Duy  
**Đối tượng sử dụng:** Bình Minh, Phúc An  
**Mục tiêu:** Cung cấp tài liệu quy chuẩn kỹ thuật SSAS Multidimensional Cube, quy tắc đặt tên, cấu trúc dự án, cấu hình Data Source View (DSV), thiết lập 4 Measure Groups, Role-Playing Dimensions, User Hierarchies, câu lệnh tính toán MDX/DAX, và kịch bản Process tự động qua Airflow/PowerShell. Tài liệu giúp các thành viên và AI Agent triển khai chính xác $100\%$, đồng bộ toàn hệ thống, triệt tiêu lỗi quan hệ $N-N$ và lỗi bẫy không gian đa chiều.

---

## 1. CẤU TRÚC THƯ MỤC DỰ ÁN (PROJECT DIRECTORY STRUCTURE)

Dự án SSAS Multidimensional được đặt tại thư mục `SSAS_Logistics/` nằm ở thư mục gốc repository để tích hợp đồng bộ với SSIS và CSDL `Logistics_DW`:

```
d:\Kho\Project\ (Repo Root)
│
├── Data/                             <-- Dữ liệu thô CSV & JSON cào từ Web
├── sql/                              <-- 01 đến 07 script khởi tạo SQL Server
├── SSIS_Logistics/                   <-- Dự án SSIS Packages ETL
│
├── docs/                             
│   ├── handover_ssis_guidelines_to_team.md  <-- Quy chuẩn SSIS
│   └── handover_ssas_guidelines_to_team.md  <-- TÀI LIỆU NÀY
│
└── SSAS_Logistics/                   <-- DỰ ÁN SSAS MULTIDIMENSIONAL CUBE
    ├── SSAS_Logistics.dwproj         <-- File Solution SSAS Project
    ├── DS_Logistics_DW.ds            <-- Data Source kết nối tới Logistics_DW
    ├── DSV_Logistics_DW.dsv          <-- Data Source View (Galaxy Schema)
    │
    ├── Dimensions/                   <-- Các file định nghĩa Dimensions (.dim)
    │   ├── Dim_Date.dim              <-- Role-Playing Date Dimension
    │   ├── Dim_Customer.dim          
    │   ├── Dim_Route.dim             <-- Chứa 2 nhánh Hierarchy (Origin & Destination)
    │   ├── Dim_Driver.dim            
    │   ├── Dim_Facility.dim          <-- Role-Playing Facility Dimension
    │   ├── Dim_Truck.dim             
    │   ├── Dim_Trailer.dim           
    │   ├── Dim_Load_Profile.dim      <-- Junk Dimension
    │   └── Dim_Maintenance_Profile.dim<-- Junk Dimension
    │
    ├── Cubes/                        
    │   └── Cube_Logistics_Galaxy.cube<-- Galaxy Cube (4 Measure Groups)
    │
    └── Scripts/                      <-- Script tự động hóa Deployment & Process
        ├── process_cube.xmla         <-- Script XMLA Process Full Cube
        └── process_ssas.ps1          <-- PowerShell Script chạy XMLA cho Airflow
```

---

## 2. HƯỚNG DẪN THIẾT LẬP HẠ TẦNG KẾT NỐI SSAS (DATA SOURCE & DSV)

Trước khi khởi tạo Cube, tất cả thành viên (hoặc AI Agent) phải kết nối dự án SSAS vào CSDL `Logistics_DW` đã được nạp dữ liệu sạch từ SSIS.

### A. Thiết lập Data Source (`DS_Logistics_DW.ds`)
1. **Provider:** Native OLE DB\Microsoft OLE DB Driver for SQL Server (hoặc `SQLNCLI11`).
2. **Server Name:** `localhost` (hoặc `.`).
3. **Authentication:** Windows Authentication (Integrated Security).
4. **Database Name:** `Logistics_DW`.
5. **Impersonation Information:** Chọn **`Use the credentials of the current user`** (hoặc `ImpersonateServiceAccount`).

### B. Thiết lập Data Source View (`DSV_Logistics_DW.dsv`)
Kéo toàn bộ **4 bảng Fact** và **9 bảng Dimension** từ CSDL `Logistics_DW` vào màn hình DSV. Kiểm tra và bổ sung quan hệ Logical Relationships (Khóa ngoại $\rightarrow$ Khóa chính) nếu SSAS chưa tự động nhận diện:

> [!IMPORTANT]
> **Quy tắc bắt buộc trong DSV:** Chỉ tạo quan hệ giữa **bảng Dimension với bảng Fact** (chiều → fact). Tuyệt đối **KHÔNG nối Fact với Fact** — SSAS không hỗ trợ quan hệ FK trực tiếp giữa các bảng Fact và sẽ gây lỗi Cartesian Product khi Process Cube.

Sơ đồ quan hệ **chính xác** theo DDL trong `sql/04_create_dwh.sql`:

```
  ┌────────────────┐     ┌─────────────────┐
  │  Dim_Customer  │     │ Dim_Load_Profile │
  └───────┬────────┘     └────────┬────────┘
          │  customer_key         │ load_profile_key
          │              ┌────────┘
          └──────────────▼──────────────┐
                  ┌──────────────────┐  │  ┌────────────┐
                  │   Fact_Load      ◄──┴──►  Dim_Date  │ (Conformed)
                  │ load_date_key    │     │ (1 chiều   │
                  │ customer_key     │     │  dùng chung│
                  │ route_key        │     │  cả 4 Fact)│
                  │ load_profile_key │     └─────┬──────┘
                  └──────────────────┘           │ date_key
                                                 │
  ┌────────────┐  ┌────────────┐    ┌────────────▼──────────────────┐
  │  Dim_Truck │  │ Dim_Driver │    │          Fact_Trip             │
  └─────┬──────┘  └─────┬──────┘    │ dispatch_date_key → Dim_Date  │
        │               │           │ driver_key  → Dim_Driver       │
        │               └───────────► truck_key   → Dim_Truck        │
        │                           │ trailer_key → Dim_Trailer      │
        │           ┌──────────────-┘                                │
        │           │                                                │
  ┌─────▼──────┐    │  ┌────────────────────────────────────────┐   │
  │ Dim_Trailer│    │  │       Fact_Delivery_Fulfillment         │   │
  └────────────┘    │  │ pickup_date_key   → Dim_Date (vai trò 1)│  │
                    │  │ delivery_date_key → Dim_Date (vai trò 2)│  │
  ┌─────────────┐   │  │ origin_facility_key  → Dim_Facility     │  │
  │ Dim_Facility│   │  │ destination_facility_key → Dim_Facility │  │
  │(Role-Play.) │   │  │ customer_key → Dim_Customer             │  │
  └──────┬──────┘   │  │ route_key    → Dim_Route               │  │
         │           │  └──────────────────────────────────────--┘  │
  ┌──────▼──────┐   │                                               │
  │  Dim_Route  │   │  ┌──────────────────────────────────────┐     │
  └─────────────┘   │  │          Fact_Maintenance             │     │
                    │  │ maintenance_date_key → Dim_Date       │     │
                    └──► truck_key  → Dim_Truck                │     │
                       │ maintenance_profile_key → Dim_Maint.. │     │
                       │ facility_location (Degenerate Dim)    │     │
                       └──────────────────────────────────────-┘     │
                                                                     │
  ┌──────────────────────────────┐                                   │
  │ Dim_Maintenance_Profile      │                                   │
  └──────────────────────────────┘                                   │
```

> [!WARNING]
> `Fact_Maintenance` **KHÔNG** có khóa ngoại tới `Dim_Facility`. Địa điểm bảo dưỡng được lưu dạng cột text `facility_location` (Degenerate Dimension) — không nối Fact này vào `Dim_Facility` trong DSV!

---

## 3. QUY CHUẨN ĐẶT TÊN (NAMING CONVENTIONS FOR SSAS)

Tất cả các đối tượng trong dự án SSAS bắt buộc phải tuân thủ tiền tố và định dạng sau để đảm bảo báo cáo Power BI / Excel đọc vào dễ hiểu $100\%$:

### A. Data Source & DSV:
* Data Source: `DS_Logistics_DW`
* Data Source View: `DSV_Logistics_DW`
* Cube Name: `Cube_Logistics_Galaxy`

### B. Dimensions & Attributes:
* **Dimension File:** `Dim_<Tên Chiều>.dim` (Ví dụ: `Dim_Customer.dim`, `Dim_Date.dim`).
* **Role-Playing Dimension trong Cube:** `<Vai trò> <Tên Chiều>`  
  *(Ví dụ: `Pickup Date`, `Delivery Date` — chỉ dùng cho `Fact_Delivery_Fulfillment`; `Origin Facility`, `Destination Facility` — chỉ dùng cho `Fact_Delivery_Fulfillment`)*.
  
  > **LƯU Ý CONFORMED DIMENSION:** `Dim_Date` là chiều dùng chung (Conformed Dimension) của toàn bộ Galaxy Cube. Mỗi bảng Fact chỉ map 1 vai trò Date chính (`load_date_key`, `dispatch_date_key`, `pickup_date_key`, `maintenance_date_key`). **KHÔNG** tạo 5 Role-Playing Date riêng lẻ cho từng Fact — điều này phá vỡ khả năng Drill-Across liên Fact theo thời gian trên Power BI. Role-Playing chỉ áp dụng khi **cùng 1 Fact** cần nối tới cùng 1 Dimension theo 2 vai trò khác nhau (như `pickup_date_key` và `delivery_date_key` trong `Fact_Delivery_Fulfillment`).
* **Attribute Key (Khóa chính):** Giữ nguyên tên cột Surrogate Key (`customer_key`, `date_key`, `truck_key`). Chuyển thuộc tính `AttributeHierarchyVisible = False` cho các cột Key thô không dùng trực tiếp trên báo cáo.
* **Attribute Name (Tên thuộc tính hiển thị):** Đổi tên sang dạng Tiêu chuẩn viết hoa từng từ (Capitalized Words), bỏ dấu gạch dưới `_`.  
  *(Ví dụ: `customer_name` $\rightarrow$ `Customer Name`, `cdl_class` $\rightarrow$ `CDL Class`, `city` $\rightarrow$ `City`)*.

### C. User Hierarchies (Phân cấp người dùng):
* Tiền tố: Tiêu đề rõ ràng không chứa dấu gạch dưới.
* **Date Hierarchies:**
  * `Calendar Hierarchy`: `Calendar Year` $\rightarrow$ `Calendar Quarter` $\rightarrow$ `Month Name` $\rightarrow$ `Full Date`.
  * `Fiscal Hierarchy`: `Fiscal Year` $\rightarrow$ `Fiscal Quarter` $\rightarrow$ `Month Name` $\rightarrow$ `Full Date`.
* **Route Hierarchies (Tách 2 nhánh độc lập — xem lý do tại Mục 5.A):**
  * `Route Origin Hierarchy`: `Origin State` $\rightarrow$ `Origin City` $\rightarrow$ `Route ID`.
  * `Route Destination Hierarchy`: `Destination State` $\rightarrow$ `Destination City` $\rightarrow$ `Route ID`.
  
  > Lá cuối cùng của phân cấp phải khớp với tên cột thực tế trong DDL: cột **`route_id`** (ví dụ `RT00001`), **không phải** `Route Code` — dùng sai tên cột sẽ báo lỗi biên dịch SSAS.
* **Facility Hierarchy:** `Facility State` $\rightarrow$ `Facility City` $\rightarrow$ `Facility Name`.

### D. Measure Groups & Measures:
* **Measure Group Name:** `MG_<Tên Bảng Fact>` (Ví dụ: `MG_Fact_Load`, `MG_Fact_Trip`, `MG_Fact_Delivery_Fulfillment`, `MG_Fact_Maintenance`).
* **Physical Measures (Số liệu gốc):** Đặt tên rõ ràng, kèm định dạng format string phù hợp.
  * `Total Revenue` (Format: `Currency`, Aggregation: `Sum`)
  * `Load Count` (Format: `#,##0`, Aggregation: `Sum`)
  * `Fuel Gallons Used` (Format: `#,##0.00`, Aggregation: `Sum`)
  * `Actual Duration Hours` (Format: `#,##0.00`, Aggregation: `Sum`)
  * `Odometer Reading` (Format: `#,##0`, Aggregation: `Max`) — xem lý do tại Mục 5.B
* **Calculated Measures (Biểu thức MDX/DAX):** Tiền tố `CM_` trong code MDX, tên hiển thị trên Cube chuyên nghiệp.
  * `[Measures].[CM_On_Time_Delivery_Rate]` (Tỷ lệ giao hàng đúng hẹn SLA %)
  * `[Measures].[CM_Fleet_TCO]` (Tổng chi phí sở hữu đội xe)
  * `[Measures].[CM_Revenue_Per_Pound]` (Doanh thu thực tế trên mỗi lb)
  * `[Measures].[CM_Idle_Time_Percentage]` (Tỷ lệ nổ máy dừng chờ lãng phí %)

---

## 4. QUY TRÌNH 5 BƯỚC CHUẨN ĐỂ XÂY DỰNG SSAS CUBE (GUIDE CHO AGENT & DEV)

Mỗi khi thành viên hoặc AI Agent nhận nhiệm vụ dựng mảng SSAS Cube, hãy tuân thủ tuần tự 5 bước kỹ thuật sau:

```
[Bước 1: Khai báo DSV & Logical Keys] ──> [Bước 2: Tạo Shared Dimensions & Hierarchies]
                                                             │
                                                             ▼
[Bước 4: Cấu hình Dimension Usage & Roles] <── [Bước 3: Tạo Galaxy Cube & 4 Measure Groups]
               │
               ▼
[Bước 5: Viết Biểu thức MDX, Deploy & Process XMLA]
```

### Bước 1: Khai báo DSV & Logical Keys
1. Mở `DSV_Logistics_DW.dsv`, kiểm tra 4 bảng Fact và 9 bảng Dimension.
2. Đảm bảo tất cả các bảng Dimension đều có **Primary Key** chuẩn (Surrogate Key).
3. Đảm bảo các bảng Fact có các quan hệ **Foreign Key** chỉ tới các bảng Dimension tương ứng.

### Bước 2: Tạo Shared Dimensions & User Hierarchies
1. Chuột phải mục **Dimensions** $\rightarrow$ **New Dimension** $\rightarrow$ Dùng Wizard tạo từ DSV.
2. Cấu hình `KeyColumns` và `NameColumn` cho từng thuộc tính (Ví dụ: `date_key` làm KeyColumn, `full_date` làm NameColumn).
3. Kéo thả các thuộc tính từ cột *Attributes* sang cột *Hierarchies* để tạo cây phân cấp.
4. **Bắt buộc:** Đặt thuộc tính `AttributeRelationships` giữa các cấp trong Hierarchy (Ví dụ: `Full Date` $\rightarrow$ `Month Name` $\rightarrow$ `Calendar Quarter` $\rightarrow$ `Calendar Year`) để SSAS tối ưu hóa Index và Pre-aggregation.

### Bước 3: Tạo Galaxy Cube & 4 Measure Groups
1. Chuột phải mục **Cubes** $\rightarrow$ **New Cube** $\rightarrow$ Select `DSV_Logistics_DW`.
2. Select Fact Tables: Tích chọn cả **4 bảng Fact** (`Fact_Load`, `Fact_Trip`, `Fact_Delivery_Fulfillment`, `Fact_Maintenance`).
3. Select Measures: Tích chọn các cột số đo lường (`revenue`, `fuel_gallons_used`, `actual_duration_hours`, `labor_cost`, `parts_cost`...) và bỏ tích các cột khóa ngoại.
4. Đổi tên Measure Groups thành `MG_Fact_Load`, `MG_Fact_Trip`, `MG_Fact_Delivery_Fulfillment`, `MG_Fact_Maintenance`.

### Bước 4: Cấu hình Dimension Usage & Role-Playing Relationships
Mở tab **Dimension Usage** trong Cửa sổ Thiết kế Cube để map mối quan hệ giữa Measure Groups và Dimensions:

**Bảng Bus Matrix chuẩn hóa (✔ = Regular Relationship, RP = Role-Playing, — = không có quan hệ):**

| Dimension | MG_Fact_Load | MG_Fact_Trip | MG_Fact_Delivery_Fulfillment | MG_Fact_Maintenance |
| :--- | :---: | :---: | :---: | :---: |
| `Dim_Date` | ✔ `load_date_key` | ✔ `dispatch_date_key` | RP `pickup_date_key` + RP `delivery_date_key` | ✔ `maintenance_date_key` |
| `Dim_Customer` | ✔ `customer_key` | — | ✔ `customer_key` | — |
| `Dim_Route` | ✔ `route_key` | — | ✔ `route_key` | — |
| `Dim_Load_Profile` | ✔ `load_profile_key` | — | ✔ `load_profile_key` | — |
| `Dim_Driver` | — | ✔ `driver_key` | — | — |
| `Dim_Truck` | — | ✔ `truck_key` | — | ✔ `truck_key` |
| `Dim_Trailer` | — | ✔ `trailer_key` | — | — |
| `Dim_Facility` | — | — | RP `origin_facility_key` + RP `destination_facility_key` | — |
| `Dim_Maintenance_Profile` | — | — | — | ✔ `maintenance_profile_key` |

**Cấu hình Role-Playing (chỉ áp dụng trong `Fact_Delivery_Fulfillment`):**
* Map `Dim_Date` lần 1 với `pickup_date_key` → Đặt tên vai trò: **`Pickup Date`**.
* Map `Dim_Date` lần 2 với `delivery_date_key` → Đặt tên vai trò: **`Delivery Date`**.
* Map `Dim_Facility` lần 1 với `origin_facility_key` → Đặt tên vai trò: **`Origin Facility`**.
* Map `Dim_Facility` lần 2 với `destination_facility_key` → Đặt tên vai trò: **`Destination Facility`**.

### Bước 5: Viết Biểu thức MDX, Deploy & Process XMLA
1. Chuyển sang tab **Calculations** trong Cube Designer để viết các Calculated Measures bằng MDX.
2. Kiểm tra biên dịch (Build Solution - `Ctrl + Shift + B`).
3. Chuột phải vào Project `SSAS_Logistics` $\rightarrow$ **Properties** $\rightarrow$ **Deployment**:
   * Target Server: `localhost` (hoặc tên Instance SSAS Multidimensional của máy).
   * Target Database: `SSAS_Logistics_Galaxy`.
4. Chuột phải Project $\rightarrow$ **Deploy**. Bấm **Process Full** để nạp dữ liệu từ CSDL `Logistics_DW` vào Cube.

---

## 5. CÁC QUY CHUẨN KỸ THUẬT QUAN TRỌNG & BẪY KỸ THUẬT CẦN TRÁNH

### A. Tách 2 Nhánh User Hierarchies cho `Dim_Route` (Tránh lỗi Attribute Relationship Violation)
* **Bản chất vấn đề:** Mỗi tuyến đường (`Dim_Route`) có một điểm đầu (`origin_city`, `origin_state`) và một điểm cuối (`destination_city`, `destination_state`). Nếu gom chung vào 1 cây phân cấp `State` $\rightarrow$ `City` $\rightarrow$ `Route`, SSAS sẽ bị lỗi **Attribute Relationship Violation** — vì 1 `route_id` có tới 2 giá trị `State` khác nhau, vi phạm ràng buộc phân cấp 1-nhiều (Many-to-One từ cấp dưới lên cấp trên).
  
  > **Chú ý thuật ngữ:** Đây là vấn đề **Đa nhánh phân cấp độc lập (Multiple Independent Hierarchies)** trên cùng 1 Dimension, **không phải** Bẫy $N-N$ (Many-to-Many Trap). Bẫy $N-N$ trong SSAS chỉ phát sinh khi 1 Fact liên kết với nhiều dòng Dimension thông qua bảng Bridge Factless trung gian — đó là vấn đề hoàn toàn khác.

* **Quy chuẩn bắt buộc:** Trong `Dim_Route.dim`, phải thiết lập **2 cây phân cấp độc lập**:
  1. `Route Origin Hierarchy`: `Origin State` $\rightarrow$ `Origin City` $\rightarrow$ `Route ID`.
  2. `Route Destination Hierarchy`: `Destination State` $\rightarrow$ `Destination City` $\rightarrow$ `Route ID`.
  
  > Lá cuối cùng của mỗi phân cấp map tới cột **`route_id`** (không phải `Route Code`) theo đúng DDL trong `sql/04_create_dwh.sql`.

### B. Xử lý Semi-Additive Measure cho `Odometer Reading` (Chỉ số đồng hồ km)
* **Bản chất nghiệp vụ:** Số chỉ đồng hồ Odometer của xe tải không thể cộng dồn theo thời gian (không thể lấy tổng Odometer ngày 1 + ngày 2). Đây là chỉ số bán cộng dồn (Semi-additive).
* **Quy chuẩn trong SSAS — Dùng `Max`, KHÔNG dùng `LastNonEmpty`:**
  * Chọn Measure `Odometer Reading` trong `MG_Fact_Maintenance`.
  * Trong cửa sổ Properties, đổi thuộc tính `AggregateFunction` từ `Sum` sang **`Max`**.
  
  > **Lý do kỹ thuật:** `LastNonEmpty` chỉ đúng với bảng **Periodic Snapshot** (tồn kho cuối ngày, số dư cuối tháng — loại bảng ghi tổng hợp theo chu kỳ cố định). `Fact_Maintenance` là bảng **Transaction Fact** (sự kiện phát sinh bất định). Nếu dùng `LastNonEmpty` ở cấp độ **Tất cả xe (All Trucks)**, SSAS sẽ lấy số km của **chiếc xe được bảo dưỡng cuối cùng** gán cho toàn đội xe — kết quả hoàn toàn vô nghĩa về mặt nghiệp vụ. `Max` mang ý nghĩa đúng hơn: số km cao nhất từng ghi nhận trên xe đó.

### C. Công thức MDX Chuẩn hóa cho các Chỉ số KPI Nghiệp vụ Cốt lõi

> [!IMPORTANT]
> Toàn bộ 3 thành viên phải sử dụng đúng các công thức MDX được khai báo dưới đây trong tab **Calculations** của Cube để đảm bảo số liệu trên Power BI trùng khớp $100\%$.

#### 1. Tỷ lệ Giao hàng Đúng hẹn SLA (%) — Trừ đơn hàng In-Flight (`delivery_date_key = -1`):
$$CM\_On\_Time\_Delivery\_Rate = \frac{\sum(delivery\_on\_time\_count)}{\sum(completed\_fulfillment\_count)} \times 100\%$$

```mdx
CREATE MEMBER CURRENTCUBE.[Measures].[CM_On_Time_Delivery_Rate] AS
IIF(
    [Measures].[Completed Fulfillment Count] = 0,
    NULL,
    [Measures].[Delivery On Time Count] / [Measures].[Completed Fulfillment Count]
),
FORMAT_STRING = "Percent",
ASSOCIATED_MEASURE_GROUP = 'MG_Fact_Delivery_Fulfillment';
```

#### 2. Tổng Chi phí Sở hữu Đội xe (Fleet TCO - Cross-Fact Drill-Across):
$$Fleet\_TCO = \sum(Fact\_Trip.fuel\_gallons\_used \times Market\_Diesel\_Price) + \sum(Fact\_Maintenance.total\_cost)$$

> **Ghi chú kỹ thuật quan trọng:**  
> Công thức này thực hiện **Drill-Across** qua 2 Fact khác nhau (`Fact_Trip` và `Fact_Maintenance`). Hai bảng này **chỉ có 2 chiều dùng chung là `Dim_Truck` và `Dim_Date`**. Khi người dùng kéo bất kỳ chiều chỉ thuộc 1 Fact vào báo cáo (như `Dim_Driver`, `Dim_Customer`), số liệu sẽ bị lặp hoặc NULL không đúng ngữ cảnh. Bắt buộc dùng hàm `ValidMeasure()` để bảo vệ từng thành phần.  
> Ngoài ra, **không hardcode đơn giá dầu tĩnh** (như `* 3.85`) — Phúc An đã cào và nạp 27.400 bản ghi đơn giá thị trường EIA vào `Stg_Market_Fuel_Rates`. Trong phiên bản SSAS Multidimensional hiện tại, tạm thời dùng mức giá trung bình 3.85 USD/gallon nhưng phải đặt là biến `[Measures].[Avg Diesel Price]` đọc từ một Linked Measure Group hoặc hard-note rõ ràng để nhóm cập nhật sau.

```mdx
CREATE MEMBER CURRENTCUBE.[Measures].[CM_Fleet_TCO] AS
(
    -- ValidMeasure() đảm bảo không sinh NULL khi ngữ cảnh chỉ có 1 trong 2 Fact
    -- Đơn giá 3.85 USD/gallon là giá trung bình EIA 2022-2024;
    -- cần cập nhật thành Avg Diesel Price từ Linked Measure Group khi có thể.
    ValidMeasure([Measures].[Fuel Gallons Used]) * 3.85
    + ValidMeasure([Measures].[Total Maintenance Cost])
),
FORMAT_STRING = "Currency",
ASSOCIATED_MEASURE_GROUP = 'MG_Fact_Maintenance';
```


#### 3. Doanh thu Thực tế trên mỗi Pound Tải trọng (Revenue per Pound):
$$Revenue\_Per\_Pound = \frac{\sum(Fact\_Load.total\_revenue)}{\sum(Fact\_Load.weight\_lbs)}$$

```mdx
CREATE MEMBER CURRENTCUBE.[Measures].[CM_Revenue_Per_Pound] AS
IIF(
    [Measures].[Weight Lbs] = 0,
    0,
    [Measures].[Total Revenue] / [Measures].[Weight Lbs]
),
FORMAT_STRING = "$#,##0.0000",
ASSOCIATED_MEASURE_GROUP = 'MG_Fact_Load';
```

#### 4. Tỷ lệ Nổ máy Dừng chờ Lãng phí (Idle Time %):
$$Idle\_Time\_Percentage = \frac{\sum(Fact\_Trip.idle\_time\_hours)}{\sum(Fact\_Trip.actual\_duration\_hours + Fact\_Trip.idle\_time\_hours)} \times 100\%$$

```mdx
CREATE MEMBER CURRENTCUBE.[Measures].[CM_Idle_Time_Percentage] AS
IIF(
    ([Measures].[Actual Duration Hours] + [Measures].[Idle Time Hours]) = 0,
    0,
    [Measures].[Idle Time Hours] / ([Measures].[Actual Duration Hours] + [Measures].[Idle Time Hours])
),
FORMAT_STRING = "Percent",
ASSOCIATED_MEASURE_GROUP = 'MG_Fact_Trip';
```

---

### D. Script XMLA & PowerShell Tự động hóa Process Cube cho Airflow

Để Apache Airflow có thể tự động kích hoạt **Process Cube** sau khi SSIS nạp xong DWH, tạo 2 file script tại thư mục `SSAS_Logistics/Scripts/`:

#### File 1: `SSAS_Logistics/Scripts/process_cube.xmla`
```xml
<Process xmlns="http://schemas.microsoft.com/analysisservices/2003/engine">
  <Object>
    <DatabaseID>SSAS_Logistics_Galaxy</DatabaseID>
  </Object>
  <Type>ProcessFull</Type>
  <WriteBackTableCreation>UseExisting</WriteBackTableCreation>
</Process>
```

#### File 2: `SSAS_Logistics/Scripts/process_ssas.ps1`
```powershell
# PowerShell script triggered by Apache Airflow BashOperator
$serverName = "localhost"
$xmlaFilePath = "D:\Kho\Project\SSAS_Logistics\Scripts\process_cube.xmla"

Import-Module SQLASCmdlets -ErrorAction SilentlyContinue

Invoke-ASCmd -Server $serverName -InputFile $xmlaFilePath
Write-Host "SSAS Galaxy Cube Processed Successfully at $(Get-Date)"
```

---

## 6. MA TRẬN PHÂN CHIA GÓI CÔNG VIỆC SSAS & WORK BREAKDOWN MATRIX

> [!IMPORTANT]
> Toàn bộ **9 Dimensions** và **4 Measure Groups** trong SSAS Galaxy Cube đã được quy hoạch đồng bộ. Các thành viên nhận nhiệm vụ xây dựng cấu trúc Semantic Layer trên SSAS theo đúng phân công dưới đây:

### BẢNG TỔNG QUAN PHÂN BỔ TRÁCH NHIỆM SSAS (3 THÀNH VIÊN):

| STT | Thành phần trong SSAS Cube | Loại đối tượng SSAS | Thành viên phụ trách | Nhiệm vụ kỹ thuật SSAS & Biểu thức MDX |
| :---: | :--- | :--- | :---: | :--- |
| **1** | **SSAS Project & DSV Setup** | Infrastructure | **Bình Minh** | Khởi tạo Dự án SSAS Multidimensional, cấu hình Connection `DS_Logistics_DW`, tạo DSV hiển thị Galaxy Schema. |
| **2** | **`Dim_Customer` & `Dim_Route`** | Shared Dimensions | **Bình Minh** | Cấu hình attributes `Dim_Customer`. Tách 2 nhánh `Route Origin` & `Route Destination` Hierarchies. |
| **3** | **`Dim_Load_Profile`** | Junk Dimension | **Bình Minh** | Cấu hình thuộc tính trạng thái đơn hàng (`load_status`, `booking_type`, `load_type`). |
| **4** | **`MG_Fact_Load`** | Measure Group | **Bình Minh** | Map Regular Dimensions. Viết MDX `CM_Revenue_Per_Pound` và truy vấn MDX Top 10 Khách hàng Doanh thu. |
| **—** | ----------------------- | ----------------------- | :---: | ---------------------------------------------------- |
| **5** | **`Dim_Truck` & `Dim_Trailer`** | Conformed Dimensions | **Phúc An** | Cấu hình thuộc tính kỹ thuật xe tải, rơ-moóc. Viết Calculated Measure đếm rơ-moóc nhàn rỗi `low_utilization_trailer_count`. |
| **6** | **`Dim_Maintenance_Profile`** | Junk Dimension | **Phúc An** | Cấu hình phân loại bảo dưỡng & mức độ cấp thiết (`service_urgency`). |
| **7** | **`MG_Fact_Maintenance`** | Measure Group | **Phúc An** | Cấu hình Semi-additive `Odometer Reading` (`AggregateFunction = Max`). Viết MDX `CM_Fleet_TCO` Cross-Fact Drill-Across với `ValidMeasure()`. |
| **—** | ----------------------- | ----------------------- | :---: | ---------------------------------------------------- |
| **8** | **`Dim_Driver` & `Dim_Facility`** | Core / Role-Playing Dims | **Quang Duy** | Cấu hình `Dim_Driver` và Role-Playing `Dim_Facility` (`Origin Facility` & `Destination Facility`). |
| **9** | **`Dim_Date` (Conformed)** | Conformed Dimension | **Quang Duy** | Cấu hình `Calendar Hierarchy` & `Fiscal Hierarchy`. Map `Dim_Date` Regular Relationship với 4 Fact chính. **Chỉ** tạo Role-Playing (`Pickup Date`, `Delivery Date`) trong `Fact_Delivery_Fulfillment`. |
| **10**| **`MG_Fact_Trip`** | Measure Group | **Quang Duy** | Cấu hình `MG_Fact_Trip`. Viết MDX `CM_Idle_Time_Percentage`. |
| **11**| **`MG_Fact_Delivery_Fulfillment`**| Measure Group | **Quang Duy** | Cấu hình Accumulating Measure Group. Viết MDX `CM_On_Time_Delivery_Rate` (khử mẫu số đơn In-Flight). |
| **12**| **SSAS Automation & Process** | Orchestration Script | **Quang Duy** | Viết script `process_cube.xmla` & `process_ssas.ps1` tích hợp vào Airflow DAG để tự động Process Cube. |

---

## 7. CHECKLIST KIỂM THỬ TRƯỚC KHI COMMIT & DEPLOY (DEFINITION OF DONE FOR SSAS)

* [ ] Đã kiểm tra CSDL `Logistics_DW` được nạp đầy đủ dữ liệu từ SSIS.
* [ ] Khởi tạo thành công `DS_Logistics_DW.ds` kết nối tới `localhost`.
* [ ] File `DSV_Logistics_DW.dsv` hiển thị đủ **4 Fact Tables** và **9 Dimension Tables** kèm các đường nối quan hệ.
* [ ] `Dim_Route.dim` đã được tách thành **2 cây phân cấp riêng biệt**: `Route Origin Hierarchy` và `Route Destination Hierarchy` (lá cuối cùng là `route_id`, không phải `Route Code` — không còn báo đỏ lỗi Attribute Relationship).
* [ ] Tab **Dimension Usage** đã cấu hình đúng theo **Bus Matrix**:
  * `Dim_Date` — Regular Relationship với cả 4 Fact (`load_date_key`, `dispatch_date_key`, `pickup_date_key`, `maintenance_date_key`).
  * 2 vai trò Role-Playing **chỉ trong `Fact_Delivery_Fulfillment`**: `Pickup Date` (pickup_date_key) + `Delivery Date` (delivery_date_key).
  * 2 vai trò Role-Playing **chỉ trong `Fact_Delivery_Fulfillment`**: `Origin Facility` + `Destination Facility`.
  * **`Fact_Maintenance` KHÔNG map với `Dim_Facility`** (dùng Degenerate Dimension `facility_location`).
* [ ] Cột `Odometer Reading` trong `MG_Fact_Maintenance` đã chuyển `AggregateFunction = Max` (không phải `LastNonEmpty`).
* [ ] Khai báo đủ **4 Calculated Measures MDX**: `CM_On_Time_Delivery_Rate`, `CM_Fleet_TCO`, `CM_Revenue_Per_Pound`, `CM_Idle_Time_Percentage`.
* [ ] Nhấn **Build Solution (`Ctrl + Shift + B`)**: Kết quả **Build Succeeded**, không có lỗi cú pháp MDX.
* [ ] Thực hiện **Deploy** lên SSAS Server `localhost` và chạy **Process Full**: Trạng thái **Process Complete Successfully**.
* [ ] Đã viết file `process_cube.xmla` và `process_ssas.ps1` sẵn sàng cho Quang Duy tích hợp vào Airflow.
```
eof
```

# BÁO CÁO CÁC CÔNG VIỆC ĐÃ HOÀN THÀNH (SETUP SKELETON)

Bộ khung hạ tầng dự án SSAS Multidimensional đã được khởi tạo và commit thành công lên nhánh `main` tại thư mục `SSAS_Logistics/`. Cụ thể bao gồm:

1. **SSAS Solution & Project Structure:** Khởi tạo dự án `SSAS_Logistics` dạng Analysis Services Multidimensional Project tại vị trí chuẩn `d:\Kho\Project\SSAS_Logistics\`.

2. **Data Source (`DS_Logistics_DW.ds`):** Khai báo kết nối OLE DB tới CSDL `Logistics_DW` trên `localhost` sử dụng Windows Authentication và impersonation `Use the credentials of the current user`.

3. **Data Source View (`DSV_Logistics_DW.dsv`)**: 
   - Đã kéo đủ **4 Bảng Fact** (`Fact_Load`, `Fact_Trip`, `Fact_Delivery_Fulfillment`, `Fact_Maintenance`) và **9 Bảng Dimension** với mối quan hệ chuẩn 1-N.
   - ⚠️ **LƯU Ý QUAN TRỌNG VỀ GIAO DIỆN DSV:** Để tránh tình trạng sơ đồ Galaxy Schema bị rối "như mạng nhện" (Spaghetti design), sử dụng tính năng **Diagram Organizer** chia nhỏ DSV thành 4 sơ đồ riêng biệt theo từng chuyên đề. 
   - Khi mọi người mở file `DSV_Logistics_DW.dsv`, hãy nhìn sang cột **Diagram Organizer** (bên trái) và nhấp đúp vào sơ đồ tương ứng với phần việc của mình để xem nhé:
     * 📁 `1. Commercial (Fact_Load)` -> Dành cho **Bình Minh**
     * 📁 `2. Fleet Operations (Fact_Trip)` -> Dành cho **Duy**
     * 📁 `3. Fulfillment (Fact_Delivery)` -> Dành cho **Duy**
     * 📁 `4. Maintenance (Fact_Maintenance)` -> Dành cho **Phúc An**
     *(Mọi người làm phần nào thì mở tab sơ đồ đó ra xem, cấu trúc bảng tự động dàn xếp rất gọn gàng và dễ nhìn).*

   * *Đã kiểm tra quan hệ Logical Relationships:* Đảm bảo quan hệ $1-N$ chuẩn từ Dimension sang Fact. Không có liên kết trực tiếp giữa các bảng Fact.

4. **9 File Dimension Shells (`.dim`):** Khởi tạo khung 9 chiều dữ liệu qua Wizard, đã lựa chọn sẵn thuộc tính nghiệp vụ cốt lõi và **bỏ tích toàn bộ các cột quản trị SCD kỹ thuật** (`Effective Date`, `Expiration Date`, `Is Current`).

5. **Cube Shell (`Cube_Logistics_Galaxy.cube`):** Tạo vỏ Galaxy Cube chứa **4 Measure Groups** (`MG_Fact_Load`, `MG_Fact_Trip`, `MG_Fact_Delivery_Fulfillment`, `MG_Fact_Maintenance`) cùng 9 Dimensions.

6. **Git Version Control:** Lưu trữ và đồng bộ toàn bộ bộ khung rỗng lên GitHub Repository.

## PHÂN CÔNG CÔNG VIỆC TIẾP THEO CHO TỪNG THÀNH VIÊN

Sau khi `git pull` bộ khung về máy, các thành viên mở dự án trong Visual Studio và triển khai tiếp các nhiệm vụ theo phân công dưới đây:

### 1. BÌNH MINH (Mảng Thương mại & Đơn hàng)

* **`Dim_Customer.dim`**:

  * Đổi `AttributeHierarchyVisible = False` cho thuộc tính `Customer Key`.

  * Gán `NameColumn = Dim_Customer.customer_name (WChar)`.

  * Tạo User Hierarchy `Customer Hierarchy`: `Customer Type` $\rightarrow$ `Customer Name`.

  * Cấu hình Attribute Relationships dạng chuỗi tuyến tính: `Customer Key` $\rightarrow$ `Customer Name` $\rightarrow$ `Customer Type`.

* **`Dim_Route.dim`**:

  * **Tách 2 nhánh phân cấp độc lập (Tránh lỗi Attribute Relationship Violation):**

    1. `Route Origin Hierarchy`: `Origin State` $\rightarrow$ `Origin City` $\rightarrow$ `route_id`

    2. `Route Destination Hierarchy`: `Destination State` $\rightarrow$ `Destination City` $\rightarrow$ `route_id`

  * *Lưu ý:* Lá cuối cùng bắt buộc map tới cột **`route_id`** (theo DDL), không dùng `Route Code`.

* **`Dim_Load_Profile.dim`**: Rà soát các thuộc tính trạng thái đơn hàng phẳng (`load_status`, `booking_type`, `load_type`).

* **`MG_Fact_Load`**:

  * Map Dimension Usage chuẩn theo Bus Matrix.

  * Khai báo Calculated Measure MDX: `CM_Revenue_Per_Pound` (Doanh thu trên mỗi pound tải trọng).

### 2. PHÚC AN (Mảng Đội xe & Bảo dưỡng)

* **`Dim_Truck.dim` & `Dim_Trailer.dim`**:

  * Cấu hình thuộc tính kỹ thuật xe và rơ-moóc.

  * Viết Calculated Measure đếm rơ-moóc nhàn rỗi `low_utilization_trailer_count`.

* **`Dim_Maintenance_Profile.dim`**: Cấu hình phân loại bảo dưỡng và mức độ cấp thiết (`service_urgency`).

* **`MG_Fact_Maintenance`**:

  * Đổi thuộc tính `AggregateFunction` của cột `Odometer Reading` từ `Sum` sang **`Max`** *(Tuyệt đối KHÔNG dùng `LastNonEmpty` vì đây là Transaction Fact)*.

  * Khai báo Calculated Measure MDX `CM_Fleet_TCO` thực hiện Cross-Fact Drill-Across, bắt buộc bọc hàm `ValidMeasure()` để tránh lỗi NULL/lặp dữ liệu.

### 3. QUANG DUY (Mảng Vận hành & Chu trình Giao nhận)

* **`Dim_Driver.dim` & `Dim_Facility.dim`**:

  * Cấu hình thuộc tính chuẩn hóa.

  * Thiết lập Role-Playing Relationships (`Origin Facility`, `Destination Facility`) cho `Fact_Delivery_Fulfillment`.

* **`Dim_Date.dim`**:

  * Tạo 2 cây phân cấp `Calendar Hierarchy` & `Fiscal Hierarchy`.

  * Map `Dim_Date` dạng Conformed Dimension với cả 4 Fact. Chỉ tạo Role-Playing (`Pickup Date`, `Delivery Date`) riêng trong `Fact_Delivery_Fulfillment`.

* **`MG_Fact_Trip` & `MG_Fact_Delivery_Fulfillment`**:

  * Khai báo MDX `CM_Idle_Time_Percentage` (Tỷ lệ dừng chờ lãng phí).

  * Khai báo MDX `CM_On_Time_Delivery_Rate` (Tỷ lệ giao hàng đúng hẹn SLA - trừ các đơn hàng In-Flight `delivery_date_key = -1`).

* **SSAS Automation & Process Orchestration**:

  * Viết file script `process_cube.xmla` và `process_ssas.ps1` đặt tại thư mục `SSAS_Logistics/Scripts/` để tích hợp tự động Process Cube vào Airflow DAG.

## NGUYÊN TẮC SỐNG CÒN & CHECKLIST KIỂM THỬ (DEFINITION OF DONE)

Khi các thành viên thực hiện công việc, phải tuyệt đối tuân thủ 3 quy tắc sau trước khi Push code lên Git:

1. **Đúng Bus Matrix:** Chiều `Dim_Facility` **KHÔNG** được map tới `Fact_Maintenance` trong tab Dimension Usage (địa điểm bảo dưỡng sử dụng Degenerate Dimension `facility_location`).

2. **Kiểm tra biên dịch Local:** Trước khi Commit, nhấn **`Ctrl + Shift + B`** trong Visual Studio. Kết quả phải đạt **Build Succeeded**, không có lỗi đỏ syntax MDX hay Attribute Relationship.

3. **Deploy & Process:** Chạy **Deploy** thành công lên SSAS Instance `localhost` và bấm **Process Full** đạt trạng thái *Process Complete Successfully*.