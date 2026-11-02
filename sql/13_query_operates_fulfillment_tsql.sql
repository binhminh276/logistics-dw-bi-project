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
-- Mục tiêu: Đánh giá dòng xe của hãng nào tiết kiệm nhiên liệu nhất qua từng năm
SELECT 
    ISNULL(CAST(d.calendar_year AS VARCHAR(4)), 'Grand Total') AS CalendarYear, 
    ISNULL(t.make, 'All Makes') AS TruckMake, 
    SUM(f.actual_distance_miles) AS TotalDistance,
    SUM(f.fuel_gallons_used) AS TotalFuel,
    CAST(SUM(f.actual_distance_miles) * 1.0 / NULLIF(SUM(f.fuel_gallons_used), 0) AS DECIMAL(10,2)) AS MilesPerGallon
FROM Logistics_DW.dbo.Fact_Trip f
JOIN Logistics_DW.dbo.Dim_Date d ON f.dispatch_date_key = d.date_key
JOIN Logistics_DW.dbo.Dim_Truck t ON f.truck_key = t.truck_key
GROUP BY ROLLUP(d.calendar_year, t.make)
ORDER BY d.calendar_year DESC, MilesPerGallon DESC;

-- Đánh giá Tỷ lệ Giao hàng Đúng giờ (SLA Compliance) & Nút thắt Kho bãi
-- Mục tiêu: Tìm ra những khách hàng có tỷ lệ được giao hàng đúng giờ thấp nhất (rủi ro mất khách cao).
SELECT 
    c.customer_name,
    SUM(f.total_fulfillment_count) AS TotalDeliveries,
    SUM(f.delivery_on_time_count) AS OnTimeDeliveries,
    CAST(SUM(f.delivery_on_time_count) * 100.0 / NULLIF(SUM(f.total_fulfillment_count), 0) AS DECIMAL(5,2)) AS OnTimePct
FROM Logistics_DW.dbo.Fact_Delivery_Fulfillment f
JOIN Logistics_DW.dbo.Dim_Customer c ON f.customer_key = c.customer_key
WHERE f.total_fulfillment_count > 0 
GROUP BY c.customer_name
HAVING SUM(f.total_fulfillment_count) > 50 -- Bỏ qua các khách hàng nhỏ lẻ
ORDER BY OnTimePct ASC;

-- Phân tích Nút thắt Kho bãi - Điểm nóng kẹt xe (Detention Analysis)
-- Mục tiêu: Phát hiện các Kho (Facility) có thời gian ngâm xe (Detention Minutes) cao nhất, làm giảm vòng quay đầu xe.
SELECT TOP 10
    fac.facility_name AS DestinationFacility,
    SUM(f.total_fulfillment_count) AS TotalTripsArrived,
    SUM(f.delivery_detention_minutes) AS TotalDetentionMinutes,
    CAST(SUM(f.delivery_detention_minutes) * 1.0 / NULLIF(SUM(f.total_fulfillment_count), 0) AS DECIMAL(10,2)) AS AvgDetentionMinPerTrip
FROM Logistics_DW.dbo.Fact_Delivery_Fulfillment f
JOIN Logistics_DW.dbo.Dim_Facility fac ON f.destination_facility_key = fac.facility_key
GROUP BY fac.facility_name
ORDER BY AvgDetentionMinPerTrip DESC;

-- Đánh giá chất lượng toàn trình (Perfect Fulfillment Rate) theo Tuyến đường (Route)
-- Mục tiêu: Đánh giá tuyến đường nào (Origin $\rightarrow$ Destination) vận hành trơn tru nhất (Giao đúng giờ, không rớt hàng).
SELECT TOP 10
    r.origin_city + ', ' + r.origin_state AS Origin,
    r.destination_city + ', ' + r.destination_state AS Destination,
    SUM(f.total_fulfillment_count) AS TotalShipments,
    SUM(f.perfect_fulfillment_count) AS PerfectShipments,
    CAST(SUM(f.perfect_fulfillment_count) * 100.0 / NULLIF(SUM(f.total_fulfillment_count), 0) AS DECIMAL(5,2)) AS PerfectFulfillmentPct
FROM Logistics_DW.dbo.Fact_Delivery_Fulfillment f
JOIN Logistics_DW.dbo.Dim_Route r ON f.route_key = r.route_key
GROUP BY r.origin_city, r.origin_state, r.destination_city, r.destination_state
HAVING SUM(f.total_fulfillment_count) > 20 -- Chỉ xét tuyến chạy thường xuyên
ORDER BY PerfectFulfillmentPct DESC;