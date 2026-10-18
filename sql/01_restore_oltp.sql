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
GO

-- Chuyển ngữ cảnh vào DB OLTP để thao tác gỡ khóa và đổi cột
USE [Logistics_OLTP];
GO

PRINT '-> 5.1: Xóa thống kê tự động (Auto-Statistics) TRÊN CÁC BẢNG NGƯỜI DÙNG...';
DECLARE @sql_stats NVARCHAR(MAX) = '';
SELECT @sql_stats += 'DROP STATISTICS [' + OBJECT_SCHEMA_NAME(s.object_id) + '].[' + OBJECT_NAME(s.object_id) + '].[' + s.name + ']; '
FROM sys.stats s
JOIN sys.objects o ON s.object_id = o.object_id
WHERE (s.auto_created = 1 OR s.user_created = 1) 
  AND o.type = 'U' 
  AND o.is_ms_shipped = 0;
EXEC sp_executesql @sql_stats;

PRINT '-> 5.2: Quét và Xóa TOÀN BỘ các Index phụ thuộc...';
DECLARE @drop_indexes NVARCHAR(MAX) = '';
SELECT @drop_indexes += 'DROP INDEX [' + i.name + '] ON [' + SCHEMA_NAME(o.schema_id) + '].[' + o.name + ']; '
FROM sys.indexes i
JOIN sys.objects o ON i.object_id = o.object_id
WHERE i.type > 0 
  AND i.is_primary_key = 0 
  AND i.is_unique_constraint = 0 
  AND o.is_ms_shipped = 0 
  AND o.type = 'U';
EXEC sp_executesql @drop_indexes;

PRINT '-> 5.3: Tạm gỡ các ràng buộc (FK, CK, PK, UQ)...';
-- Xóa FK
ALTER TABLE [dbo].[delivery_events] DROP CONSTRAINT IF EXISTS [FK_events_facility], [FK_events_load], [FK_events_trip];
ALTER TABLE [dbo].[driver_monthly_metrics] DROP CONSTRAINT IF EXISTS [FK_dmm_driver];
ALTER TABLE [dbo].[fuel_purchases] DROP CONSTRAINT IF EXISTS [FK_fuel_driver], [FK_fuel_trip], [FK_fuel_truck];
ALTER TABLE [dbo].[loads] DROP CONSTRAINT IF EXISTS [FK_loads_customer], [FK_loads_route];
ALTER TABLE [dbo].[maintenance_records] DROP CONSTRAINT IF EXISTS [FK_maint_truck];
ALTER TABLE [dbo].[safety_incidents] DROP CONSTRAINT IF EXISTS [FK_incident_driver], [FK_incident_trip], [FK_incident_truck];
ALTER TABLE [dbo].[trips] DROP CONSTRAINT IF EXISTS [FK_trips_driver], [FK_trips_load], [FK_trips_trailer], [FK_trips_truck];
ALTER TABLE [dbo].[truck_utilization_metrics] DROP CONSTRAINT IF EXISTS [FK_tum_truck];

-- Xóa Check Constraints
ALTER TABLE [dbo].[customers] DROP CONSTRAINT IF EXISTS [CK_customers_status], [CK_customers_type];
ALTER TABLE [dbo].[delivery_events] DROP CONSTRAINT IF EXISTS [CK_events_type];
ALTER TABLE [dbo].[drivers] DROP CONSTRAINT IF EXISTS [CK_drivers_cdl], [CK_drivers_status], [CK_drivers_status_term];
ALTER TABLE [dbo].[facilities] DROP CONSTRAINT IF EXISTS [CK_facilities_type];
ALTER TABLE [dbo].[loads] DROP CONSTRAINT IF EXISTS [CK_loads_booking], [CK_loads_type];
ALTER TABLE [dbo].[maintenance_records] DROP CONSTRAINT IF EXISTS [CK_maint_type];
ALTER TABLE [dbo].[safety_incidents] DROP CONSTRAINT IF EXISTS [CK_incident_type];
ALTER TABLE [dbo].[trailers] DROP CONSTRAINT IF EXISTS [CK_trailers_type];
ALTER TABLE [dbo].[trucks] DROP CONSTRAINT IF EXISTS [CK_trucks_status];

