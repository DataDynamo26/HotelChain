-- BLOCK 1: Setup (run this first ALWAYS as ACCOUNTADMIN)
USE ROLE ACCOUNTADMIN;

CREATE DATABASE IF NOT EXISTS RAW_DB;
CREATE SCHEMA IF NOT EXISTS RAW_DB.BRONZE;
CREATE SCHEMA IF NOT EXISTS RAW_DB.SILVER;
CREATE SCHEMA IF NOT EXISTS RAW_DB.GOLD;

CREATE WAREHOUSE IF NOT EXISTS STAYSPHERE_WH
    WAREHOUSE_SIZE = 'X-SMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE;

USE DATABASE RAW_DB;
USE WAREHOUSE STAYSPHERE_WH;

-- BLOCK 2: Storage Integration (connects Snowflake to your AWS S3)
USE ROLE ACCOUNTADMIN;

CREATE OR REPLACE STORAGE INTEGRATION staysphere_s3_integration
    TYPE = EXTERNAL_STAGE
    STORAGE_PROVIDER = 'S3'
    ENABLED = TRUE
    STORAGE_AWS_ROLE_ARN = 'arn:aws:iam::543558876382:role/SnowflakeS3Role'
    STORAGE_ALLOWED_LOCATIONS = ('s3://staysphere-snowflake-stage/Hotelchain/');

-- Run this and copy the two values shown in output
DESC INTEGRATION staysphere_s3_integration;

-- BLOCK 3: File Format + External Stage
USE SCHEMA RAW_DB.BRONZE;
USE ROLE ACCOUNTADMIN;
USE DATABASE RAW_DB;
USE SCHEMA RAW_DB.BRONZE;
USE WAREHOUSE STAYSPHERE_WH;

-- ════════════════════════════════════════════════════
-- DROP AND RECREATE STAGE WITH CORRECT FORMAT
-- ════════════════════════════════════════════════════
CREATE OR REPLACE FILE FORMAT staysphere_csv_format
    TYPE                           = 'CSV'
    FIELD_DELIMITER                = ','
    RECORD_DELIMITER               = '\n'
    SKIP_HEADER                    = 1
    FIELD_OPTIONALLY_ENCLOSED_BY   = '"'
    NULL_IF                        = ('', 'NULL', 'null', 'N/A', 'NA', 'none', 'None')
    EMPTY_FIELD_AS_NULL            = TRUE
    TRIM_SPACE                     = TRUE
    DATE_FORMAT                    = 'AUTO'
    TIMESTAMP_FORMAT               = 'AUTO'
    ENCODING                       = 'UTF-8'
    ERROR_ON_COLUMN_COUNT_MISMATCH = FALSE;

-- Recreate stage using the named file format
CREATE OR REPLACE STAGE staysphere_stage
    STORAGE_INTEGRATION = staysphere_s3_integration
    URL                 = 's3://staysphere-snowflake-stage/Hotelchain/'
    FILE_FORMAT         = staysphere_csv_format;


-- Verify files are visible
LIST @staysphere_stage;


-- BLOCK 4: All 5 Bronze Tables
USE SCHEMA RAW_DB.BRONZE;

CREATE OR REPLACE TABLE RAW_GUESTS (
    guest_id STRING, name STRING, dob DATE,
    gender STRING, email STRING, phone STRING,
    address STRING, city STRING, country STRING,
    loyalty_tier STRING, registration_date DATE,
    _loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    _file_name STRING
);

CREATE OR REPLACE TABLE RAW_RESERVATIONS (
    reservation_id STRING, guest_id STRING, room_id STRING,
    check_in_date DATE, check_out_date DATE,
    booking_channel STRING, booking_time TIMESTAMP,
    cancellation_time TIMESTAMP, status STRING,
    _loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    _file_name STRING
);

CREATE OR REPLACE TABLE RAW_ROOMS (
    room_id STRING, hotel_id STRING, room_type STRING,
    floor NUMBER, capacity NUMBER, amenities STRING,
    status STRING, base_price FLOAT,
    _loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    _file_name STRING
);

CREATE OR REPLACE TABLE RAW_HOUSEKEEPING (
    task_id STRING, room_id STRING, task_type STRING,
    assigned_staff STRING, scheduled_time TIMESTAMP,
    start_time TIMESTAMP, end_time TIMESTAMP,
    issue_detected_flag BOOLEAN, status STRING,
    _loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    _file_name STRING
);


CREATE OR REPLACE TABLE RAW_BILLING (
    bill_id STRING, reservation_id STRING, guest_id STRING,
    total_amount FLOAT, taxes FLOAT, discounts FLOAT,
    payment_mode STRING, payment_time TIMESTAMP,
    is_flagged BOOLEAN,
    _loaded_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP(),
    _file_name STRING
);

-- BLOCK 5: COPY INTO (load all CSV files from S3)

--------------------------------------------------
USE SCHEMA RAW_DB.BRONZE;

-- ══════════════════════════════════════════════
-- 1. GUESTS
-- ══════════════════════════════════════════════
COPY INTO RAW_GUESTS
    (guest_id, name, dob, gender, email, phone,
     address, city, country, loyalty_tier,
     registration_date, _file_name)
FROM (
    SELECT
        $1,                                        -- guest_id
        $2,                                        -- name
        TRY_TO_DATE($3),                           -- dob
        $4,                                        -- gender
        $5,                                        -- email
        $6,                                        -- phone
        $7,                                        -- address
        $8,                                        -- city
        $9,                                        -- country
        $10,                                       -- loyalty_tier
        TRY_TO_DATE($11),                          -- registration_date
        METADATA$FILENAME                          -- _file_name
    FROM @staysphere_stage/guests/
)
FILE_FORMAT = (
    TYPE                         = 'CSV'
    SKIP_HEADER                  = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF                      = ('', 'NULL', 'null', 'N/A')
    EMPTY_FIELD_AS_NULL          = TRUE
    DATE_FORMAT                  = 'AUTO'
)
ON_ERROR = 'CONTINUE'
FORCE    = TRUE;

-- Check rows loaded
SELECT COUNT(*) AS guests_loaded FROM RAW_GUESTS;


-- ══════════════════════════════════════════════
-- 2. RESERVATIONS
-- ══════════════════════════════════════════════
COPY INTO RAW_RESERVATIONS
    (reservation_id, guest_id, room_id,
     check_in_date, check_out_date,
     booking_channel, booking_time,
     cancellation_time, status, _file_name)
FROM (
    SELECT
        $1,                                        -- reservation_id
        $2,                                        -- guest_id
        $3,                                        -- room_id
        TRY_TO_DATE($4),                           -- check_in_date
        TRY_TO_DATE($5),                           -- check_out_date
        $6,                                        -- booking_channel
        TRY_TO_TIMESTAMP($7),                      -- booking_time
        TRY_TO_TIMESTAMP($8),                      -- cancellation_time
        $9,                                        -- status
        METADATA$FILENAME                          -- _file_name
    FROM @staysphere_stage/reservations/
)
FILE_FORMAT = (
    TYPE                         = 'CSV'
    SKIP_HEADER                  = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF                      = ('', 'NULL', 'null', 'N/A')
    EMPTY_FIELD_AS_NULL          = TRUE
    DATE_FORMAT                  = 'AUTO'
    TIMESTAMP_FORMAT             = 'AUTO'
)
ON_ERROR = 'CONTINUE'
FORCE    = TRUE;

-- Check rows loaded
SELECT COUNT(*) AS reservations_loaded FROM RAW_RESERVATIONS;


-- ══════════════════════════════════════════════
-- 3. ROOMS
-- ══════════════════════════════════════════════
COPY INTO RAW_ROOMS
    (room_id, hotel_id, room_type, floor,
     capacity, amenities, status,
     base_price, _file_name)
FROM (
    SELECT
        $1,                                        -- room_id
        $2,                                        -- hotel_id
        $3,                                        -- room_type
        TRY_TO_NUMBER($4),                         -- floor
        TRY_TO_NUMBER($5),                         -- capacity
        $6,                                        -- amenities
        $7,                                        -- status
        TRY_TO_DOUBLE($8),                         -- base_price
        METADATA$FILENAME                          -- _file_name
    FROM @staysphere_stage/rooms/
)
FILE_FORMAT = (
    TYPE                         = 'CSV'
    SKIP_HEADER                  = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF                      = ('', 'NULL', 'null', 'N/A')
    EMPTY_FIELD_AS_NULL          = TRUE
)
ON_ERROR = 'CONTINUE'
FORCE    = TRUE;

-- Check rows loaded
SELECT COUNT(*) AS rooms_loaded FROM RAW_ROOMS;


-- ══════════════════════════════════════════════
-- 4. HOUSEKEEPING
-- ══════════════════════════════════════════════
COPY INTO RAW_HOUSEKEEPING
(
task_id,
room_id,
task_type,
assigned_staff,
scheduled_time,
start_time,
end_time,
issue_detected_flag,
status,
_file_name
)
FROM (
SELECT
$1,
$2,
$3,
$4,
$5,
$6,
$7,
$8,
$9,
METADATA$FILENAME
FROM @STAYSPHERE_STAGE/housekeeping/
)
FILE_FORMAT = (
TYPE = 'CSV'
SKIP_HEADER = 1
FIELD_OPTIONALLY_ENCLOSED_BY = '"'
NULL_IF = ('', 'NULL', 'null', 'N/A')
EMPTY_FIELD_AS_NULL = TRUE
)
ON_ERROR = 'CONTINUE'
FORCE = TRUE;
-- Check rows loaded
SELECT COUNT(*) AS housekeeping_loaded FROM RAW_HOUSEKEEPING;


-- ══════════════════════════════════════════════
-- 5. BILLING
-- ══════════════════════════════════════════════
COPY INTO RAW_BILLING
(
    bill_id,
    reservation_id,
    guest_id,
    total_amount,
    taxes,
    discounts,
    payment_mode,
    payment_time,
    is_flagged,
    _file_name
)
FROM (
    SELECT
        $1,
        $2,
        $3,
        TRY_TO_DOUBLE($4),
        TRY_TO_DOUBLE($5),
        TRY_TO_DOUBLE($6),
        $7,
        TRY_TO_TIMESTAMP($8),
        $9,
        METADATA$FILENAME
    FROM @staysphere_stage/billing/
)
FILE_FORMAT = (
    TYPE = 'CSV'
    SKIP_HEADER = 1
    FIELD_OPTIONALLY_ENCLOSED_BY = '"'
    NULL_IF = ('', 'NULL', 'null', 'N/A')
    EMPTY_FIELD_AS_NULL = TRUE
)
ON_ERROR = 'CONTINUE'
FORCE = TRUE;
-- Check rows loaded
SELECT COUNT(*) AS billing_loaded FROM RAW_BILLING;

LIST @staysphere_stage;
LIST @staysphere_stage/guests/;
LIST @staysphere_stage/rooms/;
LIST @staysphere_stage/reservations/;
LIST @staysphere_stage/housekeeping/;
LIST @staysphere_stage/billing/;

-- Test guests - should show separate columns now
SELECT
    $1  AS guest_id,
    $2  AS name,
    $3  AS dob,
    $4  AS gender,
    $5  AS email,
    $6  AS phone,
    $7  AS address,
    $8  AS city,
    $9  AS country,
    $10 AS loyalty_tier,
    $11 AS registration_date
FROM @staysphere_stage/guests/
LIMIT 5;

SELECT *FROM RAW_BILLING;
SELECT *FROM RAW_GUESTS;
SELECT *FROM RAW_HOUSEKEEPING;
SELECT *FROM RAW_RESERVATIONS;
SELECT *FROM RAW_ROOMS;

SELECT TABLE_NAME
FROM RAW_DB.INFORMATION_SCHEMA.TABLES
WHERE TABLE_SCHEMA = 'BRONZE';

-- BLOCK 6: Silver Layer
-- STEP 0 — EXCEPTION LOG TABLE
-- Captures every DQ violation with reason
-- ============================================================
-- ════════════════════════════════════════════════════════════════
-- SILVER LAYER — COMPLETE OUTPUT VERIFICATION
-- Run after all INSERT / MERGE operations
-- ════════════════════════════════════════════════════════════════

USE ROLE ACCOUNTADMIN;
USE DATABASE RAW_DB;
USE SCHEMA RAW_DB.SILVER;
USE WAREHOUSE STAYSPHERE_WH;


