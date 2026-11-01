-- ================================================================================
-- SCRIPT: sql/15_query_maintenance_tco_tsql.sql
-- MỤC ĐÍCH: Tập hợp các truy vấn T-SQL phân tích nghiệp vụ chuyên sâu 
--           cho Fact_Maintenance và tính toán Tổng chi phí sở hữu (Fleet TCO)
-- PHỤ TRÁCH: Nguyễn Phúc An
-- ================================================================================

USE Logistics_DW;
GO

-- --------------------------------------------------------------------------------
-- CÂU HỎI 1: SO SÁNH HIỆU QUẢ KINH TẾ GIỮA 6 HÃNG XE ĐẦU KÉO (MAKE EFFICIENCY)
-- Mục tiêu: Tìm ra hãng xe có chi phí bảo trì kinh tế nhất và downtime thấp nhất
-- --------------------------------------------------------------------------------
SELECT 
    t.make AS Truck_Make,
    COUNT(fm.maintenance_event_key) AS Total_Maintenance_Events,
    SUM(fm.total_maintenance_cost) AS Total_Cost_USD,
    ROUND(AVG(fm.total_maintenance_cost), 2) AS Avg_Cost_Per_Event_USD,
    ROUND(AVG(fm.downtime_hours), 2) AS Avg_Downtime_Hours,
    ROUND(SUM(fm.parts_cost) * 100.0 / NULLIF(SUM(fm.total_maintenance_cost), 0), 2) AS Parts_Cost_Pct,
    ROUND(SUM(fm.labor_cost) * 100.0 / NULLIF(SUM(fm.total_maintenance_cost), 0), 2) AS Labor_Cost_Pct
FROM dbo.Fact_Maintenance fm
JOIN dbo.Dim_Truck t ON fm.truck_key = t.truck_key
WHERE t.make <> 'Unknown'
GROUP BY t.make
ORDER BY Total_Cost_USD DESC;
GO


-- --------------------------------------------------------------------------------
-- CÂU HỎI 2: MA TRẬN 7 LOẠI BẢO DƯỠNG X MỨC ĐỘ KHẨN CẤP (FAILURE MODE ANALYSIS)
-- Mục tiêu: Nhận diện loại hỏng hóc thường xảy ra khẩn cấp (Emergency) và tốn kém nhất
-- --------------------------------------------------------------------------------
SELECT 
    mp.maintenance_type AS Maintenance_Type,
    mp.service_urgency AS Urgency_Level,
    COUNT(fm.maintenance_event_key) AS Event_Count,
    SUM(fm.total_maintenance_cost) AS Total_Cost_USD,
    ROUND(AVG(fm.total_maintenance_cost), 2) AS Avg_Cost_USD,
    ROUND(AVG(fm.downtime_hours), 2) AS Avg_Downtime_Hours,
    SUM(fm.parts_cost) AS Total_Parts_USD,
    SUM(fm.labor_cost) AS Total_Labor_USD
FROM dbo.Fact_Maintenance fm
JOIN dbo.Dim_Maintenance_Profile mp ON fm.maintenance_profile_key = mp.maintenance_profile_key
WHERE mp.maintenance_type <> 'Unknown'
GROUP BY mp.maintenance_type, mp.service_urgency
ORDER BY mp.maintenance_type, Total_Cost_USD DESC;
GO


-- --------------------------------------------------------------------------------
-- CÂU HỎI 3: TOP 10 ĐẦU XE CÁ BIỆT TỐN KÉM NHẤT CẦN ĐỀ XUẤT THANH LÝ
-- Mục tiêu: Áp dụng Window Function DENSE_RANK() để lập danh sách đen các xe quá tải chi phí
-- --------------------------------------------------------------------------------
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


-- --------------------------------------------------------------------------------
-- CÂU HỎI 4: FLEET TCO DRILL-ACROSS (KẾT HỢP FACT_TRIP + FACT_MAINTENANCE)
-- Mục tiêu: Tính tổng chi phí sở hữu đội xe và xác định Chi phí sàn vận hành ($/dặm)
-- --------------------------------------------------------------------------------
WITH FuelCostByTruck AS (
    -- Tổng hợp chi phí nhiên liệu từ Fact_Trip
    SELECT 
        ft.truck_key,
        SUM(ft.actual_distance_miles) AS Total_Miles,
        SUM(ft.fuel_gallons_used) AS Total_Fuel_Gallons,
        -- Đơn giá diesel trung bình thu thập từ EIA Crawler là $3.85 / gallon
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
    -- Chi phí sàn vận hành trên mỗi dặm ($/mile)
    ROUND((SUM(fc.Total_Fuel_Cost_USD) + SUM(mc.Total_Maintenance_Cost_USD)) / NULLIF(SUM(fc.Total_Miles), 0), 4) AS Operating_Cost_Per_Mile
FROM dbo.Dim_Truck t
LEFT JOIN FuelCostByTruck fc ON t.truck_key = fc.truck_key
LEFT JOIN MaintenanceCostByTruck mc ON t.truck_key = mc.truck_key
WHERE t.make <> 'Unknown'
GROUP BY t.make
ORDER BY Fleet_TCO_USD DESC;
GO


-- --------------------------------------------------------------------------------
-- CÂU HỎI 5: XU HƯỚNG VÒNG ĐỜI BẢO DƯỠNG THEO THỜI GIAN (HÌNH CHỮ U)
-- --------------------------------------------------------------------------------
SELECT 
    d.calendar_year AS Calendar_Year,
    d.calendar_quarter AS Calendar_Quarter,
    COUNT(fm.maintenance_event_key) AS Event_Count,
    SUM(fm.total_maintenance_cost) AS Total_Cost_USD,
    ROUND(AVG(fm.total_maintenance_cost), 2) AS Avg_Cost_Per_Event,
    SUM(fm.downtime_hours) AS Total_Downtime_Hours
FROM dbo.Fact_Maintenance fm
JOIN dbo.Dim_Date d ON fm.maintenance_date_key = d.date_key
GROUP BY d.calendar_year, d.calendar_quarter
ORDER BY d.calendar_year, d.calendar_quarter;
GO

