/*
================================================================================
ĐƯỜNG DẪN ĐÍCH: sql/04_create_dwh.sql
MỤC ĐÍCH: DDL CSDL Logistics_DW - Kiến trúc Kimball Galaxy Schema gồm 9 Dimensions và 4 Facts.
          - Toàn bộ chuỗi sử dụng NVARCHAR (Unicode DT_WSTR) để triệt tiêu vĩnh viễn
            lỗi xung đột bảng mã Windows (Code Page 1252 vs 1258) trong Union All và OLE DB Command.
          - Đồng bộ chuẩn xác 100% kiểu số học với OLTP (SMALLINT, INT, TINYINT, BIGINT)
            để loại bỏ cảnh báo lệch kiểu trong SSIS SCD Wizard.
NGÀY CẬP NHẬT: 2026-10-07
================================================================================
*/

SET IMPLICIT_TRANSACTIONS OFF;
WHILE @@TRANCOUNT > 0 ROLLBACK TRANSACTION;
GO

USE master;
GO

-- 1. XÓA CSDL NẾU ĐÃ TẠO DỞ DANG
IF EXISTS (SELECT name FROM sys.databases WHERE name = 'Logistics_DW')
BEGIN
    ALTER DATABASE Logistics_DW SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE Logistics_DW;
END
GO

-- 2. TẠO LẠI CSDL LOGISTICS_DW
CREATE DATABASE Logistics_DW;
GO

USE Logistics_DW;
GO

-- ==============================================================================
-- PHẦN A: CÁC BẢNG DIMENSION (9 BẢNG)
-- ==============================================================================

-- 1. Dim_Date (Chiều thời gian)
CREATE TABLE Dim_Date (
    date_key INT PRIMARY KEY, -- YYYYMMDD hoặc -1
    full_date DATE NULL,
    day_of_week TINYINT NULL,
    day_name NVARCHAR(15) NULL,
    month_number TINYINT NULL,
    month_name NVARCHAR(15) NULL,
    calendar_quarter TINYINT NULL,
    calendar_year SMALLINT NULL,
    fiscal_quarter NVARCHAR(10) NULL,
    fiscal_year SMALLINT NULL,
    is_weekend BIT NULL,
    holiday_flag BIT NULL
);

-- 2. Dim_Customer (SCD Type 1 & 2)
CREATE TABLE Dim_Customer (
    customer_key INT IDENTITY(1,1) PRIMARY KEY,
    customer_id NVARCHAR(20) NOT NULL,
    customer_name NVARCHAR(100) NOT NULL,
    customer_type NVARCHAR(50),
    credit_terms_days TINYINT,               -- Đồng bộ TINYINT với OLTP customers.credit_terms_days
    primary_freight_type NVARCHAR(50),
    account_status NVARCHAR(20),
    contract_start_date DATE,
    annual_revenue_potential BIGINT,         -- Đồng bộ BIGINT với OLTP customers.annual_revenue_potential
    effective_date DATE NOT NULL,
    expiration_date DATE NULL,
    is_current BIT NOT NULL DEFAULT 1
);

-- 3. Dim_Driver (SCD Type 1 & 2)
CREATE TABLE Dim_Driver (
    driver_key INT IDENTITY(1,1) PRIMARY KEY,
    driver_id NVARCHAR(20) NOT NULL,
    first_name NVARCHAR(50),
    last_name NVARCHAR(50),
    full_name NVARCHAR(100),
    license_number NVARCHAR(50),
    license_state NVARCHAR(10),
    date_of_birth DATE,
    hire_date DATE,
    termination_date DATE,
    home_terminal NVARCHAR(50),
    employment_status NVARCHAR(20),
    cdl_class NVARCHAR(10),
    years_experience TINYINT,                -- Đồng bộ TINYINT với OLTP drivers.years_experience
    effective_date DATE NOT NULL,
    expiration_date DATE NULL,
    is_current BIT NOT NULL DEFAULT 1
);

-- 4. Dim_Truck (SCD Type 0, 1, 2)
CREATE TABLE Dim_Truck (
    truck_key INT IDENTITY(1,1) PRIMARY KEY,
    truck_id NVARCHAR(20) NOT NULL,          -- NVARCHAR (DT_WSTR) miễn nhiễm lỗi Code Page 1252/1258
    unit_number NVARCHAR(20),
    make NVARCHAR(50),
    model_year SMALLINT,                     -- Đồng bộ SMALLINT khớp OLTP trucks.model_year
    vin NVARCHAR(50),
    acquisition_date DATE,
    acquisition_mileage INT,                 -- Đồng bộ INT khớp OLTP trucks.acquisition_mileage
    fuel_type NVARCHAR(30),
    tank_capacity_gallons SMALLINT,          -- Đồng bộ SMALLINT khớp OLTP trucks.tank_capacity_gallons
    status NVARCHAR(50),
    home_terminal NVARCHAR(50),
    effective_date DATE NOT NULL,
    expiration_date DATE NULL,
    is_current BIT NOT NULL DEFAULT 1
);