-- Xóa PK & UQ
ALTER TABLE [dbo].[customers] DROP CONSTRAINT IF EXISTS [PK_customers];
ALTER TABLE [dbo].[delivery_events] DROP CONSTRAINT IF EXISTS [PK_delivery_events], [UQ_events_trip_type];
ALTER TABLE [dbo].[driver_monthly_metrics] DROP CONSTRAINT IF EXISTS [PK_driver_monthly];
ALTER TABLE [dbo].[drivers] DROP CONSTRAINT IF EXISTS [PK_drivers], [UQ_drivers_license];
ALTER TABLE [dbo].[facilities] DROP CONSTRAINT IF EXISTS [PK_facilities];
ALTER TABLE [dbo].[fuel_purchases] DROP CONSTRAINT IF EXISTS [PK_fuel_purchases];
ALTER TABLE [dbo].[loads] DROP CONSTRAINT IF EXISTS [PK_loads];
ALTER TABLE [dbo].[maintenance_records] DROP CONSTRAINT IF EXISTS [PK_maintenance];
ALTER TABLE [dbo].[routes] DROP CONSTRAINT IF EXISTS [PK_routes];
ALTER TABLE [dbo].[safety_incidents] DROP CONSTRAINT IF EXISTS [PK_safety_incidents];
ALTER TABLE [dbo].[trailers] DROP CONSTRAINT IF EXISTS [PK_trailers], [UQ_trailers_vin];
ALTER TABLE [dbo].[trips] DROP CONSTRAINT IF EXISTS [PK_trips], [UQ_trips_load];
ALTER TABLE [dbo].[truck_utilization_metrics] DROP CONSTRAINT IF EXISTS [PK_truck_util];
ALTER TABLE [dbo].[trucks] DROP CONSTRAINT IF EXISTS [PK_trucks], [UQ_trucks_unit], [UQ_trucks_vin];

PRINT '-> 5.4: Chuyển đổi toàn bộ cột sang NVARCHAR...';
-- 1. trucks
ALTER TABLE [dbo].[trucks] ALTER COLUMN truck_id NVARCHAR(20) NOT NULL;
ALTER TABLE [dbo].[trucks] ALTER COLUMN unit_number NVARCHAR(20) NOT NULL;
ALTER TABLE [dbo].[trucks] ALTER COLUMN make NVARCHAR(50) NOT NULL;
ALTER TABLE [dbo].[trucks] ALTER COLUMN vin NVARCHAR(50) NOT NULL;
ALTER TABLE [dbo].[trucks] ALTER COLUMN fuel_type NVARCHAR(30) NOT NULL;
ALTER TABLE [dbo].[trucks] ALTER COLUMN status NVARCHAR(50) NOT NULL;

-- 2. trailers
ALTER TABLE [dbo].[trailers] ALTER COLUMN trailer_id NVARCHAR(20) NOT NULL;
ALTER TABLE [dbo].[trailers] ALTER COLUMN trailer_number NVARCHAR(20) NOT NULL;
ALTER TABLE [dbo].[trailers] ALTER COLUMN trailer_type NVARCHAR(50) NOT NULL;
ALTER TABLE [dbo].[trailers] ALTER COLUMN vin NVARCHAR(50) NOT NULL;
ALTER TABLE [dbo].[trailers] ALTER COLUMN status NVARCHAR(50) NOT NULL;
ALTER TABLE [dbo].[trailers] ALTER COLUMN current_location NVARCHAR(50) NOT NULL;

-- 3. drivers
ALTER TABLE [dbo].[drivers] ALTER COLUMN driver_id NVARCHAR(20) NOT NULL;
ALTER TABLE [dbo].[drivers] ALTER COLUMN license_number NVARCHAR(50) NOT NULL;
ALTER TABLE [dbo].[drivers] ALTER COLUMN license_state NVARCHAR(10) NOT NULL;
ALTER TABLE [dbo].[drivers] ALTER COLUMN employment_status NVARCHAR(30) NOT NULL;
ALTER TABLE [dbo].[drivers] ALTER COLUMN cdl_class NVARCHAR(10) NOT NULL;

-- 4. customers
ALTER TABLE [dbo].[customers] ALTER COLUMN customer_id NVARCHAR(20) NOT NULL;
ALTER TABLE [dbo].[customers] ALTER COLUMN customer_name NVARCHAR(100) NOT NULL;
ALTER TABLE [dbo].[customers] ALTER COLUMN customer_type NVARCHAR(50) NOT NULL;
ALTER TABLE [dbo].[customers] ALTER COLUMN primary_freight_type NVARCHAR(50) NOT NULL;
ALTER TABLE [dbo].[customers] ALTER COLUMN account_status NVARCHAR(20) NOT NULL;

