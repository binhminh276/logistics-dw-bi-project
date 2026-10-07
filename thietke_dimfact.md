# **TÀI LIỆU THIẾT KẾ KIẾN TRÚC DATA WAREHOUSE LOGISTICS & FLEET OPERATIONS**

## **(PHIÊN BẢN CHUẨN HÓA TOÀN DIỆN & KHẮC PHỤC RỦI RO ETL THEO RALPH KIMBALL)**

* **Phương pháp luận:** Chu trình 4 bước thiết kế Dimensional Modeling của Ralph Kimball & Enterprise Bus Matrix.

* **Tập dữ liệu áp dụng:** Logistics and Fleet Operations Management Master Dataset (Bộ dữ liệu giai đoạn 2022–2024; bao gồm các tệp nguồn: `loads`, `trips`, `delivery_events`, `maintenance`, `customers`, `facilities`, `drivers`, `trucks`, `trailers`, `routes`).

* **Các điểm cải tiến & hiệu chỉnh then chốt sau rà soát thực nghiệm:**

  1. **Chuẩn hóa Định danh Khóa Ngày Role-Playing (Role-Playing Date Foreign Keys):** Thay thế tên gọi chung chung `date_key` tại các bảng Fact bằng các khóa ngoại định danh tường minh theo vai trò nghiệp vụ: `load_date_key` (`Fact_Load`), `dispatch_date_key` (`Fact_Trip`), `maintenance_date_key` (`Fact_Maintenance`), `pickup_date_key` và `delivery_date_key` (`Fact_Delivery_Fulfillment`). Điều này triệt tiêu hoàn toàn rủi ro xung đột ngữ cảnh quan hệ Active/Inactive khi thiết kế mô hình dữ liệu trên BI/OLAP.

  2. **Đồng bộ Thuộc tính Khoảng cách Tuyến Đường (`typical_distance_miles`):** Hiệu chỉnh tên cột trong `Dim_Route` từ `standard_distance_miles` thành `typical_distance_miles` để khớp $100\%$ với schema vật lý của file nguồn `routes.csv`, đảm bảo pipeline trích xuất ETL vận hành tự động không phát sinh lỗi ánh xạ.

  3. **Làm sạch Cơ chế Khóa và Vị trí Cơ sở Bảo dưỡng (`Fact_Maintenance`):** Loại bỏ hoàn toàn cơ chế tạo surrogate key ảo cấp thành phố làm ô nhiễm bảng `Dim_Facility`. Trường `facility_location` (tên thành phố xưởng bảo dưỡng) được lưu trữ chuẩn hóa dưới dạng Degenerate Dimension trực tiếp tại `Fact_Maintenance`, bảo vệ tính toàn vẹn danh mục kho bãi vật lý của `Dim_Facility`.

  4. **Quy hoạch Chuẩn hóa Đơn giá Doanh thu Thực tế (`revenue_per_pound`):** Cập nhật công thức tính đơn giá doanh thu trên mỗi pound tải trọng dựa trên tổng giá trị thu về thực tế (`total_revenue` = $revenue + fuel\_surcharge + accessorial\_charges$) thay vì chỉ tính trên cước cơ bản thuần túy, phản ánh chính xác hiệu quả thương mại trên từng pound hàng vận chuyển.

  5. **Quy hoạch Chỉ số Quản trị Sức khỏe & Sẵn sàng Tài sản Đội xe (`low_utilization_trailer_count`):** Chuyển giao chỉ số giám sát rơ-moóc đắp chiếu/kém hiệu quả sang nhóm Quản trị Sức khỏe & Độ sẵn sàng Tài sản Đội xe tại `Fact_Maintenance`. Do tệp nguồn bảo dưỡng không ghi nhận `trailer_id`, logic DAX được quy hoạch phân tích phối hợp giữa danh mục tài sản `Dim_Trailer` và dặm lăn bánh thực tế từ `Fact_Trip` nhằm phục vụ kế hoạch kiểm tra kỹ thuật và thanh lý tài sản.

  6. **Hoàn thiện Logic Phân tích Đơn hàng Đang chuyển tiếp (In-Flight Fulfillment Handling):** Xử lý triệt để lỗi mẫu số trong `Fact_Delivery_Fulfillment`. Các chỉ số đo lường cam kết dịch vụ SLA (`on_time_delivery_rate`, `perfect_fulfillment_rate`), độ trễ thời gian (`avg_transit_lead_time`) và độ lệch thời gian vận chuyển (`transit_variance_hours`) được bổ sung bộ lọc bắt buộc loại trừ các đơn hàng đang trên đường đi (`delivery_date_key = -1`), ngăn ngừa hiện tượng kéo tụt tỷ lệ giao đúng hạn và kết quả sai lệch âm thời gian.

  7. **Bảo toàn Chiến lược Tinh giản Vận hành & Lưu trữ Degenerate Dimension:** Giữ nguyên thuộc tính `trip_status` dưới dạng Degenerate Dimension trong `Fact_Trip` phục vụ lọc tức thời; duy trì độc lập $100\%$ nguồn nạp của `Fact_Trip` từ `trips.csv` không phụ thuộc bước join `loads.csv`.

  8. **Bảo vệ Pipeline Junk Dimension (`Dim_Maintenance_Profile`):** Bổ sung giá trị mặc định `Unknown / Standard` và khóa $-1$ cho trường phái sinh `service_urgency`, ngăn ngừa rủi ro treo pipeline ETL khi xuất hiện các mã bảo dưỡng mới chưa có trong từ điển quy tắc.

---

## **SƠ ĐỒ TỔNG THỂ KIẾN TRÚC GALAXY SCHEMA**

```
                                      +--------------------+  
                                      |      Dim_Date      |  
                                      +--------------------+  
                                       /   |     |    |   \  
                         (Load Date)  /    |     |    |    \ (Maint Date)
                                     v     v     |    v     v  
            +-------------------------+ +---------+   |   +---------------------+  
            |        Fact_Load        | |Fact_Trip|   |   |  Fact_Maintenance   |  
            |   (Transaction Fact)    | |(Trans.) |   |   | (Transaction Fact)  |  
            +-------------------------+ +---------+   |   +---------------------+  
             |       |         |         | | |        |      |                 |  
             |       |         |         | | |        |      |                 v  
             v       v         v         | | +-> Dim_Trailer |       Dim_Maint_Profile
        Dim_Cust  Dim_Route  Dim_Profile | +---> Dim_Truck <-+  
             ^         ^         ^       +-----> Dim_Driver  
             |         |         |                   |
             |         |         +------+            |
             |         |                |            |
             |         |    (Pickup & Delivery Dates)|
             |         |                v            v
             |         |        +--------------------------------+
             +---------+------->|   Fact_Delivery_Fulfillment    |
             | (Customer & Type)|    (Accumulating Snapshot)     |
             +----------------->+--------------------------------+
                                        |                |
                                        v                v
                                   Dim_Facility     Dim_Facility
                                 (Origin Facility)(Dest Facility)
```