-- ════════════════════════════════════════════════════════════════
-- 1. MASTER SUMMARY — Row counts for ALL Silver tables
-- ════════════════════════════════════════════════════════════════
SELECT '1. VAL_GUESTS (ALL versions)'        AS table_name, COUNT(*) AS total_rows FROM RAW_DB.SILVER.VAL_GUESTS
UNION ALL
SELECT '1. VAL_GUESTS (current only)',        COUNT(*) FROM RAW_DB.SILVER.VAL_GUESTS       WHERE is_current = TRUE
UNION ALL
SELECT '1. VAL_GUESTS (expired SCD2 rows)',   COUNT(*) FROM RAW_DB.SILVER.VAL_GUESTS       WHERE is_current = FALSE
UNION ALL
SELECT '2. VAL_ROOMS  (ALL versions)',        COUNT(*) FROM RAW_DB.SILVER.VAL_ROOMS
UNION ALL
SELECT '2. VAL_ROOMS  (current only)',        COUNT(*) FROM RAW_DB.SILVER.VAL_ROOMS        WHERE is_current = TRUE
UNION ALL
SELECT '2. VAL_ROOMS  (expired SCD2 rows)',   COUNT(*) FROM RAW_DB.SILVER.VAL_ROOMS        WHERE is_current = FALSE
UNION ALL
SELECT '3. VAL_RESERVATIONS',                 COUNT(*) FROM RAW_DB.SILVER.VAL_RESERVATIONS
UNION ALL
SELECT '4. VAL_HOUSEKEEPING',                 COUNT(*) FROM RAW_DB.SILVER.VAL_HOUSEKEEPING
UNION ALL
SELECT '5. VAL_BILLING',                      COUNT(*) FROM RAW_DB.SILVER.VAL_BILLING
UNION ALL
SELECT '6. DQ_EXCEPTION_LOG (violations)',    COUNT(*) FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
ORDER BY table_name;


-- ════════════════════════════════════════════════════════════════
-- 2. VAL_GUESTS — Full Data Output
-- ════════════════════════════════════════════════════════════════

-- 2A. All current guest records
SELECT
    guest_id,
    name,
    dob,
    gender,
    email,
    phone,
    address,
    city,
    country,
    loyalty_tier,
    registration_date,
    scd_start_date,
    scd_end_date,
    is_current,
    scd_version,
    _loaded_at,
    _source_file
FROM RAW_DB.SILVER.VAL_GUESTS
WHERE is_current = TRUE
ORDER BY guest_id;

-- 2B. SCD2 History — guests who have changed loyalty_tier
-- This should show 50 rows — one version per guest
SELECT
    guest_id,
    name,
    loyalty_tier,
    scd_start_date,
    scd_end_date,
    is_current,
    scd_version,
    _source_file
FROM RAW_DB.SILVER.VAL_GUESTS
ORDER BY guest_id;

-- This must be 50
SELECT COUNT(*) AS total_guests FROM RAW_DB.SILVER.VAL_GUESTS;

-- This must also be 50 (all current, no history yet)
SELECT COUNT(*) AS current_guests
FROM RAW_DB.SILVER.VAL_GUESTS
WHERE is_current = TRUE;

-- Simulate guest 1001 upgrading from Gold → Platinum
-- (as if this came in the _inc file)
INSERT INTO RAW_DB.BRONZE.RAW_GUESTS
    (guest_id, name, dob, gender, email, phone,
     address, city, country, loyalty_tier,
     registration_date, _file_name)
VALUES
    ('1001', 'Arjun Mehta', '1985-07-12', 'M',
     'arjun.mehta@email.com', '+91-9876543210',
     '14 MG Road', 'Bangalore', 'India',
     'Platinum',                          -- ← changed from Gold to Platinum
     '2020-03-15',
     'guests_inc_simulation.csv');        -- ← _inc file pattern

-- Simulate guest 1002 upgrading from Gold → Platinum
INSERT INTO RAW_DB.BRONZE.RAW_GUESTS
    (guest_id, name, dob, gender, email, phone,
     address, city, country, loyalty_tier,
     registration_date, _file_name)
VALUES
    ('1002', 'Sophia Williams', '1990-03-25', 'F',
     'sophia.williams@email.com', '+1-2025550199',
     '120 Maple Avenue', 'Boston', 'USA',
     'Platinum',                          -- ← changed from Gold to Platinum
     '2021-06-10',
     'guests_inc_simulation.csv');

-- Simulate guest 1005 downgrading from Bronze → Silver
INSERT INTO RAW_DB.BRONZE.RAW_GUESTS
    (guest_id, name, dob, gender, email, phone,
     address, city, country, loyalty_tier,
     registration_date, _file_name)
VALUES
    ('1005', 'James Smith', '1988-12-01', 'M',
     'james.smith@email.com', '+44-7911123456',
     '32 Baker Street', 'London', 'UK',
     'Silver',                            -- ← changed from Bronze to Silver
     '2023-02-14',
     'guests_inc_simulation.csv');

-- ════════════════════════════════════════════════════
-- STEP 1: CREATE THE PROCEDURE FIRST
-- ════════════════════════════════════════════════════

CREATE OR REPLACE PROCEDURE RAW_DB.SILVER.MERGE_SCD2_GUESTS()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    expired_count  NUMBER DEFAULT 0;
    inserted_count NUMBER DEFAULT 0;
BEGIN

    -- ── STEP A: Expire old record when loyalty_tier has changed ──
    UPDATE RAW_DB.SILVER.VAL_GUESTS tgt
    SET
        scd_end_date = DATEADD('day', -1, CURRENT_DATE()),
        is_current   = FALSE
    WHERE tgt.is_current = TRUE
      AND EXISTS (
            SELECT 1
            FROM RAW_DB.BRONZE.RAW_GUESTS src
            WHERE src.guest_id      = tgt.guest_id
              AND src._file_name   LIKE '%_inc%'
              AND src.loyalty_tier != tgt.loyalty_tier
              AND src.loyalty_tier IN ('Bronze','Silver','Gold','Platinum')
      );

    expired_count := SQLROWCOUNT;

    -- ── STEP B: Insert NEW version for changed guests ──
    INSERT INTO RAW_DB.SILVER.VAL_GUESTS (
        guest_id, name, dob, gender, email, phone,
        address, city, country, loyalty_tier, registration_date,
        scd_start_date, scd_end_date,
        is_current, scd_version,
        _loaded_at, _source_file
    )
    SELECT
        src.guest_id,
        src.name,
        src.dob,
        src.gender,
        src.email,
        src.phone,
        src.address,
        src.city,
        src.country,
        src.loyalty_tier,
        src.registration_date,
        CURRENT_DATE()                AS scd_start_date,
        TO_DATE('9999-12-31')         AS scd_end_date,
        TRUE                          AS is_current,
        old.scd_version + 1           AS scd_version,
        CURRENT_TIMESTAMP()           AS _loaded_at,
        src._file_name                AS _source_file
    FROM (
        SELECT *,
               ROW_NUMBER() OVER (
                   PARTITION BY guest_id
                   ORDER BY _loaded_at DESC
               ) AS rn
        FROM RAW_DB.BRONZE.RAW_GUESTS
        WHERE _file_name   LIKE '%_inc%'
          AND guest_id     IS NOT NULL
          AND loyalty_tier IN ('Bronze','Silver','Gold','Platinum')
    ) src
    JOIN RAW_DB.SILVER.VAL_GUESTS old
        ON src.guest_id   = old.guest_id
       AND old.is_current = FALSE         -- just expired in STEP A
    WHERE src.rn = 1;

    inserted_count := SQLROWCOUNT;

    -- ── STEP C: MERGE non-SCD2 fields (SCD1 overwrite) ──
    MERGE INTO RAW_DB.SILVER.VAL_GUESTS tgt
    USING (
        SELECT guest_id, name, email, phone,
               address, city, country, _file_name
        FROM (
            SELECT *,
                   ROW_NUMBER() OVER (
                       PARTITION BY guest_id
                       ORDER BY _loaded_at DESC
                   ) AS rn
            FROM RAW_DB.BRONZE.RAW_GUESTS
            WHERE _file_name LIKE '%_inc%'
              AND guest_id   IS NOT NULL
        )
        WHERE rn = 1
    ) src
    ON  tgt.guest_id   = src.guest_id
    AND tgt.is_current = TRUE
    WHEN MATCHED THEN UPDATE SET
        tgt.name    = src.name,
        tgt.email   = src.email,
        tgt.phone   = src.phone,
        tgt.address = src.address,
        tgt.city    = src.city,
        tgt.country = src.country
    -- Insert brand new guests from _inc not in Silver at all
    WHEN NOT MATCHED THEN INSERT (
        guest_id, name, email, phone, address,
        city, country,
        scd_start_date, scd_end_date,
        is_current, scd_version, _source_file
    )
    VALUES (
        src.guest_id, src.name, src.email, src.phone, src.address,
        src.city, src.country,
        CURRENT_DATE(), TO_DATE('9999-12-31'),
        TRUE, 1, src._file_name
    );

    RETURN '✅ SCD2 Guests DONE | Expired: ' || expired_count
        || ' | New versions inserted: ' || inserted_count;
END;
$$;

-- ════════════════════════════════════════════════════
-- STEP 2: VERIFY PROCEDURE WAS CREATED
-- ════════════════════════════════════════════════════
SHOW PROCEDURES LIKE 'MERGE_SCD2_GUESTS' IN SCHEMA RAW_DB.SILVER;


-- ════════════════════════════════════════════════════
-- STEP 3: CALL IT
-- ════════════════════════════════════════════════════
CALL RAW_DB.SILVER.MERGE_SCD2_GUESTS();


-- ════════════════════════════════════════════════════
-- STEP 4: CHECK OUTPUT
-- ════════════════════════════════════════════════════

-- Total records (all versions)
SELECT COUNT(*) AS total_all_versions    FROM RAW_DB.SILVER.VAL_GUESTS;
SELECT COUNT(*) AS current_records       FROM RAW_DB.SILVER.VAL_GUESTS WHERE is_current = TRUE;
SELECT COUNT(*) AS historical_records    FROM RAW_DB.SILVER.VAL_GUESTS WHERE is_current = FALSE;

-- SCD2 version history (guests with more than 1 version)
SELECT
    guest_id,
    name,
    loyalty_tier,
    scd_start_date,
    scd_end_date,
    is_current,
    scd_version,
    _source_file
FROM RAW_DB.SILVER.VAL_GUESTS
WHERE guest_id IN (
    SELECT guest_id
    FROM RAW_DB.SILVER.VAL_GUESTS
    GROUP BY guest_id
    HAVING COUNT(*) > 1
)
ORDER BY guest_id, scd_version;

-- Full guest list (current only)
SELECT
    guest_id, name, loyalty_tier,
    scd_start_date, scd_end_date,
    is_current, scd_version
FROM RAW_DB.SILVER.VAL_GUESTS
WHERE is_current = TRUE
ORDER BY guest_id;
-- 2C. Loyalty tier distribution
SELECT
    loyalty_tier,
    COUNT(*)                                          AS guest_count,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct
FROM RAW_DB.SILVER.VAL_GUESTS
WHERE is_current = TRUE
GROUP BY loyalty_tier
ORDER BY guest_count DESC;

-- 2D. Guests by country
SELECT
    country,
    COUNT(*) AS guest_count
FROM RAW_DB.SILVER.VAL_GUESTS
WHERE is_current = TRUE
GROUP BY country
ORDER BY guest_count DESC;


-- ════════════════════════════════════════════════════════════════
-- 3. VAL_ROOMS — Full Data Output
-- ════════════════════════════════════════════════════════════════
DESC TABLE RAW_DB.SILVER.VAL_ROOMS;
-- 3A. All current room records
-- ════════════════════════════════════════════════════
-- STEP 2: RECREATE WITH ALL SCD2 COLUMNS
-- ════════════════════════════════════════════════════
CREATE OR REPLACE TABLE RAW_DB.SILVER.VAL_ROOMS (
    room_id        STRING        NOT NULL,
    hotel_id       STRING,
    room_type      STRING,
    floor          NUMBER,
    capacity       NUMBER,
    amenities      STRING,
    status         STRING,
    base_price     FLOAT,
    -- SCD2 columns
    scd_start_date DATE          DEFAULT CURRENT_DATE(),
    scd_end_date   DATE          DEFAULT TO_DATE('9999-12-31'),
    is_current     BOOLEAN       DEFAULT TRUE,
    scd_version    NUMBER        DEFAULT 1,
    -- audit
    _loaded_at     TIMESTAMP     DEFAULT CURRENT_TIMESTAMP(),
    _source_file   STRING
);

-- ════════════════════════════════════════════════════
-- STEP 3: RELOAD DATA INTO VAL_ROOMS
-- ════════════════════════════════════════════════════
INSERT INTO RAW_DB.SILVER.VAL_ROOMS (
    room_id, hotel_id, room_type, floor, capacity,
    amenities, status, base_price,
    scd_start_date, scd_end_date,
    is_current, scd_version,
    _loaded_at, _source_file
)
SELECT
    room_id,
    hotel_id,
    room_type,
    floor,
    capacity,
    amenities,
    status,
    base_price,
    CURRENT_DATE()         AS scd_start_date,
    TO_DATE('9999-12-31')  AS scd_end_date,
    TRUE                   AS is_current,
    1                      AS scd_version,
    CURRENT_TIMESTAMP()    AS _loaded_at,
    _file_name             AS _source_file