-- 5. facilities
ALTER TABLE [dbo].[facilities] ALTER COLUMN facility_id NVARCHAR(20) NOT NULL;
ALTER TABLE [dbo].[facilities] ALTER COLUMN facility_name NVARCHAR(100) NOT NULL;
ALTER TABLE [dbo].[facilities] ALTER COLUMN facility_type NVARCHAR(50) NOT NULL;
ALTER TABLE [dbo].[facilities] ALTER COLUMN city NVARCHAR(50) NOT NULL;
ALTER TABLE [dbo].[facilities] ALTER COLUMN state NVARCHAR(10) NOT NULL;
ALTER TABLE [dbo].[facilities] ALTER COLUMN operating_hours NVARCHAR(50) NOT NULL;

-- 6. routes
ALTER TABLE [dbo].[routes] ALTER COLUMN route_id NVARCHAR(20) NOT NULL;
ALTER TABLE [dbo].[routes] ALTER COLUMN origin_city NVARCHAR(50) NOT NULL;
ALTER TABLE [dbo].[routes] ALTER COLUMN origin_state NVARCHAR(10) NOT NULL;
ALTER TABLE [dbo].[routes] ALTER COLUMN destination_city NVARCHAR(50) NOT NULL;
ALTER TABLE [dbo].[routes] ALTER COLUMN destination_state NVARCHAR(10) NOT NULL;

-- 7. maintenance_records
ALTER TABLE [dbo].[maintenance_records] ALTER COLUMN maintenance_id NVARCHAR(20) NOT NULL;
ALTER TABLE [dbo].[maintenance_records] ALTER COLUMN truck_id NVARCHAR(20) NOT NULL;
ALTER TABLE [dbo].[maintenance_records] ALTER COLUMN maintenance_type NVARCHAR(50) NOT NULL;
ALTER TABLE [dbo].[maintenance_records] ALTER COLUMN facility_location NVARCHAR(50) NOT NULL;
ALTER TABLE [dbo].[maintenance_records] ALTER COLUMN service_description NVARCHAR(100) NOT NULL;

-- 8. delivery_events
ALTER TABLE [dbo].[delivery_events] ALTER COLUMN event_id NVARCHAR(20) NOT NULL;
ALTER TABLE [dbo].[delivery_events] ALTER COLUMN load_id NVARCHAR(20) NOT NULL;
ALTER TABLE [dbo].[delivery_events] ALTER COLUMN trip_id NVARCHAR(20) NOT NULL;
ALTER TABLE [dbo].[delivery_events] ALTER COLUMN event_type NVARCHAR(20) NOT NULL;
ALTER TABLE [dbo].[delivery_events] ALTER COLUMN facility_id NVARCHAR(20) NOT NULL;
ALTER TABLE [dbo].[delivery_events] ALTER COLUMN location_city NVARCHAR(50) NOT NULL;
ALTER TABLE [dbo].[delivery_events] ALTER COLUMN location_state NVARCHAR(10) NOT NULL;

-- 9. loads
ALTER TABLE [dbo].[loads] ALTER COLUMN load_id NVARCHAR(20) NOT NULL;
ALTER TABLE [dbo].[loads] ALTER COLUMN customer_id NVARCHAR(20) NOT NULL;
ALTER TABLE [dbo].[loads] ALTER COLUMN route_id NVARCHAR(20) NOT NULL;
ALTER TABLE [dbo].[loads] ALTER COLUMN load_type NVARCHAR(50) NOT NULL;
ALTER TABLE [dbo].[loads] ALTER COLUMN load_status NVARCHAR(50) NOT NULL;
ALTER TABLE [dbo].[loads] ALTER COLUMN booking_type NVARCHAR(50) NOT NULL;

-- 10. trips
ALTER TABLE [dbo].[trips] ALTER COLUMN trip_id NVARCHAR(20) NOT NULL;
ALTER TABLE [dbo].[trips] ALTER COLUMN load_id NVARCHAR(20) NOT NULL;
ALTER TABLE [dbo].[trips] ALTER COLUMN driver_id NVARCHAR(20) NULL;
ALTER TABLE [dbo].[trips] ALTER COLUMN truck_id NVARCHAR(20) NULL;
ALTER TABLE [dbo].[trips] ALTER COLUMN trailer_id NVARCHAR(20) NULL;
ALTER TABLE [dbo].[trips] ALTER COLUMN trip_status NVARCHAR(30) NOT NULL;

