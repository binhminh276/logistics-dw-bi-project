/*
================================================================================
ĐƯỜNG DẪN ĐÍCH: sql/01_restore_oltp.sql
MỤC ĐÍCH: Khảo sát thông tin bản sao lưu, kiểm tra tính toàn vẹn (VERIFYONLY),
          khôi phục (RESTORE) CSDL Logistics_OLTP từ tệp LogisticsOLTP_v2.bak,
          và chuẩn hóa 100% các cột chuỗi sang kiểu NVARCHAR (Unicode / DT_WSTR).
          Việc chuẩn hóa này giúp mọi thành viên khi clone về và chạy file này
          sẽ sở hữu CSDL tương thích hoàn toàn với SSIS, triệt tiêu vĩnh viễn
          lỗi xung đột bảng mã Windows (Code Page 1252 vs 1258).
NGÀY CẬP NHẬT: 2026-10-07
CÁCH CHẠY:
  1. Mở trong SSMS (kết nối instance localhost) -> Bấm Execute (F5).
  2. Hoặc chạy qua PowerShell / Command Prompt:
     sqlcmd -E -S localhost -i sql/01_restore_oltp.sql
================================================================================
*/

USE [master];
GO

-- =============================================================================
-- BẢO VỆ PHIÊN LÀM VIỆC: Tắt giao dịch ngầm và Rollback mọi transaction đang treo
-- =============================================================================
SET IMPLICIT_TRANSACTIONS OFF;
GO
WHILE @@TRANCOUNT > 0
    ROLLBACK TRANSACTION;
GO

-- =============================================================================
-- KHAI BÁO THAM SỐ T-SQL THUẦN
-- =============================================================================
DECLARE @BackupFile NVARCHAR(500);
SET @BackupFile = 'd:\Kho\Project\LogisticsOLTP_v2.bak';

DECLARE @TargetDb NVARCHAR(128);
SET @TargetDb = 'Logistics_OLTP';

-- Tự động nhận diện đường dẫn Data/Log mặc định của instance SQL Server
DECLARE @DefaultDataPath NVARCHAR(500);
SET @DefaultDataPath = CAST(SERVERPROPERTY('InstanceDefaultDataPath') AS NVARCHAR(500));

DECLARE @DefaultLogPath NVARCHAR(500);
SET @DefaultLogPath = CAST(SERVERPROPERTY('InstanceDefaultLogPath') AS NVARCHAR(500));

IF @DefaultDataPath IS NULL
    SET @DefaultDataPath = 'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\';
IF @DefaultLogPath IS NULL
    SET @DefaultLogPath = @DefaultDataPath;

PRINT '======================================================================';
PRINT 'BƯỚC 1: KHẢO SÁT FILELIST VÀ HEADER CỦA BẢN SAO LƯU';
PRINT '======================================================================';

RESTORE HEADERONLY FROM DISK = @BackupFile;
RESTORE FILELISTONLY FROM DISK = @BackupFile;

PRINT '======================================================================';
PRINT 'BƯỚC 2: KIỂM TRA TÍNH TOÀN VẸN CỦA FILE BACKUP (VERIFYONLY)';
PRINT '======================================================================';

RESTORE VERIFYONLY FROM DISK = @BackupFile;
IF @@ERROR = 0
    PRINT '-> Bản sao lưu HỢP LỆ và có thể khôi phục an toàn.'
ELSE
    RAISERROR('-> LỖI: Tệp sao lưu bị hỏng hoặc không tương thích phiên bản!', 16, 1);

PRINT '======================================================================';
PRINT 'BƯỚC 3: ĐÓNG CÁC KẾT NỐI ĐANG MỞ VÀ TIẾN HÀNH RESTORE CSDL';
PRINT '======================================================================';

IF EXISTS (SELECT 1 FROM sys.databases WHERE name = @TargetDb)
BEGIN
    PRINT '-> Database [' + @TargetDb + '] đã tồn tại. Đang ngắt kết nối hiện hành...';
    DECLARE @KillSql NVARCHAR(500);
    SET @KillSql = 'ALTER DATABASE [' + @TargetDb + '] SET SINGLE_USER WITH ROLLBACK IMMEDIATE;';
    EXEC sp_executesql @KillSql;