---

## **PHẦN 1: BỐN BƯỚC THIẾT KẾ DATA WAREHOUSE THEO RALPH KIMBALL**

### **BƯỚC 1: CHỌN QUY TRÌNH NGHIỆP VỤ (SELECT THE BUSINESS PROCESS)**

Hệ thống bao phủ 4 mắt xích cốt lõi tạo ra doanh thu và phát sinh chi phí vận hành:

1. **Quản lý Đơn hàng Thương mại (Load Commercial Fulfillment):** Tiếp nhận yêu cầu vận tải, xác lập tải trọng, hình thức hợp đồng và ghi nhận doanh thu cùng các khoản phụ phí.

2. **Vận hành Chuyến xe Thực tế (Trip Execution Operations):** Giám sát các chuyến xe lăn bánh; đo lường quãng đường, thời gian chạy, dầu tiêu thụ và thời gian nổ máy chờ (*idle time*).

3. **Chu trình Hoàn tất Giao nhận Hai đầu Bến (End-to-End Stop Fulfillment Pipeline):** Giám sát vòng đời di chuyển từ kho bốc (*Origin*) đến kho dỡ (*Destination*); đối chiếu thời gian giam bãi (*Detention*) hai đầu bến và độ trễ vận chuyển (*Transit Lead Time*).

4. **Bảo dưỡng & Kỹ thuật Đội xe (Fleet Maintenance & Asset Integrity):** Giám sát chi phí vật tư, nhân công thợ máy, thời gian phương tiện ngưng hoạt động nằm xưởng (*downtime*) và theo dõi mức độ khai thác tài sản đội xe.

---

### **BƯỚC 2: XÁC ĐỊNH ĐỘ HẠT (DECLARE THE GRAIN)**

* **`Fact_Load`:** Mỗi dòng đại diện cho **đúng một đơn hàng vận tải riêng biệt** được tạo lập trong hệ thống thương mại (tương ứng với một `load_id`). Phân loại: *Transaction Fact Table*.

* **`Fact_Trip`:** Mỗi dòng đại diện cho **đúng một chuyến xe lăn bánh thực tế** trên đường (tương ứng với một `trip_id`). Phân loại: *Transaction Fact Table*.

* **`Fact_Delivery_Fulfillment`:** Mỗi dòng đại diện cho **đúng một chu trình giao nhận trọn vẹn từ trạm bốc đến trạm dỡ (Origin-to-Destination Stop Pair Lifecycle)** của một đơn hàng (`load_id`). Phân loại: *Accumulating Snapshot Fact Table*.

* **`Fact_Maintenance`:** Mỗi dòng đại diện cho **đúng một lần phương tiện vào xưởng bảo dưỡng/sửa chữa** (tương ứng với một `maintenance_id`). Phân loại: *Transaction Fact Table*.

---

### **BƯỚC 3: THIẾT KẾ CÁC BẢNG CHIỀU (DIMENSIONS, SCD & HIERARCHIES)**

#### **1. Dim_Date (Chiều Thời gian Chuẩn hóa)**

* **Nguồn dữ liệu:** Sinh tự động bằng SQL Script từ 01/01/2020 đến 31/12/2030.

* **Phân loại:** Conformed Dimension & Role-Playing Dimension (`load_date_key`, `dispatch_date_key`, `pickup_date_key`, `delivery_date_key`, `maintenance_date_key`).

* **Chiến lược SCD:** **SCD Type 0** (Dữ liệu cố định).

* **Bản ghi mặc định (Default Record):** Chèn bản ghi `date_key = -1` đại diện cho giá trị *'Not Applicable / In-Flight (Chưa hoàn tất)'*.

* **Khóa chính:** `date_key` (Dạng số nguyên thông minh YYYYMMDD, ví dụ: 20230519).

* **Hệ thống phân cấp người dùng (User Hierarchies):**

  * *Calendar Hierarchy:* Calendar Year $\rightarrow$ Calendar Quarter $\rightarrow$ Month $\rightarrow$ Date

  * *Fiscal Hierarchy:* Fiscal Year $\rightarrow$ Fiscal Quarter $\rightarrow$ Month $\rightarrow$ Date

* **Thuộc tính chi tiết:** `date_key` (INT, PK), `full_date` (DATE), `day_of_week` (TINYINT), `day_name` (VARCHAR(15)), `month_number` (TINYINT), `month_name` (VARCHAR(15)), `calendar_quarter` (TINYINT), `calendar_year` (SMALLINT), `fiscal_quarter` (VARCHAR(10)), `fiscal_year` (SMALLINT), `is_weekend` (BIT), `holiday_flag` (BIT).

#### **2. Dim_Customer (Chiều Khách hàng)**

* **Nguồn dữ liệu:** `customers.csv`.

* **Phân loại:** Conformed Dimension.

* **Chiến lược SCD:**

  * `customer_name`, `primary_freight_type`, `contract_start_date`: **SCD Type 1**.

  * `credit_terms_days`, `customer_type`, `account_status`, `annual_revenue_potential`: **SCD Type 2**.

* **Khóa:** `customer_key` (INT, IDENTITY, PK), `customer_id` (VARCHAR(20), BK). Bản ghi $-1$: *'Unknown Customer'*.

* **Hệ thống phân cấp:** Customer Type $\rightarrow$ Customer Name.

* **Thuộc tính chi tiết:** `customer_key` (INT, PK), `customer_id` (VARCHAR(20), BK), `customer_name` (VARCHAR(100)), `customer_type` (VARCHAR(50)), `credit_terms_days` (INT), `primary_freight_type` (VARCHAR(50)), `account_status` (VARCHAR(20)), `contract_start_date` (DATE), `annual_revenue_potential` (DECIMAL(15,2)), `effective_date` (DATE), `expiration_date` (DATE), `is_current` (BIT).

#### **3. Dim_Driver (Chiều Tài xế)**

* **Nguồn dữ liệu:** Bảng hồ sơ nhân sự `drivers.csv` (phân biệt với bảng số liệu tổng kết tháng `driver_monthly_metrics.csv`).

* **Phân loại:** Conformed Dimension.

* **Chiến lược SCD:**

  * `first_name`, `last_name`, `date_of_birth`, `license_number`, `years_experience`: **SCD Type 1**.

  * `full_name`: **SCD Type 1** (Derived: `CONCAT(TRIM(first_name), ' ', TRIM(last_name))`).

  * `hire_date`: **SCD Type 0**.

  * `cdl_class`, `license_state`, `home_terminal`, `employment_status`, `termination_date`: **SCD Type 2**.

* **Khóa:** `driver_key` (INT, IDENTITY, PK), `driver_id` (VARCHAR(20), BK).

* **Bản ghi mặc định (Bắt buộc cho ETL):** Chèn bản ghi `driver_key = -1`, `driver_id = 'UNASSIGNED'`, `full_name = 'Unassigned Driver'` để hứng các chuyến xe chưa có tài xế phụ trách (ví dụ dòng `TRIP00000067`).

