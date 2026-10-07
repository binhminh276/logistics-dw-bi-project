/*
================================================================================
ĐƯỜNG DẪN ĐÍCH: sql/06_create_etl_metadata.sql
MỤC ĐÍCH: DDL bảng quản lý metadata và watermark ETL (Logistics_Staging).
NGÀY TẠO: 2026-10-06
================================================================================
*/

USE Logistics_Staging;
GO

DROP TABLE IF EXISTS ETL_Metadata;
CREATE TABLE ETL_Metadata (
    table_name NVARCHAR(100) PRIMARY KEY,
    last_load_date DATETIME NOT NULL,
    rows_inserted INT DEFAULT 0,
    rows_updated INT DEFAULT 0,
    execution_status NVARCHAR(30) DEFAULT 'SUCCESS',
    updated_at DATETIME DEFAULT GETDATE()
);

-- Khởi tạo mốc Watermark ban đầu
INSERT INTO ETL_Metadata (table_name, last_load_date, execution_status)
VALUES 
    (N'Fact_Maintenance', '1900-01-01 00:00:00', N'INIT'),
    (N'Fact_Delivery_Fulfillment', '1900-01-01 00:00:00', N'INIT'),
    (N'Fact_Trip', '1900-01-01 00:00:00', N'INIT'),
    (N'Fact_Load', '1900-01-01 00:00:00', N'INIT');
GO