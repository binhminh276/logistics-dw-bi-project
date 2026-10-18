USE Logistics_Staging;
GO

IF OBJECT_ID('dbo.Stg_CDC_Customers', 'U') IS NOT NULL
    DROP TABLE dbo.Stg_CDC_Customers;
GO

CREATE TABLE dbo.Stg_CDC_Customers (
    customer_id NVARCHAR(20) NOT NULL,
    customer_name NVARCHAR(100) NULL,
    customer_type NVARCHAR(50) NULL,
    credit_terms_days INT NULL,
    primary_freight_type NVARCHAR(50) NULL,
    account_status NVARCHAR(20) NULL,
    contract_start_date DATE NULL,
    annual_revenue_potential DECIMAL(15,2) NULL,
    cdc_operation NVARCHAR(20) NULL,
    cdc_timestamp DATETIME NULL
);
GO