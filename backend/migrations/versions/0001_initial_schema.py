"""Initial schema: users, drivers, vehicles, driver_locations, rides

Revision ID: 0001_initial
Revises: 
Create Date: 2026-08-26
"""

from alembic import op
import sqlalchemy as sa
import geoalchemy2

# revision identifiers
revision = '0001_initial'
down_revision = None
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Ensure extensions
    op.execute("CREATE EXTENSION IF NOT EXISTS postgis")
    op.execute("CREATE EXTENSION IF NOT EXISTS pgcrypto")

    # 1. Users table
    op.execute("""
        CREATE TABLE IF NOT EXISTS users (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            firebase_uid VARCHAR(128) UNIQUE NOT NULL,
            role VARCHAR(32) NOT NULL DEFAULT 'passenger',
            name VARCHAR(128),
            phone VARCHAR(32),
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
    """)
    op.execute("CREATE INDEX IF NOT EXISTS ix_users_firebase_uid ON users(firebase_uid)")

    # 2. Drivers table
    op.execute("""
        CREATE TABLE IF NOT EXISTS drivers (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            driver_uid VARCHAR(128) UNIQUE NOT NULL REFERENCES users(firebase_uid) ON DELETE CASCADE,
            license_number VARCHAR(64),
            is_verified BOOLEAN NOT NULL DEFAULT FALSE,
            rating FLOAT NOT NULL DEFAULT 5.0,
            total_trips INTEGER NOT NULL DEFAULT 0,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
    """)
    op.execute("CREATE INDEX IF NOT EXISTS ix_drivers_driver_uid ON drivers(driver_uid)")

    # 3. Vehicles table
    op.execute("""
        CREATE TABLE IF NOT EXISTS vehicles (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            driver_uid VARCHAR(128) NOT NULL REFERENCES drivers(driver_uid) ON DELETE CASCADE,
            vehicle_number VARCHAR(32) NOT NULL,
            model VARCHAR(64),
            is_active BOOLEAN NOT NULL DEFAULT TRUE,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
    """)
    op.execute("CREATE INDEX IF NOT EXISTS ix_vehicles_driver_uid ON vehicles(driver_uid)")

    # 4. Driver Locations table
    op.execute("""
        CREATE TABLE IF NOT EXISTS driver_locations (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            driver_uid VARCHAR(128) UNIQUE NOT NULL REFERENCES drivers(driver_uid) ON DELETE CASCADE,
            location GEOGRAPHY(POINT, 4326) NOT NULL,
            accuracy_meters FLOAT,
            heading_degrees FLOAT,
            speed_mps FLOAT,
            is_available BOOLEAN NOT NULL DEFAULT TRUE,
            captured_at TIMESTAMPTZ,
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
    """)
    op.execute("CREATE INDEX IF NOT EXISTS ix_driver_locations_driver_uid ON driver_locations(driver_uid)")
    op.execute("CREATE INDEX IF NOT EXISTS ix_driver_locations_is_available ON driver_locations(is_available)")

    # 5. Rides table
    op.execute("""
        CREATE TABLE IF NOT EXISTS rides (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            passenger_uid VARCHAR(128) NOT NULL REFERENCES users(firebase_uid),
            driver_uid VARCHAR(128) REFERENCES drivers(driver_uid),
            pickup_location GEOGRAPHY(POINT, 4326) NOT NULL,
            dropoff_location GEOGRAPHY(POINT, 4326),
            status VARCHAR(32) NOT NULL DEFAULT 'requested',
            distance_km FLOAT,
            duration_seconds INTEGER,
            notes TEXT,
            created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
            updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
        )
    """)
    op.execute("CREATE INDEX IF NOT EXISTS ix_rides_passenger_uid ON rides(passenger_uid)")
    op.execute("CREATE INDEX IF NOT EXISTS ix_rides_driver_uid ON rides(driver_uid)")
    op.execute("CREATE INDEX IF NOT EXISTS ix_rides_status ON rides(status)")


def downgrade() -> None:
    op.execute("DROP TABLE IF EXISTS rides CASCADE")
    op.execute("DROP TABLE IF EXISTS driver_locations CASCADE")
    op.execute("DROP TABLE IF EXISTS vehicles CASCADE")
    op.execute("DROP TABLE IF EXISTS drivers CASCADE")
    op.execute("DROP TABLE IF EXISTS users CASCADE")