END

PRINT '-> Bắt đầu RESTORE DATABASE [' + @TargetDb + ']...';
DECLARE @MdfPath NVARCHAR(500);
SET @MdfPath = @DefaultDataPath + @TargetDb + '.mdf';

DECLARE @LdfPath NVARCHAR(500);
SET @LdfPath = @DefaultLogPath + @TargetDb + '_log.ldf';

DECLARE @RestoreSql NVARCHAR(MAX);
SET @RestoreSql = '
RESTORE DATABASE [' + @TargetDb + ']
FROM DISK = @BackupPath
WITH 
    MOVE ''LogisticsOLTP'' TO @DestMdf,
    MOVE ''LogisticsOLTP_log'' TO @DestLdf,
    REPLACE,
    STATS = 10;';

EXEC sp_executesql @RestoreSql, 
    N'@BackupPath NVARCHAR(500), @DestMdf NVARCHAR(500), @DestLdf NVARCHAR(500)', 
    @BackupFile, @MdfPath, @LdfPath;

PRINT '======================================================================';
PRINT 'BƯỚC 4: CẤU HÌNH HẬU RESTORE (MULTI_USER & CHUẨN HÓA DATABASE OWNER)';
PRINT '======================================================================';

DECLARE @MultiSql NVARCHAR(500);
SET @MultiSql = 'ALTER DATABASE [' + @TargetDb + '] SET MULTI_USER;';
EXEC sp_executesql @MultiSql;

DECLARE @OwnerSql NVARCHAR(500);
SET @OwnerSql = 'ALTER AUTHORIZATION ON DATABASE::[' + @TargetDb + '] TO [sa];';
BEGIN TRY
    EXEC sp_executesql @OwnerSql;
    PRINT '-> Đã gán chủ sở hữu CSDL về [sa] thành công.';
END TRY
BEGIN CATCH
    PRINT '-> Cảnh báo đổi owner: ' + ERROR_MESSAGE();
END CATCH

PRINT '======================================================================';
PRINT 'BƯỚC 5: CHUẨN HÓA TOÀN BỘ CỘT CHUỖI CSDL SANG NVARCHAR (UNICODE / DT_WSTR)';
PRINT '======================================================================';

-- 1. trucks
ALTER TABLE [Logistics_OLTP].dbo.trucks ALTER COLUMN truck_id NVARCHAR(20) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.trucks ALTER COLUMN unit_number NVARCHAR(20) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.trucks ALTER COLUMN make NVARCHAR(50) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.trucks ALTER COLUMN vin NVARCHAR(50) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.trucks ALTER COLUMN fuel_type NVARCHAR(30) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.trucks ALTER COLUMN status NVARCHAR(50) NOT NULL;

-- 2. trailers
ALTER TABLE [Logistics_OLTP].dbo.trailers ALTER COLUMN trailer_id NVARCHAR(20) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.trailers ALTER COLUMN trailer_number NVARCHAR(20) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.trailers ALTER COLUMN trailer_type NVARCHAR(50) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.trailers ALTER COLUMN vin NVARCHAR(50) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.trailers ALTER COLUMN status NVARCHAR(50) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.trailers ALTER COLUMN current_location NVARCHAR(50) NOT NULL;

-- 3. drivers
ALTER TABLE [Logistics_OLTP].dbo.drivers ALTER COLUMN driver_id NVARCHAR(20) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.drivers ALTER COLUMN license_number NVARCHAR(50) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.drivers ALTER COLUMN license_state NVARCHAR(10) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.drivers ALTER COLUMN employment_status NVARCHAR(30) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.drivers ALTER COLUMN cdl_class NVARCHAR(10) NOT NULL;

