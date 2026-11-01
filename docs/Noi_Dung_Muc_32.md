# 3.2 Phân tích đa chiều phân hệ Kỹ thuật - Bảo dưỡng

Trong hệ sinh thái Kho dữ liệu Vận tải & Quản trị đội xe (Logistics & Fleet Operations DWH), phân hệ Kỹ thuật - Bảo dưỡng giữ vị trí trung tâm trong việc kiểm soát chi phí sửa chữa, giám sát tình trạng hao mòn cơ khí và tối ưu hóa tính sẵn sàng của tài sản phương tiện. Việc tổ chức mô hình phân tích đa chiều (OLAP Cube) cho phân hệ này cho phép giải quyết bài toán quản trị vận hành phức tạp: từ việc đối chiếu định mức chi phí giữa các nhà chế tạo động cơ, theo dõi thời gian xe ngừng hoạt động (Downtime), cho đến phát hiện các đầu kéo cá biệt gây thâm hụt ngân sách để đưa ra quyết định thanh lý kịp thời.

Khối đa chiều **`Cube_Maintenance`** được xây dựng trên bảng sự kiện hạt nhân **`Fact_Maintenance`** (chứa $5.840$ bản ghi sự kiện bảo dưỡng kỹ thuật phát sinh liên tục trong giai đoạn 2022–2024), liên kết trực tiếp với 3 chiều phân tích chuẩn mực (Conformed Dimensions) theo phương pháp luận Ralph Kimball:

* **`Dim_Date` (Chiều thời gian chuẩn hóa):** Tổ chức theo cây phân cấp *Calendar Hierarchy* (`Calendar Year` $\rightarrow$ `Calendar Quarter` $\rightarrow$ `Month Name` $\rightarrow$ `Full Date`), hỗ trợ bóc tách chu kỳ biến động chi phí bảo dưỡng theo mùa vụ và nhận diện quy luật già hóa tài sản theo từng mốc thời gian.
* **`Dim_Truck` (Chiều phương tiện đầu kéo):** Tổ chức theo cây phân cấp *Truck Fleet Hierarchy* (`Make` $\rightarrow$ `Model Year` $\rightarrow$ `Unit Number`), cho phép nhà quản trị thực hiện lát cắt tổng thể ở cấp hãng xe, sau đó khoan sâu (*drill-down*) xuống từng năm sản xuất và định danh chính xác từng biển số đầu xe cụ thể.
* **`Dim_Maintenance_Profile` (Chiều hồ sơ phân loại bảo dưỡng):** Là Junk Dimension kết hợp giữa **7 loại hình tác nghiệp kỹ thuật** (*Preventive, Repair, Brake, Engine, Tire, Transmission, Inspection*) và **3 mức độ khẩn cấp** (*Emergency, Scheduled, Routine*), tạo nên 21 profile kỹ thuật chuẩn xác nhằm phân tích chuyên sâu các chế độ hỏng hóc (*Failure Modes*).

---

## 3.2.1 Cấu hình Measure Group Bảo dưỡng và Calculated Measures sức khỏe tài sản trên SSAS

### A. Cấu hình Measure Group Fact Maintenance và phân loại độ đo cơ sở

Trong dự án `SSAS_Logistics`, Measure Group **`Fact Maintenance`** được cấu hình từ bảng `Fact_Maintenance`. Các độ đo cơ sở (*Base Measures*) được lựa chọn kỹ lưỡng và gán đúng hàm tổng hợp (*Aggregate Function*) theo đúng bản chất vật lý của từng chỉ số dữ liệu:

| Tên Measure trong Cube | Cột dữ liệu nguồn | Hàm Aggregate | Bản chất & Ý nghĩa nghiệp vụ |
| :--- | :--- | :---: | :--- |
| **`Total Maintenance Cost`** | `total_maintenance_cost` | **Sum** | *Additive*: Tổng chi phí bảo dưỡng phát sinh (USD), cộng dồn đa chiều. |
| **`Labor Cost`** | `labor_cost` | **Sum** | *Additive*: Chi phí trả cho nhân công thợ máy (USD). |
| **`Parts Cost`** | `parts_cost` | **Sum** | *Additive*: Chi phí mua sắm vật tư, linh kiện thay thế (USD). |
| **`Downtime Hours`** | `downtime_hours` | **Sum** | *Additive*: Tổng số giờ xe phải ngừng hoạt động nằm xưởng (giờ). |
| **`Labor Hours`** | `labor_hours` | **Sum** | *Additive*: Tổng số giờ công thợ trực tiếp sửa chữa (giờ). |
| **`Maintenance Count`** | `maintenance_count` | **Sum / Count** | *Additive*: Số lượt phát sinh sự kiện sửa chữa/bảo dưỡng. |
| **`Fact Maintenance Count`** | *(Row Count)* | **Count** | Đếm tổng số bản ghi trong bảng Fact phục vụ các phép tính tỷ lệ. |
| **`Odometer Reading`** | `odometer_reading` | **Max** | *Semi-Additive*: Số km tích lũy cao nhất của từng đầu xe (**MAX**). |

