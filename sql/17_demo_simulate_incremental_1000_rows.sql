USE [Logistics_OLTP];
GO

PRINT '======================================================================';
PRINT 'BUOC 1: KIEM TRA SO DONG HIEN TAI TRUOC KHI GIA LAP PHAT SINH MOI';
PRINT '======================================================================';

SELECT 'OLTP.dbo.loads' AS TableName, COUNT(*) AS CurrentRowCount, MIN(load_date) AS MinDate, MAX(load_date) AS MaxDate FROM Logistics_OLTP.dbo.loads
UNION ALL
SELECT 'OLTP.dbo.trips' AS TableName, COUNT(*) AS CurrentRowCount, MIN(dispatch_date) AS MinDate, MAX(dispatch_date) AS MaxDate FROM Logistics_OLTP.dbo.trips
UNION ALL
SELECT 'DWH.dbo.Fact_Load' AS TableName, COUNT(*) AS CurrentRowCount, NULL, NULL FROM Logistics_DW.dbo.Fact_Load
UNION ALL
SELECT 'DWH.dbo.Fact_Trip' AS TableName, COUNT(*) AS CurrentRowCount, NULL, NULL FROM Logistics_DW.dbo.Fact_Trip;
GO

PRINT '======================================================================';
PRINT 'BUOC 2: TIEN HANH GIA LAP NAP DU LIEU THANG 8, 9, 10 / 2023 VAO OLTP';
PRINT '======================================================================';

DECLARE @StartDate DATE = '2023-08-01';
DECLARE @EndDate   DATE = '2023-10-31';

IF EXISTS (SELECT 1 FROM dbo.loads WHERE load_date >= @StartDate AND load_date <= @EndDate)
BEGIN
    PRINT 'Du lieu giai doan tu ' + CONVERT(VARCHAR(10), @StartDate) + ' den ' + CONVERT(VARCHAR(10), @EndDate) + ' da ton tai trong OLTP.';
    PRINT 'Chay BUOC 4 neu muon reset de dien tap lai.';