-- 5. Dim_Trailer (SCD Type 0, 1, 2)
CREATE TABLE Dim_Trailer (
    trailer_key INT IDENTITY(1,1) PRIMARY KEY,
    trailer_id NVARCHAR(20) NOT NULL,
    trailer_number NVARCHAR(20),
    trailer_type NVARCHAR(50),
    length_feet TINYINT,                     -- Đồng bộ TINYINT khớp OLTP trailers.length_feet
    model_year SMALLINT,                     -- Đồng bộ SMALLINT khớp OLTP trailers.model_year
    vin NVARCHAR(50),
    acquisition_date DATE,
    status NVARCHAR(50),
    current_location NVARCHAR(50),
    effective_date DATE NOT NULL,
    expiration_date DATE NULL,
    is_current BIT NOT NULL DEFAULT 1
);

-- 6. Dim_Facility (Role-playing: Origin / Destination)
CREATE TABLE Dim_Facility (
    facility_key INT IDENTITY(1,1) PRIMARY KEY,
    facility_id NVARCHAR(20) NOT NULL,
    facility_name NVARCHAR(100) NOT NULL,
    facility_type NVARCHAR(50),
    city NVARCHAR(50),
    state NVARCHAR(10),
    latitude DECIMAL(9,6),
    longitude DECIMAL(9,6),
    dock_doors SMALLINT,                     -- Đồng bộ SMALLINT khớp OLTP facilities.dock_doors
    operating_hours NVARCHAR(50),
    effective_date DATE NOT NULL,
    expiration_date DATE NULL,
    is_current BIT NOT NULL DEFAULT 1
);

-- 7. Dim_Route (2 nhánh phân cấp Origin & Destination)
CREATE TABLE Dim_Route (
    route_key INT IDENTITY(1,1) PRIMARY KEY,
    route_id NVARCHAR(20) NOT NULL,
    origin_city NVARCHAR(50),
    origin_state NVARCHAR(10),
    destination_city NVARCHAR(50),
    destination_state NVARCHAR(10),
    typical_distance_miles INT,              -- Đồng bộ INT khớp OLTP routes.typical_distance_miles
    base_rate_per_mile DECIMAL(10,2),
    fuel_surcharge_rate DECIMAL(10,4),
    typical_transit_days TINYINT             -- Đồng bộ TINYINT khớp OLTP routes.typical_transit_days
);

-- 8. Dim_Load_Profile (Khóa surrogate SMALLINT hỗ trợ bản ghi -1)
CREATE TABLE Dim_Load_Profile (
    load_profile_key SMALLINT IDENTITY(1,1) PRIMARY KEY,
    load_status NVARCHAR(30) NOT NULL,
    booking_type NVARCHAR(30) NOT NULL,
    load_type NVARCHAR(30) NOT NULL
);

-- 9. Dim_Maintenance_Profile (Khóa surrogate SMALLINT hỗ trợ bản ghi -1)
CREATE TABLE Dim_Maintenance_Profile (
    maintenance_profile_key SMALLINT IDENTITY(1,1) PRIMARY KEY,
    maintenance_type NVARCHAR(50) NOT NULL,
    service_urgency NVARCHAR(30) NOT NULL
);

-- ==============================================================================
-- PHẦN B: CÁC BẢNG FACT (4 BẢNG CHUẨN GALAXY)
-- ==============================================================================

-- 1. Fact_Load (Transaction Fact)
CREATE TABLE Fact_Load (
    load_date_key INT NOT NULL,
    customer_key INT NOT NULL,
    route_key INT NOT NULL,
    load_profile_key SMALLINT NOT NULL,
    load_id NVARCHAR(50) NOT NULL,
    weight_lbs INT,                          -- Đồng bộ INT với OLTP loads.weight_lbs
    pieces INT,
    revenue DECIMAL(14,2),
    fuel_surcharge DECIMAL(14,2),
    accessorial_charges DECIMAL(14,2),
    total_revenue DECIMAL(14,2),
    load_count INT DEFAULT 1,
    CONSTRAINT FK_FactLoad_Date FOREIGN KEY (load_date_key) REFERENCES Dim_Date(date_key),
    CONSTRAINT FK_FactLoad_Customer FOREIGN KEY (customer_key) REFERENCES Dim_Customer(customer_key),
    CONSTRAINT FK_FactLoad_Route FOREIGN KEY (route_key) REFERENCES Dim_Route(route_key),
    CONSTRAINT FK_FactLoad_Profile FOREIGN KEY (load_profile_key) REFERENCES Dim_Load_Profile(load_profile_key)
);

