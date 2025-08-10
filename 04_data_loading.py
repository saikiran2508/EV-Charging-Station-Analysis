import os
import sys
from dotenv import load_dotenv
import psycopg2
from sqlalchemy import create_engine, text
from sqlalchemy.exc import SQLAlchemyError
import pandas as pd
from datetime import datetime
import logging

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

# Load environment variables from .env file
load_dotenv()

# Database connection parameters from environment
db_params = {
    'host': os.getenv('DB_HOST', 'localhost'),
    'database': os.getenv('DB_NAME', 'ev_stations'),
    'user': os.getenv('DB_USER', 'postgres'),
    'password': os.getenv('DB_PASSWORD', ''),
    'port': os.getenv('DB_PORT', '5432')
}

def create_db_connection():
    """Create SQLAlchemy engine with error handling"""
    try:
        engine = create_engine(
            f"postgresql+psycopg2://{db_params['user']}:{db_params['password']}@"
            f"{db_params['host']}:{db_params['port']}/{db_params['database']}"
        )
        # Test connection
        with engine.connect() as conn:
            conn.execute(text("SELECT 1"))
        logger.info("Database connection successful")
        return engine
    except Exception as e:
        logger.error(f"Failed to connect to database: {e}")
        sys.exit(1)

def load_and_clean_data(csv_file):
    """Load CSV data and clean it for database insertion"""
    try:
        df = pd.read_csv(csv_file)
        logger.info(f"Loaded {len(df)} rows from CSV")
        
        # Fix column mapping based on actual CSV structure
        column_mapping = {
            'ID': 'station_id',
            'latitude': 'latitude',
            'longitude': 'longitude',
            'city': 'city',
            'postal_code': 'postal_code',
            'country': 'country',
            'access_comments': 'access_comments',
            'num_charging_points': 'num_charging_points',
            'is_operational': 'is_operational',
            'last_verified_date': 'last_verified_date',
            'creation_date': 'creation_date',
            'usage_cost': 'usage_cost',
            'is_pay_at_location': 'is_pay_at_location',
            'is_membership_required': 'is_membership_required',
            'operator': 'operator',
            'county': 'county',
            'original_text': 'original_text',
            'is_free': 'is_free',
            'is_paid_unspecified': 'is_paid_unspecified',
            'is_inaccessible': 'is_inaccessible',
            'ac_price_huf_kwh': 'ac_price_huf_kwh',
            'dc_price_huf_kwh': 'dc_price_huf_kwh',
            'time_based_price_huf_min': 'time_based_price_huf_min',
            'additional_fees': 'additional_fees',
            'notes': 'notes',
            'tesla_type': 'tesla_type'
        }
        
        # Only rename columns that exist in the dataframe
        existing_columns = {k: v for k, v in column_mapping.items() if k in df.columns}
        df = df.rename(columns=existing_columns)
        
        # Data cleaning and type conversion
        
        # Convert boolean columns
        bool_cols = ['is_operational', 'is_free', 'is_paid_unspecified', 'is_inaccessible', 
                    'is_pay_at_location', 'is_membership_required']
        for col in bool_cols:
            if col in df.columns:
                df[col] = df[col].fillna(False).astype(bool)
        
        # Convert date columns
        date_cols = ['last_verified_date', 'creation_date']
        for col in date_cols:
            if col in df.columns:
                df[col] = pd.to_datetime(df[col], errors='coerce').dt.date
        
        # Convert numeric columns
        numeric_cols = ['ac_price_huf_kwh', 'dc_price_huf_kwh', 'time_based_price_huf_min']
        for col in numeric_cols:
            if col in df.columns:
                df[col] = pd.to_numeric(df[col], errors='coerce')
        
        # Ensure station_id is integer
        if 'station_id' in df.columns:
            df['station_id'] = pd.to_numeric(df['station_id'], errors='coerce')
            df = df.dropna(subset=['station_id'])  # Remove rows with invalid IDs
            df['station_id'] = df['station_id'].astype('int64')
        
        # Ensure coordinates are valid
        df = df.dropna(subset=['latitude', 'longitude'])
        df['latitude'] = pd.to_numeric(df['latitude'], errors='coerce')
        df['longitude'] = pd.to_numeric(df['longitude'], errors='coerce')
        
        # Remove rows with invalid coordinates
        df = df.dropna(subset=['latitude', 'longitude'])
        
        # Clean text fields
        text_cols = ['city', 'county', 'country', 'operator', 'usage_cost', 'access_comments', 'notes', 'tesla_type', 'original_text']
        for col in text_cols:
            if col in df.columns:
                df[col] = df[col].astype(str).replace('nan', '')
                df[col] = df[col].replace('', None)
        
        # Select only columns that exist in both CSV and database schema
        db_columns = [
            'station_id', 'latitude', 'longitude', 'city', 'county', 'postal_code', 'country',
            'operator', 'is_operational', 'num_charging_points', 'is_free', 'is_paid_unspecified',
            'is_inaccessible', 'is_pay_at_location', 'is_membership_required', 'ac_price_huf_kwh',
            'dc_price_huf_kwh', 'time_based_price_huf_min', 'additional_fees', 'usage_cost',
            'last_verified_date', 'creation_date', 'access_comments', 'notes', 'tesla_type', 'original_text'
        ]
        
        # Filter dataframe to only include columns that exist in both CSV and database
        final_df = df[[col for col in db_columns if col in df.columns]]
        
        logger.info(f"Data cleaned successfully. Final dataset has {len(final_df)} rows and {len(final_df.columns)} columns")
        return final_df
        
    except FileNotFoundError:
        logger.error(f"CSV file '{csv_file}' not found.")
        sys.exit(1)
    except Exception as e:
        logger.error(f"Error loading/cleaning data: {e}")
        sys.exit(1)