FROM (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY room_id
            ORDER BY _loaded_at DESC
        ) AS rn
    FROM RAW_DB.BRONZE.RAW_ROOMS
    WHERE room_id    IS NOT NULL
      AND capacity    > 0
      AND base_price >= 0
      AND status IN ('Available', 'Occupied', 'Maintenance')
) t
WHERE rn = 1;

-- Verify row count
SELECT COUNT(*) AS rooms_loaded FROM RAW_DB.SILVER.VAL_ROOMS;

SELECT
    room_id,
    hotel_id,
    room_type,
    floor,
    capacity,
    amenities,
    status,
    base_price,
    scd_start_date,
    scd_end_date,
    is_current,
    scd_version,
    _loaded_at,
    _source_file
FROM RAW_DB.SILVER.VAL_ROOMS
WHERE is_current = TRUE
ORDER BY room_id;
-- Verify all columns are present
DESC TABLE RAW_DB.SILVER.VAL_ROOMS;
-- 3B. SCD2 History — rooms where price or amenities changed
-- ════════════════════════════════════════════════════
-- STEP 1: SIMULATE ROOM CHANGES IN BRONZE
-- (price increase and amenities upgrade)

-- Room 301: base_price changed 120 → 150
INSERT INTO RAW_DB.BRONZE.RAW_ROOMS
    (room_id, hotel_id, room_type, floor, capacity,
     amenities, status, base_price, _file_name)
VALUES
    ('301', 'H001', 'Deluxe', 3, 2,

    
     'WiFi;TV;MiniBar',
     'Available',
     150,                              -- ← price changed 120 → 150
     'rooms_inc_simulation.csv');

-- Room 302: amenities upgraded (added Balcony)
INSERT INTO RAW_DB.BRONZE.RAW_ROOMS
    (room_id, hotel_id, room_type, floor, capacity,
     amenities, status, base_price, _file_name)
VALUES
    ('302', 'H001', 'Suite', 5, 4,
     'WiFi;TV;MiniBar;Jacuzzi;Balcony', -- ← amenities changed (Balcony added)
     'Occupied',
     250,
     'rooms_inc_simulation.csv');

-- Room 305: both price and amenities changed
INSERT INTO RAW_DB.BRONZE.RAW_ROOMS
    (room_id, hotel_id, room_type, floor, capacity,
     amenities, status, base_price, _file_name)
VALUES
    ('305', 'H003', 'Suite', 6, 4,
     'WiFi;TV;MiniBar;Kitchenette;Jacuzzi', -- ← Jacuzzi added
     'Occupied',
     350,                              -- ← price changed 300 → 350
     'rooms_inc_simulation.csv');

-- Room 310: price drop
INSERT INTO RAW_DB.BRONZE.RAW_ROOMS
    (room_id, hotel_id, room_type, floor, capacity,
     amenities, status, base_price, _file_name)
VALUES
    ('310', 'H002', 'Deluxe', 3, 2,
     'WiFi;TV;MiniBar',
     'Available',
     110,                              -- ← price changed 125 → 110
     'rooms_inc_simulation.csv');

-- Verify inserts in Bronze
SELECT room_id, amenities, base_price, status, _file_name
FROM RAW_DB.BRONZE.RAW_ROOMS
WHERE _file_name LIKE '%_inc%'
ORDER BY room_id;

-- ════════════════════════════════════════════════════
-- STEP 2: CREATE AND CALL MERGE_SCD2_ROOMS PROCEDURE
-- ════════════════════════════════════════════════════
USE SCHEMA RAW_DB.SILVER;

CREATE OR REPLACE PROCEDURE RAW_DB.SILVER.MERGE_SCD2_ROOMS()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    expired_count  NUMBER DEFAULT 0;
    inserted_count NUMBER DEFAULT 0;
BEGIN
    -- STEP A: Expire current record if price OR amenities changed
    UPDATE RAW_DB.SILVER.VAL_ROOMS tgt
    SET
        scd_end_date = DATEADD('day', -1, CURRENT_DATE()),
        is_current   = FALSE
    WHERE tgt.is_current = TRUE
      AND EXISTS (
            SELECT 1
            FROM RAW_DB.BRONZE.RAW_ROOMS src
            WHERE src.room_id    =  tgt.room_id
              AND src._file_name LIKE '%_inc%'
              AND (
                    src.base_price != tgt.base_price
                 OR src.amenities  != tgt.amenities
              )
      );

    expired_count := SQLROWCOUNT;

    -- STEP B: Insert new version for changed rooms
    INSERT INTO RAW_DB.SILVER.VAL_ROOMS (
        room_id, hotel_id, room_type, floor, capacity,
        amenities, status, base_price,
        scd_start_date, scd_end_date,
        is_current, scd_version,
        _loaded_at, _source_file
    )
    SELECT
        src.room_id,
        src.hotel_id,
        src.room_type,
        src.floor,
        src.capacity,
        src.amenities,
        src.status,
        src.base_price,
        CURRENT_DATE()         AS scd_start_date,
        TO_DATE('9999-12-31')  AS scd_end_date,
        TRUE                   AS is_current,
        old.scd_version + 1    AS scd_version,
        CURRENT_TIMESTAMP()    AS _loaded_at,
        src._file_name         AS _source_file
    FROM (
        SELECT *,
               ROW_NUMBER() OVER (
                   PARTITION BY room_id
                   ORDER BY _loaded_at DESC
               ) AS rn
        FROM RAW_DB.BRONZE.RAW_ROOMS
        WHERE _file_name  LIKE '%_inc%'
          AND room_id     IS NOT NULL
          AND capacity     > 0
          AND base_price  >= 0
    ) src
    JOIN RAW_DB.SILVER.VAL_ROOMS old
        ON  src.room_id    = old.room_id
        AND old.is_current = FALSE
    WHERE src.rn = 1;

    inserted_count := SQLROWCOUNT;

    -- STEP C: SCD1 overwrite for status changes only
    MERGE INTO RAW_DB.SILVER.VAL_ROOMS tgt
    USING (
        SELECT room_id, status, floor, capacity, _file_name
        FROM (
            SELECT *,
                   ROW_NUMBER() OVER (
                       PARTITION BY room_id
                       ORDER BY _loaded_at DESC
                   ) AS rn
            FROM RAW_DB.BRONZE.RAW_ROOMS
            WHERE _file_name LIKE '%_inc%'
              AND room_id    IS NOT NULL
        )
        WHERE rn = 1
    ) src
    ON  tgt.room_id    = src.room_id
    AND tgt.is_current = TRUE
    WHEN MATCHED THEN UPDATE SET
        tgt.status   = src.status,
        tgt.floor    = src.floor,
        tgt.capacity = src.capacity
    WHEN NOT MATCHED THEN INSERT (
        room_id, status, floor, capacity,
        scd_start_date, scd_end_date,
        is_current, scd_version, _source_file
    )
    VALUES (
        src.room_id, src.status, src.floor, src.capacity,
        CURRENT_DATE(), TO_DATE('9999-12-31'),
        TRUE, 1, src._file_name
    );

    RETURN '✅ SCD2 Rooms DONE | Expired: ' || expired_count
        || ' | New versions inserted: ' || inserted_count;
END;
$$;

-- ════════════════════════════════════════════════════
-- STEP 3: NOW RUN SCD2 HISTORY QUERY — WILL SHOW ROWS
-- ════════════════════════════════════════════════════

-- 3B. SCD2 History — rooms where price or amenities changed
SELECT
    room_id,
    hotel_id,
    room_type,
    amenities,
    base_price,
    scd_start_date,
    scd_end_date,
    is_current,
    scd_version
FROM RAW_DB.SILVER.VAL_ROOMS
WHERE room_id IN (
    SELECT room_id FROM RAW_DB.SILVER.VAL_ROOMS
    GROUP BY room_id HAVING COUNT(*) > 1
)
ORDER BY room_id, scd_version;

-- Call it
CALL RAW_DB.SILVER.MERGE_SCD2_ROOMS();
-- 3C. Room status distribution
SELECT
    status,
    COUNT(*)                                          AS room_count,
    ROUND(AVG(base_price), 2)                         AS avg_price,
    MIN(base_price)                                   AS min_price,
    MAX(base_price)                                   AS max_price
FROM RAW_DB.SILVER.VAL_ROOMS
WHERE is_current = TRUE
GROUP BY status
ORDER BY room_count DESC;

-- 3D. Rooms by hotel
SELECT
    hotel_id,
    COUNT(*)              AS total_rooms,
    COUNT(CASE WHEN status = 'Available'   THEN 1 END) AS available,
    COUNT(CASE WHEN status = 'Occupied'    THEN 1 END) AS occupied,
    COUNT(CASE WHEN status = 'Maintenance' THEN 1 END) AS maintenance,
    ROUND(AVG(base_price),2)                           AS avg_price
FROM RAW_DB.SILVER.VAL_ROOMS
WHERE is_current = TRUE
GROUP BY hotel_id
ORDER BY hotel_id;


-- ════════════════════════════════════════════════════════════════
-- 4. VAL_RESERVATIONS — Full Data Output
-- ════════════════════════════════════════════════════════════════

-- 4A. All reservation records
-- ════════════════════════════════════════════════════
-- STEP 2: RECREATE VAL_RESERVATIONS WITH ALL COLUMNS
-- ════════════════════════════════════════════════════
CREATE OR REPLACE TABLE RAW_DB.SILVER.VAL_RESERVATIONS (
    reservation_id    STRING        NOT NULL,
    guest_id          STRING,
    room_id           STRING,
    check_in_date     DATE,
    check_out_date    DATE,
    length_of_stay    NUMBER,
    booking_channel   STRING,
    booking_time      TIMESTAMP,
    cancellation_time TIMESTAMP,
    status            STRING,
    -- audit columns
    _loaded_at        TIMESTAMP     DEFAULT CURRENT_TIMESTAMP(),
    _source_file      STRING
);
-- ════════════════════════════════════════════════════
-- STEP 3: RELOAD DATA
-- ════════════════════════════════════════════════════
INSERT INTO RAW_DB.SILVER.VAL_RESERVATIONS (
    reservation_id, guest_id, room_id,
    check_in_date, check_out_date, length_of_stay,
    booking_channel, booking_time,
    cancellation_time, status,
    _loaded_at, _source_file
)
SELECT
    reservation_id,
    guest_id,
    room_id,
    check_in_date,
    check_out_date,
    DATEDIFF('day', check_in_date, check_out_date) AS length_of_stay,
    booking_channel,
    booking_time,
    cancellation_time,
    LOWER(status)                                  AS status,
    CURRENT_TIMESTAMP()                            AS _loaded_at,
    _file_name                                     AS _source_file
FROM (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY reservation_id
            ORDER BY _loaded_at DESC
        ) AS rn
    FROM RAW_DB.BRONZE.RAW_RESERVATIONS
    WHERE reservation_id IS NOT NULL
      AND guest_id       IS NOT NULL
      AND room_id        IS NOT NULL
      AND check_out_date >= check_in_date
      AND (cancellation_time IS NULL
           OR DATE(cancellation_time) <= check_in_date)
      AND LOWER(status) IN ('confirmed', 'cancelled', 'completed')
) t
WHERE rn = 1;

SELECT COUNT(*) AS reservations_loaded FROM RAW_DB.SILVER.VAL_RESERVATIONS;
DESC TABLE RAW_DB.SILVER.VAL_RESERVATIONS;

-- 4B. Reservation status breakdown
SELECT
    status,
    COUNT(*)                      AS total,
    ROUND(AVG(length_of_stay),1)  AS avg_stay_days,
    MIN(check_in_date)            AS earliest_checkin,
    MAX(check_out_date)           AS latest_checkout
FROM RAW_DB.SILVER.VAL_RESERVATIONS
GROUP BY status
ORDER BY total DESC;

-- 4C. Bookings by channel
SELECT
    booking_channel,
    COUNT(*)                                           AS bookings,
    ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS pct
FROM RAW_DB.SILVER.VAL_RESERVATIONS
GROUP BY booking_channel
ORDER BY bookings DESC;

-- 4D. Cancelled reservations detail
SELECT
    reservation_id,
    guest_id,
    room_id,
    check_in_date,
    cancellation_time,
    DATEDIFF('day', DATE(cancellation_time), check_in_date) AS days_before_checkin
FROM RAW_DB.SILVER.VAL_RESERVATIONS
WHERE status = 'cancelled'
   OR LOWER(status) = 'cancelled'
ORDER BY reservation_id;


-- ════════════════════════════════════════════════════════════════
-- 5. VAL_HOUSEKEEPING — Full Data Output
-- ════════════════════════════════════════════════════════════════

