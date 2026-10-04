-- Migration 025: Create storage buckets + policies
-- P1G-01: Create `merchant-assets` bucket (public read, service role write)
-- P1G-02: Create `item-images` bucket (public read, service role write)
-- P1G-03: Create `driver-documents` bucket (private, service role + own driver write) 🔒
-- P1G-04: Create `user-avatars` bucket (public read, authenticated write to own path)
-- P1G-05: Create `ad-creatives` bucket (public read, service role write)
-- P1G-06: Set max file size 5MB per bucket
-- P1G-07: Set allowed MIME types: image/jpeg, image/png, image/webp
--
-- Supabase Storage uses the `storage.buckets` system table and
-- `storage.objects` for files. Policies are defined on storage.objects.
--
-- IMPORTANT: Storage policies are SEPARATE from RLS policies on public tables.
-- They use storage-specific auth functions:
--   auth.uid()        — current user's UUID
--   auth.role()       — current role ('anon', 'authenticated', 'service_role')
--   storage.filename  — the file path within the bucket
--   storage.extension — the file extension

-- =============================================================================
-- P1G-01: MERCHANT-ASSETS BUCKET
-- Stores merchant logos and cover images.
-- Path convention: merchant-assets/{merchant_id}/logo.{ext}
--                  merchant-assets/{merchant_id}/cover.{ext}
-- Public read: anyone can view merchant images (feed, search, merchant page).
-- Service role write: only admin/API can upload merchant images.
-- =============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'merchant-assets',
  'merchant-assets',
  TRUE,  -- public read access
  5242880,  -- 5MB in bytes (5 * 1024 * 1024)
  ARRAY['image/jpeg', 'image/png', 'image/webp']
);

-- Policy: anyone can read merchant assets (public bucket, but explicit policy for clarity)
CREATE POLICY "merchant_assets_read"
  ON storage.objects
  FOR SELECT
  USING (bucket_id = 'merchant-assets');

-- Policy: only service role can upload/update/delete merchant assets
CREATE POLICY "merchant_assets_write"
  ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'merchant-assets'
    AND auth.role() = 'service_role'
  );

CREATE POLICY "merchant_assets_update"
  ON storage.objects
  FOR UPDATE
  USING (
    bucket_id = 'merchant-assets'
    AND auth.role() = 'service_role'
  )
  WITH CHECK (
    bucket_id = 'merchant-assets'
    AND auth.role() = 'service_role'
  );

CREATE POLICY "merchant_assets_delete"
  ON storage.objects
  FOR DELETE
  USING (
    bucket_id = 'merchant-assets'
    AND auth.role() = 'service_role'
  );

-- =============================================================================
-- P1G-02: ITEM-IMAGES BUCKET
-- Stores menu item images.
-- Path convention: item-images/{merchant_id}/{item_id}.{ext}
-- Public read: anyone can view item images (menu display).
-- Service role write: only admin/API can upload item images.
-- =============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'item-images',
  'item-images',
  TRUE,  -- public read access
  5242880,  -- 5MB in bytes
  ARRAY['image/jpeg', 'image/png', 'image/webp']
);

-- Policy: anyone can read item images
CREATE POLICY "item_images_read"
  ON storage.objects
  FOR SELECT
  USING (bucket_id = 'item-images');

-- Policy: only service role can upload/update/delete item images
CREATE POLICY "item_images_write"
  ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'item-images'
    AND auth.role() = 'service_role'
  );

CREATE POLICY "item_images_update"
  ON storage.objects
  FOR UPDATE
  USING (
    bucket_id = 'item-images'
    AND auth.role() = 'service_role'
  )
  WITH CHECK (
    bucket_id = 'item-images'
    AND auth.role() = 'service_role'
  );

CREATE POLICY "item_images_delete"
  ON storage.objects
  FOR DELETE
  USING (
    bucket_id = 'item-images'
    AND auth.role() = 'service_role'
  );

-- =============================================================================
-- P1G-03: DRIVER-DOCUMENTS BUCKET (🔒 SECURITY-CRITICAL)
-- Stores driver verification documents (national ID, license, vehicle reg, etc.).
-- Path convention: driver-documents/{driver_id}/{document_type}.{ext}
--
-- 🔒 PRIVATE BUCKET — no public access.
--   - Driver can read their own documents (path starts with their user ID)
--   - Driver can upload (insert) their own documents during onboarding
--   - Driver CANNOT update or delete documents after upload (prevents tampering)
--   - Service role full access (admin reviews documents, creates signed URLs)
--
-- Per 21-SECURITY-AUDIT-COMPLIANCE.md:
--   "Driver documents stored in private bucket (not publicly accessible)"
--   "Signed URLs with expiration for viewing"
-- =============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'driver-documents',
  'driver-documents',
  FALSE,  -- PRIVATE bucket — no public access
  5242880,  -- 5MB in bytes
  ARRAY['image/jpeg', 'image/png', 'image/webp']
);

