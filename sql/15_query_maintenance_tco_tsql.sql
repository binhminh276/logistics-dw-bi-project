-- ================================================================================
-- SCRIPT: sql/15_query_maintenance_tco_tsql.sql
-- MỤC ĐÍCH: Tập hợp 3 truy vấn T-SQL phân tích nghiệp vụ chuyên sâu 
--           cho Fact_Maintenance và tính toán Tổng chi phí sở hữu (Fleet TCO)
--           (Tương ứng với Mục 3.3.2.4 / 3.2.2.4 trong Báo cáo Đồ án)
-- PHỤ TRÁCH: Nguyễn Phúc An
-- ================================================================================

USE Logistics_DW;
GO

-- ================================================================================
-- TRUY VẤN 1: PHÂN TÍCH LIÊN THÔNG FACT-TO-FACT TÍNH FLEET TCO & CHI PHÍ SÀN/DẶM
-- Kỹ thuật: Common Table Expressions (CTE) kết hợp Fact_Trip & Fact_Maintenance qua Dim_Truck
-- Nghiệp vụ: Xác định ngưỡng chi phí tối thiểu ($/mile) để duy trì hoạt động đội xe
-- ================================================================================
WITH FuelCostByTruck AS (
    -- 1. Tổng hợp chi phí nhiên liệu hành trình từ Fact_Trip
    SELECT 
        ft.truck_key,
        SUM(ft.actual_distance_miles) AS Total_Miles,
        SUM(ft.fuel_gallons_used) AS Total_Fuel_Gallons,
        -- Đơn giá diesel trung bình thu thập từ crawler EIA 2022-2024 là $3.85 / gallon
        SUM(ft.fuel_gallons_used * 3.85) AS Total_Fuel_Cost_USD
    FROM dbo.Fact_Trip ft
    WHERE ft.truck_key <> -1
    GROUP BY ft.truck_key
),
MaintenanceCostByTruck AS (
    -- 2. Tổng hợp chi phí bảo dưỡng kỹ thuật từ Fact_Maintenance
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
    -- Chi phí sàn vận hành trên mỗi dặm ($/mile)
    ROUND((SUM(fc.Total_Fuel_Cost_USD) + SUM(mc.Total_Maintenance_Cost_USD)) / NULLIF(SUM(fc.Total_Miles), 0), 4) AS Operating_Cost_Per_Mile
FROM dbo.Dim_Truck t
LEFT JOIN FuelCostByTruck fc ON t.truck_key = fc.truck_key
LEFT JOIN MaintenanceCostByTruck mc ON t.truck_key = mc.truck_key
WHERE t.make <> 'Unknown'
GROUP BY t.make
ORDER BY Fleet_TCO_USD DESC;
GO


-- ================================================================================
-- TRUY VẤN 2: XẾP HẠNG CHI PHÍ & TỰ ĐỘNG PHÂN LOẠI CHÍNH SÁCH QUẢN TRỊ TÀI SẢN
-- Kỹ thuật: Window Function DENSE_RANK() kết hợp CASE WHEN phân loại 3 tầng chính sách
-- Nghiệp vụ: Cô lập Top đầu xe cá biệt vượt ngưỡng chịu đựng ngân sách (Điển hình Unit 2335)
-- ================================================================================
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
        WHEN Total_Maintenance_Cost_USD > 120000 THEN N'⚡ THEO DÕI ĐẶC BIỆT'
        ELSE N'BÌNH THƯỜNG'
    END AS Asset_Recommendation
FROM TruckMaintenanceSummary
WHERE Cost_Rank <= 10
ORDER BY Cost_Rank ASC;
GO


-- ================================================================================
-- TRUY VẤN 3: KIỂM TOÁN ĐỐI SOÁT TÍNH TOÀN VẸN DỮ LIỆU ĐA CHIỀU (CROSS-VALIDATION)
-- Kỹ thuật: Phép tổng hợp SQL trên Fact_Maintenance đối chiếu trực tiếp với SSAS Cube
-- Nghiệp vụ: Chứng minh độ sai lệch bằng 0 giữa Relational DWH và Semantic OLAP Cube
-- ================================================================================
SELECT 
    'Fact_Maintenance Reconciliation' AS Audit_Scope,
    COUNT(fm.maintenance_event_key) AS Total_Events_Count,          -- Kỳ vọng: 5,840 lượt
    SUM(fm.total_maintenance_cost) AS Total_Maintenance_Cost_USD,   -- Kỳ vọng: $11,461,146.00
    SUM(fm.parts_cost) AS Total_Parts_Cost_USD,                     -- Kỳ vọng: $8,899,286.00
    SUM(fm.labor_cost) AS Total_Labor_Cost_USD,                     -- Kỳ vọng: $2,561,860.00
    SUM(fm.downtime_hours) AS Total_Downtime_Hours,                 -- Kỳ vọng: 144,461.00 giờ
    SUM(fm.labor_hours) AS Total_Labor_Hours,                       -- Kỳ vọng: 24,453.00 giờ
    ROUND(AVG(fm.total_maintenance_cost), 2) AS Avg_Cost_Per_Event, -- Kỳ vọng: $1,962.53
    ROUND(AVG(fm.downtime_hours), 2) AS Avg_Downtime_Per_Event      -- Kỳ vọng: 24.74 giờ
FROM dbo.Fact_Maintenance fm;
GO
