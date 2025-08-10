-- Count how many charging stations are operational vs non-operational
SELECT 
  is_operational,
  COUNT(*) AS station_count
FROM stations
GROUP BY is_operational;


-- Find the top 5 cities with the most charging stations
SELECT city, COUNT(station_id) AS No_of_charging_stations
FROM stations
GROUP BY city
ORDER BY COUNT(station_id) DESC
LIMIT 5;


-- Calculate the percentage of stations operated by each company
SELECT
    operator,
    COUNT(*) AS station_count,
    ROUND(COUNT(*)::numeric / (SELECT COUNT(*) FROM stations) * 100, 2) AS percentage_of_total_stations
FROM stations
WHERE operator IS NOT NULL
GROUP BY operator
ORDER BY percentage_of_total_stations DESC;


-- Find the average AC charging price per kWh by operator (excluding free stations)
SELECT
   operator,
   ROUND(AVG(ac_price_huf_kwh), 2) AS average_ac_price_per_kWh
FROM stations
WHERE is_free = FALSE AND ac_price_huf_kwh IS NOT NULL
GROUP BY operator
ORDER BY average_ac_price_per_kWh DESC;


-- Count how many stations were added each month (based on creation_date)
SELECT
    DATE_TRUNC('month', creation_date) AS month,
    COUNT(*) AS stations_added
FROM stations
WHERE creation_date IS NOT NULL
GROUP BY month
ORDER BY month;


-- Find the distribution of charging points per station
SELECT
    num_charging_points,
    COUNT(*) AS station_count
FROM stations
WHERE num_charging_points IS NOT NULL
GROUP BY num_charging_points
ORDER BY num_charging_points;


-- Calculate stations per 1000 km² in each county (approximate)
SELECT
    county,
    COUNT(*) AS station_count,
    ROUND(COUNT(*)::numeric / (SELECT COUNT(*) FROM stations) * 1000, 0) AS stations_per_1000_km2
FROM stations
GROUP BY county
ORDER BY stations_per_1000_km2 DESC;


-- Identify stations with potentially missing or inconsistent data
SELECT 
  station_id,
  city,
  operator,
  CASE 
    WHEN is_free = FALSE AND ac_price_huf_kwh IS NULL THEN 'Missing price'
    WHEN is_operational IS NULL THEN 'Missing operational status'
    WHEN num_charging_points IS NULL THEN 'Missing charging points count'
    WHEN last_verified_date < creation_date THEN 'Verification before creation'
    ELSE 'Other issue'
  END AS data_issue
FROM stations
WHERE 
  (is_free = FALSE AND ac_price_huf_kwh IS NULL) OR
  is_operational IS NULL OR
  num_charging_points IS NULL OR
  last_verified_date < creation_date;


-- Find nearest charging stations to a given location

-- Budapest center
WITH user_location AS (
    SELECT ST_SetSRID(ST_MakePoint(19.0402, 47.4979), 4326) AS user_point
    -- EPSG:4326 refers to WGS84 geographic coordinates (latitude/longitude in degrees) 
)
SELECT
    s.station_id,
    s.city,
    s.operator,
    s.num_charging_points,
    s.usage_cost,
    ROUND((ST_Distance(
        ST_Transform(s.location_point, 3857),
        ST_Transform(u.user_point, 3857)
    ) / 1000)::numeric,2) AS distance_km
    -- EPSG:3857 refers to the Web Mercator projection, which maps lon/lat into a “pseudo-Mercator” planar coordinate system with units in meters.
FROM stations s, user_location u
WHERE s.is_operational = TRUE AND usage_cost IS NOT NULL
ORDER BY s.location_point <-> u.user_point
LIMIT 10;

-- Hódmezővásárhely
WITH user_location AS (
    SELECT ST_SetSRID(ST_MakePoint(20.3188, 46.4303), 4326) AS user_point 
    -- EPSG:4326 refers to WGS84 geographic coordinates (latitude/longitude in degrees)
)
SELECT
    s.station_id,
    s.city,
    s.operator,
    s.num_charging_points,
    s.usage_cost,
    ROUND((ST_Distance(
        ST_Transform(s.location_point, 3857),
        ST_Transform(u.user_point, 3857)
    ) / 1000)::numeric,2) AS distance_km
FROM stations s, user_location u
WHERE s.is_operational = TRUE AND usage_cost IS NOT NULL
ORDER BY s.location_point <-> u.user_point
LIMIT 10;

-- Find areas more than 50km from any charging station
SELECT
    city,
    COUNT(*) AS stations_in_city,
    ST_ConvexHull(ST_Collect(location_point)) AS city_coverage_area
