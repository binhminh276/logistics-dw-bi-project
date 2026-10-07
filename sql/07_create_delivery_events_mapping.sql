/*
================================================================================
ĐƯỜNG DẪN ĐÍCH: sql/07_create_delivery_events_mapping.sql
MỤC ĐÍCH: Xử lý triệt để lỗi xung đột địa lý giữa delivery_events.csv và facilities.csv.
          1. Tạo bảng từ điển cơ sở ưu tiên (Ref_City_Facility_Mapping) và nạp dữ liệu thật.
          2. Tạo bảng ánh xạ sự kiện giao nhận chuẩn hóa (Stg_Delivery_Events_Mapping).
          3. Cung cấp Stored Procedure và lệnh INSERT THẬT toàn bộ 170.820 sự kiện
             (tự động kích hoạt khi Stg_External_Delivery_Events đã nạp dữ liệu).
          4. Toàn bộ kiểu chuỗi ký tự sử dụng NVARCHAR để hỗ trợ Unicode hoàn toàn.
NGÀY CẬP NHẬT: 2026-10-07
TÁC GIẢ: Phúc An (Senior Data Engineer)
CÁCH CHẠY:
  1. Mở trong SSMS (kết nối instance localhost).
  2. Hoặc chạy qua PowerShell / Command Prompt:
     sqlcmd -E -S localhost -i sql/07_create_delivery_events_mapping.sql
================================================================================
*/

SET IMPLICIT_TRANSACTIONS OFF;
WHILE @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO

USE [Logistics_Staging];
GO

PRINT '======================================================================';
PRINT 'BƯỚC 1: TẠO BẢNG TỪ ĐIỂN CƠ SỞ ƯU TIÊN THEO ĐỊA BÀN (CITY, STATE)';
PRINT '======================================================================';

-- Bảng lưu trữ cơ sở chuẩn được chọn duy nhất cho từng (city, state)
IF OBJECT_ID('dbo.Ref_City_Facility_Mapping', 'U') IS NOT NULL
    DROP TABLE dbo.Ref_City_Facility_Mapping;
GO

CREATE TABLE dbo.Ref_City_Facility_Mapping (
    city NVARCHAR(100) NOT NULL,
    state NVARCHAR(20) NOT NULL,
    selected_facility_id NVARCHAR(50) NOT NULL,
    selected_facility_name NVARCHAR(150),
    selected_facility_type NVARCHAR(50),
    total_facilities_in_city INT,
    selection_rule NVARCHAR(255),
    CONSTRAINT PK_Ref_City_Facility_Mapping PRIMARY KEY (city, state)
);
GO

-- Nạp danh mục 21 thành phố có cơ sở từ 50 cơ sở gốc
-- Áp dụng giải thuật ưu tiên tất định:
-- 1. Ưu tiên loại hình: Terminal (1) > Distribution Center (2) > Cross-Dock (3) > Warehouse (4)
-- 2. Nếu cùng loại hình: Chọn facility_id nhỏ nhất MIN(facility_id)
WITH RankedFacilities AS (
    SELECT 
        TRIM(city) AS city,
        TRIM(state) AS state,
        facility_id,
        facility_name,
        facility_type,
        COUNT(*) OVER (PARTITION BY TRIM(city), TRIM(state)) AS total_fac,
        ROW_NUMBER() OVER (
            PARTITION BY TRIM(city), TRIM(state) 
            ORDER BY 
                CASE TRIM(facility_type)
                    WHEN 'Terminal' THEN 1
                    WHEN 'Distribution Center' THEN 2
                    WHEN 'Cross-Dock' THEN 3
                    WHEN 'Warehouse' THEN 4
                    ELSE 5
                END ASC,
                facility_id ASC
        ) AS rn
    FROM (
        -- Đọc trực tiếp danh mục từ CSDL OLTP hoặc bảng Stg_External_Facilities đã nạp
        SELECT facility_id, facility_name, facility_type, city, state 
        FROM Logistics_OLTP.dbo.facilities
    ) f
)
INSERT INTO dbo.Ref_City_Facility_Mapping (
    city, state, selected_facility_id, selected_facility_name, 
    selected_facility_type, total_facilities_in_city, selection_rule
)
SELECT 
    city,
    state,
    facility_id,
    facility_name,
    facility_type,
    total_fac,
    CASE 
        WHEN total_fac = 1 THEN N'Cơ sở duy nhất tại thành phố'
        ELSE N'Ưu tiên loại hình (Terminal > DC > Cross-Dock > Warehouse) và MIN(facility_id)'
    END
