/*
================================================================================
SCRIPT DEMO: sql/17_demo_simulate_incremental_1000_rows.sql
MỤC ĐÍCH: Giả lập dữ liệu mới phát sinh (Đơn hàng & Chuyến xe) trên CSDL OLTP
          cho THÁNG 8, 9, 10 / 2023 (Tổng cộng 7.068 giao dịch mới)
          phục vụ KỊCH BẢN DEMO NẠP TĂNG TRƯỞNG (Incremental Load & CDC) trước Hội đồng.
NGUỒN DỮ LIỆU: Đọc trực tiếp từ file CSV gốc:
               - data/raw/loads.csv
               - data/raw/trips.csv
               Bằng kỹ thuật BULK INSERT siêu tốc vào bảng tạm, tự động làm sạch
               và nạp an toàn vào CSDL Logistics_OLTP.
DẢI THỜI GIAN:
   - Mặc định: 01/08/2023 -> 31/10/2023 (Đúng 3 tháng: 7.068 đơn hàng & 7.068 chuyến xe)
   - Tùy chọn: Có thể đổi @StartDate = '2023-07-03' để nạp liền mạch toàn bộ
               từ sau mốc 02/07/2023 đến hết 31/10/2023 (9.356 đơn & chuyến).
CÁCH DÙNG KHI DEMO:
  1. Chạy BƯỚC 1 để xem số dòng hiện tại ở OLTP và DWH (đang dừng ở mốc 02/07/2023: 42.715 dòng).
  2. Chạy BƯỚC 2 để nạp dữ liệu Tháng 8, 9, 10/2023 vào Logistics_OLTP (OLTP tăng thêm 7.068 dòng).
  3. Kích hoạt Job SQL Server Agent: Logistics_Daily_ETL_Orchestration (hoặc chạy Master_Orchestrator.dtsx).
  4. Chạy BƯỚC 3 để chứng minh DWH và Audit Log đã tự động bắt biến động và tăng thêm đúng 7.068 dòng!
  5. (Tùy chọn) Chạy BƯỚC 4 để xóa sạch trả lại trạng thái ban đầu nếu muốn diễn tập lại.
================================================================================
*/

USE [Logistics_OLTP];
GO

PRINT '======================================================================';
PRINT 'BƯỚC 1: KIỂM TRA SỐ DÒNG HIỆN TẠI TRƯỚC KHI GIẢ LẬP PHÁT SINH MỚI';
PRINT '======================================================================';

SELECT 'OLTP.dbo.loads' AS TableName, COUNT(*) AS CurrentRowCount, MIN(load_date) AS MinDate, MAX(load_date) AS MaxDate FROM Logistics_OLTP.dbo.loads
UNION ALL
SELECT 'OLTP.dbo.trips' AS TableName, COUNT(*) AS CurrentRowCount, MIN(dispatch_date) AS MinDate, MAX(dispatch_date) AS MaxDate FROM Logistics_OLTP.dbo.trips
UNION ALL
SELECT 'DWH.dbo.Fact_Load' AS TableName, COUNT(*) AS CurrentRowCount, NULL, NULL FROM Logistics_DW.dbo.Fact_Load
UNION ALL
SELECT 'DWH.dbo.Fact_Trip' AS TableName, COUNT(*) AS CurrentRowCount, NULL, NULL FROM Logistics_DW.dbo.Fact_Trip;
GO

PRINT '======================================================================';
PRINT 'BƯỚC 2: TIẾN HÀNH GIẢ LẬP NẠP DỮ LIỆU THÁNG 8, 9, 10 / 2023 VÀO OLTP';
PRINT '======================================================================';

-- Cấu hình dải thời gian nạp tăng trưởng
DECLARE @StartDate DATE = '2023-08-01'; -- Mặc định: Tháng 8, 9, 10/2023 (Có thể đổi thành '2023-07-03' để nối tiếp liền mạch)
DECLARE @EndDate   DATE = '2023-10-31';

-- Đường dẫn tuyệt đối tới file CSV gốc
DECLARE @CsvLoadsPath NVARCHAR(500) = N'D:\Kho\Project\data\raw\loads.csv';
DECLARE @CsvTripsPath NVARCHAR(500) = N'D:\Kho\Project\data\raw\trips.csv';

