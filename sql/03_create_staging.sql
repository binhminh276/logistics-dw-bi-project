/*
================================================================================
ĐƯỜNG DẪN ĐÍCH: sql/03_create_staging.sql
MỤC ĐÍCH: DDL CSDL Logistics_Staging - Tầng đệm phục vụ nạp nhanh khối lượng lớn (Bulk Insert).
          Không đặt ràng buộc khóa ngoại (Foreign Keys) để tránh xung đột thứ tự nạp.
          Toàn bộ chuỗi sử dụng NVARCHAR (Unicode DT_WSTR) đồng bộ 100% với OLTP và DWH,
          loại bỏ hoàn toàn lỗi Code Page (1252 vs 1258) trong SSIS cho mọi thành viên nhóm.
NGÀY CẬP NHẬT: 2026-10-07
================================================================================
*/

USE master;
GO

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'Logistics_Staging')
BEGIN
    CREATE DATABASE Logistics_Staging;
END
GO

USE Logistics_Staging;
GO

-- ==============================================================================
-- 1. BẢNG ĐỆM CDC TỪ NGUỒN OLTP
-- ==============================================================================
DROP TABLE IF EXISTS Stg_CDC_Loads;
CREATE TABLE Stg_CDC_Loads (
    load_id NVARCHAR(50),
    customer_id NVARCHAR(50),
    route_id NVARCHAR(50),           -- Bổ sung để Lookup route_key cho Fact_Load
    origin_city NVARCHAR(100),
    origin_state NVARCHAR(20),
    destination_city NVARCHAR(100),
    destination_state NVARCHAR(20),
    booking_type NVARCHAR(50),
    load_type NVARCHAR(50),
    load_status NVARCHAR(50),
    load_date DATE,                  -- Đồng bộ DATE với OLTP loads.load_date
    weight_lbs INT,                  -- Đồng bộ INT với OLTP loads.weight_lbs
    pieces INT,
    revenue DECIMAL(14,2),
    fuel_surcharge DECIMAL(14,2),
    accessorial_charges DECIMAL(14,2),
    cdc_operation NVARCHAR(10),
    cdc_timestamp DATETIME DEFAULT GETDATE()
);

DROP TABLE IF EXISTS Stg_CDC_Trips;
CREATE TABLE Stg_CDC_Trips (
    trip_id NVARCHAR(50),
    load_id NVARCHAR(50),
    driver_id NVARCHAR(50),
    truck_id NVARCHAR(50),
    trailer_id NVARCHAR(50),
    dispatch_date DATE,              -- Đồng bộ DATE với OLTP trips.dispatch_date
    actual_distance_miles INT,       -- Đồng bộ INT với OLTP trips.actual_distance_miles
    actual_duration_hours DECIMAL(6,1), -- Đồng bộ DECIMAL(6,1) với OLTP trips.actual_duration_hours
    fuel_gallons_used DECIMAL(8,1),     -- Đồng bộ DECIMAL(8,1) với OLTP trips.fuel_gallons_used
    average_mpg DECIMAL(5,2),           -- Bổ sung theo đúng cấu trúc OLTP trips.average_mpg
    idle_time_hours DECIMAL(6,1),       -- Đồng bộ DECIMAL(6,1) với OLTP trips.idle_time_hours
    trip_status NVARCHAR(50),
    cdc_operation NVARCHAR(10),
    cdc_timestamp DATETIME DEFAULT GETDATE()
);

DROP TABLE IF EXISTS Stg_CDC_Drivers;
CREATE TABLE Stg_CDC_Drivers (
    driver_id NVARCHAR(50),
    first_name NVARCHAR(50),
    last_name NVARCHAR(50),
    cdl_class NVARCHAR(20),
    license_state NVARCHAR(20),
    license_number NVARCHAR(50),
    date_of_birth DATE,
    hire_date DATE,
    termination_date DATE,
    home_terminal NVARCHAR(50),
    employment_status NVARCHAR(30),
    years_experience TINYINT,        -- Đồng bộ TINYINT với OLTP drivers.years_experience
    cdc_operation NVARCHAR(10),
    cdc_timestamp DATETIME DEFAULT GETDATE()
);

-- ==============================================================================
-- 2. BẢNG ĐỆM NẠP TỪ FILE FLAT CSV
-- ==============================================================================
DROP TABLE IF EXISTS Stg_External_Facilities;
CREATE TABLE Stg_External_Facilities (
    facility_id NVARCHAR(50),
    facility_name NVARCHAR(150),
    facility_type NVARCHAR(50),
    city NVARCHAR(100),
    state NVARCHAR(20),
    latitude DECIMAL(9,6),
    longitude DECIMAL(9,6),
    dock_doors SMALLINT,             -- Đồng bộ SMALLINT với OLTP facilities.dock_doors
    operating_hours NVARCHAR(50)
);

DROP TABLE IF EXISTS Stg_External_Routes;
CREATE TABLE Stg_External_Routes (
    route_id NVARCHAR(50),
    origin_city NVARCHAR(100),
    origin_state NVARCHAR(20),
    destination_city NVARCHAR(100),
    destination_state NVARCHAR(20),
    typical_distance_miles INT,      -- Đồng bộ INT với OLTP routes.typical_distance_miles
    base_rate_per_mile DECIMAL(10,2),
    fuel_surcharge_rate DECIMAL(10,4),
    typical_transit_days TINYINT     -- Đồng bộ TINYINT với OLTP routes.typical_transit_days
);

DROP TABLE IF EXISTS Stg_External_Delivery_Events;
CREATE TABLE Stg_External_Delivery_Events (
    event_id NVARCHAR(50),
    load_id NVARCHAR(50),
    trip_id NVARCHAR(50),
    event_type NVARCHAR(50),
    facility_id NVARCHAR(50),
    scheduled_datetime DATETIME,
    actual_datetime DATETIME,
    detention_minutes INT,
    on_time_flag NVARCHAR(10),       -- Dạng chuỗi 'True'/'False' từ CSV để nạp an toàn
    location_city NVARCHAR(100),     -- Bổ sung khớp file CSV và bảng ánh xạ 07
    location_state NVARCHAR(20)      -- Bổ sung khớp file CSV và bảng ánh xạ 07
);

DROP TABLE IF EXISTS Stg_External_Maintenance;
CREATE TABLE Stg_External_Maintenance (
    maintenance_id NVARCHAR(50),
    truck_id NVARCHAR(50),
    maintenance_date DATE,
    maintenance_type NVARCHAR(50),
    odometer_reading INT,
    labor_hours DECIMAL(6,2),
    labor_cost DECIMAL(12,2),
    parts_cost DECIMAL(12,2),
    total_cost DECIMAL(14,2),        -- Bổ sung khớp file CSV và OLTP maintenance_records
    facility_location NVARCHAR(100),
    downtime_hours DECIMAL(8,2),
    service_description NVARCHAR(255)
);

-- ==============================================================================
-- 3. BẢNG ĐỆM DỮ LIỆU GIÁ DẦU TỪ WEB CRAWLER / REST API
-- ==============================================================================
DROP TABLE IF EXISTS Stg_Market_Fuel_Rates;
CREATE TABLE Stg_Market_Fuel_Rates (
    rate_date DATE,
    city NVARCHAR(100),
    state NVARCHAR(20),
    padd_region NVARCHAR(50),
    diesel_price_per_gallon DECIMAL(8,4),
    created_at DATETIME DEFAULT GETDATE()
);
GO