-- 4. customers
ALTER TABLE [Logistics_OLTP].dbo.customers ALTER COLUMN customer_id NVARCHAR(20) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.customers ALTER COLUMN customer_name NVARCHAR(100) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.customers ALTER COLUMN customer_type NVARCHAR(50) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.customers ALTER COLUMN primary_freight_type NVARCHAR(50) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.customers ALTER COLUMN account_status NVARCHAR(20) NOT NULL;

-- 5. facilities
ALTER TABLE [Logistics_OLTP].dbo.facilities ALTER COLUMN facility_id NVARCHAR(20) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.facilities ALTER COLUMN facility_name NVARCHAR(100) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.facilities ALTER COLUMN facility_type NVARCHAR(50) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.facilities ALTER COLUMN city NVARCHAR(50) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.facilities ALTER COLUMN state NVARCHAR(10) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.facilities ALTER COLUMN operating_hours NVARCHAR(50) NOT NULL;

-- 6. routes
ALTER TABLE [Logistics_OLTP].dbo.routes ALTER COLUMN route_id NVARCHAR(20) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.routes ALTER COLUMN origin_city NVARCHAR(50) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.routes ALTER COLUMN origin_state NVARCHAR(10) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.routes ALTER COLUMN destination_city NVARCHAR(50) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.routes ALTER COLUMN destination_state NVARCHAR(10) NOT NULL;

-- 7. maintenance_records
ALTER TABLE [Logistics_OLTP].dbo.maintenance_records ALTER COLUMN maintenance_id NVARCHAR(20) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.maintenance_records ALTER COLUMN truck_id NVARCHAR(20) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.maintenance_records ALTER COLUMN maintenance_type NVARCHAR(50) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.maintenance_records ALTER COLUMN facility_location NVARCHAR(50) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.maintenance_records ALTER COLUMN service_description NVARCHAR(100) NOT NULL;

-- 8. delivery_events
ALTER TABLE [Logistics_OLTP].dbo.delivery_events ALTER COLUMN event_id NVARCHAR(20) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.delivery_events ALTER COLUMN load_id NVARCHAR(20) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.delivery_events ALTER COLUMN trip_id NVARCHAR(20) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.delivery_events ALTER COLUMN event_type NVARCHAR(20) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.delivery_events ALTER COLUMN facility_id NVARCHAR(20) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.delivery_events ALTER COLUMN location_city NVARCHAR(50) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.delivery_events ALTER COLUMN location_state NVARCHAR(10) NOT NULL;

-- 9. loads
ALTER TABLE [Logistics_OLTP].dbo.loads ALTER COLUMN load_id NVARCHAR(20) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.loads ALTER COLUMN customer_id NVARCHAR(20) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.loads ALTER COLUMN route_id NVARCHAR(20) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.loads ALTER COLUMN load_type NVARCHAR(50) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.loads ALTER COLUMN load_status NVARCHAR(50) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.loads ALTER COLUMN booking_type NVARCHAR(50) NOT NULL;

-- 10. trips
ALTER TABLE [Logistics_OLTP].dbo.trips ALTER COLUMN trip_id NVARCHAR(20) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.trips ALTER COLUMN load_id NVARCHAR(20) NOT NULL;
ALTER TABLE [Logistics_OLTP].dbo.trips ALTER COLUMN driver_id NVARCHAR(20) NULL;
ALTER TABLE [Logistics_OLTP].dbo.trips ALTER COLUMN truck_id NVARCHAR(20) NULL;
ALTER TABLE [Logistics_OLTP].dbo.trips ALTER COLUMN trailer_id NVARCHAR(20) NULL;
ALTER TABLE [Logistics_OLTP].dbo.trips ALTER COLUMN trip_status NVARCHAR(30) NOT NULL;

PRINT '-> Đã chuẩn hóa 100% cột chuỗi của Logistics_OLTP sang NVARCHAR (Unicode) thành công.';

PRINT '======================================================================';
PRINT 'HOÀN TẤT RESTORE VÀ CHUẨN HÓA CSDL [' + @TargetDb + '] TRÊN LOCALHOST!';
PRINT '======================================================================';
GO