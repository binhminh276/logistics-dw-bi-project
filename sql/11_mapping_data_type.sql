-- 1. Dong bo tai CSDL Logistics_Staging
USE Logistics_Staging;
GO
ALTER TABLE dbo.Stg_CDC_Customers 
ALTER COLUMN annual_revenue_potential DECIMAL(15,2) NULL;
GO

-- 2. Dong bo tai CSDL Logistics_DW
USE Logistics_DW;
GO
ALTER TABLE dbo.Dim_Customer 
ALTER COLUMN annual_revenue_potential DECIMAL(15,2) NULL;
GO

-- 1. Chuyen cot o CSDL DWH ve kieu INT
USE Logistics_DW;
GO
ALTER TABLE dbo.Dim_Customer 
ALTER COLUMN credit_terms_days INT NULL;
GO

-- 2. Dam bao cot o CSDL Staging cung la kieu INT
USE Logistics_Staging;
GO
ALTER TABLE dbo.Stg_CDC_Customers 
ALTER COLUMN credit_terms_days INT NULL;
GO