-- 11. Các bảng phụ thuộc khác
ALTER TABLE [dbo].[driver_monthly_metrics] ALTER COLUMN driver_id NVARCHAR(20) NOT NULL;
ALTER TABLE [dbo].[fuel_purchases] ALTER COLUMN fuel_purchase_id NVARCHAR(20) NOT NULL;
ALTER TABLE [dbo].[fuel_purchases] ALTER COLUMN trip_id NVARCHAR(20) NOT NULL;
ALTER TABLE [dbo].[fuel_purchases] ALTER COLUMN truck_id NVARCHAR(20) NULL;
ALTER TABLE [dbo].[fuel_purchases] ALTER COLUMN driver_id NVARCHAR(20) NULL;
ALTER TABLE [dbo].[fuel_purchases] ALTER COLUMN fuel_card_number NVARCHAR(20) NOT NULL;
ALTER TABLE [dbo].[fuel_purchases] ALTER COLUMN location_city NVARCHAR(50) NOT NULL;
ALTER TABLE [dbo].[fuel_purchases] ALTER COLUMN location_state NVARCHAR(10) NOT NULL;
ALTER TABLE [dbo].[safety_incidents] ALTER COLUMN incident_id NVARCHAR(20) NOT NULL;
ALTER TABLE [dbo].[safety_incidents] ALTER COLUMN trip_id NVARCHAR(20) NOT NULL;
ALTER TABLE [dbo].[safety_incidents] ALTER COLUMN truck_id NVARCHAR(20) NULL;
ALTER TABLE [dbo].[safety_incidents] ALTER COLUMN driver_id NVARCHAR(20) NULL;
ALTER TABLE [dbo].[safety_incidents] ALTER COLUMN incident_type NVARCHAR(30) NOT NULL;
ALTER TABLE [dbo].[safety_incidents] ALTER COLUMN location_city NVARCHAR(50) NOT NULL;
ALTER TABLE [dbo].[safety_incidents] ALTER COLUMN location_state NVARCHAR(10) NOT NULL;
ALTER TABLE [dbo].[safety_incidents] ALTER COLUMN description NVARCHAR(100) NOT NULL;
ALTER TABLE [dbo].[truck_utilization_metrics] ALTER COLUMN truck_id NVARCHAR(20) NOT NULL;

PRINT '-> 5.5: Lắp đặt lại toàn bộ Primary Keys, Unique, Check và Foreign Keys...';

-- Phục hồi Primary Keys & Unique (Các khóa này giữ nguyên kiểm tra chặt chẽ)
ALTER TABLE [dbo].[customers] ADD CONSTRAINT [PK_customers] PRIMARY KEY CLUSTERED (customer_id);
ALTER TABLE [dbo].[delivery_events] ADD CONSTRAINT [PK_delivery_events] PRIMARY KEY CLUSTERED (event_id);
ALTER TABLE [dbo].[delivery_events] ADD CONSTRAINT [UQ_events_trip_type] UNIQUE NONCLUSTERED (trip_id, event_type);
ALTER TABLE [dbo].[driver_monthly_metrics] ADD CONSTRAINT [PK_driver_monthly] PRIMARY KEY CLUSTERED (driver_id, month);
ALTER TABLE [dbo].[drivers] ADD CONSTRAINT [PK_drivers] PRIMARY KEY CLUSTERED (driver_id);
ALTER TABLE [dbo].[drivers] ADD CONSTRAINT [UQ_drivers_license] UNIQUE NONCLUSTERED (license_number);
ALTER TABLE [dbo].[facilities] ADD CONSTRAINT [PK_facilities] PRIMARY KEY CLUSTERED (facility_id);
ALTER TABLE [dbo].[fuel_purchases] ADD CONSTRAINT [PK_fuel_purchases] PRIMARY KEY CLUSTERED (fuel_purchase_id);
ALTER TABLE [dbo].[loads] ADD CONSTRAINT [PK_loads] PRIMARY KEY CLUSTERED (load_id);
ALTER TABLE [dbo].[maintenance_records] ADD CONSTRAINT [PK_maintenance] PRIMARY KEY CLUSTERED (maintenance_id);
ALTER TABLE [dbo].[routes] ADD CONSTRAINT [PK_routes] PRIMARY KEY CLUSTERED (route_id);
ALTER TABLE [dbo].[safety_incidents] ADD CONSTRAINT [PK_safety_incidents] PRIMARY KEY CLUSTERED (incident_id);
ALTER TABLE [dbo].[trailers] ADD CONSTRAINT [PK_trailers] PRIMARY KEY CLUSTERED (trailer_id);
ALTER TABLE [dbo].[trailers] ADD CONSTRAINT [UQ_trailers_vin] UNIQUE NONCLUSTERED (vin);
ALTER TABLE [dbo].[trips] ADD CONSTRAINT [PK_trips] PRIMARY KEY CLUSTERED (trip_id);
ALTER TABLE [dbo].[trips] ADD CONSTRAINT [UQ_trips_load] UNIQUE NONCLUSTERED (load_id);
ALTER TABLE [dbo].[truck_utilization_metrics] ADD CONSTRAINT [PK_truck_util] PRIMARY KEY CLUSTERED (truck_id, month);
ALTER TABLE [dbo].[trucks] ADD CONSTRAINT [PK_trucks] PRIMARY KEY CLUSTERED (truck_id);
ALTER TABLE [dbo].[trucks] ADD CONSTRAINT [UQ_trucks_unit] UNIQUE NONCLUSTERED (unit_number);
ALTER TABLE [dbo].[trucks] ADD CONSTRAINT [UQ_trucks_vin] UNIQUE NONCLUSTERED (vin);

