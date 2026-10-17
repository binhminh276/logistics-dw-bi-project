USE Logistics_OLTP;
GO

IF (SELECT is_cdc_enabled FROM sys.databases WHERE name = 'Logistics_OLTP') = 0
BEGIN
    EXEC sys.sp_cdc_enable_db;
END
GO

IF (SELECT is_tracked_by_cdc FROM sys.tables WHERE name = 'Loads') = 0
BEGIN
    EXEC sys.sp_cdc_enable_table
        @source_schema = 'dbo',
        @source_name = 'Loads',
        @role_name = NULL,
        @supports_net_changes = 1;
END
GO

IF (SELECT is_tracked_by_cdc FROM sys.tables WHERE name = 'Trips') = 0
BEGIN
    EXEC sys.sp_cdc_enable_table
        @source_schema = 'dbo',
        @source_name = 'Trips',
        @role_name = NULL,
        @supports_net_changes = 1;
END
GO

IF (SELECT is_tracked_by_cdc FROM sys.tables WHERE name = 'Drivers') = 0
BEGIN
    EXEC sys.sp_cdc_enable_table
        @source_schema = 'dbo',
        @source_name = 'Drivers',
        @role_name = NULL,
        @supports_net_changes = 1;
END
GO

SELECT name, is_tracked_by_cdc 
FROM sys.tables 
WHERE name IN ('Loads', 'Trips', 'Drivers');

USE Logistics_OLTP;
GO

-- Kích hoạt CDC ghi nhận toàn bộ Drivers hiện có
UPDATE dbo.drivers SET first_name = first_name;

-- Kích hoạt CDC ghi nhận toàn bộ Loads hiện có
UPDATE dbo.loads SET revenue = revenue;

-- Kích hoạt CDC ghi nhận toàn bộ Trips hiện có
UPDATE dbo.trips SET actual_distance_miles = actual_distance_miles;