> **Cơ chế Semi-Additive Measure cho Odometer Reading:**  
> Chỉ số số km hiển thị trên công-tơ-mét (`odometer_reading`) là một độ đo bán cộng dồn điển hình (*Semi-Additive*). Nếu áp dụng hàm tổng hợp mặc định `SUM`, hệ thống sẽ thực hiện phép tính cộng gộp số km của toàn bộ 120 đầu kéo thành một con số hàng chục triệu km hoàn toàn vô nghĩa về mặt vật lý. Trong thiết kế `Cube_Maintenance`, thuộc tính `AggregateFunction` của độ đo này bắt buộc phải được cấu hình là **`MAX`**. Với thiết lập này, khi truy vấn theo chiều `Dim_Truck`, giá trị trả về đại diện chính xác cho quãng đường lăn bánh cao nhất (vòng đời lũy kế) của từng đầu xe tại thời điểm kết thúc kỳ quan sát, cung cấp dữ liệu nền tảng phục vụ việc đối chiếu với ngưỡng thanh lý tài sản định lượng.

---

### B. Xây dựng các Calculated Measures đo lường sức khỏe tài sản bằng MDX Script

Nhằm cung cấp các chỉ số đo lường hiệu suất (*KPIs*) phản ánh chính xác hiệu quả vận hành kỹ thuật và sức khỏe tài sản đội xe, 4 thước đo tính toán (*Calculated Measures*) được định nghĩa trực tiếp vào Semantic Layer của `Cube_Maintenance` thông qua ngôn ngữ MDX Script.

Một nguyên tắc lập trình MDX quan trọng được áp dụng là **kiểm soát triệt để lỗi chia cho 0**. Do người dùng có thể thực hiện thao tác cắt lát qua các chiều dữ liệu mà tại đó không có sự kiện bảo dưỡng nào diễn ra, biểu thức MDX bắt buộc phải bao bọc trong cấu trúc điều kiện `IIF(Denominator = 0, 0, Numerator / Denominator)`, kèm theo định dạng hiển thị trực quan (*Currency*, *Percent*, *Number*).

```mdx
CALCULATE;

/* -------------------------------------------------------------------------
   CALCULATED MEASURES CHO PHÂN HỆ QUẢN TRỊ BẢO DƯỠNG XE - PHÚC AN
   ------------------------------------------------------------------------- */

-- 1. Chi phí bảo dưỡng trung bình cho mỗi lần vào xưởng (Avg Maintenance Cost per Event)
CREATE MEMBER CURRENTCUBE.[Measures].[CM_Avg_Maintenance_Cost] AS
IIF(
    [Measures].[Fact Maintenance Count] = 0,
    0,
    [Measures].[Total Maintenance Cost] / [Measures].[Fact Maintenance Count]
),
FORMAT_STRING = "Currency",
ASSOCIATED_MEASURE_GROUP = 'Fact Maintenance';

-- 2. Thời gian dừng xe trung bình cho mỗi đợt sửa chữa (Avg Downtime per Event)
CREATE MEMBER CURRENTCUBE.[Measures].[CM_Avg_Downtime_Hours] AS
IIF(
    [Measures].[Fact Maintenance Count] = 0,
    0,
    [Measures].[Downtime Hours] / [Measures].[Fact Maintenance Count]
),
FORMAT_STRING = "#,##0.00",
ASSOCIATED_MEASURE_GROUP = 'Fact Maintenance';

-- 3. Chi phí nhân công trung bình mỗi giờ công thợ (Hourly Labor Rate)
CREATE MEMBER CURRENTCUBE.[Measures].[CM_Hourly_Labor_Rate] AS
IIF(
    [Measures].[Labor Hours] = 0,
    0,
    [Measures].[Labor Cost] / [Measures].[Labor Hours]
),
FORMAT_STRING = "Currency",
ASSOCIATED_MEASURE_GROUP = 'Fact Maintenance';

-- 4. Tỷ trọng chi phí phụ tùng trên tổng chi phí bảo dưỡng (Parts Cost Ratio %)
CREATE MEMBER CURRENTCUBE.[Measures].[CM_Parts_Cost_Ratio] AS
IIF(
    [Measures].[Total Maintenance Cost] = 0,
    0,
    [Measures].[Parts Cost] / [Measures].[Total Maintenance Cost]
),
FORMAT_STRING = "Percent",
ASSOCIATED_MEASURE_GROUP = 'Fact Maintenance';
```

