"""Ensure PostGIS spatial indexes on critical tables

Revision ID: 0003_spatial_indexes
Revises: 0002_destinations
Create Date: 2026-08-26

Idempotent — uses CREATE INDEX IF NOT EXISTS throughout.
These indexes are essential for:
  - ST_DWithin (nearby driver search)
  - ST_Distance (distance calculation)
  - KNN (k-nearest-neighbour ordering)
"""

from alembic import op

revision = '0003_spatial_indexes'
down_revision = '0002_destinations'
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Ensure GIST indexes exist on spatial columns."""

    # ── driver_locations ─────────────────────────────────────────────────────
    op.execute("""
        CREATE INDEX IF NOT EXISTS driver_locations_location_gix
        ON driver_locations USING GIST(location)
    """)

    # ── ride_requests ─────────────────────────────────────────────────────────
    # Only add if the table exists (the FastAPI backend creates it)
    op.execute("""
        DO $$
        BEGIN
            IF EXISTS (
                SELECT 1 FROM information_schema.tables
                WHERE table_name = 'ride_requests'
                  AND table_schema = 'public'
            ) THEN
                CREATE INDEX IF NOT EXISTS ride_requests_pickup_location_gix
                ON ride_requests USING GIST(pickup_location);
            END IF;
        END $$;
    """)

    # ── rides (completed rides table) ─────────────────────────────────────────
    op.execute("""
        DO $$
        BEGIN
            IF EXISTS (
                SELECT 1 FROM information_schema.tables
                WHERE table_name = 'rides'
                  AND table_schema = 'public'
            ) THEN
                CREATE INDEX IF NOT EXISTS rides_origin_location_gix
                ON rides USING GIST(origin_location);

                CREATE INDEX IF NOT EXISTS rides_destination_location_gix
                ON rides USING GIST(destination_location);
            END IF;
        END $$;
    """)

    # ── Compound index on driver availability + location freshness ────────────
    # Speeds up the most common query: nearby AVAILABLE and FRESH drivers
    op.execute("""
        DO $$
        BEGIN
            IF EXISTS (
                SELECT 1 FROM information_schema.tables
                WHERE table_name = 'driver_locations'
                  AND table_schema = 'public'
            ) THEN
                -- Partial index for available, recently-updated drivers
                CREATE INDEX IF NOT EXISTS driver_locations_available_updated_idx
                ON driver_locations (is_available, updated_at DESC)
                WHERE is_available = true;
            END IF;
        END $$;
    """)


def downgrade() -> None:
    """Remove the indexes added by this migration."""
    op.execute("DROP INDEX IF EXISTS driver_locations_location_gix")
    op.execute("DROP INDEX IF EXISTS ride_requests_pickup_location_gix")
    op.execute("DROP INDEX IF EXISTS rides_origin_location_gix")
    op.execute("DROP INDEX IF EXISTS rides_destination_location_gix")
    op.execute("DROP INDEX IF EXISTS driver_locations_available_updated_idx")