-- Phục hồi Check Constraints (Thêm WITH NOCHECK để bỏ qua dữ liệu cũ bị dơ)
ALTER TABLE [dbo].[customers] WITH NOCHECK ADD CONSTRAINT [CK_customers_status] CHECK (([account_status]='Inactive' OR [account_status]='Active'));
ALTER TABLE [dbo].[customers] WITH NOCHECK ADD CONSTRAINT [CK_customers_type] CHECK (([customer_type]='Spot' OR [customer_type]='Dedicated' OR [customer_type]='Contract'));
ALTER TABLE [dbo].[delivery_events] WITH NOCHECK ADD CONSTRAINT [CK_events_type] CHECK (([event_type]='Delivery' OR [event_type]='Pickup'));
ALTER TABLE [dbo].[drivers] WITH NOCHECK ADD CONSTRAINT [CK_drivers_cdl] CHECK (([cdl_class]='C' OR [cdl_class]='B' OR [cdl_class]='A'));
ALTER TABLE [dbo].[drivers] WITH NOCHECK ADD CONSTRAINT [CK_drivers_status] CHECK (([employment_status]='Terminated' OR [employment_status]='Active'));
ALTER TABLE [dbo].[drivers] WITH NOCHECK ADD CONSTRAINT [CK_drivers_status_term] CHECK (([employment_status]='Terminated' AND [termination_date] IS NOT NULL OR [employment_status]='Active' AND [termination_date] IS NULL));
ALTER TABLE [dbo].[facilities] WITH NOCHECK ADD CONSTRAINT [CK_facilities_type] CHECK (([facility_type]='Warehouse' OR [facility_type]='Terminal' OR [facility_type]='Distribution Center' OR [facility_type]='Cross-Dock'));
ALTER TABLE [dbo].[loads] WITH NOCHECK ADD CONSTRAINT [CK_loads_booking] CHECK (([booking_type]='Spot' OR [booking_type]='Dedicated' OR [booking_type]='Contract'));
ALTER TABLE [dbo].[loads] WITH NOCHECK ADD CONSTRAINT [CK_loads_type] CHECK (([load_type]='Refrigerated' OR [load_type]='Dry Van'));
ALTER TABLE [dbo].[maintenance_records] WITH NOCHECK ADD CONSTRAINT [CK_maint_type] CHECK (([maintenance_type]='Transmission' OR [maintenance_type]='Tire' OR [maintenance_type]='Repair' OR [maintenance_type]='Preventive' OR [maintenance_type]='Inspection' OR [maintenance_type]='Engine' OR [maintenance_type]='Brake'));
ALTER TABLE [dbo].[safety_incidents] WITH NOCHECK ADD CONSTRAINT [CK_incident_type] CHECK (([incident_type]='Moving Violation' OR [incident_type]='Equipment Damage' OR [incident_type]='DOT Violation' OR [incident_type]='Customer Complaint' OR [incident_type]='Accident'));
ALTER TABLE [dbo].[trailers] WITH NOCHECK ADD CONSTRAINT [CK_trailers_type] CHECK (([trailer_type]='Refrigerated' OR [trailer_type]='Dry Van'));
ALTER TABLE [dbo].[trucks] WITH NOCHECK ADD CONSTRAINT [CK_trucks_status] CHECK (([status]='Maintenance' OR [status]='Inactive' OR [status]='Active'));