| Tên Calculated Measure | Công thức toán học | Định dạng | Giá trị thực tế & Ứng dụng quản trị |
| :--- | :--- | :---: | :--- |
| **`CM_Avg_Maintenance_Cost`** | $\frac{\text{Total\_Cost}}{\text{Fact\_Count}}$ | Currency ($) | **Thực tế: $\$1.962,53$**. Thiết lập định mức tài chính chuẩn cho 1 lượt sửa; gắn cờ cảnh báo xe vượt $\$2.500$. |
| **`CM_Avg_Downtime_Hours`** | $\frac{\text{Downtime\_Hours}}{\text{Fact\_Count}}$ | #,##0.00 (h) | **Thực tế: $24,74$ giờ (~1 ngày)**. Đánh giá tính sẵn sàng của đội xe phục vụ điều phối phương tiện thay thế. |
| **`CM_Hourly_Labor_Rate`** | $\frac{\text{Labor\_Cost}}{\text{Labor\_Hours}}$ | Currency ($) | **Thực tế: $\$104,78$/h**. Kiểm soát chi phí tiền công thợ và thẩm định tính hợp lý của hóa đơn garage dịch vụ. |
| **`CM_Parts_Cost_Ratio`** | $\frac{\text{Parts\_Cost}}{\text{Total\_Cost}}$ | Percent (%) | **Thực tế: $77,65\%$**. Chỉ ra chi phí vật tư chi phối áp đảo, định hướng đàm phán hợp đồng mua sỉ phụ tùng. |

---

## 3.2.2 Xây dựng truy vấn MDX và T-SQL phân tích tổng chi phí sở hữu đội xe

### A. Cơ chế Drill-Across tính Tổng chi phí sở hữu đội xe (Fleet TCO)

Trong quản trị tài chính logistics, Tổng chi phí sở hữu đội xe (**Fleet Total Cost of Ownership – TCO**) là chỉ số mang tính sống còn để xác định điểm hòa vốn và xây dựng giá cước vận tải. TCO đội xe được cấu thành từ hai nhóm chi phí lớn nhất:

$$\text{Fleet TCO} = \text{Chi phí Nhiên liệu vận hành (Fact\_Trip)} + \text{Chi phí Kỹ thuật - Bảo dưỡng (Fact\_Maintenance)}$$

Nhờ kiến trúc Galaxy Schema chia sẻ chiều dùng chung `Dim_Truck` và `Dim_Date`, hệ thống cho phép thực hiện thao tác **Drill-Across** (khoan xuyên qua hai Fact Table độc lập) mà không cần tạo bảng gộp dư thừa, mang lại khả năng phân tích đa chiều toàn diện về hiệu quả khai thác tài sản.

---

### B. Bộ truy vấn MDX phân tích chuyên sâu trên SSAS Cube

Các truy vấn MDX dưới đây được xây dựng nhằm khai thác tối đa năng lực của `Cube_Maintenance` phục vụ việc ra quyết định điều hành:

#### 1. Đánh giá hiệu quả kinh tế và thời gian ngừng hoạt động giữa 6 hãng xe (Make Efficiency)
*(Tệp: `SSAS_Logistics/Scripts/04_query_maintenance_mdx.mdx`)*

```mdx
SELECT 
    { 
        [Measures].[Total Maintenance Cost], 
        [Measures].[Maintenance Count],
        [Measures].[CM_Avg_Maintenance_Cost],
        [Measures].[CM_Avg_Downtime_Hours]
    } ON COLUMNS,
    NON EMPTY (
        [Dim_Truck].[Make].[Make].ALLMEMBERS
    ) ON ROWS
FROM [Cube_Maintenance]
WHERE ([Dim_Date].[Calendar Year].&[2023]);
```

