USE [Logistics_DW];
GO

SELECT
    dr.route_id,
    dr.origin_city,
    dr.origin_state,
    dr.destination_city,
    dr.destination_state,
    dr.typical_distance_miles,
    COUNT(fl.load_id) AS total_loads,
    SUM(fl.weight_lbs) AS total_weight_lbs,
    SUM(fl.revenue) AS total_base_revenue,
    SUM(fl.fuel_surcharge) AS total_fuel_surcharge,
    SUM(fl.accessorial_charges) AS total_accessorial_charges,
    SUM(fl.total_revenue) AS total_revenue,
    ROUND(SUM(fl.total_revenue) / NULLIF(SUM(fl.weight_lbs), 0), 4) AS revenue_per_pound,
    ROUND(SUM(fl.revenue) * 100.0 / NULLIF(SUM(fl.total_revenue), 0), 2) AS base_revenue_pct,
    ROUND(SUM(fl.fuel_surcharge) * 100.0 / NULLIF(SUM(fl.total_revenue), 0), 2) AS fuel_surcharge_pct
FROM dbo.Fact_Load fl
JOIN dbo.Dim_Route dr 
    ON fl.route_key = dr.route_key
GROUP BY
    dr.route_key,
    dr.route_id,
    dr.origin_city,
    dr.origin_state,
    dr.destination_city,
    dr.destination_state,
    dr.typical_distance_miles
ORDER BY
    total_revenue DESC;
GO