* **Hệ thống phân cấp:**

  * *Vùng hoạt động:* License State $\rightarrow$ Home Terminal $\rightarrow$ Driver

  * *Hạng bằng:* CDL Class $\rightarrow$ Driver

* **Thuộc tính chi tiết:** `driver_key` (INT, PK), `driver_id` (VARCHAR(20), BK), `first_name` (VARCHAR(50)), `last_name` (VARCHAR(50)), `full_name` (VARCHAR(100)), `license_number` (VARCHAR(50)), `license_state` (VARCHAR(10)), `date_of_birth` (DATE), `hire_date` (DATE), `termination_date` (DATE), `home_terminal` (VARCHAR(50)), `employment_status` (VARCHAR(20)), `cdl_class` (VARCHAR(10)), `years_experience` (INT), `effective_date` (DATE), `expiration_date` (DATE), `is_current` (BIT).

#### **4. Dim_Truck (Chiều Đầu kéo / Xe tải)**

* **Nguồn dữ liệu:** `trucks.csv`.

* **Phân loại:** Conformed Dimension.

* **Chiến lược SCD:**

  * `unit_number`, `fuel_type`, `tank_capacity_gallons`: **SCD Type 1**.

  * `make`, `model_year`, `vin`, `acquisition_date`, `acquisition_mileage`: **SCD Type 0**.

  * `status` (khớp cột nguồn `status`), `home_terminal`: **SCD Type 2**.

* **Khóa:** `truck_key` (INT, IDENTITY, PK), `truck_id` (VARCHAR(20), BK).

* **Bản ghi mặc định (Bắt buộc cho ETL):** Chèn bản ghi `truck_key = -1`, `truck_id = 'UNASSIGNED'`, `unit_number = 'Unknown Unit'` để hứng các chuyến xe chưa gán đầu xe (ví dụ dòng `TRIP00000070`, `TRIP00000074`).

* **Hệ thống phân cấp:** Make $\rightarrow$ Model Year $\rightarrow$ Truck Unit.

* **Thuộc tính chi tiết:** `truck_key` (INT, PK), `truck_id` (VARCHAR(20), BK), `unit_number` (VARCHAR(20)), `make` (VARCHAR(50)), `model_year` (INT), `vin` (VARCHAR(50)), `acquisition_date` (DATE), `acquisition_mileage` (DECIMAL(12,2)), `fuel_type` (VARCHAR(30)), `tank_capacity_gallons` (DECIMAL(10,2)), `status` (VARCHAR(50)), `home_terminal` (VARCHAR(50)), `effective_date` (DATE), `expiration_date` (DATE), `is_current` (BIT).

#### **5. Dim_Trailer (Chiều Rơ-moóc / Thùng kéo)**

* **Bản chất nghiệp vụ:** Rơ-moóc là tài sản vật lý hoàn toàn độc lập với đầu kéo trong mô hình *Drop-and-Hook*.

* **Nguồn dữ liệu:** `trailers_sample.csv`.

* **Phân loại:** Conformed Dimension.

* **Chiến lược SCD:**

  * `trailer_number`, `trailer_type`: **SCD Type 1**.

  * `length_feet`, `model_year`, `vin`, `acquisition_date`: **SCD Type 0**.

  * `status`, `current_location`: **SCD Type 2**.

* **Khóa:** `trailer_key` (INT, IDENTITY, PK), `trailer_id` (VARCHAR(20), BK). Bản ghi $-1$: *'Unassigned Trailer'*.

* **Hệ thống phân cấp:** Trailer Type $\rightarrow$ Length (Feet) $\rightarrow$ Trailer Number.

* **Thuộc tính chi tiết:** `trailer_key` (INT, PK), `trailer_id` (VARCHAR(20), BK), `trailer_number` (VARCHAR(20)), `trailer_type` (VARCHAR(50)), `length_feet` (INT), `model_year` (INT), `vin` (VARCHAR(50)), `acquisition_date` (DATE), `status` (VARCHAR(50)), `current_location` (VARCHAR(50)), `effective_date` (DATE), `expiration_date` (DATE), `is_current` (BIT).

#### **6. Dim_Facility (Chiều Cơ sở / Kho bãi)**

* **Nguồn dữ liệu:** `facilities.csv`.

* **Phân loại:** Conformed & Role-Playing Dimension (*Origin Facility*, *Destination Facility*).

* **Quy chuẩn giá trị phân loại cơ sở:** Cột `facility_type` trong `facilities.csv` gồm 4 nhóm chuẩn: `Terminal`, `Distribution Center`, `Cross-Dock`, `Warehouse`.