END
ELSE
BEGIN
    PRINT '[1/4] Dang tao bang tam va BULK INSERT tu file loads.csv...';
    
    IF OBJECT_ID('tempdb..#stg_loads') IS NOT NULL DROP TABLE #stg_loads;
    CREATE TABLE #stg_loads (
        load_id NVARCHAR(50),
        customer_id NVARCHAR(50),
        route_id NVARCHAR(50),
        load_date DATE,
        load_type NVARCHAR(50),
        weight_lbs INT,
        pieces INT,
        revenue DECIMAL(18,2),
        fuel_surcharge DECIMAL(18,2),
        accessorial_charges DECIMAL(18,2),
        load_status NVARCHAR(50),
        booking_type NVARCHAR(50)
    );

    BULK INSERT #stg_loads
    FROM 'D:\KHO_DU_LIEU\CODE\DACK\logistics-dw-bi-project\data\raw\loads.csv'
    WITH (
        FIRSTROW = 2,
        FIELDTERMINATOR = ',',
        ROWTERMINATOR = '0x0a',
        CODEPAGE = '65001',
        KEEPNULLS
    );

    PRINT '[2/4] Dang tao bang tam va BULK INSERT tu file trips.csv...';

    IF OBJECT_ID('tempdb..#stg_trips') IS NOT NULL DROP TABLE #stg_trips;
    CREATE TABLE #stg_trips (
        trip_id NVARCHAR(50),
        load_id NVARCHAR(50),
        driver_id NVARCHAR(50),
        truck_id NVARCHAR(50),
        trailer_id NVARCHAR(50),
        dispatch_date DATE,
        actual_distance_miles INT,
        actual_duration_hours DECIMAL(10,2),
        fuel_gallons_used DECIMAL(10,2),
        average_mpg DECIMAL(10,2),
        idle_time_hours DECIMAL(10,2),
        trip_status NVARCHAR(50)
    );

    BULK INSERT #stg_trips
    FROM 'D:\KHO_DU_LIEU\CODE\DACK\logistics-dw-bi-project\data\raw\trips.csv'
    WITH (
        FIRSTROW = 2,
        FIELDTERMINATOR = ',',
        ROWTERMINATOR = '0x0a',
        CODEPAGE = '65001',
        KEEPNULLS
    );

    BEGIN TRANSACTION;

    PRINT '[3/4] Dang nap don hang vao Logistics_OLTP.dbo.loads...';
    INSERT INTO dbo.loads (
        load_id,
        customer_id,
        route_id,
        load_date,
        load_type, 
        weight_lbs,
        pieces,
        revenue,
        fuel_surcharge,
        accessorial_charges, 
        load_status,
        booking_type
    )
    SELECT 
        TRIM(REPLACE(REPLACE(load_id, CHAR(13), ''), CHAR(10), '')),
        TRIM(REPLACE(REPLACE(customer_id, CHAR(13), ''), CHAR(10), '')),
        TRIM(REPLACE(REPLACE(route_id, CHAR(13), ''), CHAR(10), '')),
        load_date,
        TRIM(REPLACE(REPLACE(load_type, CHAR(13), ''), CHAR(10), '')),
        weight_lbs,
        pieces,
        revenue,
        fuel_surcharge,
        accessorial_charges,
        TRIM(REPLACE(REPLACE(load_status, CHAR(13), ''), CHAR(10), '')),
        TRIM(REPLACE(REPLACE(booking_type, CHAR(13), ''), CHAR(10), ''))
    FROM #stg_loads
    WHERE load_date >= @StartDate AND load_date <= @EndDate
      AND NOT EXISTS (
          SELECT 1 
          FROM dbo.loads l 
          WHERE l.load_id = TRIM(REPLACE(REPLACE(#stg_loads.load_id, CHAR(13), ''), CHAR(10), ''))
      );

    DECLARE @LoadsInserted INT = @@ROWCOUNT;

    PRINT '[4/4] Dang nap chuyen xe vao Logistics_OLTP.dbo.trips...';
    INSERT INTO dbo.trips (
        trip_id,
        load_id,
        driver_id,
        truck_id,
        trailer_id,
        dispatch_date,
        actual_distance_miles,
        actual_duration_hours,
        fuel_gallons_used, 
        average_mpg,
        idle_time_hours,
        trip_status
    )
    SELECT 
        TRIM(REPLACE(REPLACE(trip_id, CHAR(13), ''), CHAR(10), '')),
        TRIM(REPLACE(REPLACE(load_id, CHAR(13), ''), CHAR(10), '')),
        NULLIF(TRIM(REPLACE(REPLACE(driver_id, CHAR(13), ''), CHAR(10), '')), ''),
        NULLIF(TRIM(REPLACE(REPLACE(truck_id, CHAR(13), ''), CHAR(10), '')), ''),
        NULLIF(TRIM(REPLACE(REPLACE(trailer_id, CHAR(13), ''), CHAR(10), '')), ''),
        dispatch_date,
        actual_distance_miles,
        actual_duration_hours,
        fuel_gallons_used, 
        average_mpg,
        idle_time_hours,
        TRIM(REPLACE(REPLACE(trip_status, CHAR(13), ''), CHAR(10), ''))
    FROM #stg_trips
    WHERE dispatch_date >= @StartDate AND dispatch_date <= @EndDate
      AND NOT EXISTS (
          SELECT 1 
          FROM dbo.trips t 
          WHERE t.trip_id = TRIM(REPLACE(REPLACE(#stg_trips.trip_id, CHAR(13), ''), CHAR(10), ''))
      );

    DECLARE @TripsInserted INT = @@ROWCOUNT;

    COMMIT TRANSACTION;

    DROP TABLE #stg_loads;
    DROP TABLE #stg_trips;

    PRINT '----------------------------------------------------------------------';
    PRINT 'DA NAP TANG TRUONG VAO HE THONG OLTP:';
    PRINT '   + Don hang moi (loads): ' + CAST(@LoadsInserted AS VARCHAR(10)) + ' dong';
    PRINT '   + Chuyen xe moi (trips): ' + CAST(@TripsInserted AS VARCHAR(10)) + ' dong';
    PRINT '----------------------------------------------------------------------';
END
GO

PRINT '======================================================================';
PRINT 'BUOC 3: KIEM TRA DOI SOAT';
PRINT '======================================================================';

SELECT 'OLTP.dbo.loads' AS TableName, COUNT(*) AS CurrentRowCount, MAX(load_date) AS MaxDate FROM Logistics_OLTP.dbo.loads
UNION ALL
SELECT 'OLTP.dbo.trips' AS TableName, COUNT(*) AS CurrentRowCount, MAX(dispatch_date) AS MaxDate FROM Logistics_OLTP.dbo.trips
UNION ALL
SELECT 'DWH.dbo.Fact_Load' AS TableName, COUNT(*) AS CurrentRowCount, NULL FROM Logistics_DW.dbo.Fact_Load
UNION ALL
SELECT 'DWH.dbo.Fact_Trip' AS TableName, COUNT(*) AS CurrentRowCount, NULL FROM Logistics_DW.dbo.Fact_Trip
UNION ALL
SELECT 'Audit.Package_Log (Fact_Load)', inserted_row_count, NULL 
FROM Logistics_Staging.audit.Package_Log 
WHERE package_name = 'Fact_Load.dtsx' 
  AND package_log_id = (SELECT MAX(package_log_id) FROM Logistics_Staging.audit.Package_Log WHERE package_name = 'Fact_Load.dtsx');
GO

PRINT '======================================================================';
PRINT 'BUOC 4: LENH RESET';
PRINT '======================================================================';

/*
BEGIN TRANSACTION;
DELETE FROM Logistics_OLTP.dbo.trips WHERE dispatch_date >= '2023-08-01';
DELETE FROM Logistics_OLTP.dbo.loads WHERE load_date >= '2023-08-01';
DELETE FROM Logistics_DW.dbo.Fact_Trip WHERE dispatch_date_key >= 20230801;
DELETE FROM Logistics_DW.dbo.Fact_Load WHERE load_date_key >= 20230801;
COMMIT TRANSACTION;
*/
GO