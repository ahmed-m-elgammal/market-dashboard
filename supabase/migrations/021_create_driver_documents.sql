-- Migration 021: Create driver_documents table
-- P1C-08: Create driver_documents table
-- P1C-09: Add UNIQUE(driver_id, document_type) on driver_documents

-- =============================================================================
-- DRIVER_DOCUMENTS TABLE (P1C-08)
-- Stores all uploaded documents for a driver with full audit trail.
-- Documents are uploaded by the driver during onboarding, reviewed by admin.
-- Files are stored in Supabase Storage bucket: driver-documents/{driver_id}/{doc_type}.{ext}
-- =============================================================================
CREATE TABLE driver_documents (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

  -- Driver reference
  driver_id UUID NOT NULL REFERENCES drivers(id) ON DELETE CASCADE,

  -- Document type (8 types covering all required and optional docs)
  document_type TEXT NOT NULL CHECK (document_type IN (
    'national_id_front',
    'national_id_back',
    'driving_license_front',
    'driving_license_back',
    'vehicle_registration',
    'vehicle_insurance',
    'criminal_record',
    'other'
  )),

  -- File details
  file_url TEXT NOT NULL,
  file_name TEXT NOT NULL,
  file_size_bytes INTEGER NOT NULL CHECK (file_size_bytes > 0),
  mime_type TEXT NOT NULL DEFAULT 'image/jpeg'
    CHECK (mime_type IN ('image/jpeg', 'image/png', 'image/webp')),

  -- Review status (admin reviews each document)
  status TEXT NOT NULL DEFAULT 'pending'
    CHECK (status IN ('pending', 'approved', 'rejected')),
  rejection_reason TEXT,

  -- Review audit
  reviewed_by UUID REFERENCES profiles(id),
  reviewed_at TIMESTAMPTZ,

  -- Upload timestamp
  uploaded_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),

  -- P1C-09: Unique constraint — one document per type per driver
  CONSTRAINT unique_driver_doc_type UNIQUE (driver_id, document_type)
);

-- Index: find pending documents for admin review
CREATE INDEX idx_driver_documents_status
  ON driver_documents(status) WHERE status = 'pending';

-- Index: find all documents for a driver
CREATE INDEX idx_driver_documents_driver
  ON driver_documents(driver_id);

-- =============================================================================
-- COMMENTS
-- =============================================================================
COMMENT ON TABLE driver_documents IS 'Driver verification documents. Uploaded by driver during onboarding, reviewed by admin. Files stored in driver-documents storage bucket (private).';
COMMENT ON COLUMN driver_documents.document_type IS 'national_id_front/back and driving_license_front/back are required. Others are optional.';
COMMENT ON COLUMN driver_documents.status IS 'pending=awaiting admin review, approved=admin verified, rejected=admin rejected (see rejection_reason).';
COMMENT ON COLUMN driver_documents.file_url IS 'Supabase Storage path: driver-documents/{driver_id}/{document_type}.{ext}';
COMMENT ON COLUMN driver_documents.reviewed_by IS 'Admin (profile UUID) who reviewed this document.';

-- Enable RLS
ALTER TABLE public.driver_documents ENABLE ROW LEVEL SECURITY;