* **Quy tắc ETL làm sạch xung đột địa lý (`delivery_events.csv`):** Dữ liệu nguồn `delivery_events.csv` có hiện tượng sai lệch nghiêm trọng: cột `facility_id` gốc bị gán ngẫu nhiên chỉ khớp đúng $3.45\%$ với thực tế (sai lệch tới $96.55\%$). Ngược lại, cặp `(location_city, location_state)` là **Master Ground Truth** khớp chính xác $100.00\%$ với hành lang tuyến đường (`routes.csv`) — đã được phân tích chứng minh định lượng tại [docs/profiling_facility_conflict_report.md](file:///d:/Kho/Project/docs/profiling_facility_conflict_report.md). Do đó, quy tắc chuẩn hóa của DWH là: Bắt buộc dùng cặp `(location_city, location_state)` tra cứu bảng từ điển `Ref_City_Facility_Mapping` (khởi tạo từ `sql/07_create_delivery_events_mapping.sql`) để lấy `corrected_facility_id` chuẩn hóa, sau đó mới Lookup vào `Dim_Facility`. Đối với 4 thành phố khách hàng không có cơ sở trong danh mục (Columbus OH, Seattle WA, Memphis TN, Minneapolis MN), gán `facility_key = -1` (Unknown / Missing Facility).

* **Chiến lược SCD:**

  * `facility_name`, `facility_type`, `city`, `state`, `latitude`, `longitude`: **SCD Type 1**.

  * `dock_doors`, `operating_hours`: **SCD Type 2**.

* **Khóa:** `facility_key` (INT, IDENTITY, PK), `facility_id` (VARCHAR(20), BK). Bản ghi $-1$: *'Unknown Facility'*.

* **Hệ thống phân cấp:** State $\rightarrow$ City $\rightarrow$ Facility Name.

* **Thuộc tính chi tiết:** `facility_key` (INT, PK), `facility_id` (VARCHAR(20), BK), `facility_name` (VARCHAR(100)), `facility_type` (VARCHAR(50)), `city` (VARCHAR(50)), `state` (VARCHAR(10)), `latitude` (DECIMAL(9,6)), `longitude` (DECIMAL(9,6)), `dock_doors` (INT), `operating_hours` (VARCHAR(50)), `effective_date` (DATE), `expiration_date` (DATE), `is_current` (BIT).

#### **7. Dim_Route (Chiều Tuyến đường Vận chuyển)**

* **Nguồn dữ liệu:** `routes.csv`.

* **Phân loại:** Conformed Dimension.

* **Chiến lược SCD:** **SCD Type 1**.

* **Khóa:** `route_key` (INT, IDENTITY, PK), `route_id` (VARCHAR(20), BK). Bản ghi $-1$: *'Unknown Route'*.

* **Hệ thống phân cấp (Tách 2 nhánh độc lập tránh bẫy quan hệ nhiều - nhiều trong SSAS/Power BI):**

  * *Nhánh Xuất phát (Origin):* Origin State $\rightarrow$ Origin City $\rightarrow$ Route

  * *Nhánh Đích đến (Destination):* Destination State $\rightarrow$ Destination City $\rightarrow$ Route

* **Thuộc tính chi tiết:** `route_key` (INT, PK), `route_id` (VARCHAR(20), BK), `origin_city` (VARCHAR(50)), `origin_state` (VARCHAR(10)), `destination_city` (VARCHAR(50)), `destination_state` (VARCHAR(10)), `typical_distance_miles` (DECIMAL(10,2)), `base_rate_per_mile` (DECIMAL(10,2)), `fuel_surcharge_rate` (DECIMAL(10,4)), `typical_transit_days` (INT).

#### **8. Dim_Load_Profile (Junk Dimension Đơn hàng)**

* **Nguồn dữ liệu:** Tổ hợp trạng thái từ `loads_sample.csv`.

* **Phân loại:** Junk Dimension (giải phóng Fact Table khỏi việc lưu trữ chuỗi text).

* **Khóa:** `load_profile_key` (TINYINT, PK).

* **Thuộc tính chi tiết:** `load_profile_key` (TINYINT, PK), `load_status` (VARCHAR(30)), `booking_type` (VARCHAR(30)), `load_type` (VARCHAR(30)).

#### **9. Dim_Maintenance_Profile (Junk Dimension Bảo dưỡng)**

* **Nguồn dữ liệu:** Trích xuất từ `maintenance_records_sample.csv` kết hợp quy tắc phân loại nghiệp vụ trong ETL.

* **Phân loại:** Junk Dimension.

* **Quy chuẩn trích xuất `service_urgency` (Derived Feature):** Do dữ liệu thô không có cột này, ETL áp dụng từ điển quy tắc nghiệp vụ cố định, tách từ đầu tiên (tiền tố) của chuỗi văn bản trong cột service_description để tạo trường service_urgency:

  * Nếu bắt đầu bằng Emergency $\rightarrow$ gán `'Emergency'`

  * Nếu bắt đầu bằng Routine $\rightarrow$ gán `'Routine'`.

  * Nếu bắt đầu bằng Scheduled  $\rightarrow$  gán `'Scheduled'` (hoặc gộp chung vào nhóm Routine nếu nghiệp vụ chỉ muốn chia 2 nhóm Khẩn cấp / Định kỳ)

  * Trường hợp khác $\rightarrow$ `'Standard'`

* **Khóa:** `maintenance_profile_key` (TINYINT, PK). Bản ghi $-1$: `maintenance_profile_key = -1`, `maintenance_type = 'Unknown'`, `service_urgency = 'Unspecified'`.

* **Thuộc tính chi tiết:** `maintenance_profile_key` (TINYINT, PK), `maintenance_type` (VARCHAR(50)), `service_urgency` (VARCHAR(30)).

---

### **BƯỚC 4: THIẾT KẾ CÁC BẢNG FACT VÀ ĐỘ ĐO (FACTS & MEASURES)**

#### **1. Fact_Load (Quản lý Đơn hàng Thương mại)**

* **Nguồn dữ liệu:** `loads_sample.csv`.

* **Loại Fact:** **Transaction Fact Table**.

* **Độ hạt:** Mỗi dòng là đúng một đơn hàng vận tải phát sinh (`load_id`).

* **Khóa ngoại Role-Playing:** `load_date_key` (FK $\rightarrow$ `Dim_Date`), `customer_key` (FK $\rightarrow$ `Dim_Customer`), `route_key` (FK $\rightarrow$ `Dim_Route`), `load_profile_key` (FK $\rightarrow$ `Dim_Load_Profile`).

* **Degenerate Dimension:** `load_id`.

##### **A. Measures Cộng dồn Hoàn toàn (Fully Additive Measures)**

* **`weight_lbs` (DECIMAL(12,2)):** Tổng khối lượng hàng hóa vận chuyển.

  * *Dim phân tích:* `Dim_Customer`

  * *Câu hỏi nghiệp vụ:* Khách hàng nào đem lại khối lượng vận chuyển lớn nhất để xét hạn mức chiết khấu?

* **`pieces` (INT):** Tổng số kiện hàng vận chuyển.

  * *Dim phân tích:* `Dim_Load_Profile` (`load_type`)

  * *Câu hỏi nghiệp vụ:* Tổng số lượng kiện hàng luân chuyển qua từng quý phân bổ ra sao?

* **`revenue` (DECIMAL(14,2)):** Doanh thu cước vận tải cơ bản.

  * *Dim phân tích:* `Dim_Customer`

  * *Câu hỏi nghiệp vụ:* Top 10 khách hàng có doanh thu thuần cao nhất trong năm?

* **`fuel_surcharge` (DECIMAL(14,2)):** Doanh thu phụ phí xăng dầu thu từ khách.

  * *Dim phân tích:* `Dim_Route`

  * *Câu hỏi nghiệp vụ:* Mức độ bù đắp biến động giá dầu theo từng hành lang tuyến?

* **`accessorial_charges` (DECIMAL(14,2)):** Phụ phí phát sinh ngoài hợp đồng.

  * *Dim phân tích:* `Dim_Load_Profile` (`booking_type`)

  * *Câu hỏi nghiệp vụ:* Hình thức đặt xe nào (Spot hay Contract) phát sinh phụ phí cao nhất?

* **`total_revenue` (DECIMAL(14,2)):** Tổng giá trị thanh toán thực tế của đơn hàng ($revenue + fuel\_surcharge + accessorial\_charges$).

  * *Dim phân tích:* `Dim_Route`

  * *Câu hỏi nghiệp vụ:* Tuyến đường nào mang lại tổng doanh thu thực tế cao nhất?

* **`load_count` (INT):** Đếm số lượng đơn hàng (Hằng số $1$ trên mỗi dòng).

  * *Dim phân tích:* `Dim_Date` (`load_date_key`)

  * *Câu hỏi nghiệp vụ:* Khối lượng đơn hàng tăng trưởng ra sao theo từng tháng?

##### **B. Measures Tính toán (OLAP Calculated Measures)**

* **`avg_pieces_per_load` (DECIMAL(10,2)):**

  * *Công thức:*
    $$avg\_pieces\_per\_load = \frac{\sum(Fact\_Load[pieces])}{\sum(Fact\_Load[load\_count])}$$

  * *Dim phân tích:* `Dim_Load_Profile` (`load_type`)

  * *Câu hỏi nghiệp vụ:* Mỗi loại hình chở hàng (Dry Van vs Reefer) bình quân đóng gói bao nhiêu kiện hàng trên mỗi đơn để chuẩn bị nhân lực bốc dỡ?

* **`revenue_per_pound` (DECIMAL(10,4)) - *Chuẩn hóa Tổng Thu Thực tế*:**

  * *Bản chất kỹ thuật:* Tính trên tổng giá trị thu về thực tế từ khách hàng (`total_revenue`) thay vì chỉ tính trên cước cơ bản thuần túy, nhằm phản ánh chính xác hiệu suất thu nhập trên mỗi pound tải trọng vận chuyển.

  * *Công thức:*
    $$revenue\_per\_pound = \frac{\sum(Fact\_Load[total\_revenue])}{\sum(Fact\_Load[weight\_lbs])}$$

  * *Dim phân tích:* `Dim_Route`

  * *Câu hỏi nghiệp vụ:* Tuyến vận chuyển nào có tổng giá trị thu về thực tế trên mỗi đơn vị khối lượng tốt nhất?

* **`avg_revenue_per_load` (DECIMAL(12,2)):**

  * *Công thức:*
    $$avg\_revenue\_per\_load = \frac{\sum(Fact\_Load[total\_revenue])}{\sum(Fact\_Load[load\_count])}$$

  * *Dim phân tích:* `Dim_Customer`

  * *Câu hỏi nghiệp vụ:* Khách hàng nào có giá trị trung bình trên một đơn hàng cao nhất?

---

#### **2. Fact_Trip (Vận hành Chuyến xe Thực tế)**

* **Nguồn dữ liệu:** `trips_sample.csv` (Nạp trực tiếp $100\%$, giữ nguyên ranh giới vận hành độc lập, không join gián tiếp qua `loads.csv`).

* **Loại Fact:** **Transaction Fact Table**.

* **Độ hạt:** Mỗi dòng là đúng một chuyến xe lăn bánh hoàn chỉnh (`trip_id`).

* **Khóa ngoại Role-Playing:** `dispatch_date_key` (FK $\rightarrow$ `Dim_Date`), `driver_key` (FK $\rightarrow$ `Dim_Driver`), `truck_key` (FK $\rightarrow$ `Dim_Truck`), `trailer_key` (FK $\rightarrow$ `Dim_Trailer`). Hỗ trợ khóa $-1$ cho các chuyến xe thiếu mã tài xế hoặc đầu kéo trong dữ liệu nguồn.

* **Degenerate Dimension:** `trip_id`, `load_id`, `trip_status` (Bảo toàn `trip_status` làm DD phục vụ phân tích trạng thái điều độ tức thời).

##### **A. Measures Cộng dồn Hoàn toàn (Fully Additive Measures)**

* **`actual_distance_miles` (DECIMAL(10,2)):** Quãng đường thực tế phương tiện lăn bánh.

  * *Dim phân tích 1:* `Dim_Truck` (Đầu kéo) $\rightarrow$ Đo dặm lũy kế kích hoạt lịch bảo dưỡng.

  * *Dim phân tích 2:* `Dim_Trailer` (Rơ-moóc) $\rightarrow$ Đo dặm vận hành rơ-moóc để lên lịch kiểm tra dàn lốp và trục quay.

* **`actual_duration_hours` (DECIMAL(10,2)):** Thời gian chuyến xe chạy thực tế trên đường (thời gian lăn bánh/lái xe thuần túy).

  * *Dim phân tích:* `Dim_Driver`

  * *Câu hỏi nghiệp vụ:* Kiểm soát tuân thủ quy chuẩn thời gian lái xe tối đa của tài xế (Hours of Service - HOS).

* **`fuel_gallons_used` (DECIMAL(10,2)):** Thể tích nhiên liệu tiêu hao thực tế.

  * *Dim phân tích:* `Dim_Truck` (`make`, `model_year`)

  * *Câu hỏi nghiệp vụ:* Hãng xe hoặc đời xe nào tiêu thụ nhiên liệu lớn nhất?

* **`idle_time_hours` (DECIMAL(10,2)):** Thời gian nổ máy dừng chờ lãng phí.

  * *Dim phân tích:* `Dim_Driver`

  * *Câu hỏi nghiệp vụ:* Tài xế nào có thói quen dừng xe nổ máy chờ gây hao hụt dầu?

* **`trip_count` (INT):** Tổng số chuyến xe hoàn tất (Hằng số $1$).

  * *Dim phân tích:* `Dim_Trailer` (`trailer_type`), `Dim_Truck`

  * *Câu hỏi nghiệp vụ:* Tần suất huy động các chủng loại rơ-moóc và đầu kéo ra sao?

##### **B. Measures Tính toán (OLAP Calculated Measures)**

* **`fleet_average_mpg` (DECIMAL(6,2)):** Mức tiêu hao nhiên liệu trung bình.

  * *Công thức:*
    $$fleet\_average\_mpg = \frac{\sum(Fact\_Trip[actual\_distance\_miles])}{\sum(Fact\_Trip[fuel\_gallons\_used])}$$

  * *Dim phân tích:* `Dim_Trailer` (`trailer_type`) kết hợp `Dim_Truck`

  * *Câu hỏi nghiệp vụ:* Kéo thùng lạnh Reefer làm suy giảm hiệu suất nhiên liệu (MPG) bao nhiêu % so với kéo thùng Dry Van tiêu chuẩn?

* **`avg_operating_speed` (DECIMAL(6,2)):** Tốc độ lăn bánh trung bình.

  * *Công thức:*
    $$avg\_operating\_speed = \frac{\sum(Fact\_Trip[actual\_distance\_miles])}{\sum(Fact\_Trip[actual\_duration\_hours])}$$

  * *Dim phân tích:* `Dim_Driver`, `Dim_Truck`, `Dim_Date`

  * *Câu hỏi nghiệp vụ:* Tài xế hoặc dòng xe đầu kéo nào có tốc độ di chuyển bình quân thấp; biến động tốc độ lăn bánh theo các tháng/mùa trong năm ra sao?

* **`idle_time_percentage` (DECIMAL(5,2)):**

  * *Bản chất kỹ thuật:* Mẫu số tính trên tổng thời gian điều động phương tiện ($actual\_duration\_hours + idle\_time\_hours$).

  * *Công thức:*
    $$idle\_time\_percentage = \frac{\sum(Fact\_Trip[idle\_time\_hours])}{\sum(Fact\_Trip[actual\_duration\_hours] + Fact\_Trip[idle\_time\_hours])} \times 100\%$$

  * *Dim phân tích:* `Dim_Driver`

  * *Câu hỏi nghiệp vụ:* Tài xế nào có tỷ lệ nổ máy chờ vượt quá ngưỡng cảnh báo lãng phí ($> 10\%$ tổng thời gian vận hành)?

* **`avg_miles_per_active_trailer` (DECIMAL(10,2)):**

  * *Công thức:*
    $$avg\_miles\_per\_active\_trailer = \frac{\sum(Fact\_Trip[actual\_distance\_miles])}{DISTINCTCOUNT(Fact\_Trip[trailer\_key])}$$

  * *Dim phân tích:* `Dim_Trailer` (`trailer_type`)

  * *Câu hỏi nghiệp vụ:* Cường độ khai thác trung bình của các rơ-moóc đang có chuyến lăn bánh đạt bao nhiêu dặm?

---

#### **3. Fact_Delivery_Fulfillment (Chu trình Hoàn tất Giao nhận Hai đầu Bến)**

* **Nguồn dữ liệu:** `delivery_events_sample.csv` (Pivot cặp sự kiện `Pickup` và `Delivery` theo từng `load_id`).

* **Loại Fact:** **Accumulating Snapshot Fact Table**.

* **Độ hạt:** Mỗi dòng đại diện cho **đúng một chu trình thực thi trọn vẹn từ lúc bốc hàng đến khi dỡ hàng xong** của một đơn hàng (`load_id`).

* **Khóa ngoại Role-Playing & Cơ chế In-Flight:**

  * `pickup_date_key` (FK $\rightarrow$ `Dim_Date`): Lấy từ mốc thời gian bốc hàng thực tế.

  * `delivery_date_key` (FK $\rightarrow$ `Dim_Date`): Lấy từ mốc thời gian dỡ hàng thực tế. **Nếu đơn hàng mới chỉ bốc nhưng chưa giao xong, gán `delivery_date_key = -1` (Pending / In-Flight)**.

  * `origin_facility_key` (FK $\rightarrow$ `Dim_Facility`): Cơ sở bốc hàng.

  * `destination_facility_key` (FK $\rightarrow$ `Dim_Facility`): Cơ sở dỡ hàng.

  * `customer_key` (FK $\rightarrow$ `Dim_Customer`): Làm giàu từ `load_id`.

  * `load_profile_key` (FK $\rightarrow$ `Dim_Load_Profile`): Làm giàu từ `load_id`.

  * `route_key` (FK $\rightarrow$ `Dim_Route`): Tuyến đường vận chuyển.

* **Degenerate Dimension:** `load_id`, `trip_id`, `pickup_event_id`, `delivery_event_id`.

##### **A. Measures Cộng dồn Hoàn toàn (Fully Additive Measures)**

* **`pickup_detention_minutes` (INT):** Thời gian lưu bãi chờ bốc hàng vượt chuẩn tại kho xuất phát.

  * *Dim phân tích:* `Dim_Facility` (*Origin Facility*)

  * *Câu hỏi nghiệp vụ:* Kho bãi đầu xuất phát nào thường xuyên làm chậm khâu xuất hàng?

* **`delivery_detention_minutes` (INT):** Thời gian phương tiện bị giam chờ dỡ hàng tại kho đích.

  * *Dim phân tích:* `Dim_Facility` (*Destination Facility*), `Dim_Customer`

  * *Câu hỏi nghiệp vụ:* Kho đích hoặc khách hàng nào làm giam xe quá 120 phút định mức để kích hoạt hóa đơn phạt Detention Charges?

* **`total_detention_minutes` (INT):** Tổng thời gian chết bãi hai đầu bến ($pickup\_detention\_minutes + delivery\_detention\_minutes$).

  * *Dim phân tích:* `Dim_Route`, `Dim_Load_Profile` (`booking_type`)

  * *Câu hỏi nghiệp vụ:* Loại hợp đồng đặt xe nào chịu thời gian giam giữ chờ bốc dỡ cao nhất?

* **`transit_duration_hours` (DECIMAL(10,2)):** Thời gian vận chuyển thực tế từ kho đi đến kho đến tính bằng giờ (Gán NULL hoặc $0$ nếu đơn hàng đang In-Flight).

  * *Công thức tính:*
    $$transit\_duration\_hours = \frac{DATEDIFF(MINUTE, pickup\_actual\_datetime, delivery\_actual\_datetime)}{60.0}$$

  * *Dim phân tích:* `Dim_Route`

  * *Câu hỏi nghiệp vụ:* Thời gian phương tiện thực chạy giữa 2 cơ sở là bao nhiêu tiếng?

* **`pickup_on_time_count` (INT):** Số lượt xe bốc hàng đúng hẹn ($1$ nếu đúng giờ, $0$ nếu trễ).

  * *Dim phân tích:* `Dim_Facility` (*Origin Facility*)

* **`delivery_on_time_count` (INT):** Số lượt giao hàng đến đích đạt chuẩn SLA khung giờ hẹn cam kết ($1$ nếu đạt, $0$ nếu vi phạm; gán $0$ nếu đơn hàng đang In-Flight).

  * *Dim phân tích:* `Dim_Customer`, `Dim_Facility` (*Destination Facility*)

  * *Câu hỏi nghiệp vụ:* Khách hàng nào có tỷ lệ đơn giao tới nơi đúng giờ cao nhất?

* **`perfect_fulfillment_count` (INT):** Số chuyến giao nhận hoàn hảo ($1$ nếu đồng thời: Bốc đúng giờ, Giao đúng giờ, Tổng detention $\le 120$ phút và đã hoàn tất giao hàng; ngược lại $0$).

  * *Dim phân tích:* `Dim_Route`, `Dim_Customer`

* **`total_fulfillment_count` (INT):** Tổng số đơn hàng trong pipeline giao nhận (Hằng số $1$ trên mọi dòng).

* **`completed_fulfillment_count` (INT):** Số đơn hàng đã khép kín chu trình giao hàng tới kho đích ($1$ nếu `delivery_date_key <> -1`, ngược lại $0$).

##### **B. Measures Tính toán (OLAP Calculated Measures) - *Chuẩn hóa Khử Lỗi In-Flight***

* **`transit_variance_hours` (DECIMAL(10,2)) - *Đã bổ sung bộ lọc loại trừ In-Flight*:**

  * *Bản chất kỹ thuật:* Chỉ so sánh chênh lệch thời gian trên các đơn hàng đã thực sự hoàn thành giao nhận (`delivery_date_key <> -1`). Việc loại trừ các dòng In-Flight giúp triệt tiêu hiện tượng lấy $0$ giờ trừ đi thời gian định mức gây âm kết quả. Đồng thời sử dụng `SUMX` và `RELATED` để bảo toàn ngữ cảnh lọc theo từng dòng.

  * *Công thức DAX:*
    $$transit\_variance\_hours = CALCULATE(\sum(Fact\_Delivery\_Fulfillment[transit\_duration\_hours]) - SUMX(Fact\_Delivery\_Fulfillment, RELATED(Dim\_Route[typical\_transit\_days]) \times 24), Fact\_Delivery\_Fulfillment[delivery\_date\_key] <> -1)$$

  * *Dim phân tích:* `Dim_Route`

  * *Câu hỏi nghiệp vụ:* Thời gian vận chuyển thực tế của các đơn đã hoàn tất lệch bao nhiêu giờ so với thời gian tiêu chuẩn cam kết?

* **`on_time_delivery_rate` (DECIMAL(5,2)) - *Đã chuẩn hóa mẫu số hoàn tất*:**

  * *Bản chất kỹ thuật:* Mẫu số chỉ tính trên các đơn hàng đã hoàn tất giao nhận (`delivery_date_key <> -1`), ngăn ngừa việc kéo tụt tỷ lệ giao hàng đúng hạn của doanh nghiệp bởi các đơn hàng đang trong hành trình di chuyển.

  * *Công thức DAX:*
    $$on\_time\_delivery\_rate = \frac{\sum(Fact\_Delivery\_Fulfillment[delivery\_on\_time\_count])}{CALCULATE(\sum(Fact\_Delivery\_Fulfillment[total\_fulfillment\_count]), Fact\_Delivery\_Fulfillment[delivery\_date\_key] <> -1)} \times 100\%$$

  * *Dim phân tích:* `Dim_Customer`, `Dim_Facility` (*Destination Facility*)

  * *Câu hỏi nghiệp vụ:* Tỷ lệ giao hàng đúng hẹn trên các đơn đã hoàn tất theo từng đối tác khách hàng có đạt mục tiêu SLA cam kết ($95\%$) không?

* **`perfect_fulfillment_rate` (DECIMAL(5,2)) - *Đã chuẩn hóa mẫu số hoàn tất*:**

  * *Công thức DAX:*
    $$perfect\_fulfillment\_rate = \frac{\sum(Fact\_Delivery\_Fulfillment[perfect\_fulfillment\_count])}{CALCULATE(\sum(Fact\_Delivery\_Fulfillment[total\_fulfillment\_count]), Fact\_Delivery\_Fulfillment[delivery\_date\_key] <> -1)} \times 100\%$$

  * *Dim phân tích:* `Dim_Customer`, `Dim_Route`

* **`avg_transit_lead_time` (DECIMAL(6,2)):**

  * *Công thức DAX:*
    $$avg\_transit\_lead\_time = \frac{CALCULATE(\sum(Fact\_Delivery\_Fulfillment[transit\_duration\_hours]), Fact\_Delivery\_Fulfillment[delivery\_date\_key] <> -1)}{CALCULATE(\sum(Fact\_Delivery\_Fulfillment[total\_fulfillment\_count]), Fact\_Delivery\_Fulfillment[delivery\_date\_key] <> -1)}$$

  * *Dim phân tích:* `Dim_Route`

---

#### **4. Fact_Maintenance (Bảo dưỡng & Kỹ thuật Đội xe)**

* **Nguồn dữ liệu:** `maintenance_records_sample.csv`.

* **Loại Fact:** **Transaction Fact Table**.

* **Độ hạt:** Mỗi dòng đại diện cho một lượt phương tiện vào xưởng bảo trì/sửa chữa (`maintenance_id`).

* **Khóa ngoại Role-Playing:** `maintenance_date_key` (FK $\rightarrow$ `Dim_Date`), `truck_key` (FK $\rightarrow$ `Dim_Truck`), `maintenance_profile_key` (FK $\rightarrow$ `Dim_Maintenance_Profile`).

* **Degenerate Dimension:** `maintenance_id`, `facility_location` (Lưu trực tiếp tên thành phố nơi phương tiện vào xưởng dưới dạng Degenerate Dimension, loại bỏ hoàn toàn việc gán khóa ảo làm ô nhiễm danh mục `Dim_Facility`).

##### **A. Measures Cộng dồn Hoàn toàn (Fully Additive Measures)**

* **`labor_hours` (DECIMAL(6,2)):** Tổng giờ công kỹ thuật của thợ máy.

  * *Dim phân tích:* `Dim_Maintenance_Profile` (`maintenance_type`)

  * *Câu hỏi nghiệp vụ:* Hạng mục bảo dưỡng nào tiêu tốn nhiều thời gian của thợ sửa chữa nhất?

* **`labor_cost` (DECIMAL(12,2)):** Chi phí tiền công thợ máy.

* **`parts_cost` (DECIMAL(12,2)):** Chi phí phụ tùng vật tư thay thế.

  * *Dim phân tích:* `Dim_Truck` (`make`)

  * *Câu hỏi nghiệp vụ:* Hãng đầu kéo nào ngốn nhiều chi phí vật tư linh kiện thay thế nhất?

* **`total_maintenance_cost` (DECIMAL(14,2)):** Tổng chi phí bảo dưỡng ($labor\_cost + parts\_cost$).

  * *Dim phân tích:* `Dim_Truck`

  * *Câu hỏi nghiệp vụ:* Đầu kéo nào có chi phí sửa chữa cộng dồn vượt ngưỡng hiệu quả kinh tế để quyết định thanh lý?

* **`downtime_hours` (DECIMAL(8,2)):** Thời gian phương tiện ngưng hoạt động nằm chờ sửa chữa tại xưởng.

  * *Dim phân tích:* `Dim_Maintenance_Profile` (`service_urgency`)

  * *Câu hỏi nghiệp vụ:* Các sự cố khẩn cấp (Emergency) gây thiệt hại bao nhiêu giờ ngừng hoạt động của xe?

* **`maintenance_count` (INT):** Tổng số lượt vào xưởng (Hằng số $1$).

  * *Dim phân tích:* `Dim_Truck`

  * *Câu hỏi nghiệp vụ:* Tần suất gặp sự cố của từng xe trong năm để đo độ tin cậy tài sản (Asset Reliability)?

##### **B. Measure Bán cộng dồn (Semi-Additive Measure)**

* **`odometer_reading` (INT):** Chỉ số công-tơ-mét ghi nhận khi xe vào xưởng.

  * *Tính chất:* Không thể cộng dồn theo chiều thời gian; áp dụng hàm $LAST\_NON\_EMPTY$ hoặc $MAX$ theo từng đầu xe.

  * *Dim phân tích:* `Dim_Truck`

  * *Câu hỏi nghiệp vụ:* Số dặm hoạt động lũy kế mới nhất của từng xe để cảnh báo mốc đại tu tổng thành?

##### **C. Measures Tính toán (OLAP Calculated Measures) & Quản trị Độ sẵn sàng Tài sản Đội xe**

* **`avg_cost_per_maintenance_event` (DECIMAL(12,2)):**

  * *Công thức:*
    $$avg\_cost\_per\_maintenance\_event = \frac{\sum(Fact\_Maintenance[total\_maintenance\_cost])}{\sum(Fact\_Maintenance[maintenance\_count])}$$

  * *Dim phân tích:* `Dim_Maintenance_Profile` (`maintenance_type`)

* **`avg_downtime_hours` (DECIMAL(6,2)):**

  * *Công thức:*
    $$avg\_downtime\_hours = \frac{\sum(Fact\_Maintenance[downtime\_hours])}{\sum(Fact\_Maintenance[maintenance\_count])}$$

  * *Dim phân tích:* `Dim_Maintenance_Profile` (`service_urgency`)

* **`low_utilization_trailer_count` (INT) - *Quy hoạch Quản trị Sức khỏe & Sẵn sàng Tài sản Đội xe*:**

  * *Bản chất kỹ thuật:* Là chỉ số cấp độ quản trị tài sản (Fleet Asset Integrity & Readiness). Do dữ liệu nguồn `maintenance_records_sample.csv` không ghi nhận `trailer_id`, chỉ số này được tính toán phối hợp bằng cách duyệt trên danh mục tài sản `Dim_Trailer` và tính lũy kế dặm thực chạy từ `Fact_Trip` để phát hiện các rơ-moóc bị đắp chiếu tại bãi hoặc chạy quá ít (< 500 dặm/tháng).

  * *Công thức DAX:*
    $$low\_utilization\_trailer\_count = COUNTROWS(FILTER(VALUES(Dim\_Trailer[trailer\_key]), COALESCE(CALCULATE(\sum(Fact\_Trip[actual\_distance\_miles])), 0) < 500))$$

  * *Dim phân tích:* `Dim_Trailer` (`trailer_type`, `current_location`)

  * *Câu hỏi nghiệp vụ:* Có bao nhiêu rơ-moóc chạy dưới 500 dặm trong kỳ (bao gồm cả các moóc chạy 0 dặm đắp chiếu tại bến bãi) cần lập kế hoạch bảo trì bảo dưỡng dàn lốp/trục quay hoặc thanh lý thu hồi vốn?

---

## **PHẦN 2: ENTERPRISE DATA WAREHOUSE BUS MATRIX (BẢN CHUẨN HÓA)**

Ma trận thể hiện mối quan hệ liên kết chuẩn xác giữa **4 Bảng Fact** và **9 Bảng Dimension**:

| **Quy trình Nghiệp vụ / Bảng Fact** | **Phân loại Fact theo Kimball** | **Dim_Date** | **Dim_Customer** | **Dim_Facility** | **Dim_Route** | **Dim_Driver** | **Dim_Truck** | **Dim_Trailer** | **Dim_Load_Profile** | **Dim_Maint_Profile** |
| :--- | :--- | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: | :---: |
| **1. Quản lý Đơn hàng (`Fact_Load`)** | **Transaction Fact** | **X** *(Load Date)* | **X** | | **X** | | | | **X** *(Junk)* | |
| **2. Vận hành Chuyến xe (`Fact_Trip`)** | **Transaction Fact** | **X** *(Dispatch Date)* | | | | **X** | **X** | **X** | | |
| **3. Chu trình Giao nhận (`Fact_Delivery_Fulfillment`)** | **Accumulating Snapshot Fact** | **X** *(Pickup/Deliv)* | **X** *(Enrich)* | **X** *(Origin/Dest)* | **X** *(Enrich)* | | | | **X** *(Enrich)* | |
| **4. Kỹ thuật & Bảo dưỡng (`Fact_Maintenance`)** | **Transaction Fact** | **X** *(Maint Date)* | | | | | **X** | | | **X** *(Junk)* |

*Ghi chú:* Bảng `Fact_Maintenance` lưu trữ vị trí trạm sửa chữa bằng trường thoái hóa `facility_location` (Degenerate Dimension) thay vì ép nối làm biến dạng `Dim_Facility`.

---

## **PHẦN 3: ĐÁNH GIÁ TÍNH TOÀN VẸN RÀNG BUỘC VÀ KHẢ NĂNG DRILL-ACROSS**

### **1. Chiến lược Khử bỏ Lỗi Khóa Ngoại trong Pipeline ETL**

* **Xử lý triệt để dữ liệu khuyết thiếu (NULL/Blank):**

  * Trong bảng `trips.csv`, những dòng thiếu tài xế (như `TRIP00000067`) hoặc thiếu đầu xe (như `TRIP00000070`, `TRIP00000074`) được gán trực tiếp Surrogate Key $-1$. Kỹ thuật này giữ trọn vẹn số liệu thực tế về quãng đường và chi phí nhiên liệu mà không vi phạm ràng buộc toàn vẹn khóa ngoại (Foreign Key Integrity).

  * Trong `Fact_Delivery_Fulfillment`, các đơn hàng đang trên đường vận chuyển (đã bốc nhưng chưa giao) được nạp vào Fact với `delivery_date_key = -1` và trạng thái `In-Flight`. Khi sự kiện Delivery hoàn tất, tiến trình ETL sẽ cập nhật bản ghi này theo đúng cơ chế của Accumulating Snapshot Fact Table.

* **Đồng bộ hóa địa chỉ và chuẩn hóa dữ liệu bến bãi:**
  Toàn bộ các sự kiện dừng đỗ trong `Fact_Delivery_Fulfillment` lấy vị trí chuẩn hóa `corrected_facility_id` thông qua bảng từ điển `Ref_City_Facility_Mapping` dựa trên cặp sự thật nguồn `(location_city, location_state)`, loại bỏ hoàn toàn sai lệch $96.55\%$ của mã `facility_id` gốc và gán khóa mặc định `-1` cho các sự kiện tại 4 thành phố không có cơ sở trực thuộc.

### **2. Khả năng Phân tích Phối hợp Đa quy trình (Drill-Across Analysis)**

* **Tổng Chi phí Sở hữu Đội xe (Fleet Total Cost of Ownership - TCO):**
  Thực hiện Drill-across giữa `Fact_Trip` và `Fact_Maintenance` qua conformed dimension `Dim_Truck`:
  $$Total\_Truck\_Operating\_Cost = \sum(Fuel\_Gallons\_Used \times Average\_Fuel\_Price) + \sum(Total\_Maintenance\_Cost)$$
  Giúp doanh nghiệp đánh giá chính xác chi phí vận hành ròng trên mỗi dặm lăn bánh ($Cost\_per\_Mile$) của từng dòng xe đầu kéo.

* **Hiệu quả Thương mại Tuyến và Rủi ro Bến Bãi (Corridor Revenue & Delivery Friction):**
  Thực hiện Drill-across giữa `Fact_Load` và `Fact_Delivery_Fulfillment` qua `Dim_Route` và `Dim_Customer`:
  $$Fulfillment\_Risk\_Ratio = \frac{\sum(Total\_Detention\_Minutes)}{\sum(Total\_Revenue)}$$
  Chỉ số này đối chiếu trực tiếp giữa giá trị doanh thu thu được trên từng hành lang tuyến với thời gian phương tiện bị tắc nghẽn bến bãi, giúp doanh nghiệp đàm phán lại biểu cước phụ phí hoặc điều chỉnh cam kết SLA với khách hàng.

* **Hiệu suất Khai thác và Vòng đời Tài sản Rơ-moóc (Trailer ROI & Fleet Health):**
  Kết hợp `Fact_Trip` và `Dim_Trailer` theo từng nhóm `trailer_type` và `length_feet`, kết nối cùng chỉ số kiểm soát moóc nhàn rỗi `low_utilization_trailer_count` tại nhóm Quản trị Tài sản & Bảo dưỡng để tối ưu hóa quyết định điều động tái phân bổ hoặc thanh lý tài sản.