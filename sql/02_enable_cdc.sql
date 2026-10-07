/*
================================================================================
ĐƯỜNG DẪN ĐÍCH: sql/02_enable_cdc.sql
MỤC ĐÍCH: Kích hoạt Change Data Capture (CDC) cấp CSDL Logistics_OLTP và 
          cấp bảng cho 3 thực thể cốt lõi: loads, trips, drivers.
          Hỗ trợ bắt biến động dữ liệu chi tiết và chế độ Net Changes.
NGÀY TẠO: 2026-10-05
CÁCH CHẠY:
  1. Mở trong SSMS (kết nối instance localhost).
  2. Hoặc chạy qua PowerShell / Command Prompt:
     sqlcmd -E -S localhost -i sql/02_enable_cdc.sql
================================================================================
*/

USE [Logistics_OLTP];
GO

PRINT '======================================================================';
PRINT 'BƯỚC 1: KÍCH HOẠT CDC CẤP CƠ SỞ DỮ LIỆU (DATABASE LEVEL)';
PRINT '======================================================================';

IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'Logistics_OLTP' AND is_cdc_enabled = 0)
BEGIN
    PRINT '-> Đang kích hoạt CDC cho CSDL [Logistics_OLTP]...';
    EXEC sys.sp_cdc_enable_db;
    PRINT '-> Kích hoạt CDC cấp Database THÀNH CÔNG.';
END
ELSE IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'Logistics_OLTP' AND is_cdc_enabled = 1)
BEGIN
    PRINT '-> CDC cấp CSDL [Logistics_OLTP] ĐÃ ĐƯỢC BẬT TỪ TRƯỚC.';
END
GO

PRINT '======================================================================';
PRINT 'BƯỚC 2: KÍCH HOẠT CDC CẤP BẢNG CHO 3 BẢNG: loads, trips, drivers';
PRINT '======================================================================';

-- 2.1. Bảng loads
IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'loads' AND is_tracked_by_cdc = 0)
BEGIN
    PRINT '-> Đang bật CDC cho bảng [loads]...';
    EXEC sys.sp_cdc_enable_table
        @source_schema = N'dbo',
        @source_name   = N'loads',
        @role_name     = NULL, -- Cho phép các role truy cập hoặc phân quyền sau
        @supports_net_changes = 1;
    PRINT '-> Bật CDC cho bảng [loads] THÀNH CÔNG.';
END
ELSE
BEGIN
    PRINT '-> Bảng [loads] ĐÃ ĐƯỢC BẬT CDC.';
END
GO

-- 2.2. Bảng trips
IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'trips' AND is_tracked_by_cdc = 0)
BEGIN
    PRINT '-> Đang bật CDC cho bảng [trips]...';
    EXEC sys.sp_cdc_enable_table
        @source_schema = N'dbo',
        @source_name   = N'trips',
        @role_name     = NULL,
        @supports_net_changes = 1;
    PRINT '-> Bật CDC cho bảng [trips] THÀNH CÔNG.';
END
ELSE
BEGIN
    PRINT '-> Bảng [trips] ĐÃ ĐƯỢC BẬT CDC.';
END
GO

-- 2.3. Bảng drivers
IF EXISTS (SELECT 1 FROM sys.tables WHERE name = 'drivers' AND is_tracked_by_cdc = 0)
BEGIN
    PRINT '-> Đang bật CDC cho bảng [drivers]...';
    EXEC sys.sp_cdc_enable_table
        @source_schema = N'dbo',
        @source_name   = N'drivers',
        @role_name     = NULL,
        @supports_net_changes = 1;
    PRINT '-> Bật CDC cho bảng [drivers] THÀNH CÔNG.';
END
ELSE
BEGIN
    PRINT '-> Bảng [drivers] ĐÃ ĐƯỢC BẬT CDC.';
END
GO

PRINT '======================================================================';
PRINT 'BƯỚC 3: KIỂM TRA TRẠNG THÁI CÁC BẢNG ĐANG ĐƯỢC CDC THEO DÕI';
PRINT '======================================================================';

SELECT 
    t.name AS TableName,
    t.is_tracked_by_cdc AS IsTrackedByCdc,
    ct.capture_instance AS CaptureInstance,
    ct.supports_net_changes AS SupportsNetChanges,
    ct.start_lsn AS StartLsn
FROM sys.tables t
JOIN cdc.change_tables ct ON t.object_id = ct.source_object_id
WHERE SCHEMA_NAME(t.schema_id) = 'dbo'
ORDER BY t.name;
GO

PRINT '======================================================================';
PRINT 'LƯU Ý VẬN HÀNH:';
PRINT '  - Để các tác vụ ngầm (Capture Job & Cleanup Job) chạy tự động,';
PRINT '    dịch vụ SQL Server Agent cần ở trạng thái Running.';
PRINT '  - Nếu Agent chưa bật, có thể kích hoạt quét log thủ công bằng lệnh:';
PRINT '    EXEC sys.sp_cdc_scan;';
PRINT '======================================================================';
GO