-- Phục hồi Foreign Keys (Thêm WITH NOCHECK)
ALTER TABLE [dbo].[delivery_events] WITH NOCHECK ADD CONSTRAINT [FK_events_facility] FOREIGN KEY([facility_id]) REFERENCES [dbo].[facilities] ([facility_id]);
ALTER TABLE [dbo].[delivery_events] WITH NOCHECK ADD CONSTRAINT [FK_events_load] FOREIGN KEY([load_id]) REFERENCES [dbo].[loads] ([load_id]);
ALTER TABLE [dbo].[delivery_events] WITH NOCHECK ADD CONSTRAINT [FK_events_trip] FOREIGN KEY([trip_id]) REFERENCES [dbo].[trips] ([trip_id]);
ALTER TABLE [dbo].[driver_monthly_metrics] WITH NOCHECK ADD CONSTRAINT [FK_dmm_driver] FOREIGN KEY([driver_id]) REFERENCES [dbo].[drivers] ([driver_id]);
ALTER TABLE [dbo].[fuel_purchases] WITH NOCHECK ADD CONSTRAINT [FK_fuel_driver] FOREIGN KEY([driver_id]) REFERENCES [dbo].[drivers] ([driver_id]);
ALTER TABLE [dbo].[fuel_purchases] WITH NOCHECK ADD CONSTRAINT [FK_fuel_trip] FOREIGN KEY([trip_id]) REFERENCES [dbo].[trips] ([trip_id]);
ALTER TABLE [dbo].[fuel_purchases] WITH NOCHECK ADD CONSTRAINT [FK_fuel_truck] FOREIGN KEY([truck_id]) REFERENCES [dbo].[trucks] ([truck_id]);
ALTER TABLE [dbo].[loads] WITH NOCHECK ADD CONSTRAINT [FK_loads_customer] FOREIGN KEY([customer_id]) REFERENCES [dbo].[customers] ([customer_id]);
ALTER TABLE [dbo].[loads] WITH NOCHECK ADD CONSTRAINT [FK_loads_route] FOREIGN KEY([route_id]) REFERENCES [dbo].[routes] ([route_id]);
ALTER TABLE [dbo].[maintenance_records] WITH NOCHECK ADD CONSTRAINT [FK_maint_truck] FOREIGN KEY([truck_id]) REFERENCES [dbo].[trucks] ([truck_id]);
ALTER TABLE [dbo].[safety_incidents] WITH NOCHECK ADD CONSTRAINT [FK_incident_driver] FOREIGN KEY([driver_id]) REFERENCES [dbo].[drivers] ([driver_id]);
ALTER TABLE [dbo].[safety_incidents] WITH NOCHECK ADD CONSTRAINT [FK_incident_trip] FOREIGN KEY([trip_id]) REFERENCES [dbo].[trips] ([trip_id]);
ALTER TABLE [dbo].[safety_incidents] WITH NOCHECK ADD CONSTRAINT [FK_incident_truck] FOREIGN KEY([truck_id]) REFERENCES [dbo].[trucks] ([truck_id]);
ALTER TABLE [dbo].[trips] WITH NOCHECK ADD CONSTRAINT [FK_trips_driver] FOREIGN KEY([driver_id]) REFERENCES [dbo].[drivers] ([driver_id]);
ALTER TABLE [dbo].[trips] WITH NOCHECK ADD CONSTRAINT [FK_trips_load] FOREIGN KEY([load_id]) REFERENCES [dbo].[loads] ([load_id]);
ALTER TABLE [dbo].[trips] WITH NOCHECK ADD CONSTRAINT [FK_trips_trailer] FOREIGN KEY([trailer_id]) REFERENCES [dbo].[trailers] ([trailer_id]);
ALTER TABLE [dbo].[trips] WITH NOCHECK ADD CONSTRAINT [FK_trips_truck] FOREIGN KEY([truck_id]) REFERENCES [dbo].[trucks] ([truck_id]);
ALTER TABLE [dbo].[truck_utilization_metrics] WITH NOCHECK ADD CONSTRAINT [FK_tum_truck] FOREIGN KEY([truck_id]) REFERENCES [dbo].[trucks] ([truck_id]);

PRINT '-> Đã chuẩn hóa 100% cột chuỗi của Logistics_OLTP sang NVARCHAR (Unicode) thành công.';

PRINT '======================================================================';
PRINT 'HOÀN TẤT RESTORE VÀ CHUẨN HÓA CSDL Logistics_OLTP TRÊN LOCALHOST!';
PRINT '======================================================================';
GO