FROM RankedFacilities
WHERE rn = 1;
GO

PRINT '-> Đã nạp từ điển cơ sở chuẩn cho ' + CAST(@@ROWCOUNT AS NVARCHAR(10)) + ' thành phố.';
GO

PRINT '======================================================================';
PRINT 'BƯỚC 2: TẠO BẢNG ÁNH XẠ SỰ KIỆN GIAO NHẬN CHUẨN HÓA ĐỊA LÝ';
PRINT '======================================================================';

IF OBJECT_ID('dbo.Stg_Delivery_Events_Mapping', 'U') IS NOT NULL
    DROP TABLE dbo.Stg_Delivery_Events_Mapping;
GO

CREATE TABLE dbo.Stg_Delivery_Events_Mapping (
    event_id NVARCHAR(50) NOT NULL,
    load_id NVARCHAR(50) NOT NULL,
    trip_id NVARCHAR(50),
    event_type NVARCHAR(20) NOT NULL,
    location_city NVARCHAR(100) NOT NULL,
    location_state NVARCHAR(20) NOT NULL,
    original_facility_id NVARCHAR(50) NOT NULL,
    corrected_facility_id NVARCHAR(50) NULL,
    is_corrected BIT NOT NULL,
    correction_status NVARCHAR(50) NOT NULL,
    correction_reason NVARCHAR(255),
    created_at DATETIME DEFAULT GETDATE(),
    CONSTRAINT PK_Stg_Delivery_Events_Mapping PRIMARY KEY (event_id)
);
GO

PRINT '======================================================================';
PRINT 'BƯỚC 3: THIẾT LẬP THỦ TỤC NẠP DỮ LIỆU THẬT CHO STG_DELIVERY_EVENTS_MAPPING';
PRINT '======================================================================';
GO

CREATE OR ALTER PROCEDURE dbo.usp_Populate_Delivery_Events_Mapping
AS
BEGIN
    SET NOCOUNT ON;
    
    PRINT '-> Bắt đầu nạp bảng Stg_Delivery_Events_Mapping từ Stg_External_Delivery_Events...';
    
    TRUNCATE TABLE dbo.Stg_Delivery_Events_Mapping;
    
    INSERT INTO dbo.Stg_Delivery_Events_Mapping (
        event_id, load_id, trip_id, event_type,
        location_city, location_state, original_facility_id,
        corrected_facility_id, is_corrected, correction_status, correction_reason
    )
    SELECT 
        e.event_id,
        e.load_id,
        e.trip_id,
        e.event_type,
        e.location_city,
        e.location_state,
        e.facility_id AS original_facility_id,
        m.selected_facility_id AS corrected_facility_id,
        CASE 
            WHEN m.selected_facility_id IS NULL THEN 1
            WHEN TRIM(e.facility_id) <> TRIM(m.selected_facility_id) THEN 1
            ELSE 0
        END AS is_corrected,
        CASE 
            WHEN m.selected_facility_id IS NULL THEN N'NO_FACILITY_FOUND (Gán Key -1)'
            WHEN TRIM(e.facility_id) <> TRIM(m.selected_facility_id) THEN N'CORRECTED_MATCH (Đã sửa theo địa bàn)'
            ELSE N'EXACT_MATCH (Khớp ngẫu nhiên)'
        END AS correction_status,
        ISNULL(m.selection_rule, N'Thành phố không có cơ sở trong facilities.csv -> Gán Key -1 vào Fact') AS correction_reason
    FROM dbo.Stg_External_Delivery_Events e
    LEFT JOIN dbo.Ref_City_Facility_Mapping m 
        ON TRIM(UPPER(e.location_city)) = TRIM(UPPER(m.city))
       AND TRIM(UPPER(e.location_state)) = TRIM(UPPER(m.state));
       
    PRINT '-> Hoàn tất nạp ' + CAST(@@ROWCOUNT AS NVARCHAR(10)) + ' dòng vào Stg_Delivery_Events_Mapping.';
