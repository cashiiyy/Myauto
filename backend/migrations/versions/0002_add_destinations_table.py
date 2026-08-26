"""Add destinations table

Revision ID: 0002_destinations
Revises: 0001
Create Date: 2026-08-26
"""

from alembic import op
import sqlalchemy as sa
import geoalchemy2

# revision identifiers
revision = '0002_destinations'
down_revision = '0001_initial'
branch_labels = None
depends_on = None


def upgrade() -> None:
    """Create the destinations table for passenger destination search."""

    # Ensure PostGIS extension is available
    op.execute("CREATE EXTENSION IF NOT EXISTS postgis")
    op.execute("CREATE EXTENSION IF NOT EXISTS pgcrypto")

    op.execute("""
        CREATE TABLE IF NOT EXISTS destinations (
            id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
            user_uid TEXT NOT NULL,
            place_name TEXT NOT NULL,
            display_label TEXT NOT NULL,
            location GEOGRAPHY(POINT, 4326) NOT NULL,
            created_at TIMESTAMPTZ DEFAULT NOW(),
            updated_at TIMESTAMPTZ DEFAULT NOW()
        )
    """)

    # Spatial index for proximity queries
    op.execute("""
        CREATE INDEX IF NOT EXISTS destinations_location_gix
        ON destinations USING GIST(location)
    """)

    # Index on user_uid for per-user queries
    op.execute("""
        CREATE INDEX IF NOT EXISTS destinations_user_uid_idx
        ON destinations (user_uid)
    """)

    # Index on created_at for recency sorting
    op.execute("""
        CREATE INDEX IF NOT EXISTS destinations_created_at_idx
        ON destinations (created_at DESC)
    """)


def downgrade() -> None:
    """Drop the destinations table and its indexes."""
    op.execute("DROP TABLE IF EXISTS destinations CASCADE")