-- 5A. All housekeeping records
-- ════════════════════════════════════════════════════
-- STEP 2: RECREATE WITH ALL COLUMNS
-- ════════════════════════════════════════════════════
CREATE OR REPLACE TABLE RAW_DB.SILVER.VAL_HOUSEKEEPING (
    task_id             STRING        NOT NULL,
    room_id             STRING,
    task_type           STRING,
    assigned_staff      STRING,
    scheduled_time      TIMESTAMP,
    start_time          TIMESTAMP,
    end_time            TIMESTAMP,
    duration_minutes    NUMBER,
    issue_detected_flag BOOLEAN,
    status              STRING,
    _loaded_at          TIMESTAMP     DEFAULT CURRENT_TIMESTAMP(),
    _source_file        STRING
);

-- Verify all columns exist
DESC TABLE RAW_DB.SILVER.VAL_HOUSEKEEPING;
-- ════════════════════════════════════════════════════
-- STEP 3: RELOAD DATA FROM BRONZE
-- ════════════════════════════════════════════════════
INSERT INTO RAW_DB.SILVER.VAL_HOUSEKEEPING (
    task_id, room_id, task_type, assigned_staff,
    scheduled_time, start_time, end_time,
    duration_minutes, issue_detected_flag, status,
    _loaded_at, _source_file
)
SELECT
    task_id,
    room_id,
    LOWER(TRIM(task_type))                          AS task_type,
    assigned_staff,
    scheduled_time,
    start_time,
    end_time,
    CASE
        WHEN start_time IS NOT NULL
         AND end_time   IS NOT NULL
        THEN DATEDIFF('minute', start_time, end_time)
        ELSE NULL
    END                                             AS duration_minutes,
    CASE
        WHEN UPPER(TRIM(issue_detected_flag::STRING))
             IN ('TRUE','1','YES','Y','T')           THEN TRUE
        ELSE FALSE
    END                                             AS issue_detected_flag,
    TRIM(status)                                    AS status,
    CURRENT_TIMESTAMP()                             AS _loaded_at,
    _file_name                                      AS _source_file
FROM (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY task_id
            ORDER BY _loaded_at DESC
        ) AS rn
    FROM RAW_DB.BRONZE.RAW_HOUSEKEEPING
    WHERE task_id  IS NOT NULL
      AND room_id  IS NOT NULL
      AND (end_time IS NULL OR end_time >= start_time)
      AND LOWER(TRIM(task_type)) IN ('cleaning', 'maintenance')
) 
WHERE rn = 1;

-- Verify row count


-- Verify row count
SELECT COUNT(*) AS housekeeping_loaded FROM RAW_DB.SILVER.VAL_HOUSEKEEPING;
SELECT
    task_id,
    room_id,
    task_type,
    assigned_staff,
    scheduled_time,
    start_time,
    end_time,
    duration_minutes,
    issue_detected_flag,
    status,
    _loaded_at,
    _source_file
FROM RAW_DB.SILVER.VAL_HOUSEKEEPING
ORDER BY task_id;

-- 5B. SLA performance by task type
-- Cleaning SLA = 45 min | Maintenance SLA = 120 min
SELECT
    task_type,
    COUNT(*)                                                              AS total_tasks,
    ROUND(AVG(duration_minutes), 1)                                       AS avg_duration_min,
    MIN(duration_minutes)                                                  AS min_duration,
    MAX(duration_minutes)                                                  AS max_duration,
    SUM(CASE WHEN task_type = 'cleaning'     AND duration_minutes > 45  THEN 1
             WHEN task_type = 'maintenance'  AND duration_minutes > 120 THEN 1
             ELSE 0 END)                                                   AS sla_breaches,
    ROUND(
        100.0 * SUM(CASE WHEN task_type = 'cleaning'    AND duration_minutes <= 45  THEN 1
                         WHEN task_type = 'maintenance' AND duration_minutes <= 120 THEN 1
                         ELSE 0 END) / NULLIF(COUNT(*), 0), 1)            AS sla_compliance_pct
FROM RAW_DB.SILVER.VAL_HOUSEKEEPING
WHERE duration_minutes IS NOT NULL
GROUP BY task_type;

-- 5C. Issues detected by room
SELECT
    room_id,
    COUNT(*)                                                  AS total_tasks,
    SUM(CASE WHEN issue_detected_flag = TRUE THEN 1 ELSE 0 END) AS issues_found,
    ROUND(AVG(duration_minutes), 1)                            AS avg_duration_min
FROM RAW_DB.SILVER.VAL_HOUSEKEEPING
GROUP BY room_id
ORDER BY issues_found DESC;

-- 5D. Staff performance
SELECT
    assigned_staff,
    COUNT(*)                                                   AS tasks_done,
    ROUND(AVG(duration_minutes), 1)                            AS avg_duration_min,
    SUM(CASE WHEN issue_detected_flag = TRUE THEN 1 ELSE 0 END) AS issues_reported
FROM RAW_DB.SILVER.VAL_HOUSEKEEPING
GROUP BY assigned_staff
ORDER BY tasks_done DESC;


-- ════════════════════════════════════════════════════════════════
-- 6. VAL_BILLING — Full Data Output
-- ════════════════════════════════════════════════════════════════

-- 6A. All billing records
-- ════════════════════════════════════════════════════
-- STEP 2: RECREATE WITH AUDIT COLUMNS
-- ════════════════════════════════════════════════════
CREATE OR REPLACE TABLE RAW_DB.SILVER.VAL_BILLING (
    bill_id          STRING        NOT NULL,
    reservation_id   STRING,
    guest_id         STRING,
    total_amount     FLOAT,
    taxes            FLOAT,
    discounts        FLOAT,
    payment_mode     STRING,
    payment_time     TIMESTAMP,
    is_flagged       BOOLEAN,
    _loaded_at       TIMESTAMP     DEFAULT CURRENT_TIMESTAMP(),
    _source_file     STRING
);

DESC TABLE RAW_DB.SILVER.VAL_BILLING;

-- ════════════════════════════════════════════════════
-- STEP 3: RELOAD DATA
-- ════════════════════════════════════════════════════
INSERT INTO RAW_DB.SILVER.VAL_BILLING (
    bill_id, reservation_id, guest_id,
    total_amount, taxes, discounts,
    payment_mode, payment_time,
    is_flagged, _loaded_at, _source_file
)
SELECT
    bill_id,
    reservation_id,
    guest_id,
    total_amount,
    taxes,
    discounts,
    payment_mode,
    payment_time,
    CASE
        WHEN UPPER(TRIM(is_flagged::STRING))
             IN ('TRUE','1','YES','Y','T','true') THEN TRUE
        ELSE FALSE
    END                      AS is_flagged,
    CURRENT_TIMESTAMP()      AS _loaded_at,
    _file_name               AS _source_file
FROM (
    SELECT *,
        ROW_NUMBER() OVER (
            PARTITION BY bill_id
            ORDER BY _loaded_at DESC
        ) AS rn
    FROM RAW_DB.BRONZE.RAW_BILLING
    WHERE bill_id      IS NOT NULL
      AND total_amount >= 0
      AND taxes        >= 0
      AND discounts    >= 0
) t
WHERE rn = 1;

SELECT COUNT(*) AS billing_loaded FROM RAW_DB.SILVER.VAL_BILLING;

-- ════════════════════════════════════════════════════
-- STEP 4: NOW RUN YOUR ORIGINAL QUERY — WILL WORK
-- ════════════════════════════════════════════════════
SELECT
    bill_id,
    reservation_id,
    guest_id,
    total_amount,
    taxes,
    discounts,
    ROUND(total_amount - discounts + taxes, 2) AS net_amount,
    payment_mode,
    payment_time,
    is_flagged,
    _loaded_at,
    _source_file
FROM RAW_DB.SILVER.VAL_BILLING
ORDER BY bill_id;

-- ════════════════════════════════════════════════════
-- STEP 5: RUN ALL BILLING CHECKS TOGETHER
-- ════════════════════════════════════════════════════

-- Revenue by payment mode
SELECT
    payment_mode,
    COUNT(*)                     AS transactions,
    ROUND(SUM(total_amount), 2)  AS total_revenue,
    ROUND(AVG(total_amount), 2)  AS avg_bill,
    ROUND(SUM(taxes), 2)         AS total_taxes,
    ROUND(SUM(discounts), 2)     AS total_discounts
FROM RAW_DB.SILVER.VAL_BILLING
GROUP BY payment_mode
ORDER BY total_revenue DESC;

-- Flagged transactions only
SELECT
    bill_id,
    reservation_id,
    guest_id,
    total_amount,
    payment_mode,
    payment_time,
    is_flagged
FROM RAW_DB.SILVER.VAL_BILLING
WHERE is_flagged = TRUE
ORDER BY bill_id;

-- Overall billing stats + KPI 5 (Billing Accuracy Index)
SELECT
    COUNT(*)                                                           AS total_bills,
    ROUND(SUM(total_amount), 2)                                        AS total_revenue,
    ROUND(AVG(total_amount), 2)                                        AS avg_bill_amount,
    ROUND(SUM(taxes), 2)                                               AS total_taxes,
    ROUND(SUM(discounts), 2)                                           AS total_discounts,
    SUM(CASE WHEN is_flagged = TRUE THEN 1 ELSE 0 END)                 AS flagged_count,
    ROUND(
        100.0 * SUM(CASE WHEN is_flagged = TRUE THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0), 2)                                      AS fraud_pct,
    ROUND(
        1.0 - (SUM(CASE WHEN is_flagged = TRUE THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0)), 4)                                     AS billing_accuracy_index
FROM RAW_DB.SILVER.VAL_BILLING;

-- ════════════════════════════════════════════════════════════════
-- 7. DQ_EXCEPTION_LOG — All Violations
-- ════════════════════════════════════════════════════════════════

