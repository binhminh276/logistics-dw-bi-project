/*
================================================================================
TÊN FILE: 08_ssis_prerequisites_and_patches.sql
MỤC ĐÍCH: Bổ sung các cấu trúc SQL phát sinh trong quá trình thiết kế SSIS:
          1. Vá lỗi độ chính xác micro-giây cho bảng Staging Delivery Events.
          2. Tạo View Pivot phục vụ luồng Accumulating Snapshot Fact.
          3. Kích hoạt nạp dữ liệu từ điển ánh xạ bến bãi chuẩn.
          4. Bổ sung bản ghi khóa mặc định (-1) chống lỗi Foreign Key.
THỨ TỰ CHẠY: Chạy ngay sau khi hoàn tất file 07_create_delivery_events_mapping.sql.
================================================================================
*/

-- =============================================================================
-- MỤC 1: VÁ LỖI TRÀN SỐ THẬP PHÂN MICRO-GIÂY CHO STAGING DELIVERY EVENTS
-- Lý do: File delivery_events.csv chứa mốc thời gian có 6 chữ số thập phân 
-- (micro-giây). CSDL khai báo DATETIME chỉ nhận 3 chữ số nên SSIS sẽ báo lỗi 
-- OLE DB Overflow khi nạp gói Stg_CSV_Files.dtsx.
-- =============================================================================
USE [Logistics_Staging];
GO

PRINT '-> 1. Nâng cấp kiểu dữ liệu thời gian lên DATETIME2(6)...';
ALTER TABLE [dbo].[Stg_External_Delivery_Events] 
ALTER COLUMN [scheduled_datetime] DATETIME2(6);

ALTER TABLE [dbo].[Stg_External_Delivery_Events] 
ALTER COLUMN [actual_datetime] DATETIME2(6);
GO


-- =============================================================================
-- MỤC 2: TẠO VIEW GỘP DỮ LIỆU GIAO NHẬN (vw_Delivery_Fulfillment_Pivot)
-- Lý do: Quy chuẩn nhóm cấm viết câu lệnh SQL phức tạp trong khối OLE DB Source 
-- (chỉ dùng chế độ "Table or view"). Bảng Stg_Delivery_Events_Mapping gốc chỉ 
-- lưu từng sự kiện đơn lẻ, không có cột thời gian và đo lường. View này sẽ gộp 
-- cặp Pickup - Delivery của từng load_id thành 1 dòng hoàn chỉnh.
-- =============================================================================
USE [Logistics_Staging];
GO

PRINT '-> 2. Tạo View vw_Delivery_Fulfillment_Pivot cho Fact_Delivery_Fulfillment...';
CREATE OR ALTER VIEW [dbo].[vw_Delivery_Fulfillment_Pivot] AS
SELECT 
    p.load_id,
    p.trip_id,
    p.event_id AS pickup_event_id,
    d.event_id AS delivery_event_id,
    p.actual_datetime AS pickup_actual_datetime,
    d.actual_datetime AS delivery_actual_datetime,
    p.detention_minutes AS pickup_detention_minutes,
    d.detention_minutes AS delivery_detention_minutes,
    p.on_time_flag AS pickup_on_time_flag,
    d.on_time_flag AS delivery_on_time_flag,
    pm.corrected_facility_id AS origin_corrected_facility_id,
    dm.corrected_facility_id AS dest_corrected_facility_id
FROM dbo.Stg_External_Delivery_Events p
INNER JOIN dbo.Stg_Delivery_Events_Mapping pm 
    ON p.event_id = pm.event_id
LEFT JOIN dbo.Stg_External_Delivery_Events d 
    ON p.load_id = d.load_id AND d.event_type = 'Delivery'
LEFT JOIN dbo.Stg_Delivery_Events_Mapping dm 
    ON d.event_id = dm.event_id
WHERE p.event_type = 'Pickup';
GO


-- =============================================================================
-- MỤC 3: KÍCH HOẠT THỦ TỤC NẠP DỮ LIỆU TỪ ĐIỂN ÁNH XẠ BẾN BÃI
-- Lý do: Script 07 chỉ tạo bảng và Stored Procedure chứ chưa chạy nạp. 
-- Cần kích hoạt để bảng Stg_Delivery_Events_Mapping có sẵn dữ liệu chuẩn hóa.
-- =============================================================================
USE [Logistics_Staging];
GO

PRINT '-> 3. Thực thi Procedure sửa lỗi bến bãi...';
EXEC dbo.usp_Populate_Delivery_Events_Mapping;
GO


-- =============================================================================
-- MỤC 4: BỔ SUNG BẢN GHI MẶC ĐỊNH (-1) CHO DIM_LOAD_PROFILE
-- Lý do: Khi nạp Fact_Delivery_Fulfillment, nếu gói Dim_Commercial chưa chạy, 
-- bảng Dim_Load_Profile sẽ thiếu bản ghi -1 dẫn đến vi phạm ràng buộc khóa ngoại 
-- FK_FactDeliv_Profile và làm sập package.
-- =============================================================================
USE [Logistics_DW];
GO

PRINT '-> 4. Đảm bảo tồn tại khóa mặc định (-1) trong Dim_Load_Profile...';
IF NOT EXISTS (SELECT 1 FROM dbo.Dim_Load_Profile WHERE load_profile_key = -1)
BEGIN
    SET IDENTITY_INSERT dbo.Dim_Load_Profile ON;
    INSERT INTO dbo.Dim_Load_Profile (load_profile_key, load_status, booking_type, load_type)
    VALUES (-1, N'Unknown', N'Unknown', N'Unknown');
    SET IDENTITY_INSERT dbo.Dim_Load_Profile OFF;
END
GO

PRINT '======================================================================';
PRINT 'HOÀN TẤT BỔ SUNG CÁC TIỀN ĐỀ SQL CHO SSIS!';
PRINT '======================================================================';