**Kết quả & Insight:**
* **Hãng Volvo** đạt hiệu quả kinh tế cao nhất với chi phí bảo dưỡng bình quân thấp nhất toàn đội: **$\$1.864,26$/lượt** (tổng chi phí $\$1,88M$ qua $1.010$ lượt).
* **Hãng Mack** là dòng xe kém hiệu quả nhất về mặt bảo dưỡng với chi phí trung bình lên tới **$\$2.039,39$/lượt** (cao nhất đội xe), mặc dù số lượt vào xưởng ít hơn Freightliner.
* **Hãng Kenworth** nổi bật về khả năng quay vòng và giải phóng xe nhanh nhất với thời gian nằm xưởng chỉ **$24,03$ giờ/lượt**, giúp tối đa hóa giờ lăn bánh trên đường.

---

#### 2. Phân tích 7 chế độ hỏng hóc và tỷ trọng chi phí phụ tùng (Failure Mode Analysis)

```mdx
SELECT 
    { 
        [Measures].[Total Maintenance Cost], 
        [Measures].[Parts Cost],
        [Measures].[Labor Cost],
        [Measures].[CM_Parts_Cost_Ratio]
    } ON COLUMNS,
    NON EMPTY (
        [Dim_Maintenance_Profile].[Maintenance Type].[Maintenance Type].ALLMEMBERS
    ) ON ROWS
FROM [Cube_Maintenance];
```

**Kết quả & Insight:**
Phân tích kết quả làm sáng tỏ **Nghịch lý trong chi phí kỹ thuật**: Các đợt kiểm tra kỹ thuật (**Inspection**) diễn ra với tần suất dày đặc nhất ($864$ lượt) nhưng lại tiêu tốn ít ngân sách nhất ($\$440.000$, bình quân $\$510$/lượt) do cấu phần chủ yếu là tiền công thợ rà soát. Ngược lại, bảo dưỡng dự phòng định kỳ (**Preventive**) và sửa chữa động cơ (**Engine**) đòi hỏi thay mới đồng loạt các cụm linh kiện đắt tiền (gioăng, lọc, xilanh, dầu máy cao cấp), dẫn tới chi phí bình quân chạm đỉnh **$\$2.283$/lượt** với tỷ trọng phụ tùng chiếm tới **$82,4\%$**.

---

#### 3. Sử dụng hàm `TOPCOUNT` xác định các đầu xe gây thâm hụt ngân sách lớn nhất (Fleet Replacement)

```mdx
SELECT 
    { 
        [Measures].[Total Maintenance Cost], 
        [Measures].[Maintenance Count], 
        [Measures].[Downtime Hours],
        [Measures].[Odometer Reading]
    } ON COLUMNS,
    TOPCOUNT(
        [Dim_Truck].[Truck Fleet Hierarchy].[Unit Number].ALLMEMBERS,
        5,
        [Measures].[Total Maintenance Cost]
    ) ON ROWS
FROM [Cube_Maintenance];
```

**Kết quả & Insight:**
Hàm `TOPCOUNT` kết hợp cây phân cấp *Truck Fleet Hierarchy* cho phép lọc trực tiếp 5 đầu kéo có tổng chi phí cao nhất. Điển hình là trường hợp đầu kéo **Unit 2335 (hãng Peterbilt sản xuất năm 2018)**: trong giai đoạn 3 năm đã vào xưởng tới **$82$ lần**, tổng chi phí bảo dưỡng tích lũy lên tới **$\$180.322,10$** (tương đương giá mua một xe mới) và số ngày xe chết nằm xưởng lên tới **$94,4$ ngày**. Đây là bằng chứng định lượng thuyết phục để ra quyết định dừng vận hành và thanh lý.

---

#### 4. Phân tích xu hướng biến động theo cây phân cấp thời gian Calendar Hierarchy

```mdx
SELECT 
    { 
        [Measures].[Total Maintenance Cost], 
        [Measures].[Maintenance Count] 
    } ON COLUMNS,
    NON EMPTY (
        [Dim_Date].[Calendar Hierarchy].[Calendar Quarter].ALLMEMBERS
    ) ON ROWS
FROM [Cube_Maintenance];
```

