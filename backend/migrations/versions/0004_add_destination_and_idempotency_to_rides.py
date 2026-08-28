"""Add destination, selected_driver_uid, passenger_name, idempotency_key, and lifecycle fields to rides table

Revision ID: 0004_rides_dest_idemp
Revises: 0003_spatial_indexes
Create Date: 2026-08-28
"""

from alembic import op
import sqlalchemy as sa

# revision identifiers
revision = '0004_rides_dest_idemp'
down_revision = '0003_spatial_indexes'
branch_labels = None
depends_on = None


def upgrade() -> None:
    # Check and add columns to 'rides' table safely
    op.execute("""
        DO $$
        BEGIN
            IF EXISTS (
                SELECT 1 FROM information_schema.tables
                WHERE table_name = 'rides'
                  AND table_schema = 'public'
            ) THEN
                -- Dropoff coordinates and destination metadata
                ALTER TABLE rides ADD COLUMN IF NOT EXISTS dropoff_lat FLOAT;
                ALTER TABLE rides ADD COLUMN IF NOT EXISTS dropoff_lng FLOAT;
                ALTER TABLE rides ADD COLUMN IF NOT EXISTS destination_label VARCHAR(256);

                -- Selected driver if pre-selected by passenger
                ALTER TABLE rides ADD COLUMN IF NOT EXISTS selected_driver_uid VARCHAR(128);

                -- Passenger display name snapshot
                ALTER TABLE rides ADD COLUMN IF NOT EXISTS passenger_name VARCHAR(128);

                -- Idempotency key to prevent duplicate booking
                ALTER TABLE rides ADD COLUMN IF NOT EXISTS idempotency_key VARCHAR(64);

                -- Request expiry and cancellation details
                ALTER TABLE rides ADD COLUMN IF NOT EXISTS request_expires_at TIMESTAMPTZ;
                ALTER TABLE rides ADD COLUMN IF NOT EXISTS cancelled_by VARCHAR(32);
                ALTER TABLE rides ADD COLUMN IF NOT EXISTS cancel_reason TEXT;

                -- Foreign key for selected_driver_uid if drivers table exists
                IF NOT EXISTS (
                    SELECT 1 FROM information_schema.table_constraints
                    WHERE constraint_name = 'fk_rides_selected_driver'
                      AND table_name = 'rides'
                ) THEN
                    ALTER TABLE rides
                    ADD CONSTRAINT fk_rides_selected_driver
                    FOREIGN KEY (selected_driver_uid) REFERENCES drivers(driver_uid)
                    ON DELETE SET NULL;
                END IF;

                -- Indexes for fast query and idempotency lookup
                CREATE INDEX IF NOT EXISTS ix_rides_idempotency_key ON rides(idempotency_key);
                CREATE INDEX IF NOT EXISTS ix_rides_selected_driver_uid ON rides(selected_driver_uid);
                CREATE INDEX IF NOT EXISTS ix_rides_request_expires_at ON rides(request_expires_at);
            END IF;
        END $$;
    """)


def downgrade() -> None:
    op.execute("""
        DO $$
        BEGIN
            IF EXISTS (
                SELECT 1 FROM information_schema.tables
                WHERE table_name = 'rides'
                  AND table_schema = 'public'
            ) THEN
                DROP INDEX IF EXISTS ix_rides_request_expires_at;
                DROP INDEX IF EXISTS ix_rides_selected_driver_uid;
                DROP INDEX IF EXISTS ix_rides_idempotency_key;

                ALTER TABLE rides DROP CONSTRAINT IF EXISTS fk_rides_selected_driver;

                ALTER TABLE rides DROP COLUMN IF EXISTS cancel_reason;
                ALTER TABLE rides DROP COLUMN IF EXISTS cancelled_by;
                ALTER TABLE rides DROP COLUMN IF EXISTS request_expires_at;
                ALTER TABLE rides DROP COLUMN IF EXISTS idempotency_key;
                ALTER TABLE rides DROP COLUMN IF EXISTS passenger_name;
                ALTER TABLE rides DROP COLUMN IF EXISTS selected_driver_uid;
                ALTER TABLE rides DROP COLUMN IF EXISTS destination_label;
                ALTER TABLE rides DROP COLUMN IF EXISTS dropoff_lng;
                ALTER TABLE rides DROP COLUMN IF EXISTS dropoff_lat;
            END IF;
        END $$;
    """)