-- 2. Fact_Trip (Transaction Fact)
CREATE TABLE Fact_Trip (
    dispatch_date_key INT NOT NULL,
    driver_key INT NOT NULL,
    truck_key INT NOT NULL,
    trailer_key INT NOT NULL,
    trip_id NVARCHAR(50) NOT NULL,
    load_id NVARCHAR(50),
    trip_status NVARCHAR(30),
    actual_distance_miles INT,               -- Đồng bộ INT với OLTP trips.actual_distance_miles
    actual_duration_hours DECIMAL(6,1),      -- Đồng bộ DECIMAL(6,1) với OLTP trips.actual_duration_hours
    fuel_gallons_used DECIMAL(8,1),          -- Đồng bộ DECIMAL(8,1) với OLTP trips.fuel_gallons_used
    idle_time_hours DECIMAL(6,1),            -- Đồng bộ DECIMAL(6,1) với OLTP trips.idle_time_hours
    trip_count INT DEFAULT 1,
    CONSTRAINT FK_FactTrip_Date FOREIGN KEY (dispatch_date_key) REFERENCES Dim_Date(date_key),
    CONSTRAINT FK_FactTrip_Driver FOREIGN KEY (driver_key) REFERENCES Dim_Driver(driver_key),
    CONSTRAINT FK_FactTrip_Truck FOREIGN KEY (truck_key) REFERENCES Dim_Truck(truck_key),
    CONSTRAINT FK_FactTrip_Trailer FOREIGN KEY (trailer_key) REFERENCES Dim_Trailer(trailer_key)
);

-- 3. Fact_Delivery_Fulfillment (Accumulating Snapshot Fact)
CREATE TABLE Fact_Delivery_Fulfillment (
    pickup_date_key INT NOT NULL,
    delivery_date_key INT NOT NULL, -- -1 nếu In-Flight
    origin_facility_key INT NOT NULL,
    destination_facility_key INT NOT NULL,
    customer_key INT NOT NULL,
    route_key INT NOT NULL,
    load_profile_key SMALLINT NOT NULL,
    load_id NVARCHAR(50) NOT NULL,
    trip_id NVARCHAR(50),
    pickup_event_id NVARCHAR(50),
    delivery_event_id NVARCHAR(50),
    pickup_detention_minutes INT DEFAULT 0,
    delivery_detention_minutes INT DEFAULT 0,
    total_detention_minutes INT DEFAULT 0,
    transit_duration_hours DECIMAL(10,2) NULL,
    pickup_on_time_count INT DEFAULT 0,
    delivery_on_time_count INT DEFAULT 0,
    perfect_fulfillment_count INT DEFAULT 0,
    total_fulfillment_count INT DEFAULT 1,
    completed_fulfillment_count INT DEFAULT 0,
    CONSTRAINT FK_FactDeliv_PickupDate FOREIGN KEY (pickup_date_key) REFERENCES Dim_Date(date_key),
    CONSTRAINT FK_FactDeliv_DeliveryDate FOREIGN KEY (delivery_date_key) REFERENCES Dim_Date(date_key),
    CONSTRAINT FK_FactDeliv_OriginFacility FOREIGN KEY (origin_facility_key) REFERENCES Dim_Facility(facility_key),
    CONSTRAINT FK_FactDeliv_DestFacility FOREIGN KEY (destination_facility_key) REFERENCES Dim_Facility(facility_key),
    CONSTRAINT FK_FactDeliv_Customer FOREIGN KEY (customer_key) REFERENCES Dim_Customer(customer_key),
    CONSTRAINT FK_FactDeliv_Route FOREIGN KEY (route_key) REFERENCES Dim_Route(route_key),
    CONSTRAINT FK_FactDeliv_Profile FOREIGN KEY (load_profile_key) REFERENCES Dim_Load_Profile(load_profile_key)
);

-- 4. Fact_Maintenance (Transaction Fact)
CREATE TABLE Fact_Maintenance (
    maintenance_date_key INT NOT NULL,
    truck_key INT NOT NULL,
    maintenance_profile_key SMALLINT NOT NULL,
    maintenance_id NVARCHAR(50) NOT NULL,
    facility_location NVARCHAR(50) NOT NULL, -- Degenerate Dimension
    odometer_reading INT,
    labor_hours DECIMAL(6,2),
    labor_cost DECIMAL(12,2),
    parts_cost DECIMAL(12,2),
    total_maintenance_cost DECIMAL(14,2),
    downtime_hours DECIMAL(8,2),
    maintenance_count INT DEFAULT 1,
    CONSTRAINT FK_FactMaint_Date FOREIGN KEY (maintenance_date_key) REFERENCES Dim_Date(date_key),
    CONSTRAINT FK_FactMaint_Truck FOREIGN KEY (truck_key) REFERENCES Dim_Truck(truck_key),
    CONSTRAINT FK_FactMaint_Profile FOREIGN KEY (maintenance_profile_key) REFERENCES Dim_Maintenance_Profile(maintenance_profile_key)
);