def load_data_to_database(df, engine):
    """Load cleaned data into PostgreSQL database"""
    try:
        # Load data using pandas to_sql with conflict handling
        df.to_sql(
            'stations', 
            engine, 
            if_exists='append', 
            index=False, 
            method='multi',
            chunksize=1000  # Process in chunks for better performance
        )
        logger.info(f"Successfully loaded {len(df)} records to database")
        
    except psycopg2.IntegrityError as e:
        logger.error(f"Data integrity error (duplicates/constraints): {e}")
        logger.info("Attempting to handle duplicates...")
        
        # Handle duplicates by using INSERT ... ON CONFLICT
        try:
            with engine.connect() as conn:
                # Create temporary table
                df.to_sql('temp_stations', conn, if_exists='replace', index=False)
                
                # Insert with conflict resolution
                conn.execute(text("""
                    INSERT INTO stations 
                    SELECT * FROM temp_stations 
                    ON CONFLICT (station_id) DO UPDATE SET
                        latitude = EXCLUDED.latitude,
                        longitude = EXCLUDED.longitude,
                        city = EXCLUDED.city,
                        county = EXCLUDED.county,
                        postal_code = EXCLUDED.postal_code,
                        country = EXCLUDED.country,
                        operator = EXCLUDED.operator,
                        is_operational = EXCLUDED.is_operational,
                        num_charging_points = EXCLUDED.num_charging_points,
                        last_verified_date = EXCLUDED.last_verified_date
                """))
                
                # Drop temporary table
                conn.execute(text("DROP TABLE temp_stations"))
                conn.commit()
                
            logger.info("Successfully handled duplicates and loaded data")
            
        except Exception as e:
            logger.error(f"Failed to handle duplicates: {e}")
            raise
            
    except psycopg2.DataError as e:
        logger.error(f"Invalid data format/type: {e}")
        raise
    except SQLAlchemyError as e:
        logger.error(f"SQLAlchemy error occurred: {e}")
        raise
    except Exception as e:
        logger.error(f"Unexpected error occurred: {e}")
        raise

def verify_data_load(engine):
    """Verify that data was loaded correctly"""
    try:
        with engine.connect() as conn:
            result = conn.execute(text("SELECT COUNT(*) FROM stations"))
            count = result.fetchone()[0]
            logger.info(f"Total records in database: {count}")
            
            # Check for any invalid coordinates
            result = conn.execute(text("""
                SELECT COUNT(*) FROM stations 
                WHERE latitude IS NULL OR longitude IS NULL
            """))
            invalid_coords = result.fetchone()[0]
            if invalid_coords > 0:
                logger.warning(f"Found {invalid_coords} records with invalid coordinates")
            
            # Show sample of loaded data
            result = conn.execute(text("""
                SELECT station_id, city, operator, num_charging_points, is_operational 
                FROM stations 
                LIMIT 5
            """))
            logger.info("Sample of loaded data:")
            for row in result:
                logger.info(f"  ID: {row[0]}, City: {row[1]}, Operator: {row[2]}, Points: {row[3]}, Operational: {row[4]}")
                
    except Exception as e:
        logger.error(f"Error verifying data load: {e}")

def main():
    """Main function to orchestrate the data loading process"""
    logger.info("Starting EV charging station data load process...")
    
    # Create database connection
    engine = create_db_connection()
    
    # Load and clean data
    df = load_and_clean_data('final_cleaned_ev_stations.csv')
    
    # Load data to database
    load_data_to_database(df, engine)
    
    # Verify data load
    verify_data_load(engine)
    
    logger.info("Data loading process completed successfully!")

if __name__ == "__main__":
    main()