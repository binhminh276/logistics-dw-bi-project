USE Logistics_OLTP;
GO

-- Kich hoat CDC cho cac bang nghiep vu con lai tren OLTP
IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN cdc.change_tables ct ON t.object_id = ct.source_object_id WHERE t.name = 'Customers')
BEGIN
    EXEC sys.sp_cdc_enable_table
        @source_schema = N'dbo',
        @source_name   = N'Customers',
        @role_name     = NULL,
        @supports_net_changes = 1;
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN cdc.change_tables ct ON t.object_id = ct.source_object_id WHERE t.name = 'Trucks')
BEGIN
    EXEC sys.sp_cdc_enable_table
        @source_schema = N'dbo',
        @source_name   = N'Trucks',
        @role_name     = NULL,
        @supports_net_changes = 1;
END;
GO

IF NOT EXISTS (SELECT 1 FROM sys.tables t JOIN cdc.change_tables ct ON t.object_id = ct.source_object_id WHERE t.name = 'Trailers')
BEGIN
    EXEC sys.sp_cdc_enable_table
        @source_schema = N'dbo',
        @source_name   = N'Trailers',
        @role_name     = NULL,
        @supports_net_changes = 1;
END;
GO