USE Logistics_Staging;
GO

-- 1. Tao bang Stg_CDC_Customers
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

-- 2. Tao bang Stg_CDC_Trucks
IF OBJECT_ID('dbo.Stg_CDC_Trucks', 'U') IS NOT NULL
    DROP TABLE dbo.Stg_CDC_Trucks;
GO

CREATE TABLE dbo.Stg_CDC_Trucks (
    truck_id NVARCHAR(20) NOT NULL,
    unit_number NVARCHAR(20) NULL,
    make NVARCHAR(50) NULL,
    model_year INT NULL,
    vin NVARCHAR(50) NULL,
    acquisition_date DATE NULL,
    acquisition_mileage DECIMAL(12,2) NULL,
    fuel_type NVARCHAR(30) NULL,
    tank_capacity_gallons DECIMAL(10,2) NULL,
    status NVARCHAR(50) NULL,
    home_terminal NVARCHAR(50) NULL,
    cdc_operation NVARCHAR(20) NULL,
    cdc_timestamp DATETIME NULL
);
GO

-- 3. Tao bang Stg_CDC_Trailers
IF OBJECT_ID('dbo.Stg_CDC_Trailers', 'U') IS NOT NULL
    DROP TABLE dbo.Stg_CDC_Trailers;
GO

CREATE TABLE dbo.Stg_CDC_Trailers (
    trailer_id NVARCHAR(20) NOT NULL,
    trailer_number NVARCHAR(20) NULL,
    trailer_type NVARCHAR(50) NULL,
    length_feet INT NULL,
    model_year INT NULL,
    vin NVARCHAR(50) NULL,
    acquisition_date DATE NULL,
    status NVARCHAR(50) NULL,
    current_location NVARCHAR(50) NULL,
    cdc_operation NVARCHAR(20) NULL,
    cdc_timestamp DATETIME NULL
);
GO