-- ================================================================================
-- SCRIPT: sql/14_init_audit_schema.sql
-- MỤC ĐÍCH: Khởi tạo Schema [audit] và 6 bảng quản trị chất lượng dữ liệu, 
--           kiểm toán và metadata theo tài liệu thietke_luong_dam_bao_chat_luong.md
-- CƠ CHẾ: Dành riêng cho luồng SSIS Native (No Stored Procedures)
-- ================================================================================

USE Logistics_Staging;
GO

-- 1. Tạo Schema chuyên biệt audit
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'audit')
BEGIN
    EXEC('CREATE SCHEMA audit');
    PRINT '>> Da tao Schema [audit] tren Logistics_Staging';
END
GO

-- 2. Bảng theo dõi phiên chạy cấp Batch (Job Master / Agent Job)
IF OBJECT_ID('audit.Batch_Log', 'U') IS NOT NULL DROP TABLE audit.Batch_Log;
CREATE TABLE audit.Batch_Log (
    batch_id            BIGINT IDENTITY(1,1) PRIMARY KEY,
    batch_name          VARCHAR(100) NOT NULL,
    triggered_by        VARCHAR(50) NOT NULL DEFAULT SUSER_SNAME(),
    start_time          DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    end_time            DATETIME2 NULL,
    status              VARCHAR(20) NOT NULL DEFAULT 'RUNNING', -- 'RUNNING', 'SUCCESS', 'FAILED'
    total_packages      INT NULL DEFAULT 0,
    error_summary       NVARCHAR(MAX) NULL
);
PRINT '>> Da tao bang audit.Batch_Log';

-- Tạo sẵn Batch mặc định batch_id = 1 phục vụ chạy test độc lập từng package
SET IDENTITY_INSERT audit.Batch_Log ON;
INSERT INTO audit.Batch_Log (batch_id, batch_name, status) 
VALUES (1, 'Initial_Debug_Batch', 'RUNNING');
SET IDENTITY_INSERT audit.Batch_Log OFF;
PRINT '>> Da tao san batch_id = 1 trong audit.Batch_Log';
GO

-- 3. Bảng theo dõi tiến trình chi tiết của từng Package SSIS
IF OBJECT_ID('audit.Package_Log', 'U') IS NOT NULL DROP TABLE audit.Package_Log;
CREATE TABLE audit.Package_Log (
    package_log_id      BIGINT IDENTITY(1,1) PRIMARY KEY,
    batch_id            BIGINT NOT NULL FOREIGN KEY REFERENCES audit.Batch_Log(batch_id),
    package_name        VARCHAR(100) NOT NULL,
    start_time          DATETIME2 NOT NULL DEFAULT SYSDATETIME(),
    end_time            DATETIME2 NULL,
    source_row_count    BIGINT NULL DEFAULT 0,
    inserted_row_count  BIGINT NULL DEFAULT 0,
    updated_row_count   BIGINT NULL DEFAULT 0,
    rejected_row_count  BIGINT NULL DEFAULT 0,
    status              VARCHAR(20) NOT NULL DEFAULT 'RUNNING', -- 'RUNNING', 'SUCCESS', 'FAILED'
    error_message       NVARCHAR(MAX) NULL
);
PRINT '>> Da tao bang audit.Package_Log';
GO

-- 4. Bảng ghi nhận ngoại lệ kỹ thuật toàn cục (SSIS Exception Log qua OnError Event Handler)
IF OBJECT_ID('audit.Error_Log', 'U') IS NOT NULL DROP TABLE audit.Error_Log;
CREATE TABLE audit.Error_Log (
    error_id            BIGINT IDENTITY(1,1) PRIMARY KEY,
    batch_id            BIGINT NULL,
    package_name        VARCHAR(100) NOT NULL,
    task_name           VARCHAR(100) NOT NULL,
    error_code          INT NULL,
    error_description   NVARCHAR(MAX) NOT NULL,
    logged_time         DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
PRINT '>> Da tao bang audit.Error_Log';
GO

-- 5. Bảng Dead-Letter Queue (Chứa dòng bẩn bị rẽ nhánh ở cấp Data Flow)
IF OBJECT_ID('audit.Data_Quality_Rejections', 'U') IS NOT NULL DROP TABLE audit.Data_Quality_Rejections;
CREATE TABLE audit.Data_Quality_Rejections (
    rejection_id        BIGINT IDENTITY(1,1) PRIMARY KEY,
    batch_id            BIGINT NULL,
    package_name        NVARCHAR(100) NOT NULL,
    source_table        NVARCHAR(100) NOT NULL,       -- 'maintenance_records.csv', 'fuel_rates', etc.
    business_key        NVARCHAR(100) NULL,          -- 'MAINT_001', 'TRIP00000067'
    rule_name           NVARCHAR(100) NOT NULL,      -- 'Negative Maintenance Cost', 'Type Conversion', etc.
    rejected_raw_data   NVARCHAR(MAX) NULL,          -- Lưu chuỗi dữ liệu gốc
    rejection_reason    NVARCHAR(500) NOT NULL,
    created_at          DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
PRINT '>> Da tao bang audit.Data_Quality_Rejections';
GO

-- 6. Bảng kiểm tra đối soát số liệu liên tầng (Reconciliation Log)
IF OBJECT_ID('audit.Reconciliation_Log', 'U') IS NOT NULL DROP TABLE audit.Reconciliation_Log;
CREATE TABLE audit.Reconciliation_Log (
    check_id            BIGINT IDENTITY(1,1) PRIMARY KEY,
    batch_id            BIGINT NOT NULL,
    fact_table_name     VARCHAR(50) NOT NULL,
    source_row_count    BIGINT NOT NULL,
    dwh_row_count       BIGINT NOT NULL,
    difference_count    BIGINT NOT NULL,
    source_total_value  DECIMAL(18,2) NULL,
    dwh_total_value     DECIMAL(18,2) NULL,
    is_balanced         BIT NOT NULL,               -- 1 = Khớp, 0 = Lệch
    checked_time        DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
PRINT '>> Da tao bang audit.Reconciliation_Log';
GO

-- 7. Bảng Metadata phục vụ High-Watermark Tracking
IF OBJECT_ID('audit.ETL_Metadata', 'U') IS NOT NULL DROP TABLE audit.ETL_Metadata;
CREATE TABLE audit.ETL_Metadata (
    table_name          VARCHAR(50) PRIMARY KEY,
    last_load_date      DATETIME2 NOT NULL,
    rows_inserted       BIGINT NULL DEFAULT 0,
    execution_status    VARCHAR(20) NOT NULL,
    updated_at          DATETIME2 NOT NULL DEFAULT SYSDATETIME()
);
PRINT '>> Da tao bang audit.ETL_Metadata';
GO

-- Khởi tạo mốc Watermark ban đầu
INSERT INTO audit.ETL_Metadata (table_name, last_load_date, rows_inserted, execution_status)
VALUES 
('Fact_Load', '2020-01-01 00:00:00', 0, 'INITIALIZED'),
('Fact_Trip', '2020-01-01 00:00:00', 0, 'INITIALIZED'),
('Fact_Maintenance', '2020-01-01 00:00:00', 0, 'INITIALIZED'),
('Fact_Delivery_Fulfillment', '2020-01-01 00:00:00', 0, 'INITIALIZED');
PRINT '>> Da nap moc High-Watermark ban dau vao audit.ETL_Metadata';
GO