-- ==============================================================================
-- PHẦN C: KHỞI TẠO BẢN GHI MẶC ĐỊNH -1 CHO CÁC BẢNG DIMENSION
-- ==============================================================================
SET IDENTITY_INSERT Dim_Customer ON;
INSERT INTO Dim_Customer (customer_key, customer_id, customer_name, customer_type, credit_terms_days, primary_freight_type, account_status, contract_start_date, annual_revenue_potential, effective_date, expiration_date, is_current)
VALUES (-1, N'UNKNOWN', N'Unknown Customer', N'Unknown', 0, N'Unknown', N'Active', '1900-01-01', 0, '1900-01-01', NULL, 1);
SET IDENTITY_INSERT Dim_Customer OFF;

SET IDENTITY_INSERT Dim_Driver ON;
INSERT INTO Dim_Driver (driver_key, driver_id, first_name, last_name, full_name, license_number, license_state, date_of_birth, hire_date, termination_date, home_terminal, employment_status, cdl_class, years_experience, effective_date, expiration_date, is_current)
VALUES (-1, N'UNASSIGNED', N'Unassigned', N'Driver', N'Unassigned Driver', N'N/A', N'N/A', '1900-01-01', '1900-01-01', NULL, N'N/A', N'Unknown', N'N/A', 0, '1900-01-01', NULL, 1);
SET IDENTITY_INSERT Dim_Driver OFF;

SET IDENTITY_INSERT Dim_Truck ON;
INSERT INTO Dim_Truck (truck_key, truck_id, unit_number, make, model_year, vin, acquisition_date, acquisition_mileage, fuel_type, tank_capacity_gallons, status, home_terminal, effective_date, expiration_date, is_current)
VALUES (-1, N'UNASSIGNED', N'Unknown Unit', N'Unknown', 1900, N'N/A', '1900-01-01', 0, N'Diesel', 0, N'Unknown', N'N/A', '1900-01-01', NULL, 1);
SET IDENTITY_INSERT Dim_Truck OFF;

SET IDENTITY_INSERT Dim_Trailer ON;
INSERT INTO Dim_Trailer (trailer_key, trailer_id, trailer_number, trailer_type, length_feet, model_year, vin, acquisition_date, status, current_location, effective_date, expiration_date, is_current)
VALUES (-1, N'UNASSIGNED', N'Unknown Trailer', N'Unknown', 0, 1900, N'N/A', '1900-01-01', N'Unknown', N'N/A', '1900-01-01', NULL, 1);
SET IDENTITY_INSERT Dim_Trailer OFF;

SET IDENTITY_INSERT Dim_Facility ON;
INSERT INTO Dim_Facility (facility_key, facility_id, facility_name, facility_type, city, state, latitude, longitude, dock_doors, operating_hours, effective_date, expiration_date, is_current)
VALUES (-1, N'UNKNOWN', N'Unknown Facility', N'Unknown', N'Unknown', N'NA', 0, 0, 0, N'Unknown', '1900-01-01', NULL, 1);
SET IDENTITY_INSERT Dim_Facility OFF;

SET IDENTITY_INSERT Dim_Route ON;
INSERT INTO Dim_Route (route_key, route_id, origin_city, origin_state, destination_city, destination_state, typical_distance_miles, base_rate_per_mile, fuel_surcharge_rate, typical_transit_days)
VALUES (-1, N'UNKNOWN', N'Unknown', N'NA', N'Unknown', N'NA', 0, 0, 0, 0);
SET IDENTITY_INSERT Dim_Route OFF;

SET IDENTITY_INSERT Dim_Load_Profile ON;
INSERT INTO Dim_Load_Profile (load_profile_key, load_status, booking_type, load_type)
VALUES (-1, N'Unknown', N'Unknown', N'Unknown');
SET IDENTITY_INSERT Dim_Load_Profile OFF;

SET IDENTITY_INSERT Dim_Maintenance_Profile ON;
INSERT INTO Dim_Maintenance_Profile (maintenance_profile_key, maintenance_type, service_urgency)
VALUES (-1, N'Unknown', N'Unspecified');
SET IDENTITY_INSERT Dim_Maintenance_Profile OFF;
GO