-- 7A. All exception records
CREATE TABLE IF NOT EXISTS RAW_DB.SILVER.DQ_EXCEPTION_LOG (
    log_id       NUMBER AUTOINCREMENT PRIMARY KEY,
    source_table STRING,
    record_id    STRING,
    error_type   STRING,
    error_message STRING,
    raw_value    STRING,
    logged_at    TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- ============================================================
-- SILVER LAYER — ALL DQ EXCEPTION LOGS FULLY FIXED
-- Every || concatenation uses TO_CHAR() for dates/timestamps
-- and CAST() for numbers to avoid 0-row issues
-- ============================================================

-- Clear old log entries to start fresh
TRUNCATE TABLE RAW_DB.SILVER.DQ_EXCEPTION_LOG;

SELECT 'Log cleared — starting fresh' AS status;


-- ════════════════════════════════════════════════════
-- LOG 1: GUESTS — Invalid loyalty_tier
-- ════════════════════════════════════════════════════
SELECT
    loyalty_tier,
    COUNT(*) AS guest_count
FROM RAW_DB.BRONZE.RAW_GUESTS
GROUP BY loyalty_tier
ORDER BY loyalty_tier;

-- Confirm no invalid values exist
SELECT COUNT(*) AS invalid_tier_count
FROM RAW_DB.BRONZE.RAW_GUESTS
WHERE loyalty_tier NOT IN ('Bronze','Silver','Gold','Platinum')
   OR loyalty_tier IS NULL;

SELECT 'LOG1' AS log, COUNT(*) AS inserted
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE source_table = 'RAW_GUESTS' AND error_type = 'VALUE'
  AND error_message LIKE '%loyalty_tier%';


-- ════════════════════════════════════════════════════
-- LOG 2: GUESTS — Missing guest_id or email
-- ════════════════════════════════════════════════════
INSERT INTO RAW_DB.SILVER.DQ_EXCEPTION_LOG
    (source_table, record_id, error_type, error_message, raw_value)
SELECT
    'RAW_GUESTS',
    COALESCE(CAST(guest_id AS STRING), 'NULL'),
    'VALUE',
    'Missing required field — guest_id or email is NULL',
    'guest_id=' || COALESCE(CAST(guest_id AS STRING), 'NULL')
    || ' | email=' || COALESCE(CAST(email AS STRING), 'NULL')
FROM RAW_DB.BRONZE.RAW_GUESTS
WHERE guest_id IS NULL
   OR email    IS NULL;

SELECT 'LOG2' AS log, COUNT(*) AS inserted
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE source_table = 'RAW_GUESTS'
  AND error_message LIKE '%Missing%';


-- ════════════════════════════════════════════════════
-- GUESTS SUMMARY
-- ════════════════════════════════════════════════════
SELECT 'GUESTS checks done' AS step,
       COUNT(*)              AS total_violations
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE source_table = 'RAW_GUESTS';


-- ════════════════════════════════════════════════════
-- LOG 3: ROOMS — capacity <= 0 or base_price < 0
-- ════════════════════════════════════════════════════
INSERT INTO RAW_DB.SILVER.DQ_EXCEPTION_LOG
    (source_table, record_id, error_type, error_message, raw_value)
SELECT
    'RAW_ROOMS',
    CAST(room_id AS STRING),
    'VALUE',
    'Invalid room — capacity <= 0 or base_price < 0',
    'capacity=' || CAST(capacity AS STRING)
    || ' | base_price=' || CAST(base_price AS STRING)
FROM RAW_DB.BRONZE.RAW_ROOMS
WHERE (capacity <= 0 OR base_price < 0)
  AND room_id IS NOT NULL;

SELECT 'LOG3' AS log, COUNT(*) AS inserted
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE source_table = 'RAW_ROOMS'
  AND error_message LIKE '%capacity%';


-- ════════════════════════════════════════════════════
-- LOG 4: ROOMS — Invalid status
-- ════════════════════════════════════════════════════
INSERT INTO RAW_DB.SILVER.DQ_EXCEPTION_LOG
    (source_table, record_id, error_type, error_message, raw_value)
SELECT
    'RAW_ROOMS',
    CAST(room_id AS STRING),
    'VALUE',
    'Invalid status — must be Available/Occupied/Maintenance',
    'status=' || CAST(status AS STRING)
FROM RAW_DB.BRONZE.RAW_ROOMS
WHERE TRIM(status) NOT IN ('Available','Occupied','Maintenance')
  AND status  IS NOT NULL
  AND room_id IS NOT NULL;

SELECT 'LOG4' AS log, COUNT(*) AS inserted
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE source_table = 'RAW_ROOMS'
  AND error_message LIKE '%status%';


-- ════════════════════════════════════════════════════
-- ROOMS SUMMARY
-- ════════════════════════════════════════════════════
SELECT 'ROOMS checks done' AS step,
       COUNT(*)             AS total_violations
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE source_table = 'RAW_ROOMS';


-- ════════════════════════════════════════════════════
-- LOG 5: RESERVATIONS — check_out < check_in
-- ════════════════════════════════════════════════════
INSERT INTO RAW_DB.SILVER.DQ_EXCEPTION_LOG
    (source_table, record_id, error_type, error_message, raw_value)
SELECT
    'RAW_RESERVATIONS',
    CAST(reservation_id AS STRING),
    'TEMPORAL',
    'check_out_date is before check_in_date',
    'check_in='  || TO_CHAR(check_in_date,  'YYYY-MM-DD')
    || ' | check_out=' || TO_CHAR(check_out_date, 'YYYY-MM-DD')
FROM RAW_DB.BRONZE.RAW_RESERVATIONS
WHERE check_out_date < check_in_date
  AND reservation_id IS NOT NULL;

SELECT 'LOG5' AS log, COUNT(*) AS inserted
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE source_table = 'RAW_RESERVATIONS'
  AND error_message LIKE '%check_out%';


-- ════════════════════════════════════════════════════
-- LOG 6: RESERVATIONS — cancellation after check_in
-- ════════════════════════════════════════════════════
INSERT INTO RAW_DB.SILVER.DQ_EXCEPTION_LOG
    (source_table, record_id, error_type, error_message, raw_value)
SELECT
    'RAW_RESERVATIONS',
    CAST(reservation_id AS STRING),
    'TEMPORAL',
    'cancellation_time is after check_in_date',
    'cancellation=' || TO_CHAR(cancellation_time, 'YYYY-MM-DD HH24:MI:SS')
    || ' | check_in=' || TO_CHAR(check_in_date, 'YYYY-MM-DD')
FROM RAW_DB.BRONZE.RAW_RESERVATIONS
WHERE cancellation_time IS NOT NULL
  AND DATE(cancellation_time) > check_in_date
  AND reservation_id IS NOT NULL;

SELECT 'LOG6' AS log, COUNT(*) AS inserted
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE source_table = 'RAW_RESERVATIONS'
  AND error_message LIKE '%cancellation%';


-- ════════════════════════════════════════════════════
-- LOG 7: RESERVATIONS — orphan guest_id
-- ════════════════════════════════════════════════════
INSERT INTO RAW_DB.SILVER.DQ_EXCEPTION_LOG
    (source_table, record_id, error_type, error_message, raw_value)
SELECT
    'RAW_RESERVATIONS',
    CAST(r.reservation_id AS STRING),
    'REFERENTIAL',
    'guest_id not found in VAL_GUESTS',
    'guest_id=' || CAST(r.guest_id AS STRING)
FROM RAW_DB.BRONZE.RAW_RESERVATIONS r
WHERE r.reservation_id IS NOT NULL
  AND r.guest_id        IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM RAW_DB.SILVER.VAL_GUESTS g
        WHERE CAST(g.guest_id AS STRING) = CAST(r.guest_id AS STRING)
          AND g.is_current = TRUE
  );

SELECT 'LOG7' AS log, COUNT(*) AS inserted
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE source_table = 'RAW_RESERVATIONS'
  AND error_message LIKE '%guest_id%';


-- ════════════════════════════════════════════════════
-- LOG 8: RESERVATIONS — orphan room_id
-- ════════════════════════════════════════════════════
INSERT INTO RAW_DB.SILVER.DQ_EXCEPTION_LOG
    (source_table, record_id, error_type, error_message, raw_value)
SELECT
    'RAW_RESERVATIONS',
    CAST(r.reservation_id AS STRING),
    'REFERENTIAL',
    'room_id not found in VAL_ROOMS',
    'room_id=' || CAST(r.room_id AS STRING)
FROM RAW_DB.BRONZE.RAW_RESERVATIONS r
WHERE r.reservation_id IS NOT NULL
  AND r.room_id         IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM RAW_DB.SILVER.VAL_ROOMS rm
        WHERE CAST(rm.room_id AS STRING) = CAST(r.room_id AS STRING)
          AND rm.is_current = TRUE
  );

SELECT 'LOG8' AS log, COUNT(*) AS inserted
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE source_table = 'RAW_RESERVATIONS'
  AND error_message LIKE '%room_id%';


-- ════════════════════════════════════════════════════
-- LOG 9: RESERVATIONS — invalid status
-- ════════════════════════════════════════════════════
INSERT INTO RAW_DB.SILVER.DQ_EXCEPTION_LOG
    (source_table, record_id, error_type, error_message, raw_value)
SELECT
    'RAW_RESERVATIONS',
    CAST(reservation_id AS STRING),
    'VALUE',
    'Invalid status — must be Confirmed/Cancelled/Completed',
    'status=' || CAST(status AS STRING)
FROM RAW_DB.BRONZE.RAW_RESERVATIONS
WHERE LOWER(TRIM(status)) NOT IN ('confirmed','cancelled','completed')
  AND status         IS NOT NULL
  AND reservation_id IS NOT NULL;

SELECT 'LOG9' AS log, COUNT(*) AS inserted
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE source_table = 'RAW_RESERVATIONS'
  AND error_type   = 'VALUE';


-- ════════════════════════════════════════════════════
-- RESERVATIONS SUMMARY
-- ════════════════════════════════════════════════════
SELECT 'RESERVATIONS checks done' AS step,
       COUNT(*)                    AS total_violations
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE source_table = 'RAW_RESERVATIONS';


-- ════════════════════════════════════════════════════
-- LOG 10: HOUSEKEEPING — end_time < start_time
-- ════════════════════════════════════════════════════
INSERT INTO RAW_DB.SILVER.DQ_EXCEPTION_LOG
    (source_table, record_id, error_type, error_message, raw_value)
SELECT
    'RAW_HOUSEKEEPING',
    CAST(task_id AS STRING),
    'TEMPORAL',
    'end_time is before start_time',
    'start=' || TO_CHAR(start_time, 'YYYY-MM-DD HH24:MI:SS')
    || ' | end=' || TO_CHAR(end_time, 'YYYY-MM-DD HH24:MI:SS')
FROM RAW_DB.BRONZE.RAW_HOUSEKEEPING
WHERE end_time  IS NOT NULL
  AND end_time   < start_time
  AND task_id   IS NOT NULL;

SELECT 'LOG10' AS log, COUNT(*) AS inserted
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE source_table = 'RAW_HOUSEKEEPING'
  AND error_type   = 'TEMPORAL';


-- ════════════════════════════════════════════════════
-- LOG 11: HOUSEKEEPING — orphan room_id
-- ════════════════════════════════════════════════════
INSERT INTO RAW_DB.SILVER.DQ_EXCEPTION_LOG
    (source_table, record_id, error_type, error_message, raw_value)
SELECT
    'RAW_HOUSEKEEPING',
    CAST(h.task_id AS STRING),
    'REFERENTIAL',
    'room_id not found in VAL_ROOMS',
    'room_id=' || CAST(h.room_id AS STRING)
FROM RAW_DB.BRONZE.RAW_HOUSEKEEPING h
WHERE h.task_id IS NOT NULL
  AND h.room_id IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM RAW_DB.SILVER.VAL_ROOMS rm
        WHERE CAST(rm.room_id AS STRING) = CAST(h.room_id AS STRING)
          AND rm.is_current = TRUE
  );

SELECT 'LOG11' AS log, COUNT(*) AS inserted
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE source_table = 'RAW_HOUSEKEEPING'
  AND error_type   = 'REFERENTIAL';


-- ════════════════════════════════════════════════════
-- LOG 12: HOUSEKEEPING — invalid task_type
-- ════════════════════════════════════════════════════
INSERT INTO RAW_DB.SILVER.DQ_EXCEPTION_LOG
    (source_table, record_id, error_type, error_message, raw_value)
SELECT
    'RAW_HOUSEKEEPING',
    CAST(task_id AS STRING),
    'VALUE',
    'Invalid task_type — must be cleaning or maintenance',
    'task_type=' || CAST(task_type AS STRING)
FROM RAW_DB.BRONZE.RAW_HOUSEKEEPING
WHERE LOWER(TRIM(task_type)) NOT IN ('cleaning','maintenance')
  AND task_type IS NOT NULL
  AND task_id   IS NOT NULL;

SELECT 'LOG12' AS log, COUNT(*) AS inserted
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE source_table = 'RAW_HOUSEKEEPING'
  AND error_type   = 'VALUE';


-- ════════════════════════════════════════════════════
-- HOUSEKEEPING SUMMARY
-- ════════════════════════════════════════════════════
SELECT 'HOUSEKEEPING checks done' AS step,
       COUNT(*)                    AS total_violations
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE source_table = 'RAW_HOUSEKEEPING';


-- ════════════════════════════════════════════════════
-- LOG 13: BILLING — negative amounts
-- ════════════════════════════════════════════════════
INSERT INTO RAW_DB.SILVER.DQ_EXCEPTION_LOG
    (source_table, record_id, error_type, error_message, raw_value)
SELECT
    'RAW_BILLING',
    CAST(bill_id AS STRING),
    'VALUE',
    'Negative amount — total/taxes/discounts must be >= 0',
    'total=' || CAST(total_amount AS STRING)
    || ' | taxes='     || CAST(taxes AS STRING)
    || ' | discounts=' || CAST(discounts AS STRING)
FROM RAW_DB.BRONZE.RAW_BILLING
WHERE (total_amount < 0 OR taxes < 0 OR discounts < 0)
  AND bill_id IS NOT NULL;

SELECT 'LOG13' AS log, COUNT(*) AS inserted
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE source_table = 'RAW_BILLING'
  AND error_message LIKE '%Negative%';


-- ════════════════════════════════════════════════════
-- LOG 14: BILLING — orphan reservation_id
-- ════════════════════════════════════════════════════
INSERT INTO RAW_DB.SILVER.DQ_EXCEPTION_LOG
    (source_table, record_id, error_type, error_message, raw_value)
SELECT
    'RAW_BILLING',
    CAST(b.bill_id AS STRING),
    'REFERENTIAL',
    'reservation_id not found in VAL_RESERVATIONS',
    'reservation_id=' || CAST(b.reservation_id AS STRING)
FROM RAW_DB.BRONZE.RAW_BILLING b
WHERE b.bill_id          IS NOT NULL
  AND b.reservation_id   IS NOT NULL
  AND NOT EXISTS (
        SELECT 1
        FROM RAW_DB.SILVER.VAL_RESERVATIONS r
        WHERE CAST(r.reservation_id AS STRING)
            = CAST(b.reservation_id AS STRING)
  );

SELECT 'LOG14' AS log, COUNT(*) AS inserted
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE source_table = 'RAW_BILLING'
  AND error_type   = 'REFERENTIAL';


-- ════════════════════════════════════════════════════
-- LOG 15: BILLING — payment_time before booking_time
-- ════════════════════════════════════════════════════
INSERT INTO RAW_DB.SILVER.DQ_EXCEPTION_LOG
    (source_table, record_id, error_type, error_message, raw_value)
SELECT
    'RAW_BILLING',
    CAST(b.bill_id AS STRING),
    'TEMPORAL',
    'payment_time is before booking_time',
    'payment='  || TO_CHAR(b.payment_time,  'YYYY-MM-DD HH24:MI:SS')
    || ' | booking=' || TO_CHAR(r.booking_time, 'YYYY-MM-DD HH24:MI:SS')
