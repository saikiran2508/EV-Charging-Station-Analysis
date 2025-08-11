# EV Charging Station Analysis

This project provides a complete pipeline for analyzing electric vehicle (EV) charging station data, including data cleaning, loading into a spatially-enabled PostgreSQL database, and advanced SQL-based analysis.

---

## 🚗 Dataset

The dataset contains detailed information about EV charging stations, including:
- Location (latitude, longitude, city, county, country, postal code)
- Operator and operational status
- Number of charging points
- Pricing models (per kWh, per minute, free, hybrid)
- Access and usage restrictions
- Timestamps (creation, last verification)
- Technical details (connection types, power, etc.)

The data was collected from public APIs and may include both Hungarian and international stations.

---

## 🛠️ Technologies Used

- **Python** (Pandas, SQLAlchemy): Data cleaning, transformation, and loading scripts
- **PostgreSQL** with **PostGIS**: Spatial database for storing and querying geospatial data
- **SQL**: Advanced analysis and reporting
- **Jupyter Notebook**: Exploratory data analysis and cleaning
- **VS Code**: Development environment

---

## 📊 Project Workflow

### 1. Data Cleaning (`02_data_celaning.ipynb`)
- Standardizes geographic and operator fields
- Handles missing values using reverse geocoding
- Cleans and parses pricing information
- Normalizes nested connection data
- Outputs cleaned CSV files for loading

### 2. Data Loading (`04_data_loading.py`, `03_data_loading.sql`)
- Defines the PostgreSQL schema with spatial support (PostGIS)
- Loads cleaned data into the database
- Ensures data types and integrity
- Creates indexes and triggers for performance and spatial queries

### 3. Data Analysis (`05_data_analysis.sql`)
- Computes key statistics (station counts, operator market share, pricing trends)
- Performs spatial queries (nearest stations, coverage areas)
- Analyzes pricing models and competition
- Identifies data quality issues and outliers

---

## 📂 Repository Structure

```
├── 01_data_aquistion/         # (optional) Scripts for data collection
├── 02_data_celaning.ipynb     # Data cleaning and transformation notebook
├── 03_data_loading.sql        # Database schema and spatial setup
├── 04_data_loading.py         # Python script for loading data into PostgreSQL
├── 05_data_analysis.sql       # Advanced SQL queries for analysis
├── cleaned_ev_pricing.csv     # Cleaned dataset (example)
├── connections_data.csv       # Normalized connections data
├── final_cleaned_ev_stations.csv # Final cleaned stations data
```

---

## 📈 **Dashboard Visualizations**

**1. EV Network Growth & Capacity Trends**  
![EV Network Growth Dashboard]

**2. Geographic Coverage & Accessibility**  
![EV Coverage Dashboard](path_to_image2.png)  

**3. Pricing Distribution**  
![Pricing Distribution](path_to_image3.png) 
