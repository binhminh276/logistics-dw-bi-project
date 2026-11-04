-- ================================================================================
-- SCRIPT: sql/15_query_maintenance_tco_tsql.sql
-- MỤC ĐÍCH: Tập hợp đúng 3 truy vấn T-SQL phân tích nghiệp vụ chuyên sâu 
--           cho Fact_Maintenance và tính toán Tổng chi phí sở hữu (Fleet TCO)
--           Đồng bộ 100% với Mục 3.3.2.3 trong Báo cáo Đồ án
-- PHỤ TRÁCH: Nguyễn Phúc An
-- ================================================================================
USE Logistics_DW;
GO -- ================================================================================
    -- TRUY VẤN 1: PHÂN TÍCH LIÊN THÔNG FACT-TO-FACT TÍNH FLEET TCO & CHI PHÍ SÀN/DẶM
    -- Kỹ thuật: Common Table Expressions (CTE) kết hợp Fact_Trip & Fact_Maintenance qua Dim_Truck
    -- Nghiệp vụ: Trực tiếp định lượng Tổng TCO toàn đội và Ngưỡng sàn chi phí vận hành biến đổi ($ / dặm)
    -- ================================================================================
    WITH Fleet_Fuel AS (
        -- 1. Tổng hợp chi phí nhiên liệu hành trình từ Fact_Trip
        SELECT ft.truck_key,
            SUM(ft.actual_distance_miles) AS Total_Miles,
            SUM(ft.fuel_gallons_used * 3.85) AS Total_Fuel_Cost_USD
        FROM dbo.Fact_Trip ft
        WHERE ft.truck_key <> -1
        GROUP BY ft.truck_key
    ),
    Fleet_Maint AS (
        -- 2. Tổng hợp chi phí bảo dưỡng kỹ thuật từ Fact_Maintenance
        SELECT fm.truck_key,
            SUM(fm.total_maintenance_cost) AS Total_Maintenance_Cost_USD
        FROM dbo.Fact_Maintenance fm
        WHERE fm.truck_key <> -1
        GROUP BY fm.truck_key
    ),
    Truck_TCO AS (
        -- 3. Hợp nhất hai quy trình nghiệp vụ độc lập qua Dim_Truck
        SELECT t.truck_id,
            ISNULL(f.Total_Miles, 0) AS Total_Miles,
            ISNULL(f.Total_Fuel_Cost_USD, 0) AS Total_Fuel_Cost_USD,
            ISNULL(m.Total_Maintenance_Cost_USD, 0) AS Total_Maintenance_Cost_USD,
            (
                ISNULL(f.Total_Fuel_Cost_USD, 0) + ISNULL(m.Total_Maintenance_Cost_USD, 0)
            ) AS Fleet_TCO_USD
        FROM dbo.Dim_Truck t
            LEFT JOIN Fleet_Fuel f ON t.truck_key = f.truck_key
            LEFT JOIN Fleet_Maint m ON t.truck_key = m.truck_key
        WHERE t.truck_key <> -1
    ) -- 4. Trực tiếp tính toán các chỉ số kinh tế - kỹ thuật toàn đội xe
SELECT COUNT(DISTINCT truck_id) AS Total_Trucks,
    SUM(Total_Miles) AS Total_Fleet_Miles,
    ROUND(SUM(Total_Fuel_Cost_USD), 2) AS Total_Fuel_Cost_USD,
    ROUND(
        SUM(Total_Fuel_Cost_USD) * 100.0 / SUM(Fleet_TCO_USD),
        2
    ) AS Fuel_Cost_Pct,
    ROUND(SUM(Total_Maintenance_Cost_USD), 2) AS Total_Maintenance_Cost_USD,
    ROUND(
        SUM(Total_Maintenance_Cost_USD) * 100.0 / SUM(Fleet_TCO_USD),
        2
    ) AS Maintenance_Cost_Pct,
    ROUND(SUM(Fleet_TCO_USD), 2) AS Total_Fleet_TCO_USD,
    ROUND(
        SUM(Fleet_TCO_USD) / NULLIF(SUM(Total_Miles), 0),
        4
    ) AS Operating_Cost_Per_Mile
FROM Truck_TCO;
GO -- ================================================================================
    -- TRUY VẤN 2: XẾP HẠNG CHI PHÍ & TỰ ĐỘNG PHÂN LOẠI CHÍNH SÁCH QUẢN TRỊ TÀI SẢN
    -- Kỹ thuật: Window Function DENSE_RANK() kết hợp CASE WHEN phân loại 3 tầng chính sách
    -- Nghiệp vụ: Cô lập Top đầu xe cá biệt vượt ngưỡng chịu đựng ngân sách (Điển hình Unit 2335)
    -- ================================================================================
    WITH TruckMaintenanceSummary AS (
        SELECT t.truck_key,
            t.unit_number,
            t.make,
            t.model_year,
            MAX(fm.odometer_reading) AS Latest_Odometer_Km,
            COUNT(*) AS Total_Visits,
            SUM(fm.total_maintenance_cost) AS Total_Maintenance_Cost_USD,
            SUM(fm.downtime_hours) AS Total_Downtime_Hours,
            ROUND(SUM(fm.downtime_hours) / 24.0, 1) AS Total_Downtime_Days,
            DENSE_RANK() OVER (
                ORDER BY SUM(fm.total_maintenance_cost) DESC
            ) AS Cost_Rank
        FROM dbo.Fact_Maintenance fm
            JOIN dbo.Dim_Truck t ON fm.truck_key = t.truck_key
        WHERE t.truck_key <> -1
        GROUP BY t.truck_key,
            t.unit_number,
            t.make,
            t.model_year
    )
SELECT Cost_Rank,
    unit_number AS Unit_Number,
    make AS Make,
    model_year AS Model_Year,
    Latest_Odometer_Km,
    Total_Visits,
    Total_Maintenance_Cost_USD,
    Total_Downtime_Hours,
    Total_Downtime_Days,
    CASE
        WHEN Total_Maintenance_Cost_USD >= 70000
        OR Total_Downtime_Hours >= 750 THEN N'Nhóm 1: Thanh lý khẩn cấp (Urgent Salvage)'
        WHEN Total_Maintenance_Cost_USD >= 50000
        OR Latest_Odometer_Km >= 700000 THEN N'Nhóm 2: Đại tu & Chuyển tuyến ngắn (Overhaul)'
        ELSE N'Nhóm 3: Khai thác tuyến dài (Max Utilization)'
    END AS Fleet_Lifecycle_Policy
FROM TruckMaintenanceSummary
ORDER BY Cost_Rank ASC;
Go