END;
GO

-- Tự động chạy nạp nếu bảng Stg_External_Delivery_Events đã có dữ liệu
IF EXISTS (SELECT 1 FROM dbo.Stg_External_Delivery_Events)
BEGIN
    EXEC dbo.usp_Populate_Delivery_Events_Mapping;
END
ELSE
BEGIN
    PRINT '-> Ghi chú: Stg_External_Delivery_Events chưa có dữ liệu. Sau khi nạp CSV, chạy EXEC dbo.usp_Populate_Delivery_Events_Mapping để nạp toàn bộ 170.820 dòng phục vụ đối soát phản biện.';
END
GO

PRINT '======================================================================';
PRINT 'BƯỚC 4: KIỂM CHỨNG TRÊN CÁC EVENT MẪU MINH HỌA LOGIC';
PRINT '======================================================================';

WITH SampleEvents AS (
    SELECT 'EVT00000001' AS event_id, 'LOAD00000001' AS load_id, 'Pickup' AS event_type, 'FAC00034' AS original_facility_id, 'Houston' AS location_city, 'TX' AS location_state UNION ALL
    SELECT 'EVT00000002', 'LOAD00000001', 'Delivery', 'FAC00046', 'Detroit', 'MI' UNION ALL
    SELECT 'EVT00000003', 'LOAD00000002', 'Pickup', 'FAC00015', 'Kansas City', 'MO' UNION ALL
    SELECT 'EVT00000005', 'LOAD00000003', 'Pickup', 'FAC00001', 'Columbus', 'OH'
)
SELECT 
    s.event_id,
    s.event_type,
    s.location_city + ', ' + s.location_state AS TrueLocation,
    s.original_facility_id AS RawFacilityId,
    m.selected_facility_id AS CorrectedFacilityId,
    m.selected_facility_name AS CorrectedFacilityName,
    CASE 
        WHEN m.selected_facility_id IS NULL THEN 1
        WHEN s.original_facility_id <> m.selected_facility_id THEN 1
        ELSE 0
    END AS IsCorrected,
    CASE 
        WHEN m.selected_facility_id IS NULL THEN N'NO_FACILITY_FOUND (Gán Key -1)'
        WHEN s.original_facility_id <> m.selected_facility_id THEN N'CORRECTED_MATCH (Đã sửa theo địa bàn)'
        ELSE N'EXACT_MATCH (Khớp ngẫu nhiên)'
    END AS CorrectionStatus,
    ISNULL(m.selection_rule, N'Thành phố không có cơ sở trong facilities.csv -> Gán Key -1 vào Fact') AS CorrectionReason
FROM SampleEvents s
LEFT JOIN dbo.Ref_City_Facility_Mapping m 
    ON TRIM(UPPER(s.location_city)) = TRIM(UPPER(m.city))
   AND TRIM(UPPER(s.location_state)) = TRIM(UPPER(m.state));
GO

PRINT '======================================================================';
PRINT 'HOÀN TẤT THIẾT LẬP BẢNG, THỦ TỤC VÀ TỪ ĐIỂN ÁNH XẠ CƠ SỞ BẾN BÃI!';
PRINT '======================================================================';
GO
