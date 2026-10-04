-- Migration 001: Enable PostgreSQL Extensions
-- P1A-01: Enable PostGIS extension (geospatial queries for driver location, delivery zones)
-- P1A-02: Enable pg_trgm extension (trigram fuzzy search on merchant/item names)
-- P1A-03: Enable uuid-ossp extension (UUID generation for primary keys)

-- PostGIS: Required for geospatial queries (nearest driver, distance calculation, delivery zones)
CREATE EXTENSION IF NOT EXISTS postgis;

-- pg_trgm: Required for fuzzy text search on bilingual names (name_ar, name_en)
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- uuid-ossp: Provides uuid_generate_v4() for auto-generating UUIDs
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Also enable pgcrypto as a fallback/complement for UUID generation
CREATE EXTENSION IF NOT EXISTS pgcrypto;