**Kết quả & Insight:**
Dữ liệu theo các quý phản ánh quy luật **đường cong hình chữ U** của chu kỳ tài sản: Năm 2022 chi phí ở mức cao ($\$25.000$/tháng) do quá trình bảo dưỡng ban đầu khi tiếp nhận đội xe; năm 2023 chi phí hạ nhiệt và ổn định ($\$15.000 - \$18.000$/tháng); bước sang năm 2024 chi phí tăng vọt trở lại do linh kiện xe bước vào giai đoạn hao mòn tự nhiên, cảnh báo doanh nghiệp cần có quỹ dự phòng đại tu cho các năm tiếp theo.

---

### C. Bộ truy vấn T-SQL phân tích liên thông & định lượng TCO trên Data Warehouse
*(Tệp: `sql/15_query_maintenance_tco_tsql.sql`)*

Song song với khối đa chiều SSAS, các truy vấn T-SQL nâng cao được triển khai trên cơ sở dữ liệu `Logistics_DW` nhằm kiểm chứng số liệu liên tầng và thực thi các phân tích thống kê chuyên sâu.

#### 1. Truy vấn T-SQL liên thông `Fact_Trip` và `Fact_Maintenance` tính toán Fleet TCO

```sql
USE Logistics_DW;
GO

WITH FuelCostByTruck AS (
    -- Tổng hợp chi phí nhiên liệu từ Fact_Trip
    -- Giá dầu bình quân EIA Crawler thu thập là $3.85 / gallon
    SELECT 
        ft.truck_key,
        SUM(ft.actual_distance_miles) AS Total_Miles,
        SUM(ft.fuel_gallons_used) AS Total_Fuel_Gallons,
        SUM(ft.fuel_gallons_used * 3.85) AS Total_Fuel_Cost_USD
    FROM dbo.Fact_Trip ft
    WHERE ft.truck_key <> -1
    GROUP BY ft.truck_key
),
MaintenanceCostByTruck AS (
    -- Tổng hợp chi phí bảo dưỡng từ Fact_Maintenance
    SELECT 
        fm.truck_key,
        SUM(fm.total_maintenance_cost) AS Total_Maintenance_Cost_USD
    FROM dbo.Fact_Maintenance fm
    WHERE fm.truck_key <> -1
    GROUP BY fm.truck_key
)
SELECT 
    t.make AS Make,
    COUNT(DISTINCT t.truck_key) AS Number_Of_Trucks,
    ROUND(SUM(fc.Total_Miles), 0) AS Fleet_Miles,
    ROUND(SUM(fc.Total_Fuel_Cost_USD), 2) AS Total_Fuel_Cost_USD,
    ROUND(SUM(mc.Total_Maintenance_Cost_USD), 2) AS Total_Maintenance_Cost_USD,
    ROUND(SUM(fc.Total_Fuel_Cost_USD) + SUM(mc.Total_Maintenance_Cost_USD), 2) AS Fleet_TCO_USD,
    -- Chi phí sàn vận hành trên mỗi dặm lăn bánh ($/mile)
    ROUND((SUM(fc.Total_Fuel_Cost_USD) + SUM(mc.Total_Maintenance_Cost_USD)) 
          / NULLIF(SUM(fc.Total_Miles), 0), 4) AS Operating_Cost_Per_Mile
FROM dbo.Dim_Truck t
LEFT JOIN FuelCostByTruck fc ON t.truck_key = fc.truck_key
LEFT JOIN MaintenanceCostByTruck mc ON t.truck_key = mc.truck_key
WHERE t.make <> 'Unknown'
GROUP BY t.make
ORDER BY Fleet_TCO_USD DESC;
GO
```

**Bảng tổng hợp kết quả tính toán Tổng chi phí sở hữu đội xe (2022–2024):**

| Khoản mục phân tích TCO | Bảng dữ liệu nguồn | Giá trị tính toán thực tế | Tỷ trọng (%) |
| :--- | :--- | :---: | :---: |
| **Chi phí Nhiên liệu (Fuel Cost)** | `Fact_Trip` | **$\$36.621.584,20$** | **$76,16\%$** |
| **Chi phí Kỹ thuật - Bảo dưỡng** | `Fact_Maintenance` | **$\$11.461.146,56$** | **$23,84\%$** |
| **TỔNG CHI PHÍ SỞ HỮU (FLEET TCO)** | **Drill-Across liên thông** | **$\$48.082.730,76$** | **$100,00\%$** |
| **Tổng quãng đường vận chuyển** | `Fact_Trip` | **$61.299.145$ dặm** | - |
| **CHI PHÍ SÀN VẬN HÀNH BÌNH QUÂN** | **TCO / Fleet_Miles** | **$\$0,7844$ / dặm** | - |