-- Policy: drivers can read their own documents only (path = {driver_id}/...)
CREATE POLICY "driver_documents_read_own"
  ON storage.objects
  FOR SELECT
  USING (
    bucket_id = 'driver-documents'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

-- Policy: drivers can upload their own documents (insert only, no update/delete)
CREATE POLICY "driver_documents_insert_own"
  ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'driver-documents'
    AND auth.uid()::text = (storage.foldername(name))[1]
    AND auth.role() = 'authenticated'
  );

-- No UPDATE policy: drivers cannot modify documents after upload
-- No DELETE policy: drivers cannot delete documents after upload
-- Only service role can update/delete (bypasses policies)

-- =============================================================================
-- P1G-04: USER-AVATARS BUCKET
-- Stores user profile avatar images.
-- Path convention: user-avatars/{user_id}/avatar.{ext}
-- Public read: avatars are visible in reviews, order tracking, etc.
-- Authenticated write: users can upload their own avatar (path must match their user ID).
-- =============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'user-avatars',
  'user-avatars',
  TRUE,  -- public read access
  5242880,  -- 5MB in bytes
  ARRAY['image/jpeg', 'image/png', 'image/webp']
);

-- Policy: anyone can read user avatars
CREATE POLICY "user_avatars_read"
  ON storage.objects
  FOR SELECT
  USING (bucket_id = 'user-avatars');

-- Policy: authenticated users can upload their own avatar
-- Path must start with their user ID: user-avatars/{user_id}/avatar.{ext}
CREATE POLICY "user_avatars_insert_own"
  ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'user-avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
    AND auth.role() = 'authenticated'
  );

-- Policy: users can update their own avatar
CREATE POLICY "user_avatars_update_own"
  ON storage.objects
  FOR UPDATE
  USING (
    bucket_id = 'user-avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  )
  WITH CHECK (
    bucket_id = 'user-avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

-- Policy: users can delete their own avatar
CREATE POLICY "user_avatars_delete_own"
  ON storage.objects
  FOR DELETE
  USING (
    bucket_id = 'user-avatars'
    AND auth.uid()::text = (storage.foldername(name))[1]
  );

-- =============================================================================
-- P1G-05: AD-CREATIVES BUCKET
-- Stores promotional/ad creative images for promoted slots.
-- Path convention: ad-creatives/{promoted_slot_id}/creative.{ext}
-- Public read: ads are displayed to all users in the feed.
-- Service role write: only admin/API can upload ad creatives.
-- =============================================================================

INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'ad-creatives',
  'ad-creatives',
  TRUE,  -- public read access
  5242880,  -- 5MB in bytes
  ARRAY['image/jpeg', 'image/png', 'image/webp']
);

-- Policy: anyone can read ad creatives
CREATE POLICY "ad_creatives_read"
  ON storage.objects
  FOR SELECT
  USING (bucket_id = 'ad-creatives');

-- Policy: only service role can upload/update/delete ad creatives
CREATE POLICY "ad_creatives_write"
  ON storage.objects
  FOR INSERT
  WITH CHECK (
    bucket_id = 'ad-creatives'
    AND auth.role() = 'service_role'
  );

CREATE POLICY "ad_creatives_update"
  ON storage.objects
  FOR UPDATE
  USING (
    bucket_id = 'ad-creatives'
    AND auth.role() = 'service_role'
  )
  WITH CHECK (
    bucket_id = 'ad-creatives'
    AND auth.role() = 'service_role'
  );

CREATE POLICY "ad_creatives_delete"
  ON storage.objects
  FOR DELETE
  USING (
    bucket_id = 'ad-creatives'
    AND auth.role() = 'service_role'
  );

-- =============================================================================
-- P1G-06: MAX FILE SIZE 5MB PER BUCKET
-- Already set above via file_size_limit = 5242880 (5 * 1024 * 1024 bytes)
-- on each bucket. This enforces the limit at the Supabase Storage level.
-- =============================================================================

-- =============================================================================
-- P1G-07: ALLOWED MIME TYPES
-- Already set above via allowed_mime_types = ARRAY['image/jpeg', 'image/png', 'image/webp']
-- on each bucket. This enforces the limit at the Supabase Storage level.
-- Rejects uploads of any other file type (PDF, SVG, GIF, video, executable, etc.)
-- =============================================================================


