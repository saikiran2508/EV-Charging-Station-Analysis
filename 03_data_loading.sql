 -- EV Charging Station Database Schema
-- PostgreSQL with PostGIS for geospatial analysis

-- Enable PostGIS extension for geographic data
CREATE EXTENSION IF NOT EXISTS postgis;


-- Create table stations
CREATE TABLE IF NOT EXISTS stations (
    station_id BIGINT PRIMARY KEY,
    latitude DECIMAL(12,8) NOT NULL,
    longitude DECIMAL(12,8) NOT NULL,
    city VARCHAR(100),
    county VARCHAR(100),
    postal_code VARCHAR(20),
    country VARCHAR(50),
    operator VARCHAR(100),
    is_operational BOOLEAN DEFAULT TRUE,
    num_charging_points INTEGER,
    is_free BOOLEAN DEFAULT FALSE,
    is_paid_unspecified BOOLEAN DEFAULT FALSE,
    is_inaccessible BOOLEAN DEFAULT FALSE,
    is_pay_at_location BOOLEAN DEFAULT FALSE,
    is_membership_required BOOLEAN DEFAULT FALSE,
    ac_price_huf_kwh DECIMAL(6,2),
    dc_price_huf_kwh DECIMAL(6,2),
    time_based_price_huf_min DECIMAL(6,2),
    additional_fees TEXT,
    usage_cost TEXT,
    tesla_type TEXT,
    last_verified_date DATE,
    creation_date DATE,
    access_comments TEXT,
    notes TEXT,
    original_text TEXT,
    location_point GEOMETRY(POINT, 4326),  -- PostGIS geometry column
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP
);

-- Create indexes for performance
CREATE INDEX IF NOT EXISTS idx_stations_location ON stations USING GIST(location_point);
CREATE INDEX IF NOT EXISTS idx_stations_city ON stations(city);
CREATE INDEX IF NOT EXISTS idx_stations_operator ON stations(operator);
CREATE INDEX IF NOT EXISTS idx_stations_operational ON stations(is_operational);
CREATE INDEX IF NOT EXISTS idx_charging_sessions_station ON charging_sessions(station_id);
CREATE INDEX IF NOT EXISTS idx_charging_sessions_start_time ON charging_sessions(start_time);


-- Create function to automatically update geometry column
CREATE OR REPLACE FUNCTION update_location_point()
RETURNS TRIGGER AS $$
BEGIN
    NEW.location_point = ST_SetSRID(ST_MakePoint(NEW.longitude, NEW.latitude), 4326);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- Create trigger to automatically update geometry when coordinates change
CREATE TRIGGER trigger_update_location_point
    BEFORE INSERT OR UPDATE ON stations
    FOR EACH ROW
    EXECUTE FUNCTION update_location_point();