> **Ứng dụng định giá cước vận tải:**  
> Chỉ số **$\$0,7844$ / dặm** chính là **Chi phí sàn vận hành (Operating Cost Floor)**. Trong mô hình vận tải, để một đơn hàng trong `Fact_Load` mang lại lợi nhuận thực tế, mức cước chào bán cho khách hàng bắt buộc phải bù đắp được mức chi phí sàn này cộng thêm chi phí khấu hao phương tiện và lương tài xế. Đây là đóng góp liên thông quan trọng nhất giữa phân hệ của Phúc An và các phân hệ Thương mại của nhóm.

---

#### 2. Ứng dụng Window Function `DENSE_RANK()` phân loại 3 nhóm xe phục vụ thanh lý và đại tu

```sql
WITH TruckMaintenanceSummary AS (
    SELECT 
        t.truck_key,
        t.unit_number,
        t.make,
        t.model_year,
        MAX(fm.odometer_reading) AS Latest_Odometer_Km,
        COUNT(fm.maintenance_event_key) AS Total_Visits,
        SUM(fm.total_maintenance_cost) AS Total_Maintenance_Cost_USD,
        SUM(fm.downtime_hours) AS Total_Downtime_Hours,
        ROUND(SUM(fm.downtime_hours) / 24.0, 1) AS Total_Downtime_Days,
        DENSE_RANK() OVER (ORDER BY SUM(fm.total_maintenance_cost) DESC) AS Cost_Rank
    FROM dbo.Fact_Maintenance fm
    JOIN dbo.Dim_Truck t ON fm.truck_key = t.truck_key
    WHERE t.unit_number <> 'Unknown'
    GROUP BY t.truck_key, t.unit_number, t.make, t.model_year
)
SELECT 
    Cost_Rank,
    unit_number AS Unit_Number,
    make AS Make,
    model_year AS Model_Year,
    Latest_Odometer_Km,
    Total_Visits,
    Total_Maintenance_Cost_USD,
    Total_Downtime_Days,
    CASE 
        WHEN Total_Maintenance_Cost_USD > 150000 OR Total_Downtime_Days > 80 THEN N'⚠️ THANH LÝ KHẨN CẤP'
        WHEN Total_Maintenance_Cost_USD > 120000 THEN N'⚡ THEO DÕI ĐẶC BIỆT / ĐẠI TU'
        ELSE N'BÌNH THƯỜNG'
    END AS Asset_Recommendation
FROM TruckMaintenanceSummary
WHERE Cost_Rank <= 10
ORDER BY Cost_Rank ASC;
GO
```

**Chính sách quản trị tài sản kiến nghị dựa trên kết quả phân loại:**
1. **Nhóm Thanh lý khẩn cấp (Chi phí $> \$150.000$ hoặc Downtime $> 80$ ngày):** Tiêu biểu là **Unit 2335** ($\$180.322$) và **Unit 1104** (nằm xưởng $88$ ngày). Các xe này đang chịu tình trạng "lỗ ròng kép": vừa ngốn kinh phí mua phụ tùng, vừa làm mất doanh thu do không thể nhận chuyến. Cần lập kế hoạch bán thanh lý ngay lập tức để thu hồi vốn phế liệu.
2. **Nhóm Đại tu / Chuyển vùng tác nghiệp (Chi phí $\$120.000 – \$150.000$):** Gồm các xe đời 2018–2019 có số km đã lăn bánh vượt ngưỡng $720.000$ km. Khuyến nghị chuyển các đầu kéo này từ các tuyến liên bang đường dài sang phục vụ các tuyến ngắn nội đô (*Short-Haul*) để giảm tải và hạn chế tối đa rủi ro chết máy dọc đường.
3. **Nhóm Khai thác tối đa:** Các dòng xe đời mới (2020–2022) của hãng Volvo và Kenworth có chi phí bảo trì ổn định, ưu tiên gán cho các tuyến cao tốc huyết mạch để tối ưu hóa hiệu suất đầu tư.

