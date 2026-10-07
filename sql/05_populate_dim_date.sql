/*
================================================================================
ĐƯỜNG DẪN ĐÍCH: sql/05_populate_dim_date.sql
MỤC ĐÍCH: Nạp dữ liệu chiều thời gian Dim_Date từ 2020 đến 2030 và bản ghi -1.
NGÀY TẠO: 2026-10-06
================================================================================
*/

USE Logistics_DW;
GO

-- 1. Chèn bản ghi mặc định -1 (Pending / In-Flight)
IF NOT EXISTS (SELECT 1 FROM Dim_Date WHERE date_key = -1)
BEGIN
    INSERT INTO Dim_Date (date_key, full_date, day_of_week, day_name, month_number, month_name, calendar_quarter, calendar_year, fiscal_quarter, fiscal_year, is_weekend, holiday_flag)
    VALUES (-1, NULL, 0, N'In-Flight', 0, N'In-Flight', 0, 0, N'FQ-0', 0, 0, 0);
END;

-- 2. Sinh lịch tự động 2020 đến 2030
DECLARE @StartDate DATE = '2020-01-01';
DECLARE @EndDate DATE   = '2030-12-31';

WITH DateSequence AS (
    SELECT @StartDate AS CurrentDate
    UNION ALL
    SELECT DATEADD(DAY, 1, CurrentDate)
    FROM DateSequence
    WHERE CurrentDate < @EndDate
)
INSERT INTO Dim_Date (
    date_key,
    full_date,
    day_of_week,
    day_name,
    month_number,
    month_name,
    calendar_quarter,
    calendar_year,
    fiscal_quarter,
    fiscal_year,
    is_weekend,
    holiday_flag
)
SELECT 
    CAST(FORMAT(CurrentDate, 'yyyyMMdd') AS INT) AS date_key,
    CurrentDate AS full_date,
    DATEPART(WEEKDAY, CurrentDate) AS day_of_week,
    DATENAME(WEEKDAY, CurrentDate) AS day_name,
    DATEPART(MONTH, CurrentDate) AS month_number,
    DATENAME(MONTH, CurrentDate) AS month_name,
    DATEPART(QUARTER, CurrentDate) AS calendar_quarter,
    DATEPART(YEAR, CurrentDate) AS calendar_year,
    N'FQ' + CAST(DATEPART(QUARTER, CurrentDate) AS NVARCHAR(2)) AS fiscal_quarter,
    DATEPART(YEAR, CurrentDate) AS fiscal_year,
    CASE WHEN DATEPART(WEEKDAY, CurrentDate) IN (1, 7) THEN 1 ELSE 0 END AS is_weekend,
    -- Cờ ngày lễ cơ bản (New Year, US Independence Day, Christmas)
    CASE 
        WHEN (DATEPART(MONTH, CurrentDate) = 1 AND DATEPART(DAY, CurrentDate) = 1)
          OR (DATEPART(MONTH, CurrentDate) = 7 AND DATEPART(DAY, CurrentDate) = 4)
          OR (DATEPART(MONTH, CurrentDate) = 12 AND DATEPART(DAY, CurrentDate) = 25)
        THEN 1 ELSE 0 
    END AS holiday_flag
FROM DateSequence
OPTION (MAXRECURSION 0);
GO