-- Chuẩn bị
UPDATE Fact_Trip
SET truck_key = (ABS(CHECKSUM(NEWID())) % 120) + 1
WHERE truck_key = -1;

UPDATE Fact_Delivery_Fulfillment
SET customer_key = (ABS(CHECKSUM(NEWID())) % 100) + 1
WHERE customer_key = -1;

UPDATE Fact_Trip
SET trailer_key = (ABS(CHECKSUM(NEWID())) % 50) + 1
WHERE trailer_key = -1;

-- Phân tích hiệu suất nhiên liệu (MPG) theo Hãng xe qua các năm
SELECT 
    d.calendar_year AS CalendarYear, 
    t.make AS TruckMake, 
    SUM(f.actual_distance_miles) AS TotalDistance,
    SUM(f.fuel_gallons_used) AS TotalFuel,
    CAST(SUM(f.actual_distance_miles) * 1.0 / NULLIF(SUM(f.fuel_gallons_used), 0) AS DECIMAL(10,2)) AS MilesPerGallon
FROM Fact_Trip f
JOIN Dim_Date d ON f.dispatch_date_key = d.date_key
JOIN Dim_Truck t ON f.truck_key = t.truck_key
GROUP BY ROLLUP(d.calendar_year, t.make)
ORDER BY d.calendar_year DESC, MilesPerGallon DESC;

-- Theo dõi xu hướng lưu bãi bằng Trung bình trượt (Moving Average)
WITH FacilityDetention AS (
    SELECT 
        fac.facility_name,
        d.calendar_year,
        d.month_number,
        SUM(f.pickup_detention_minutes) AS TotalPickupDetention
    FROM Fact_Delivery_Fulfillment f
    JOIN Dim_Facility fac ON f.origin_facility_key = fac.facility_key
    JOIN Dim_Date d ON f.pickup_date_key = d.date_key
    GROUP BY fac.facility_name, d.calendar_year, d.month_number
)
SELECT 
    facility_name, 
    calendar_year, 
    month_number, 
    TotalPickupDetention,
    AVG(TotalPickupDetention) OVER (
        PARTITION BY facility_name 
        ORDER BY calendar_year, month_number 
        ROWS BETWEEN 2 PRECEDING AND CURRENT ROW
    ) AS MovingAvg_3Month_Detention
FROM FacilityDetention;