FROM RAW_DB.BRONZE.RAW_BILLING b
JOIN RAW_DB.SILVER.VAL_RESERVATIONS r
    ON CAST(b.reservation_id AS STRING) = CAST(r.reservation_id AS STRING)
WHERE b.bill_id        IS NOT NULL
  AND b.payment_time    IS NOT NULL
  AND b.payment_time   < r.booking_time;

SELECT 'LOG15' AS log, COUNT(*) AS inserted
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE source_table = 'RAW_BILLING'
  AND error_type   = 'TEMPORAL';


-- ════════════════════════════════════════════════════
-- BILLING SUMMARY
-- ════════════════════════════════════════════════════
SELECT 'BILLING checks done' AS step,
       COUNT(*)               AS total_violations
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE source_table = 'RAW_BILLING';
-- ════════════════════════════════════════════════════
-- 8. REFERENTIAL INTEGRITY — All must be 0
-- ════════════════════════════════════════════════════
SELECT
    'reservations.guest_id → guests'        AS ri_check,
    COUNT(*)                                AS broken_refs
FROM RAW_DB.SILVER.VAL_RESERVATIONS r
WHERE NOT EXISTS (
    SELECT 1 FROM RAW_DB.SILVER.VAL_GUESTS g
    WHERE CAST(g.guest_id AS STRING) = CAST(r.guest_id AS STRING)
      AND g.is_current = TRUE
)
UNION ALL
SELECT
    'reservations.room_id → rooms',
    COUNT(*)
FROM RAW_DB.SILVER.VAL_RESERVATIONS r
WHERE NOT EXISTS (
    SELECT 1 FROM RAW_DB.SILVER.VAL_ROOMS rm
    WHERE CAST(rm.room_id AS STRING) = CAST(r.room_id AS STRING)
      AND rm.is_current = TRUE
)
UNION ALL
SELECT
    'housekeeping.room_id → rooms',
    COUNT(*)
FROM RAW_DB.SILVER.VAL_HOUSEKEEPING h
WHERE NOT EXISTS (
    SELECT 1 FROM RAW_DB.SILVER.VAL_ROOMS rm
    WHERE CAST(rm.room_id AS STRING) = CAST(h.room_id AS STRING)
      AND rm.is_current = TRUE
)
UNION ALL
SELECT
    'billing.reservation_id → reservations',
    COUNT(*)
FROM RAW_DB.SILVER.VAL_BILLING b
WHERE NOT EXISTS (
    SELECT 1 FROM RAW_DB.SILVER.VAL_RESERVATIONS r
    WHERE CAST(r.reservation_id AS STRING) = CAST(b.reservation_id AS STRING)
)
ORDER BY ri_check;
-- ✅ All broken_refs must be 0


-- ════════════════════════════════════════════════════
-- 9. TEMPORAL CHECKS — All must be 0
-- ════════════════════════════════════════════════════
SELECT
    'RES: check_out < check_in'           AS temporal_check,
    COUNT(*)                              AS violations
FROM RAW_DB.SILVER.VAL_RESERVATIONS
WHERE check_out_date < check_in_date
UNION ALL
SELECT
    'RES: cancellation > check_in',
    COUNT(*)
FROM RAW_DB.SILVER.VAL_RESERVATIONS
WHERE cancellation_time IS NOT NULL
  AND DATE(cancellation_time) > check_in_date
UNION ALL
SELECT
    'HK: end_time < start_time',
    COUNT(*)
FROM RAW_DB.SILVER.VAL_HOUSEKEEPING
WHERE end_time IS NOT NULL
  AND end_time  < start_time
UNION ALL
SELECT
    'BILLING: payment < booking_time',
    COUNT(*)
FROM RAW_DB.SILVER.VAL_BILLING        b
JOIN RAW_DB.SILVER.VAL_RESERVATIONS   r
    ON CAST(b.reservation_id AS STRING) = CAST(r.reservation_id AS STRING)
WHERE b.payment_time < r.booking_time
ORDER BY temporal_check;
-- ✅ All violations must be 0


-- ════════════════════════════════════════════════════
-- 10. SCD2 AUDIT
-- ════════════════════════════════════════════════════
SELECT
    'VAL_GUESTS'   AS scd2_table,
    MAX(scd_version)                                     AS max_version,
    SUM(CASE WHEN is_current = TRUE  THEN 1 ELSE 0 END)  AS current_records,
    SUM(CASE WHEN is_current = FALSE THEN 1 ELSE 0 END)  AS historical_records,
    COUNT(*)                                             AS total_records
FROM RAW_DB.SILVER.VAL_GUESTS
UNION ALL
SELECT
    'VAL_ROOMS',
    MAX(scd_version),
    SUM(CASE WHEN is_current = TRUE  THEN 1 ELSE 0 END),
    SUM(CASE WHEN is_current = FALSE THEN 1 ELSE 0 END),
    COUNT(*)
FROM RAW_DB.SILVER.VAL_ROOMS
ORDER BY scd2_table;


-- ════════════════════════════════════════════════════
-- 11. FINAL ROW COUNT — ALL SILVER TABLES
-- ════════════════════════════════════════════════════
SELECT 'VAL_GUESTS (all versions)'  AS table_name, COUNT(*) AS rows
FROM RAW_DB.SILVER.VAL_GUESTS
UNION ALL
SELECT 'VAL_GUESTS (current)',       COUNT(*)
FROM RAW_DB.SILVER.VAL_GUESTS        WHERE is_current = TRUE
UNION ALL
SELECT 'VAL_GUESTS (SCD2 history)',  COUNT(*)
FROM RAW_DB.SILVER.VAL_GUESTS        WHERE is_current = FALSE
UNION ALL
SELECT 'VAL_ROOMS (all versions)',   COUNT(*)
FROM RAW_DB.SILVER.VAL_ROOMS
UNION ALL
SELECT 'VAL_ROOMS (current)',        COUNT(*)
FROM RAW_DB.SILVER.VAL_ROOMS         WHERE is_current = TRUE
UNION ALL
SELECT 'VAL_ROOMS (SCD2 history)',   COUNT(*)
FROM RAW_DB.SILVER.VAL_ROOMS         WHERE is_current = FALSE
UNION ALL
SELECT 'VAL_RESERVATIONS',           COUNT(*)
FROM RAW_DB.SILVER.VAL_RESERVATIONS
UNION ALL
SELECT 'VAL_HOUSEKEEPING',           COUNT(*)
FROM RAW_DB.SILVER.VAL_HOUSEKEEPING
UNION ALL
SELECT 'VAL_BILLING',                COUNT(*)
FROM RAW_DB.SILVER.VAL_BILLING
UNION ALL
SELECT 'DQ_EXCEPTION_LOG',           COUNT(*)
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
ORDER BY table_name;

-- ============================================================
-- ALL VALUE CHECKS FROM HACKATHON PAPER
-- total_amount ≥ 0
-- taxes ≥ 0
-- discounts ≥ 0
-- room_capacity > 0
-- status ∈ valid list
-- ============================================================

-- Clear old value check logs only
DELETE FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE error_type = 'VALUE';

SELECT 'Old VALUE logs cleared' AS status;

-- ════════════════════════════════════════════════════
-- VALUE CHECK 1: total_amount ≥ 0
-- Table: RAW_BILLING
-- ════════════════════════════════════════════════════
INSERT INTO RAW_DB.SILVER.DQ_EXCEPTION_LOG
    (source_table, record_id, error_type, error_message, raw_value)
SELECT
    'RAW_BILLING',
    CAST(bill_id AS STRING),
    'VALUE',
    'total_amount must be >= 0',
    'bill_id='      || CAST(bill_id      AS STRING)
    || ' | total_amount=' || CAST(total_amount AS STRING)
FROM RAW_DB.BRONZE.RAW_BILLING
WHERE total_amount < 0
  AND bill_id IS NOT NULL;

SELECT 'VC1 — total_amount >= 0' AS value_check,
       COUNT(*) AS violations
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE source_table  = 'RAW_BILLING'
  AND error_message LIKE '%total_amount%';
-- Expected: 0 ✅
-- ════════════════════════════════════════════════════
-- VALUE CHECK 2: taxes ≥ 0
-- Table: RAW_BILLING
-- ════════════════════════════════════════════════════
INSERT INTO RAW_DB.SILVER.DQ_EXCEPTION_LOG
    (source_table, record_id, error_type, error_message, raw_value)
SELECT
    'RAW_BILLING',
    CAST(bill_id AS STRING),
    'VALUE',
    'taxes must be >= 0',
    'bill_id=' || CAST(bill_id AS STRING)
    || ' | taxes=' || CAST(taxes AS STRING)
FROM RAW_DB.BRONZE.RAW_BILLING
WHERE taxes   < 0
  AND bill_id IS NOT NULL;

SELECT 'VC2 — taxes >= 0' AS value_check,
       COUNT(*) AS violations
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE source_table  = 'RAW_BILLING'
  AND error_message LIKE '%taxes%';
-- Expected: 0 ✅
-- ════════════════════════════════════════════════════
-- VALUE CHECK 3: discounts ≥ 0
-- Table: RAW_BILLING
-- ════════════════════════════════════════════════════
INSERT INTO RAW_DB.SILVER.DQ_EXCEPTION_LOG
    (source_table, record_id, error_type, error_message, raw_value)
SELECT
    'RAW_BILLING',
    CAST(bill_id AS STRING),
    'VALUE',
    'discounts must be >= 0',
    'bill_id='    || CAST(bill_id   AS STRING)
    || ' | discounts=' || CAST(discounts AS STRING)
FROM RAW_DB.BRONZE.RAW_BILLING
WHERE discounts < 0
  AND bill_id   IS NOT NULL;

SELECT 'VC3 — discounts >= 0' AS value_check,
       COUNT(*) AS violations
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE source_table  = 'RAW_BILLING'
  AND error_message LIKE '%discounts%';
-- Expected: 0 ✅
-- ════════════════════════════════════════════════════
-- VALUE CHECK 4: room_capacity > 0
-- Table: RAW_ROOMS
-- ════════════════════════════════════════════════════
INSERT INTO RAW_DB.SILVER.DQ_EXCEPTION_LOG
    (source_table, record_id, error_type, error_message, raw_value)
SELECT
    'RAW_ROOMS',
    CAST(room_id AS STRING),
    'VALUE',
    'room_capacity must be > 0',
    'room_id='   || CAST(room_id   AS STRING)
    || ' | capacity=' || CAST(capacity AS STRING)
FROM RAW_DB.BRONZE.RAW_ROOMS
WHERE capacity <= 0
  AND room_id  IS NOT NULL;

SELECT 'VC4 — room_capacity > 0' AS value_check,
       COUNT(*) AS violations
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE source_table  = 'RAW_ROOMS'
  AND error_message LIKE '%room_capacity%';
-- Expected: 0 ✅
-- ════════════════════════════════════════════════════
-- VALUE CHECK 5A: status ∈ valid list — RESERVATIONS
-- Valid: Confirmed / Cancelled / Completed
-- ════════════════════════════════════════════════════
INSERT INTO RAW_DB.SILVER.DQ_EXCEPTION_LOG
    (source_table, record_id, error_type, error_message, raw_value)
SELECT
    'RAW_RESERVATIONS',
    CAST(reservation_id AS STRING),
    'VALUE',
    'status must be Confirmed/Cancelled/Completed',
    'reservation_id=' || CAST(reservation_id AS STRING)
    || ' | status='       || CAST(status         AS STRING)
FROM RAW_DB.BRONZE.RAW_RESERVATIONS
WHERE LOWER(TRIM(status)) NOT IN ('confirmed','cancelled','completed')
  AND status         IS NOT NULL
  AND reservation_id IS NOT NULL;

SELECT 'VC5A — reservations status valid' AS value_check,
       COUNT(*) AS violations
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE source_table  = 'RAW_RESERVATIONS'
  AND error_message LIKE '%Confirmed%';
-- Expected: 0 ✅
-- ════════════════════════════════════════════════════
-- VALUE CHECK 5B: status ∈ valid list — ROOMS
-- Valid: Available / Occupied / Maintenance
-- ════════════════════════════════════════════════════
INSERT INTO RAW_DB.SILVER.DQ_EXCEPTION_LOG
    (source_table, record_id, error_type, error_message, raw_value)
SELECT
    'RAW_ROOMS',
    CAST(room_id AS STRING),
    'VALUE',
    'status must be Available/Occupied/Maintenance',
    'room_id=' || CAST(room_id AS STRING)
    || ' | status=' || CAST(status AS STRING)
FROM RAW_DB.BRONZE.RAW_ROOMS
WHERE TRIM(status) NOT IN ('Available','Occupied','Maintenance')
  AND status  IS NOT NULL
  AND room_id IS NOT NULL;

SELECT 'VC5B — rooms status valid' AS value_check,
       COUNT(*) AS violations
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE source_table  = 'RAW_ROOMS'
  AND error_message LIKE '%Available%';