FROM stations
WHERE is_operational = TRUE
GROUP BY city
HAVING COUNT(*) > 1;

-- Comprehensive pricing model analysis
WITH pricing_model_analysis AS (
    SELECT 
        station_id,
        city,
        county,
        operator,
        num_charging_points,
        CASE 
            WHEN ac_price_huf_kwh IS NOT NULL AND time_based_price_huf_min IS NULL THEN 'Per kWh Only'
            WHEN time_based_price_huf_min IS NOT NULL AND ac_price_huf_kwh IS NULL THEN 'Per Minute Only'
            WHEN ac_price_huf_kwh IS NOT NULL AND time_based_price_huf_min IS NOT NULL THEN 'Hybrid Pricing'
            WHEN is_free = true THEN 'Free'
            ELSE 'Unknown/Other'
        END as pricing_model,
        ac_price_huf_kwh,
        time_based_price_huf_min,
        CASE 
            WHEN city IN ('Budapest', 'Debrecen', 'Szeged', 'Miskolc', 'Pécs') THEN 'Major City'
            WHEN city ~ '^[A-Z]' THEN 'Town/City'
            ELSE 'Rural/Other'
        END as location_type
    FROM stations 
    WHERE is_operational = true
),
pricing_effectiveness AS (
    SELECT 
        pricing_model,
        location_type,
        COUNT(*) as station_count,
        AVG(num_charging_points) as avg_charging_points,
        AVG(ac_price_huf_kwh) as avg_kwh_price,
        AVG(time_based_price_huf_min) as avg_minute_price,
        -- Calculate market share by operator
        COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () as market_share_pct
    FROM pricing_model_analysis
    GROUP BY pricing_model, location_type
)
SELECT 
    pricing_model,
    location_type,
    station_count,
    ROUND(avg_charging_points, 1) as avg_charging_points,
    ROUND(avg_kwh_price, 0) as avg_kwh_price_huf,
    ROUND(avg_minute_price, 1) as avg_minute_price_huf,
    ROUND(market_share_pct, 1) as market_share_pct
FROM pricing_effectiveness
ORDER BY pricing_model, location_type;

-- Operator pricing strategy comparison
WITH operator_pricing AS (
    SELECT 
        operator,
        COUNT(*) as total_stations,
        COUNT(CASE WHEN ac_price_huf_kwh IS NOT NULL THEN 1 END) as kwh_pricing_stations,
        COUNT(CASE WHEN time_based_price_huf_min IS NOT NULL THEN 1 END) as minute_pricing_stations,
        COUNT(CASE WHEN is_free = true THEN 1 END) as free_stations,
        AVG(ac_price_huf_kwh) as avg_kwh_price,
        MIN(ac_price_huf_kwh) as min_kwh_price,
        MAX(ac_price_huf_kwh) as max_kwh_price,
        STDDEV(ac_price_huf_kwh) as price_variance
    FROM stations 
    WHERE is_operational = true
    GROUP BY operator
    HAVING COUNT(*) >= 5  -- Only operators with significant presence
)
SELECT 
    operator,
    total_stations,
    ROUND(kwh_pricing_stations * 100.0 / total_stations, 1) as kwh_model_pct,
    ROUND(minute_pricing_stations * 100.0 / total_stations, 1) as minute_model_pct,
    ROUND(free_stations * 100.0 / total_stations, 1) as free_model_pct,
    ROUND(avg_kwh_price, 0) as avg_kwh_price,
    ROUND(price_variance, 1) as price_consistency_score
FROM operator_pricing
ORDER BY total_stations DESC;

-- Location-based pricing optimization analysis
SELECT 
    city,
    COUNT(*) as station_count,
    COUNT(DISTINCT operator) as operator_count,
    AVG(ac_price_huf_kwh) as avg_market_price,
    MIN(ac_price_huf_kwh) as min_price,
    MAX(ac_price_huf_kwh) as max_price,
    (MAX(ac_price_huf_kwh) - MIN(ac_price_huf_kwh)) as price_spread,
    -- Competitive intensity indicator
    CASE 
        WHEN COUNT(DISTINCT operator) >= 3 AND 
             (MAX(ac_price_huf_kwh) - MIN(ac_price_huf_kwh)) > 50 
        THEN 'High Competition'
        WHEN COUNT(DISTINCT operator) = 2 THEN 'Moderate Competition'
        ELSE 'Low Competition'
    END as competition_level
FROM stations 
WHERE is_operational = true 
    AND ac_price_huf_kwh IS NOT NULL
    AND city IS NOT NULL
GROUP BY city
HAVING COUNT(*) >= 3
ORDER BY price_spread DESC;