-- Kiểm tra xem dữ liệu trong dải thời gian này đã có trong OLTP chưa
IF EXISTS (SELECT 1 FROM dbo.loads WHERE load_date >= @StartDate AND load_date <= @EndDate)
BEGIN
    PRINT '-> CẢNH BÁO: Dữ liệu giai đoạn ' + CONVERT(VARCHAR(10), @StartDate) + ' đến ' + CONVERT(VARCHAR(10), @EndDate) + ' đã tồn tại trong OLTP!';
    PRINT '-> Nếu muốn nạp lại từ đầu, vui lòng chạy BƯỚC 4 ở cuối file để Reset.';
END
ELSE
BEGIN
    PRINT '-> [1/4] Đang tạo bảng tạm và BULK INSERT từ file loads.csv...';
    
    IF OBJECT_ID('tempdb..#stg_loads') IS NOT NULL DROP TABLE #stg_loads;
    CREATE TABLE #stg_loads (
        load_id NVARCHAR(50), customer_id NVARCHAR(50), route_id NVARCHAR(50),
        load_date DATE, load_type NVARCHAR(50), weight_lbs INT, pieces INT,
        revenue DECIMAL(18,2), fuel_surcharge DECIMAL(18,2), accessorial_charges DECIMAL(18,2),
        load_status NVARCHAR(50), booking_type NVARCHAR(50)
    );

    BULK INSERT #stg_loads
    FROM 'D:\Kho\Project\data\raw\loads.csv'
    WITH (
        FIRSTROW = 2,
        FIELDTERMINATOR = ',',
        ROWTERMINATOR = '0x0a',
        CODEPAGE = '65001',
        KEEPNULLS
    );

    PRINT '-> [2/4] Đang tạo bảng tạm và BULK INSERT từ file trips.csv...';

    IF OBJECT_ID('tempdb..#stg_trips') IS NOT NULL DROP TABLE #stg_trips;
    CREATE TABLE #stg_trips (
        trip_id NVARCHAR(50), load_id NVARCHAR(50), driver_id NVARCHAR(50),
        truck_id NVARCHAR(50), trailer_id NVARCHAR(50), dispatch_date DATE,
        actual_distance_miles INT, actual_duration_hours DECIMAL(10,2),
        fuel_gallons_used DECIMAL(10,2), average_mpg DECIMAL(10,2),
        idle_time_hours DECIMAL(10,2), trip_status NVARCHAR(50)
    );

    BULK INSERT #stg_trips
    FROM 'D:\Kho\Project\data\raw\trips.csv'
    WITH (
        FIRSTROW = 2,
        FIELDTERMINATOR = ',',
        ROWTERMINATOR = '0x0a',
        CODEPAGE = '65001',
        KEEPNULLS
    );

    BEGIN TRANSACTION;

    PRINT '-> [3/4] Đang nạp đơn hàng Tháng 8, 9, 10/2023 vào Logistics_OLTP.dbo.loads...';
    INSERT INTO dbo.loads (
        load_id, customer_id, route_id, load_date, load_type, 
        weight_lbs, pieces, revenue, fuel_surcharge, accessorial_charges, 
        load_status, booking_type
    )
    SELECT 
        load_id, customer_id, route_id, load_date, load_type, 
        weight_lbs, pieces, revenue, fuel_surcharge, accessorial_charges, 
        load_status, booking_type
    FROM #stg_loads
    WHERE load_date >= @StartDate AND load_date <= @EndDate
      AND NOT EXISTS (SELECT 1 FROM dbo.loads l WHERE l.load_id = #stg_loads.load_id);

    DECLARE @LoadsInserted INT = @@ROWCOUNT;

    PRINT '-> [4/4] Đang nạp chuyến xe Tháng 8, 9, 10/2023 vào Logistics_OLTP.dbo.trips...';
    INSERT INTO dbo.trips (
        trip_id, load_id, driver_id, truck_id, trailer_id, dispatch_date,
        actual_distance_miles, actual_duration_hours, fuel_gallons_used, 
        average_mpg, idle_time_hours, trip_status
    )
    SELECT 
        trip_id, load_id, 
        NULLIF(driver_id, ''),
        NULLIF(truck_id, ''),
        NULLIF(trailer_id, ''),
        dispatch_date,
        actual_distance_miles, actual_duration_hours, fuel_gallons_used, 
        average_mpg, idle_time_hours, trip_status
    FROM #stg_trips
    WHERE dispatch_date >= @StartDate AND dispatch_date <= @EndDate
      AND NOT EXISTS (SELECT 1 FROM dbo.trips t WHERE t.trip_id = #stg_trips.trip_id);

    DECLARE @TripsInserted INT = @@ROWCOUNT;

    COMMIT TRANSACTION;

    DROP TABLE #stg_loads;
    DROP TABLE #stg_trips;

    PRINT '----------------------------------------------------------------------';
    PRINT '-> [THÀNH CÔNG] ĐÃ NẠP TĂNG TRƯỞNG VÀO HỆ THỐNG OLTP:';
    PRINT '   + Đơn hàng mới (loads): ' + CAST(@LoadsInserted AS VARCHAR(10)) + ' dòng';
    PRINT '   + Chuyến xe mới (trips): ' + CAST(@TripsInserted AS VARCHAR(10)) + ' dòng';
    PRINT '-> Cơ chế CDC (Change Data Capture) của SQL Server đã tự động ghi nhận các biến động này.';
    PRINT '-> BÂY GIỜ BẠN CÓ THỂ KÍCH HOẠT JOB SQL AGENT ĐỂ PIPELINE TỰ ĐỘNG NẠP TĂNG CƯỜNG VÀO DWH.';
    PRINT '----------------------------------------------------------------------';
END
GO

PRINT '======================================================================';
PRINT 'BƯỚC 3: CÂU LỆNH KIỂM TRA ĐỐI SOÁT SAU KHI CHẠY PIPELINE ETL';
PRINT '======================================================================';
/*
-- HƯỚNG DẪN: Sau khi bạn kích hoạt Job SQL Server Agent (Logistics_Daily_ETL_Orchestration)
-- hoặc chạy package Master_Orchestrator.dtsx trên Visual Studio, mở tab này chạy câu dưới đây:
-- Kết quả Fact_Load và Fact_Trip trong DWH sẽ tự động TĂNG THÊM ĐÚNG SỐ DÒNG ĐÃ NẠP!

SELECT 'OLTP.dbo.loads' AS TableName, COUNT(*) AS CurrentRowCount, MAX(load_date) AS MaxDate FROM Logistics_OLTP.dbo.loads
UNION ALL
SELECT 'OLTP.dbo.trips' AS TableName, COUNT(*) AS CurrentRowCount, MAX(dispatch_date) AS MaxDate FROM Logistics_OLTP.dbo.trips
UNION ALL
SELECT 'DWH.dbo.Fact_Load' AS TableName, COUNT(*) AS CurrentRowCount, NULL FROM Logistics_DW.dbo.Fact_Load
UNION ALL
SELECT 'DWH.dbo.Fact_Trip' AS TableName, COUNT(*) AS CurrentRowCount, NULL FROM Logistics_DW.dbo.Fact_Trip
UNION ALL
SELECT 'Audit.Package_Log (Fact_Load lần chạy mới nhất)', inserted_row_count, NULL FROM Logistics_Staging.audit.Package_Log 
WHERE package_name = 'Fact_Load.dtsx' AND package_log_id = (SELECT MAX(package_log_id) FROM Logistics_Staging.audit.Package_Log WHERE package_name = 'Fact_Load.dtsx');
*/
GO

PRINT '======================================================================';
PRINT 'BƯỚC 4: (TÙY CHỌN) LỆNH DỌN DẸP / RESET ĐỂ DIỄN TẬP DEMO NHIỀU LẦN';
PRINT '======================================================================';
/*
-- Nếu muốn quay lại trạng thái ban đầu để diễn tập lại (chỉ xóa dữ liệu từ tháng 8/2023 trở đi):
BEGIN TRANSACTION;
DELETE FROM Logistics_OLTP.dbo.trips WHERE dispatch_date >= '2023-08-01';
DELETE FROM Logistics_OLTP.dbo.loads WHERE load_date >= '2023-08-01';
DELETE FROM Logistics_DW.dbo.Fact_Trip WHERE dispatch_date_key >= 20230801;
DELETE FROM Logistics_DW.dbo.Fact_Load WHERE load_date_key >= 20230801;
COMMIT TRANSACTION;
PRINT '-> Đã Reset sạch dữ liệu phát sinh từ tháng 8/2023 trên cả OLTP và DWH!';
*/
GO