-- Expected: 0 ✅
-- ════════════════════════════════════════════════════
-- VALUE CHECK 5C: status ∈ valid list — HOUSEKEEPING
-- Valid: Completed / Pending / In Progress / Pending Review
-- ════════════════════════════════════════════════════
INSERT INTO RAW_DB.SILVER.DQ_EXCEPTION_LOG
    (source_table, record_id, error_type, error_message, raw_value)
SELECT
    'RAW_HOUSEKEEPING',
    CAST(task_id AS STRING),
    'VALUE',
    'status must be Completed/Pending/In Progress/Pending Review',
    'task_id=' || CAST(task_id AS STRING)
    || ' | status=' || CAST(status AS STRING)
FROM RAW_DB.BRONZE.RAW_HOUSEKEEPING
WHERE LOWER(TRIM(status)) NOT IN (
        'completed',
        'pending',
        'in progress',
        'pending review'
      )
  AND status  IS NOT NULL
  AND task_id IS NOT NULL;

SELECT 'VC5C — housekeeping status valid' AS value_check,
       COUNT(*) AS violations
FROM RAW_DB.SILVER.DQ_EXCEPTION_LOG
WHERE source_table  = 'RAW_HOUSEKEEPING'
  AND error_message LIKE '%Completed%';
-- Expected: 0 ✅

-- ============================================================
-- STAYSPHERE HOTEL — GOLD LAYER (CURATED)
-- Kimball Dimensional Model
-- DIM_HOTEL | DIM_GUEST | DIM_ROOM
-- FACT_RESERVATION | FACT_HOUSEKEEPING | FACT_BILLING
-- ============================================================
-- ============================================================
-- STEP 0: DROP AND RECREATE ALL GOLD TABLES (CLEAN START)
-- ============================================================
DROP TABLE IF EXISTS RAW_DB.GOLD.FACT_BILLING;
DROP TABLE IF EXISTS RAW_DB.GOLD.FACT_HOUSEKEEPING;
DROP TABLE IF EXISTS RAW_DB.GOLD.FACT_RESERVATION;
DROP TABLE IF EXISTS RAW_DB.GOLD.DIM_ROOM;
DROP TABLE IF EXISTS RAW_DB.GOLD.DIM_GUEST;
DROP TABLE IF EXISTS RAW_DB.GOLD.DIM_HOTEL;

SELECT 'Gold tables dropped — clean start' AS status;


-- ============================================================
-- STEP 1: DIM_HOTEL
-- Static reference dimension
-- ============================================================
CREATE OR REPLACE TABLE RAW_DB.GOLD.DIM_HOTEL (
    hotel_sk        NUMBER AUTOINCREMENT PRIMARY KEY,
    hotel_id        STRING  NOT NULL UNIQUE,
    hotel_name      STRING,
    city            STRING,
    country         STRING,
    star_rating     NUMBER,
    total_rooms     NUMBER,
    _loaded_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- Insert hotel reference data
INSERT INTO RAW_DB.GOLD.DIM_HOTEL
    (hotel_id, hotel_name, city, country, star_rating, total_rooms)
VALUES
    ('H001', 'StaySphere Mumbai Central',    'Mumbai',    'India', 5, 120),
    ('H002', 'StaySphere Delhi North',       'Delhi',     'India', 4, 95),
    ('H003', 'StaySphere Bangalore Tech',    'Bangalore', 'India', 5, 110),
    ('H004', 'StaySphere Hyderabad Pearl',   'Hyderabad', 'India', 4, 85),
    ('H005', 'StaySphere Chennai Marina',    'Chennai',   'India', 3, 70);

SELECT 'DIM_HOTEL loaded'        AS step,
       COUNT(*)                   AS row_count
FROM RAW_DB.GOLD.DIM_HOTEL;


-- ============================================================
-- STEP 2: DIM_GUEST (SCD2 — from Silver VAL_GUESTS)
-- Only current records promoted to Gold
-- ============================================================
CREATE OR REPLACE TABLE RAW_DB.GOLD.DIM_GUEST (
    guest_sk          NUMBER AUTOINCREMENT PRIMARY KEY,
    guest_id          STRING  NOT NULL,
    name              STRING,
    dob               DATE,
    gender            STRING,
    email             STRING,
    phone             STRING,
    address           STRING,
    city              STRING,
    country           STRING,
    loyalty_tier      STRING,
    registration_date DATE,
    -- SCD2 tracking columns
    scd_start_date    DATE,
    scd_end_date      DATE,
    is_current        BOOLEAN,
    scd_version       NUMBER,
    -- audit
    _loaded_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- Load ALL versions (current + historical) for full SCD2 lineage
INSERT INTO RAW_DB.GOLD.DIM_GUEST (
    guest_id, name, dob, gender, email, phone,
    address, city, country, loyalty_tier, registration_date,
    scd_start_date, scd_end_date, is_current, scd_version
)
SELECT
    guest_id,
    name,
    dob,
    gender,
    email,
    phone,
    address,
    city,
    country,
    loyalty_tier,
    registration_date,
    scd_start_date,
    scd_end_date,
    is_current,
    scd_version
FROM RAW_DB.SILVER.VAL_GUESTS
ORDER BY guest_id, scd_version;

SELECT 'DIM_GUEST loaded' AS step,
       COUNT(*)           AS total_rows,
       SUM(CASE WHEN is_current = TRUE  THEN 1 ELSE 0 END) AS current_rows,
       SUM(CASE WHEN is_current = FALSE THEN 1 ELSE 0 END) AS historical_rows
FROM RAW_DB.GOLD.DIM_GUEST;


-- ============================================================
-- STEP 3: DIM_ROOM (SCD2 — from Silver VAL_ROOMS)
-- ============================================================
CREATE OR REPLACE TABLE RAW_DB.GOLD.DIM_ROOM (
    room_sk        NUMBER AUTOINCREMENT PRIMARY KEY,
    room_id        STRING  NOT NULL,
    hotel_sk       NUMBER,
    hotel_id       STRING,
    room_type      STRING,
    floor          NUMBER,
    capacity       NUMBER,
    amenities      STRING,
    status         STRING,
    base_price     FLOAT,
    -- SCD2 tracking columns
    scd_start_date DATE,
    scd_end_date   DATE,
    is_current     BOOLEAN,
    scd_version    NUMBER,
    -- audit
    _loaded_at     TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

-- Load ALL versions with hotel_sk lookup
INSERT INTO RAW_DB.GOLD.DIM_ROOM (
    room_id, hotel_sk, hotel_id,
    room_type, floor, capacity,
    amenities, status, base_price,
    scd_start_date, scd_end_date,
    is_current, scd_version
)
SELECT
    r.room_id,
    h.hotel_sk,
    r.hotel_id,
    r.room_type,
    r.floor,
    r.capacity,
    r.amenities,
    r.status,
    r.base_price,
    r.scd_start_date,
    r.scd_end_date,
    r.is_current,
    r.scd_version
FROM RAW_DB.SILVER.VAL_ROOMS r
LEFT JOIN RAW_DB.GOLD.DIM_HOTEL h
    ON r.hotel_id = h.hotel_id
ORDER BY r.room_id, r.scd_version;

SELECT 'DIM_ROOM loaded' AS step,
       COUNT(*)          AS total_rows,
       SUM(CASE WHEN is_current = TRUE  THEN 1 ELSE 0 END) AS current_rows,
       SUM(CASE WHEN is_current = FALSE THEN 1 ELSE 0 END) AS historical_rows
FROM RAW_DB.GOLD.DIM_ROOM;


-- ============================================================
-- STEP 4: FACT_RESERVATION
-- ============================================================
CREATE OR REPLACE TABLE RAW_DB.GOLD.FACT_RESERVATION (
    reservation_sk        NUMBER AUTOINCREMENT PRIMARY KEY,
    -- foreign keys
    reservation_id        STRING  NOT NULL UNIQUE,
    guest_sk              NUMBER,
    room_sk               NUMBER,
    hotel_sk              NUMBER,
    -- measures
    check_in_date         DATE,
    check_out_date        DATE,
    length_of_stay        NUMBER,
    booking_channel       STRING,
    booking_time          TIMESTAMP,
    cancellation_time     TIMESTAMP,
    status                STRING,
    -- anomaly flags (populated by stored procedures)
    is_double_booked      BOOLEAN DEFAULT FALSE,
    is_suspicious_cancel  BOOLEAN DEFAULT FALSE,
    -- audit
    _loaded_at            TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO RAW_DB.GOLD.FACT_RESERVATION (
    reservation_id,
    guest_sk, room_sk, hotel_sk,
    check_in_date, check_out_date, length_of_stay,
    booking_channel, booking_time,
    cancellation_time, status
)
SELECT
    r.reservation_id,
    g.guest_sk,
    rm.room_sk,
    rm.hotel_sk,
    r.check_in_date,
    r.check_out_date,
    r.length_of_stay,
    r.booking_channel,
    r.booking_time,
    r.cancellation_time,
    r.status
FROM RAW_DB.SILVER.VAL_RESERVATIONS r
-- Join to CURRENT dimension records only
LEFT JOIN RAW_DB.GOLD.DIM_GUEST g
    ON CAST(r.guest_id AS STRING) = CAST(g.guest_id AS STRING)
    AND g.is_current = TRUE
LEFT JOIN RAW_DB.GOLD.DIM_ROOM rm
    ON CAST(r.room_id AS STRING) = CAST(rm.room_id AS STRING)
    AND rm.is_current = TRUE;

SELECT 'FACT_RESERVATION loaded' AS step,
       COUNT(*)                   AS total_rows,
       SUM(CASE WHEN status = 'confirmed'  THEN 1 ELSE 0 END) AS confirmed,
       SUM(CASE WHEN status = 'cancelled'  THEN 1 ELSE 0 END) AS cancelled,
       SUM(CASE WHEN status = 'completed'  THEN 1 ELSE 0 END) AS completed
FROM RAW_DB.GOLD.FACT_RESERVATION;


-- ============================================================
-- STEP 5: FACT_HOUSEKEEPING
-- ============================================================
CREATE OR REPLACE TABLE RAW_DB.GOLD.FACT_HOUSEKEEPING (
    housekeeping_sk      NUMBER AUTOINCREMENT PRIMARY KEY,
    -- foreign keys
    task_id              STRING  NOT NULL UNIQUE,
    room_sk              NUMBER,
    hotel_sk             NUMBER,
    -- measures
    task_type            STRING,
    assigned_staff       STRING,
    scheduled_time       TIMESTAMP,
    start_time           TIMESTAMP,
    end_time             TIMESTAMP,
    duration_minutes     NUMBER,
    issue_detected_flag  BOOLEAN,
    -- SLA flag (cleaning > 45 min | maintenance > 120 min)
    sla_breached         BOOLEAN DEFAULT FALSE,
    status               STRING,
    -- audit
    _loaded_at           TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO RAW_DB.GOLD.FACT_HOUSEKEEPING (
    task_id, room_sk, hotel_sk,
    task_type, assigned_staff,
    scheduled_time, start_time, end_time,
    duration_minutes, issue_detected_flag,
    sla_breached, status
)
SELECT
    h.task_id,
    rm.room_sk,
    rm.hotel_sk,
    h.task_type,
    h.assigned_staff,
    h.scheduled_time,
    h.start_time,
    h.end_time,
    h.duration_minutes,
    h.issue_detected_flag,
    -- SLA breach flag from paper
    CASE
        WHEN h.task_type = 'cleaning'
             AND h.duration_minutes > 45   THEN TRUE
        WHEN h.task_type = 'maintenance'
             AND h.duration_minutes > 120  THEN TRUE
        ELSE FALSE
    END AS sla_breached,
    h.status
FROM RAW_DB.SILVER.VAL_HOUSEKEEPING h
LEFT JOIN RAW_DB.GOLD.DIM_ROOM rm
    ON CAST(h.room_id AS STRING) = CAST(rm.room_id AS STRING)
    AND rm.is_current = TRUE;

SELECT 'FACT_HOUSEKEEPING loaded' AS step,
       COUNT(*)                    AS total_rows,
       SUM(CASE WHEN sla_breached        = TRUE THEN 1 ELSE 0 END) AS sla_breaches,
       SUM(CASE WHEN issue_detected_flag = TRUE THEN 1 ELSE 0 END) AS issues_found
FROM RAW_DB.GOLD.FACT_HOUSEKEEPING;


-- ============================================================
-- STEP 6: FACT_BILLING
-- ============================================================
CREATE OR REPLACE TABLE RAW_DB.GOLD.FACT_BILLING (
    billing_sk        NUMBER AUTOINCREMENT PRIMARY KEY,
    -- foreign keys
    bill_id           STRING  NOT NULL UNIQUE,
    reservation_sk    NUMBER,
    guest_sk          NUMBER,
    -- measures
    total_amount      FLOAT,
    taxes             FLOAT,
    discounts         FLOAT,
    net_amount        FLOAT,
    payment_mode      STRING,
    payment_time      TIMESTAMP,
    -- anomaly flags
    is_flagged        BOOLEAN DEFAULT FALSE,
    billing_mismatch  BOOLEAN DEFAULT FALSE,
    -- audit
    _loaded_at        TIMESTAMP DEFAULT CURRENT_TIMESTAMP()
);

INSERT INTO RAW_DB.GOLD.FACT_BILLING (
    bill_id,
    reservation_sk, guest_sk,
    total_amount, taxes, discounts, net_amount,
    payment_mode, payment_time,
    is_flagged, billing_mismatch
)
SELECT
    b.bill_id,
    fr.reservation_sk,
    g.guest_sk,
    b.total_amount,
    b.taxes,
    b.discounts,
    ROUND(b.total_amount - b.discounts + b.taxes, 2) AS net_amount,
    b.payment_mode,
    b.payment_time,
    b.is_flagged,
    -- Billing mismatch: total != room base_price * length_of_stay
    CASE
        WHEN ABS(b.total_amount -
                (rm.base_price * fr.length_of_stay)) > 500
        THEN TRUE
        ELSE FALSE
    END AS billing_mismatch
FROM RAW_DB.SILVER.VAL_BILLING b
LEFT JOIN RAW_DB.GOLD.FACT_RESERVATION fr
    ON CAST(b.reservation_id AS STRING) = CAST(fr.reservation_id AS STRING)
LEFT JOIN RAW_DB.GOLD.DIM_GUEST g
    ON CAST(b.guest_id AS STRING) = CAST(g.guest_id AS STRING)
    AND g.is_current = TRUE
LEFT JOIN RAW_DB.GOLD.DIM_ROOM rm
    ON fr.room_sk = rm.room_sk
    AND rm.is_current = TRUE;

SELECT 'FACT_BILLING loaded' AS step,
       COUNT(*)               AS total_rows,
       SUM(CASE WHEN is_flagged       = TRUE THEN 1 ELSE 0 END) AS flagged_bills,
       SUM(CASE WHEN billing_mismatch = TRUE THEN 1 ELSE 0 END) AS mismatch_bills,
       ROUND(SUM(total_amount), 2)                              AS total_revenue
FROM RAW_DB.GOLD.FACT_BILLING;


-- ============================================================
-- STEP 7: ANOMALY DETECTION STORED PROCEDURES
-- ============================================================

-- 7A: Double Booking Detection
CREATE OR REPLACE PROCEDURE RAW_DB.GOLD.DETECT_DOUBLE_BOOKINGS()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    flagged NUMBER DEFAULT 0;
BEGIN
    UPDATE RAW_DB.GOLD.FACT_RESERVATION r1
    SET is_double_booked = TRUE
    WHERE r1.status != 'cancelled'
      AND EXISTS (
            SELECT 1
            FROM RAW_DB.GOLD.FACT_RESERVATION r2
            WHERE r2.room_sk         =  r1.room_sk
              AND r2.reservation_id  != r1.reservation_id
              AND r2.status          != 'cancelled'
              AND r2.check_in_date   <  r1.check_out_date
              AND r2.check_out_date  >  r1.check_in_date
      );
    flagged := SQLROWCOUNT;
    RETURN '✅ Double booking detection done | Flagged: ' || flagged;
END;
$$;

-- 7B: Suspicious Cancellation Detection
CREATE OR REPLACE PROCEDURE RAW_DB.GOLD.DETECT_SUSPICIOUS_CANCELS(threshold NUMBER)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    flagged NUMBER DEFAULT 0;
BEGIN
    UPDATE RAW_DB.GOLD.FACT_RESERVATION
    SET is_suspicious_cancel = TRUE
    WHERE status = 'cancelled'
      AND guest_sk IN (
            SELECT guest_sk
            FROM RAW_DB.GOLD.FACT_RESERVATION
            WHERE status            = 'cancelled'
              AND cancellation_time >= DATEADD('hour', -24, CURRENT_TIMESTAMP())
            GROUP BY guest_sk
            HAVING COUNT(*) > :threshold
      );
    flagged := SQLROWCOUNT;
    RETURN '✅ Suspicious cancel detection done | Flagged: ' || flagged;
END;
$$;

-- 7C: Housekeeping SLA Refresh
CREATE OR REPLACE PROCEDURE RAW_DB.GOLD.REFRESH_SLA_FLAGS()
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    updated NUMBER DEFAULT 0;
BEGIN
    UPDATE RAW_DB.GOLD.FACT_HOUSEKEEPING
    SET sla_breached = CASE
        WHEN task_type = 'cleaning'    AND duration_minutes > 45  THEN TRUE
        WHEN task_type = 'maintenance' AND duration_minutes > 120 THEN TRUE
        ELSE FALSE
    END;
    updated := SQLROWCOUNT;
    RETURN '✅ SLA flags refreshed | Updated: ' || updated;
END;
$$;

-- 7D: Billing Mismatch Detection
CREATE OR REPLACE PROCEDURE RAW_DB.GOLD.DETECT_BILLING_MISMATCH(tolerance FLOAT)
RETURNS STRING
LANGUAGE SQL
AS
$$
DECLARE
    flagged NUMBER DEFAULT 0;
BEGIN
    UPDATE RAW_DB.GOLD.FACT_BILLING fb
    SET billing_mismatch = TRUE
    WHERE EXISTS (
        SELECT 1
        FROM RAW_DB.GOLD.FACT_RESERVATION fr
        JOIN RAW_DB.GOLD.DIM_ROOM rm
            ON fr.room_sk = rm.room_sk AND rm.is_current = TRUE
        WHERE fr.reservation_sk = fb.reservation_sk
          AND ABS(fb.total_amount - (rm.base_price * fr.length_of_stay)) > :tolerance
    );
    flagged := SQLROWCOUNT;
    RETURN '✅ Billing mismatch detection done | Flagged: ' || flagged;
END;
$$;


-- ============================================================
-- STEP 8: RUN ALL ANOMALY PROCEDURES
-- ============================================================
CALL RAW_DB.GOLD.DETECT_DOUBLE_BOOKINGS();
CALL RAW_DB.GOLD.DETECT_SUSPICIOUS_CANCELS(3);
CALL RAW_DB.GOLD.REFRESH_SLA_FLAGS();
CALL RAW_DB.GOLD.DETECT_BILLING_MISMATCH(500.0);


-- ============================================================
-- STEP 9: KPI VIEWS (5 KPIs from hackathon paper)
-- ============================================================

-- KPI 1: Room Occupancy Rate
-- Occupied room nights / Total available room nights
CREATE OR REPLACE VIEW RAW_DB.GOLD.VW_KPI1_OCCUPANCY AS
SELECT
    fr.check_in_date                                                    AS date,
    COUNT(DISTINCT fr.room_sk)                                          AS occupied_rooms,
    (SELECT COUNT(*) FROM RAW_DB.GOLD.DIM_ROOM
     WHERE is_current = TRUE)                                           AS total_rooms,
    ROUND(
        100.0 * COUNT(DISTINCT fr.room_sk) /
        NULLIF((SELECT COUNT(*) FROM RAW_DB.GOLD.DIM_ROOM
                WHERE is_current = TRUE), 0)
    , 2)                                                                AS occupancy_rate_pct
FROM RAW_DB.GOLD.FACT_RESERVATION fr
WHERE fr.status != 'cancelled'
GROUP BY 1
ORDER BY 1;

-- KPI 2: Booking Conversion Efficiency
-- (Completed stays / Total reservations) * 100
CREATE OR REPLACE VIEW RAW_DB.GOLD.VW_KPI2_CONVERSION AS
SELECT
    COUNT(*)                                                            AS total_reservations,
    SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END)              AS completed_stays,
    SUM(CASE WHEN status = 'cancelled' THEN 1 ELSE 0 END)              AS cancellations,
    ROUND(
        100.0 * SUM(CASE WHEN status = 'completed' THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0)
    , 2)                                                                AS conversion_pct
FROM RAW_DB.GOLD.FACT_RESERVATION;

-- KPI 3: Housekeeping SLA Compliance
-- % of tasks completed within scheduled time ± threshold
CREATE OR REPLACE VIEW RAW_DB.GOLD.VW_KPI3_SLA AS
SELECT
    task_type,
    COUNT(*)                                                            AS total_tasks,
    SUM(CASE WHEN sla_breached = FALSE THEN 1 ELSE 0 END)              AS on_time_tasks,
    SUM(CASE WHEN sla_breached = TRUE  THEN 1 ELSE 0 END)              AS breached_tasks,
    ROUND(
        100.0 * SUM(CASE WHEN sla_breached = FALSE THEN 1 ELSE 0 END)
        / NULLIF(COUNT(*), 0)
    , 2)                                                                AS sla_compliance_pct,
    ROUND(AVG(duration_minutes), 1)                                     AS avg_duration_min,
    CASE
        WHEN task_type = 'cleaning'    THEN 45
        WHEN task_type = 'maintenance' THEN 120
    END                                                                 AS sla_threshold_min
FROM RAW_DB.GOLD.FACT_HOUSEKEEPING
WHERE duration_minutes IS NOT NULL
GROUP BY task_type;

-- KPI 4: RevPAR (Revenue per Available Room)
-- Total revenue / Total available rooms
CREATE OR REPLACE VIEW RAW_DB.GOLD.VW_KPI4_REVPAR AS
SELECT
    ROUND(SUM(fb.total_amount), 2)                                      AS total_revenue,
    (SELECT COUNT(*) FROM RAW_DB.GOLD.DIM_ROOM
     WHERE is_current = TRUE)                                           AS total_rooms,
    ROUND(
        SUM(fb.total_amount) /
        NULLIF((SELECT COUNT(*) FROM RAW_DB.GOLD.DIM_ROOM
                WHERE is_current = TRUE), 0)
    , 2)                                                                AS revpar
FROM RAW_DB.GOLD.FACT_BILLING fb
JOIN RAW_DB.GOLD.FACT_RESERVATION fr
    ON fb.reservation_sk = fr.reservation_sk
WHERE fr.status != 'cancelled';

-- KPI 5: Billing Accuracy Index
-- 1 - (billing anomalies / total bills)
CREATE OR REPLACE VIEW RAW_DB.GOLD.VW_KPI5_BILLING_ACCURACY AS
SELECT
    COUNT(*)                                                            AS total_bills,
    SUM(CASE WHEN is_flagged       = TRUE THEN 1 ELSE 0 END)           AS flagged_bills,
    SUM(CASE WHEN billing_mismatch = TRUE THEN 1 ELSE 0 END)           AS mismatch_bills,
    SUM(CASE WHEN is_flagged = TRUE
              OR billing_mismatch = TRUE THEN 1 ELSE 0 END)            AS total_anomalies,
    ROUND(
        1.0 - (
            SUM(CASE WHEN is_flagged = TRUE
                      OR billing_mismatch = TRUE THEN 1 ELSE 0 END)
            / NULLIF(COUNT(*), 0)
        )
    , 4)                                                                AS billing_accuracy_index
FROM RAW_DB.GOLD.FACT_BILLING;


-- 
?l;-- STEP 10: FINAL VERIFICATION — ALL GOLD TABLES
-- ============================================================

-- KPI Results
SELECT 'KPI 1 — Occupancy Rate' AS kpi, * FROM RAW_DB.GOLD.VW_KPI1_OCCUPANCY LIMIT 5;
SELECT 'KPI 2 — Conversion'     AS kpi, * FROM RAW_DB.GOLD.VW_KPI2_CONVERSION;
SELECT 'KPI 3 — SLA Compliance' AS kpi, * FROM RAW_DB.GOLD.VW_KPI3_SLA;
SELECT 'KPI 4 — RevPAR'         AS kpi, * FROM RAW_DB.GOLD.VW_KPI4_REVPAR;
SELECT 'KPI 5 — Billing Index'  AS kpi, * FROM RAW_DB.GOLD.VW_KPI5_BILLING_ACCURACY;

-- Anomaly summary
SELECT
    SUM(CASE WHEN is_double_booked     = TRUE THEN 1 ELSE 0 END) AS double_bookings,
    SUM(CASE WHEN is_suspicious_cancel = TRUE THEN 1 ELSE 0 END) AS suspicious_cancels
FROM RAW_DB.GOLD.FACT_RESERVATION;

SELECT
    SUM(CASE WHEN sla_breached        = TRUE THEN 1 ELSE 0 END) AS sla_breaches,
    SUM(CASE WHEN issue_detected_flag = TRUE THEN 1 ELSE 0 END) AS issues_found
FROM RAW_DB.GOLD.FACT_HOUSEKEEPING;

SELECT
    SUM(CASE WHEN is_flagged       = TRUE THEN 1 ELSE 0 END) AS flagged_bills,
    SUM(CASE WHEN billing_mismatch = TRUE THEN 1 ELSE 0 END) AS billing_mismatches
FROM RAW_DB.GOLD.FACT_BILLING;
