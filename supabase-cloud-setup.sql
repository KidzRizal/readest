-- Mengread / Readest schema untuk Supabase Cloud.
-- Dibuat dari docker/volumes/db/init/schema.sql + migrations/*.sql (urut nama).
-- Baris "ALTER FUNCTION auth.* OWNER" dihapus (khusus Docker; tidak diizinkan di Cloud).
-- Jalankan SEKALI di Dashboard > SQL Editor pada project baru.

-- ===== init/schema.sql =====

CREATE TABLE public.books (
  user_id uuid NOT NULL,
  book_hash text NOT NULL,
  meta_hash text NULL,
  format text NULL,
  title text NULL,
  source_title text NULL,
  author text NULL,
  "group" text NULL,
  tags text[] NULL,
  created_at timestamp with time zone NULL DEFAULT now(),
  updated_at timestamp with time zone NULL DEFAULT now(),
  deleted_at timestamp with time zone NULL,
  uploaded_at timestamp with time zone NULL,
  synced_at timestamp with time zone NOT NULL DEFAULT now(),
  progress integer[] NULL,
  reading_status text NULL,
  reading_status_updated_at timestamp with time zone NULL,
  cover_hash text NULL,
  cover_updated_at timestamp with time zone NULL,
  metadata_updated_at timestamp with time zone NULL,
  group_id text NULL,
  group_name text NULL,
  group_updated_at timestamp with time zone NULL,
  metadata json NULL,
  CONSTRAINT books_pkey PRIMARY KEY (user_id, book_hash),
  CONSTRAINT books_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users (id) ON DELETE CASCADE
);

-- Server-assigned incremental-pull cursor, decoupled from updated_at (the
-- client event time / sort key). A trigger stamps it on every write so a
-- server-resolved merge propagates without reordering the date-read library.
-- See migration 016_add_books_synced_at.sql (issue #4678).
CREATE INDEX idx_books_user_synced ON public.books (user_id, synced_at);

CREATE OR REPLACE FUNCTION public.set_books_synced_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.synced_at := now();
  RETURN NEW;
END;
$$;

CREATE TRIGGER books_set_synced_at
  BEFORE INSERT OR UPDATE ON public.books
  FOR EACH ROW
  EXECUTE FUNCTION public.set_books_synced_at();

ALTER TABLE public.books ENABLE ROW LEVEL SECURITY;
CREATE POLICY select_books ON public.books FOR SELECT TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY insert_books ON public.books FOR INSERT TO authenticated WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY update_books ON public.books FOR UPDATE TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY delete_books ON public.books FOR DELETE TO authenticated USING ((SELECT auth.uid()) = user_id);

CREATE TABLE public.book_configs (
  user_id uuid NOT NULL,
  book_hash text NOT NULL,
  meta_hash text NULL,
  location text NULL,
  xpointer text NULL,
  progress jsonb NULL,
  rsvp_position text NULL,
  search_config jsonb NULL,
  view_settings jsonb NULL,
  created_at timestamp with time zone NULL DEFAULT now(),
  updated_at timestamp with time zone NULL DEFAULT now(),
  deleted_at timestamp with time zone NULL,
  CONSTRAINT book_configs_pkey PRIMARY KEY (user_id, book_hash),
  CONSTRAINT book_configs_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users (id) ON DELETE CASCADE
);

ALTER TABLE public.book_configs ENABLE ROW LEVEL SECURITY;
CREATE POLICY select_book_configs ON public.book_configs FOR SELECT TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY insert_book_configs ON public.book_configs FOR INSERT TO authenticated WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY update_book_configs ON public.book_configs FOR UPDATE TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY delete_book_configs ON public.book_configs FOR DELETE TO authenticated USING ((SELECT auth.uid()) = user_id);

CREATE TABLE public.book_notes (
  user_id uuid NOT NULL,
  book_hash text NOT NULL,
  meta_hash text NULL,
  id text NOT NULL,
  type text NULL,
  cfi text NULL,
  xpointer0 text NULL,
  xpointer1 text NULL,
  text text NULL,
  style text NULL,
  color text NULL,
  note text NULL,
  page integer NULL,
  global boolean NULL,
  created_at timestamp with time zone NULL DEFAULT now(),
  updated_at timestamp with time zone NULL DEFAULT now(),
  deleted_at timestamp with time zone NULL,
  CONSTRAINT book_notes_pkey PRIMARY KEY (user_id, book_hash, id),
  CONSTRAINT book_notes_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users (id) ON DELETE CASCADE
);

ALTER TABLE public.book_notes ENABLE ROW LEVEL SECURITY;
CREATE POLICY select_book_notes ON public.book_notes FOR SELECT TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY insert_book_notes ON public.book_notes FOR INSERT TO authenticated WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY update_book_notes ON public.book_notes FOR UPDATE TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY delete_book_notes ON public.book_notes FOR DELETE TO authenticated USING ((SELECT auth.uid()) = user_id);

CREATE TABLE public.files (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  book_hash text NULL,
  file_key text NOT NULL,
  file_size bigint NOT NULL,
  created_at timestamp with time zone NULL DEFAULT now(),
  updated_at timestamp with time zone NULL DEFAULT now(),
  deleted_at timestamp with time zone NULL,
  CONSTRAINT files_pkey PRIMARY KEY (id),
  CONSTRAINT files_file_key_key UNIQUE (file_key),
  CONSTRAINT files_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users (id) ON DELETE CASCADE
);

CREATE INDEX idx_files_user_id_deleted_at ON public.files (user_id, deleted_at);
CREATE INDEX idx_files_file_key ON public.files (file_key);
CREATE INDEX idx_files_file_key_deleted_at ON public.files (file_key, deleted_at);

ALTER TABLE public.files ENABLE ROW LEVEL SECURITY;
CREATE POLICY files_insert ON public.files FOR INSERT WITH CHECK (auth.uid() = user_id);
CREATE POLICY files_select ON public.files FOR SELECT USING (auth.uid() = user_id AND deleted_at IS NULL);
CREATE POLICY files_update ON public.files FOR UPDATE USING (auth.uid() = user_id) WITH CHECK (deleted_at IS NULL OR deleted_at > now());
CREATE POLICY files_delete ON public.files FOR DELETE USING (auth.uid() = user_id);

GRANT ALL ON public.books TO authenticated;
GRANT ALL ON public.book_configs TO authenticated;
GRANT ALL ON public.book_notes TO authenticated;
GRANT ALL ON public.files TO authenticated;

-- ===== migrations/001_add_rsvp_position.sql =====
-- Migration 001: Add rsvp_position column to book_configs

ALTER TABLE public.book_configs
  ADD COLUMN IF NOT EXISTS rsvp_position text NULL;


-- ===== migrations/002_add_book_shares.sql =====
-- Migration 002: Add book_shares table for time-limited share links

CREATE TABLE IF NOT EXISTS public.book_shares (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  -- token_hash is the lookup key (sha256(token)). It is unique-indexed so
  -- public landing-page reads and downloads are O(1). The plaintext token
  -- is also stored so the owner can copy links after the create dialog
  -- closes. RLS prevents anyone but the owner from reading the plaintext.
  -- Public endpoints look up by hash only and never select the token column.
  token_hash text NOT NULL,
  token text NOT NULL,
  user_id uuid NOT NULL,
  book_hash text NOT NULL,
  book_title text NOT NULL,
  book_author text NULL,
  book_format text NOT NULL,
  book_size bigint NOT NULL,
  cfi text NULL,
  expires_at timestamp with time zone NOT NULL,
  revoked_at timestamp with time zone NULL,
  download_count integer NOT NULL DEFAULT 0,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT book_shares_pkey PRIMARY KEY (id),
  CONSTRAINT book_shares_token_hash_key UNIQUE (token_hash),
  CONSTRAINT book_shares_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users (id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_book_shares_user_id ON public.book_shares (user_id);
CREATE INDEX IF NOT EXISTS idx_book_shares_user_id_book_hash ON public.book_shares (user_id, book_hash);

ALTER TABLE public.book_shares ENABLE ROW LEVEL SECURITY;

CREATE POLICY book_shares_select ON public.book_shares
  FOR SELECT TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY book_shares_insert ON public.book_shares
  FOR INSERT TO authenticated WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY book_shares_update ON public.book_shares
  FOR UPDATE TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY book_shares_delete ON public.book_shares
  FOR DELETE TO authenticated USING ((SELECT auth.uid()) = user_id);

-- Atomic download_count increment used by the public /download/confirm beacon.
-- Runs as SECURITY DEFINER so unauthenticated callers can bump the counter
-- (the route gate is "the share is active"; the function enforces that).
-- Only increments rows that are active right now — bypasses revoked/expired
-- so late-firing analytics pings don't pollute the count.
CREATE OR REPLACE FUNCTION public.increment_book_share_download(
  p_token_hash text,
  p_now timestamp with time zone
) RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  UPDATE public.book_shares
  SET download_count = download_count + 1
  WHERE token_hash = p_token_hash
    AND revoked_at IS NULL
    AND expires_at > p_now;
$$;

GRANT EXECUTE ON FUNCTION public.increment_book_share_download(text, timestamp with time zone)
  TO anon, authenticated, service_role;


-- ===== migrations/003_add_replicas.sql =====
-- Migration 003: Add replicas table for cross-device sync of user-imported assets
-- (dictionaries, fonts, textures, OPDS catalogs, dict settings — gated by
--  a per-kind allowlist enforced both in DB CHECK and in server validation).
-- See ~/.claude/plans/vivid-orbiting-thimble.md and
-- src/libs/crdt.README.md for the design.

-- ─────────────────────────────────────────────────────────────────────────
-- replica_keys: per-account PBKDF2 salt for the encrypted-fields envelope.
-- One row per (user_id, alg). A passphrase rotation appends a new row;
-- forgot-passphrase deletes all rows for the user (and the migrate-time
-- check on encrypted envelopes makes them unreadable client-side).
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.replica_keys (
  user_id uuid NOT NULL,
  salt_id text NOT NULL,
  alg text NOT NULL,
  salt bytea NOT NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT replica_keys_pkey PRIMARY KEY (user_id, salt_id),
  CONSTRAINT replica_keys_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users (id) ON DELETE CASCADE
);

ALTER TABLE public.replica_keys ENABLE ROW LEVEL SECURITY;

CREATE POLICY replica_keys_select ON public.replica_keys
  FOR SELECT TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY replica_keys_insert ON public.replica_keys
  FOR INSERT TO authenticated WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY replica_keys_delete ON public.replica_keys
  FOR DELETE TO authenticated USING ((SELECT auth.uid()) = user_id);

-- ─────────────────────────────────────────────────────────────────────────
-- replicas: polymorphic per-user CRDT-backed metadata.
--   kind            — server-allowlisted: 'dictionary' in PR 1; future kinds
--                     require a server release that updates the CHECK below.
--   fields_jsonb    — per-field LWW envelope: {<field>: {v, t: <Hlc>, s}}
--                     PR-validated 64 KiB / 64-field caps server-side.
--   manifest_jsonb  — committed last after binary upload completes.
--                     null = "binaries pending"; row not yet downloadable.
--   deleted_at_ts   — remove-wins tombstone HLC. A field write does NOT
--                     revive a tombstoned row.
--   reincarnation   — explicit re-import token; swaps row to alive under a
--                     new logical identity.
--   updated_at_ts   — max(field HLCs, deleted_at_ts, row-level operation
--                     HLCs such as manifest commits). Used as the pull cursor.
--   schema_version  — per-kind schema bump; server enforces bounds.
-- ─────────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.replicas (
  user_id uuid NOT NULL,
  kind text NOT NULL,
  replica_id text NOT NULL,
  fields_jsonb jsonb NOT NULL DEFAULT '{}'::jsonb,
  manifest_jsonb jsonb NULL,
  deleted_at_ts text NULL,
  reincarnation text NULL,
  updated_at_ts text NOT NULL,
  schema_version integer NOT NULL DEFAULT 1,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  modified_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT replicas_pkey PRIMARY KEY (user_id, kind, replica_id),
  CONSTRAINT replicas_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users (id) ON DELETE CASCADE,
  -- Server allowlist for kind. Adding a new kind = a coordinated client +
  -- server PR; this CHECK is part of the server release.
  CONSTRAINT replicas_kind_allowlist CHECK (kind IN ('dictionary')),
  -- Hard caps. validateRow() in src/libs/replica-schemas.ts enforces the
  -- same bounds at the API layer with a clearer error code; these CHECKs
  -- are belt-and-suspenders for direct DB writes.
  CONSTRAINT replicas_fields_size CHECK (pg_column_size(fields_jsonb) <= 65536),
  CONSTRAINT replicas_schema_version CHECK (schema_version >= 1 AND schema_version <= 1000)
);

CREATE INDEX IF NOT EXISTS idx_replicas_pull_cursor
  ON public.replicas (user_id, kind, updated_at_ts);

ALTER TABLE public.replicas ENABLE ROW LEVEL SECURITY;

CREATE POLICY replicas_select ON public.replicas
  FOR SELECT TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY replicas_insert ON public.replicas
  FOR INSERT TO authenticated WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY replicas_update ON public.replicas
  FOR UPDATE TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY replicas_delete ON public.replicas
  FOR DELETE TO authenticated USING ((SELECT auth.uid()) = user_id);


-- ===== migrations/004_crdt_merge_replica_fn.sql =====
-- Migration 004: crdt_merge_replica() — atomic CRDT merge for the replicas
-- table. Mirrors src/libs/crdt.ts mergeReplica() so client and server
-- converge on identical merge results.
--
-- Properties (verified by tests in src/__tests__/libs/crdt.test.ts and
-- the server-merge race test):
--   * commutative, associative, idempotent on fields_jsonb
--   * remove-wins: a field write never revives a tombstone (deleted_at_ts
--     stays the larger of the two sides)
--   * preserves unknown fields from either side (forwards-compat across
--     schemaVersion bumps)
--   * deviceId tiebreak when two field envelopes share the same HLC
--
-- Called via INSERT … ON CONFLICT … DO UPDATE in a single SQL statement
-- so two concurrent pushes can't interleave fetch-then-upsert. RUNS AS
-- SECURITY INVOKER (default) — the surrounding INSERT/UPDATE is RLS-
-- gated, so we don't need DEFINER. The server endpoint additionally
-- asserts auth.uid() = NEW.user_id before invoking the upsert.

-- ─────────────────────────────────────────────────────────────────────────
-- HLC max helper. NULLs lose. Plain text comparison since the HLC packing
-- format makes lexicographic order match temporal order.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.hlc_max(a text, b text)
RETURNS text
LANGUAGE sql IMMUTABLE PARALLEL SAFE
AS $$
  SELECT CASE
    WHEN a IS NULL THEN b
    WHEN b IS NULL THEN a
    WHEN a >= b THEN a
    ELSE b
  END;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- Field-level LWW merge for fields_jsonb. Per-key: keep the envelope with
-- the larger envelope.t (HLC string). Tie on HLC: deviceId (envelope.s)
-- lex-order tiebreak. Preserves keys present on either side.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.crdt_merge_fields(local_fields jsonb, remote_fields jsonb)
RETURNS jsonb
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
AS $$
DECLARE
  result jsonb := COALESCE(local_fields, '{}'::jsonb);
  k text;
  l_env jsonb;
  r_env jsonb;
  l_t text;
  r_t text;
  l_s text;
  r_s text;
BEGIN
  IF remote_fields IS NULL THEN
    RETURN result;
  END IF;
  FOR k IN SELECT jsonb_object_keys(remote_fields) LOOP
    r_env := remote_fields -> k;
    l_env := result -> k;
    IF l_env IS NULL THEN
      result := jsonb_set(result, ARRAY[k], r_env, true);
    ELSE
      l_t := l_env ->> 't';
      r_t := r_env ->> 't';
      IF r_t > l_t THEN
        result := jsonb_set(result, ARRAY[k], r_env, true);
      ELSIF r_t = l_t THEN
        l_s := COALESCE(l_env ->> 's', '');
        r_s := COALESCE(r_env ->> 's', '');
        IF r_s > l_s THEN
          result := jsonb_set(result, ARRAY[k], r_env, true);
        END IF;
      END IF;
    END IF;
  END LOOP;
  RETURN result;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- Content updated_at_ts = max over field HLCs and tombstone HLC.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.crdt_compute_updated_at(fields jsonb, deleted_at text)
RETURNS text
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE
AS $$
DECLARE
  result text := COALESCE(deleted_at, '0000000000000-00000000-');
  k text;
  env jsonb;
  t text;
BEGIN
  IF fields IS NULL THEN
    RETURN result;
  END IF;
  FOR k IN SELECT jsonb_object_keys(fields) LOOP
    env := fields -> k;
    t := env ->> 't';
    IF t IS NOT NULL AND t > result THEN
      result := t;
    END IF;
  END LOOP;
  RETURN result;
END;
$$;

-- ─────────────────────────────────────────────────────────────────────────
-- Full row merge. Used in:
--   INSERT INTO replicas (...) VALUES (...)
--   ON CONFLICT (user_id, kind, replica_id) DO UPDATE SET
--     fields_jsonb   = crdt_merge_fields(replicas.fields_jsonb, EXCLUDED.fields_jsonb),
--     deleted_at_ts  = hlc_max(replicas.deleted_at_ts, EXCLUDED.deleted_at_ts),
--     reincarnation  = CASE WHEN replicas.reincarnation = EXCLUDED.reincarnation
--                           THEN replicas.reincarnation
--                           WHEN EXCLUDED.updated_at_ts > replicas.updated_at_ts
--                           THEN EXCLUDED.reincarnation
--                           ELSE replicas.reincarnation END,
--     manifest_jsonb = CASE WHEN EXCLUDED.updated_at_ts > replicas.updated_at_ts
--                           THEN EXCLUDED.manifest_jsonb
--                           ELSE replicas.manifest_jsonb END,
--     schema_version = GREATEST(replicas.schema_version, EXCLUDED.schema_version),
--     updated_at_ts  = crdt_compute_updated_at(
--                        crdt_merge_fields(replicas.fields_jsonb, EXCLUDED.fields_jsonb),
--                        hlc_max(replicas.deleted_at_ts, EXCLUDED.deleted_at_ts)
--                      ),
--     modified_at    = now()
--
-- Or via the wrapper below for shorter call sites.
-- ─────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.crdt_merge_replica(
  p_user_id uuid,
  p_kind text,
  p_replica_id text,
  p_fields_jsonb jsonb,
  p_manifest_jsonb jsonb,
  p_deleted_at_ts text,
  p_reincarnation text,
  p_updated_at_ts text,
  p_schema_version integer
) RETURNS public.replicas
LANGUAGE plpgsql
AS $$
DECLARE
  result public.replicas;
BEGIN
  INSERT INTO public.replicas AS r (
    user_id, kind, replica_id,
    fields_jsonb, manifest_jsonb, deleted_at_ts,
    reincarnation, updated_at_ts, schema_version
  ) VALUES (
    p_user_id, p_kind, p_replica_id,
    COALESCE(p_fields_jsonb, '{}'::jsonb),
    p_manifest_jsonb, p_deleted_at_ts,
    p_reincarnation, p_updated_at_ts, p_schema_version
  )
  ON CONFLICT (user_id, kind, replica_id) DO UPDATE SET
    fields_jsonb   = public.crdt_merge_fields(r.fields_jsonb, EXCLUDED.fields_jsonb),
    deleted_at_ts  = public.hlc_max(r.deleted_at_ts, EXCLUDED.deleted_at_ts),
    reincarnation  = CASE
                       WHEN r.reincarnation IS NOT DISTINCT FROM EXCLUDED.reincarnation
                         THEN r.reincarnation
                       WHEN EXCLUDED.updated_at_ts > r.updated_at_ts
                         THEN EXCLUDED.reincarnation
                       ELSE r.reincarnation
                     END,
    manifest_jsonb = CASE
                       WHEN EXCLUDED.updated_at_ts > r.updated_at_ts
                         THEN EXCLUDED.manifest_jsonb
                       ELSE r.manifest_jsonb
                     END,
    schema_version = GREATEST(r.schema_version, EXCLUDED.schema_version),
    updated_at_ts  = public.crdt_compute_updated_at(
                       public.crdt_merge_fields(r.fields_jsonb, EXCLUDED.fields_jsonb),
                       public.hlc_max(r.deleted_at_ts, EXCLUDED.deleted_at_ts)
                     ),
    modified_at    = now()
  RETURNING * INTO result;
  RETURN result;
END;
$$;

-- Surface the function to the API role only after an explicit user-id
-- match check in src/pages/api/sync/replicas.ts. RLS on the replicas
-- table is the second line of defense (the function runs as caller).
GRANT EXECUTE ON FUNCTION public.hlc_max(text, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.crdt_merge_fields(jsonb, jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.crdt_compute_updated_at(jsonb, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.crdt_merge_replica(uuid, text, text, jsonb, jsonb, text, text, text, integer) TO authenticated;


-- ===== migrations/005_replica_manifest_cursor_updated_at.sql =====
-- Migration 005: keep replica updated_at_ts as the max row-operation HLC.
--
-- Migration 004 recomputed updated_at_ts from fields_jsonb + deleted_at_ts
-- after every conflict. That loses manifest-only operation timestamps:
-- manifest_jsonb can change, but pull cursors do not advance, so a device
-- that already pulled the metadata-only row can miss the downloadable
-- transition. Preserve the max of existing row timestamp, incoming row
-- timestamp, and content/tombstone timestamp.
--
-- Also treat incoming manifest_jsonb = null as "no manifest update" on
-- conflict. Metadata-only rows use null, and must not clear an existing
-- committed manifest.
--
-- Reincarnation is derived from the newest non-null token candidate that
-- is newer than the merged tombstone. Null metadata/manifest rows do not
-- clear a token; a newer tombstone clears it because no token candidate is
-- newer than that tombstone. Without this, editing a reincarnated
-- dictionary title publishes p_reincarnation = null and erases the revival
-- token.

CREATE OR REPLACE FUNCTION public.crdt_merge_replica(
  p_user_id uuid,
  p_kind text,
  p_replica_id text,
  p_fields_jsonb jsonb,
  p_manifest_jsonb jsonb,
  p_deleted_at_ts text,
  p_reincarnation text,
  p_updated_at_ts text,
  p_schema_version integer
) RETURNS public.replicas
LANGUAGE plpgsql
AS $$
DECLARE
  result public.replicas;
BEGIN
  INSERT INTO public.replicas AS r (
    user_id, kind, replica_id,
    fields_jsonb, manifest_jsonb, deleted_at_ts,
    reincarnation, updated_at_ts, schema_version
  ) VALUES (
    p_user_id, p_kind, p_replica_id,
    COALESCE(p_fields_jsonb, '{}'::jsonb),
    p_manifest_jsonb, p_deleted_at_ts,
    p_reincarnation, p_updated_at_ts, p_schema_version
  )
  ON CONFLICT (user_id, kind, replica_id) DO UPDATE SET
    fields_jsonb   = public.crdt_merge_fields(r.fields_jsonb, EXCLUDED.fields_jsonb),
    deleted_at_ts  = public.hlc_max(r.deleted_at_ts, EXCLUDED.deleted_at_ts),
    reincarnation  = CASE
                       WHEN r.reincarnation IS NULL AND EXCLUDED.reincarnation IS NULL
                         THEN NULL
                       WHEN r.reincarnation IS NOT NULL AND EXCLUDED.reincarnation IS NULL
                         THEN CASE
                                WHEN public.hlc_max(r.deleted_at_ts, EXCLUDED.deleted_at_ts) IS NULL
                                  OR r.updated_at_ts > public.hlc_max(r.deleted_at_ts, EXCLUDED.deleted_at_ts)
                                  THEN r.reincarnation
                                ELSE NULL
                              END
                       WHEN r.reincarnation IS NULL AND EXCLUDED.reincarnation IS NOT NULL
                         THEN CASE
                                WHEN public.hlc_max(r.deleted_at_ts, EXCLUDED.deleted_at_ts) IS NULL
                                  OR EXCLUDED.updated_at_ts > public.hlc_max(r.deleted_at_ts, EXCLUDED.deleted_at_ts)
                                  THEN EXCLUDED.reincarnation
                                ELSE NULL
                              END
                       WHEN EXCLUDED.updated_at_ts > r.updated_at_ts
                         THEN CASE
                                WHEN public.hlc_max(r.deleted_at_ts, EXCLUDED.deleted_at_ts) IS NULL
                                  OR EXCLUDED.updated_at_ts > public.hlc_max(r.deleted_at_ts, EXCLUDED.deleted_at_ts)
                                  THEN EXCLUDED.reincarnation
                                ELSE NULL
                              END
                       ELSE CASE
                              WHEN public.hlc_max(r.deleted_at_ts, EXCLUDED.deleted_at_ts) IS NULL
                                OR r.updated_at_ts > public.hlc_max(r.deleted_at_ts, EXCLUDED.deleted_at_ts)
                                THEN r.reincarnation
                              ELSE NULL
                            END
                     END,
    manifest_jsonb = CASE
                       WHEN EXCLUDED.manifest_jsonb IS NULL
                         THEN r.manifest_jsonb
                       WHEN r.manifest_jsonb IS NULL
                         THEN EXCLUDED.manifest_jsonb
                       WHEN EXCLUDED.updated_at_ts > r.updated_at_ts
                         THEN EXCLUDED.manifest_jsonb
                       ELSE r.manifest_jsonb
                     END,
    schema_version = GREATEST(r.schema_version, EXCLUDED.schema_version),
    updated_at_ts  = public.hlc_max(
                       public.hlc_max(r.updated_at_ts, EXCLUDED.updated_at_ts),
                       public.crdt_compute_updated_at(
                         public.crdt_merge_fields(r.fields_jsonb, EXCLUDED.fields_jsonb),
                         public.hlc_max(r.deleted_at_ts, EXCLUDED.deleted_at_ts)
                       )
                     ),
    modified_at    = now()
  RETURNING * INTO result;
  RETURN result;
END;
$$;

GRANT EXECUTE ON FUNCTION public.crdt_merge_replica(uuid, text, text, jsonb, jsonb, text, text, text, integer) TO authenticated;


-- ===== migrations/006_replica_more_kinds.sql =====
-- Migration 006: Extend the replicas.kind allowlist beyond 'dictionary'.
-- Pre-allows the kinds we plan to ship in upcoming client releases so
-- each adapter only needs a coordinated client + server-validation
-- update, not another DB migration. The DB CHECK is belt-and-
-- suspenders; src/libs/replicaSchemas.ts (KIND_ALLOWLIST) is the
-- actual gate that decides which kinds the server accepts on push.

ALTER TABLE public.replicas
  DROP CONSTRAINT IF EXISTS replicas_kind_allowlist;

ALTER TABLE public.replicas
  ADD CONSTRAINT replicas_kind_allowlist
  CHECK (kind IN ('dictionary', 'font', 'texture'));


-- ===== migrations/007_files_replica_grouping.sql =====
-- Migration 007: Per-replica grouping for binaries in `files`.
--
-- Replica-kind binaries (custom dictionary mdx/mdd, font ttf/woff, ...)
-- have no book_hash, so without these columns Storage Manager would
-- lump every replica binary into one "no-book" bucket. Per-replica
-- grouping needs the row to carry the replica's identity alongside
-- file_key/size.

ALTER TABLE public.files
  ADD COLUMN IF NOT EXISTS replica_kind text NULL,
  ADD COLUMN IF NOT EXISTS replica_id text NULL;

-- Composite filter index for "list / count files by replica row".
CREATE INDEX IF NOT EXISTS idx_files_replica_lookup
  ON public.files (user_id, replica_kind, replica_id);


-- ===== migrations/008_replica_keys_rpcs.sql =====
-- Migration 008: RPC helpers for the replica_keys table.
-- The bytea salt round-trips as base64 over PostgREST so the client never
-- has to deal with Postgres hex encoding. Both functions run SECURITY
-- INVOKER, so the table's RLS policies (created in migration 003) enforce
-- the auth.uid() = user_id guard.

-- gen_random_bytes() lives in pgcrypto; Supabase enables it by default,
-- but we make the dependency explicit so a fresh self-hosted database
-- works on first apply.
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

CREATE OR REPLACE FUNCTION public.replica_keys_create(p_alg text)
RETURNS TABLE(salt_id text, alg text, salt_b64 text, created_at timestamptz)
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_salt_id text := gen_random_uuid()::text;
  v_salt bytea := extensions.gen_random_bytes(32);
BEGIN
  IF p_alg <> 'pbkdf2-600k-sha256' THEN
    RAISE EXCEPTION 'Unsupported alg: %', p_alg USING ERRCODE = '22023';
  END IF;
  INSERT INTO public.replica_keys (user_id, salt_id, alg, salt)
  VALUES (auth.uid(), v_salt_id, p_alg, v_salt);
  RETURN QUERY
    SELECT v_salt_id, p_alg, encode(v_salt, 'base64'), now();
END;
$$;

CREATE OR REPLACE FUNCTION public.replica_keys_list()
RETURNS TABLE(salt_id text, alg text, salt_b64 text, created_at timestamptz)
LANGUAGE sql
SECURITY INVOKER
STABLE
AS $$
  SELECT salt_id, alg, encode(salt, 'base64') AS salt_b64, created_at
  FROM public.replica_keys
  WHERE user_id = (SELECT auth.uid())
  ORDER BY created_at DESC;
$$;

GRANT EXECUTE ON FUNCTION public.replica_keys_create(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.replica_keys_list() TO authenticated;


-- ===== migrations/009_replica_opds_catalog.sql =====
-- Migration 009: Extend the replicas.kind allowlist with 'opds_catalog'.
-- The DB CHECK is belt-and-suspenders; src/libs/replicaSchemas.ts
-- (KIND_ALLOWLIST) is the actual gate that decides which kinds the
-- server accepts on push.

ALTER TABLE public.replicas
  DROP CONSTRAINT IF EXISTS replicas_kind_allowlist;

ALTER TABLE public.replicas
  ADD CONSTRAINT replicas_kind_allowlist
  CHECK (kind IN ('dictionary', 'font', 'texture', 'opds_catalog'));


-- ===== migrations/010_replica_keys_forget.sql =====
-- Migration 010: replica_keys_forget RPC.
-- Wipes every encrypted-field envelope from the user's replica rows
-- (any field whose `v` slot contains a cipher envelope, identified by
-- the `alg` key) and deletes every replica_keys row for the user. The
-- next encrypted push from any device will mint a fresh salt + key.
--
-- Plaintext fields are untouched. Local plaintext copies on each
-- device survive — the user just has to re-enter their sync passphrase
-- on each device and the encrypted fields will be re-encrypted under
-- the new key on the next push.
--
-- SECURITY INVOKER: RLS on replicas + replica_keys gates the writes
-- to the calling user's rows.

CREATE OR REPLACE FUNCTION public.replica_keys_forget()
RETURNS void
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_user_id uuid := (SELECT auth.uid());
BEGIN
  IF v_user_id IS NULL THEN
    RAISE EXCEPTION 'replica_keys_forget called without an authenticated user';
  END IF;

  -- Strip cipher envelopes from each row's fields_jsonb. A cipher
  -- envelope is the value of a field's `v` slot when that value is an
  -- object containing the `alg` key (per CipherEnvelope shape:
  -- {c, i, s, alg, h}). Plain field envelopes have a non-object `v`.
  UPDATE public.replicas r
  SET fields_jsonb = (
    SELECT COALESCE(jsonb_object_agg(key, value), '{}'::jsonb)
    FROM jsonb_each(r.fields_jsonb)
    WHERE NOT (
      jsonb_typeof(value -> 'v') = 'object'
      AND value -> 'v' ? 'alg'
    )
  )
  WHERE r.user_id = v_user_id
    AND EXISTS (
      SELECT 1 FROM jsonb_each(r.fields_jsonb) e
      WHERE jsonb_typeof(e.value -> 'v') = 'object'
        AND e.value -> 'v' ? 'alg'
    );

  -- Drop every salt row. The next encrypted push will create a fresh
  -- one via replica_keys_create.
  DELETE FROM public.replica_keys WHERE user_id = v_user_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.replica_keys_forget() TO authenticated;


-- ===== migrations/011_replica_settings.sql =====
-- Migration 011: Extend the replicas.kind allowlist with 'settings'.
-- Per tenet 8 of the replica-sync plan, scalar settings sync via a
-- single bundled row keyed by ('settings', 'singleton') instead of N
-- per-kind adapters. The DB CHECK is belt-and-suspenders;
-- src/libs/replicaSchemas.ts (KIND_ALLOWLIST) is the actual gate.

ALTER TABLE public.replicas
  DROP CONSTRAINT IF EXISTS replicas_kind_allowlist;

ALTER TABLE public.replicas
  ADD CONSTRAINT replicas_kind_allowlist
  CHECK (kind IN ('dictionary', 'font', 'texture', 'opds_catalog', 'settings'));


-- ===== migrations/012_send_to_readest.sql =====
-- Migration 012: Send to Readest — inbound capture (email / web / extension).
--
-- Out-of-app channels (email, browser extension) drop a raw payload into
-- `send_inbox`; any Readest client drains it through the normal import
-- pipeline. `send_inbox` state transitions go ONLY through the SECURITY
-- DEFINER RPCs below — clients have SELECT but no write policy, so a client
-- cannot forge `done`/`failed` or reset another device's claim.

-- Per-user inbound email address (the local part of `<address>@send.readest.com`).
CREATE TABLE IF NOT EXISTS public.send_addresses (
  user_id uuid NOT NULL,
  address text NOT NULL,
  enabled boolean NOT NULL DEFAULT true,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  rotated_at timestamp with time zone NULL,
  CONSTRAINT send_addresses_pkey PRIMARY KEY (user_id),
  CONSTRAINT send_addresses_address_key UNIQUE (address),
  CONSTRAINT send_addresses_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users (id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_send_addresses_address ON public.send_addresses (address);

ALTER TABLE public.send_addresses ENABLE ROW LEVEL SECURITY;
CREATE POLICY send_addresses_select ON public.send_addresses FOR SELECT TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY send_addresses_insert ON public.send_addresses FOR INSERT TO authenticated WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY send_addresses_update ON public.send_addresses FOR UPDATE TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY send_addresses_delete ON public.send_addresses FOR DELETE TO authenticated USING ((SELECT auth.uid()) = user_id);

-- Approved-sender allowlist. `pending` rows are senders awaiting one-click approval.
CREATE TABLE IF NOT EXISTS public.send_allowed_senders (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  email text NOT NULL,
  status text NOT NULL DEFAULT 'approved',
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT send_allowed_senders_pkey PRIMARY KEY (id),
  CONSTRAINT send_allowed_senders_user_email_key UNIQUE (user_id, email),
  CONSTRAINT send_allowed_senders_status_check CHECK (status IN ('approved', 'pending')),
  CONSTRAINT send_allowed_senders_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users (id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_send_allowed_senders_user ON public.send_allowed_senders (user_id);

ALTER TABLE public.send_allowed_senders ENABLE ROW LEVEL SECURITY;
CREATE POLICY send_allowed_senders_select ON public.send_allowed_senders FOR SELECT TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY send_allowed_senders_insert ON public.send_allowed_senders FOR INSERT TO authenticated WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY send_allowed_senders_update ON public.send_allowed_senders FOR UPDATE TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY send_allowed_senders_delete ON public.send_allowed_senders FOR DELETE TO authenticated USING ((SELECT auth.uid()) = user_id);

-- The capture inbox. Rows are kept after `done`/`failed` as the user's
-- "Recent activity" log; the R2 payload is deleted once a row reaches `done`.
CREATE TABLE IF NOT EXISTS public.send_inbox (
  id uuid NOT NULL DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL,
  kind text NOT NULL,
  source text NOT NULL,
  payload_key text NULL,
  url text NULL,
  filename text NULL,
  subject_tag text NULL,
  byte_size bigint NOT NULL DEFAULT 0,
  status text NOT NULL DEFAULT 'pending',
  claimed_by text NULL,
  claimed_at timestamp with time zone NULL,
  attempts integer NOT NULL DEFAULT 0,
  error text NULL,
  created_at timestamp with time zone NOT NULL DEFAULT now(),
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT send_inbox_pkey PRIMARY KEY (id),
  CONSTRAINT send_inbox_kind_check CHECK (kind IN ('file', 'url', 'html')),
  CONSTRAINT send_inbox_source_check CHECK (source IN ('email', 'extension')),
  CONSTRAINT send_inbox_status_check CHECK (status IN ('pending', 'claimed', 'done', 'failed')),
  CONSTRAINT send_inbox_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users (id) ON DELETE CASCADE
);

CREATE INDEX IF NOT EXISTS idx_send_inbox_user_status ON public.send_inbox (user_id, status, created_at);

ALTER TABLE public.send_inbox ENABLE ROW LEVEL SECURITY;
-- SELECT only: the Recent-activity UI reads rows. Writes go through the RPCs.
CREATE POLICY send_inbox_select ON public.send_inbox FOR SELECT TO authenticated USING ((SELECT auth.uid()) = user_id);

-- Claim the oldest drainable row (pending, or a claim whose 15-minute lease
-- expired). FOR UPDATE SKIP LOCKED makes concurrent drainers pick distinct rows.
CREATE OR REPLACE FUNCTION public.claim_inbox_item(p_device text)
RETURNS public.send_inbox
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_row public.send_inbox;
BEGIN
  UPDATE public.send_inbox
  SET status = 'claimed', claimed_by = p_device, claimed_at = now(), updated_at = now()
  WHERE id = (
    SELECT id FROM public.send_inbox
    WHERE user_id = auth.uid()
      AND (
        status = 'pending'
        OR (status = 'claimed' AND claimed_at < now() - interval '15 minutes')
      )
    ORDER BY created_at
    LIMIT 1
    FOR UPDATE SKIP LOCKED
  )
  RETURNING * INTO v_row;
  RETURN v_row;
END;
$$;

-- Refresh the lease for a long-running job; succeeds only if still owned.
CREATE OR REPLACE FUNCTION public.renew_inbox_claim(p_id uuid, p_device text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  UPDATE public.send_inbox
  SET claimed_at = now(), updated_at = now()
  WHERE id = p_id AND user_id = auth.uid()
    AND status = 'claimed' AND claimed_by = p_device;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count > 0;
END;
$$;

-- Terminal success.
CREATE OR REPLACE FUNCTION public.complete_inbox_item(p_id uuid, p_device text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  UPDATE public.send_inbox
  SET status = 'done', error = NULL, updated_at = now()
  WHERE id = p_id AND user_id = auth.uid()
    AND status = 'claimed' AND claimed_by = p_device;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count > 0;
END;
$$;

-- Failure: increment attempts atomically; back to `pending` for retry, or
-- terminal `failed` after the third attempt.
CREATE OR REPLACE FUNCTION public.fail_inbox_item(p_id uuid, p_device text, p_error text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  UPDATE public.send_inbox
  SET attempts = attempts + 1,
      status = CASE WHEN attempts + 1 >= 3 THEN 'failed' ELSE 'pending' END,
      error = p_error,
      claimed_by = NULL,
      claimed_at = NULL,
      updated_at = now()
  WHERE id = p_id AND user_id = auth.uid()
    AND status = 'claimed' AND claimed_by = p_device;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count > 0;
END;
$$;

GRANT ALL ON public.send_addresses TO authenticated;
GRANT ALL ON public.send_allowed_senders TO authenticated;
GRANT SELECT ON public.send_inbox TO authenticated;
GRANT EXECUTE ON FUNCTION public.claim_inbox_item(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.renew_inbox_claim(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.complete_inbox_item(uuid, text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fail_inbox_item(uuid, text, text) TO authenticated;


-- ===== migrations/013_add_book_notes_global.sql =====
-- Migration 013: Add `global` flag to book_notes
--
-- The `global` flag, when true, indicates that an annotation should be
-- applied to every occurrence of `text` within the same section (chapter
-- / spine item), in addition to the original anchor identified by `cfi`.
-- Defaults to NULL/false, preserving prior single-range semantics for all
-- existing notes.

ALTER TABLE public.book_notes
  ADD COLUMN IF NOT EXISTS global boolean NULL;


-- ===== migrations/014_add_reading_stats.sql =====
-- Migration 014: reading statistics sync (KOReader-compatible page events)

CREATE TABLE IF NOT EXISTS public.stat_books (
  user_id uuid NOT NULL,
  book_hash text NOT NULL,
  title text NOT NULL DEFAULT '',
  authors text NOT NULL DEFAULT '',
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  deleted_at timestamp with time zone NULL,
  CONSTRAINT stat_books_pkey PRIMARY KEY (user_id, book_hash),
  CONSTRAINT stat_books_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users (id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_stat_books_user_updated ON public.stat_books (user_id, updated_at);

CREATE TABLE IF NOT EXISTS public.stat_pages (
  user_id uuid NOT NULL,
  book_hash text NOT NULL,
  page integer NOT NULL,
  start_time bigint NOT NULL,
  duration integer NOT NULL DEFAULT 0,
  total_pages integer NOT NULL DEFAULT 0,
  ext jsonb NULL,
  updated_at timestamp with time zone NOT NULL DEFAULT now(),
  deleted_at timestamp with time zone NULL,
  CONSTRAINT stat_pages_pkey PRIMARY KEY (user_id, book_hash, page, start_time),
  CONSTRAINT stat_pages_user_id_fkey FOREIGN KEY (user_id) REFERENCES auth.users (id) ON DELETE CASCADE
);
CREATE INDEX IF NOT EXISTS idx_stat_pages_user_updated ON public.stat_pages (user_id, updated_at);

ALTER TABLE public.stat_books ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.stat_pages ENABLE ROW LEVEL SECURITY;

CREATE POLICY stat_books_select ON public.stat_books FOR SELECT TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY stat_books_insert ON public.stat_books FOR INSERT TO authenticated WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY stat_books_update ON public.stat_books FOR UPDATE TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY stat_books_delete ON public.stat_books FOR DELETE TO authenticated USING ((SELECT auth.uid()) = user_id);

CREATE POLICY stat_pages_select ON public.stat_pages FOR SELECT TO authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY stat_pages_insert ON public.stat_pages FOR INSERT TO authenticated WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY stat_pages_update ON public.stat_pages FOR UPDATE to authenticated USING ((SELECT auth.uid()) = user_id);
CREATE POLICY stat_pages_delete ON public.stat_pages FOR DELETE TO authenticated USING ((SELECT auth.uid()) = user_id);


-- ===== migrations/015_add_reading_status_updated_at.sql =====
-- Migration 015: Add `reading_status_updated_at` to books
--
-- Field-level last-writer-wins for reading_status. The books row carries
-- both reading_status (rare, intentional) and a denormalized progress
-- (every page turn) under one updated_at, so whole-row LWW lets progress
-- updates clobber a status change across devices (issue #4634). A dedicated
-- per-field timestamp lets the merge resolve reading_status independently.
-- Additive + nullable; NULL is treated as epoch 0 (oldest) by the merge.

ALTER TABLE public.books
  ADD COLUMN IF NOT EXISTS reading_status_updated_at timestamp with time zone NULL;


-- ===== migrations/016_add_books_synced_at.sql =====
-- Migration 016: Add a server-assigned `synced_at` cursor to books (issue #4678)
--
-- `books.updated_at` was overloaded as two things with conflicting needs:
--   1. the incremental-pull cursor (GET /api/sync?since=… filters updated_at >
--      since, and each device keeps a single global max(updated_at) watermark);
--   2. the library "date read" sort key (wants the client event time).
--
-- A server-resolved merge (e.g. the reading_status field-level LWW in #4634)
-- has to be written with a timestamp greater than every peer's global cursor to
-- propagate, which forced updated_at = now() and reordered the date-read library
-- by sync-processing time (the #4677 symptom).
--
-- Decouple the two: `synced_at` is a monotonic, server-stamped cursor used ONLY
-- by the incremental pull, while `updated_at` stays pure client event time used
-- ONLY for sorting. A BEFORE INSERT/UPDATE trigger forces synced_at = now() on
-- every server write (clients never send it), so a status merge propagates by
-- bumping synced_at without touching updated_at.
--
-- Backfill synced_at = updated_at so existing devices' updated_at-based cursors
-- hand over seamlessly: `synced_at > since` returns the same rows as before
-- (synced_at == updated_at) plus, going forward, server-resolved merges.
--
-- ┌───────────────────────────────────────────────────────────────────────────┐
-- │ RUN ONLINE, NOT INSIDE A TRANSACTION.                                      │
-- │                                                                            │
-- │ Apply with psql against a live, large `books` table (millions of rows):   │
-- │     psql "$DATABASE_URL" -v ON_ERROR_STOP=1 -f 016_add_books_synced_at.sql │
-- │                                                                            │
-- │ Do NOT paste it into a wrapping BEGIN/COMMIT or the Supabase dashboard SQL │
-- │ editor: it uses CREATE INDEX CONCURRENTLY and a CALL into a procedure that │
-- │ COMMITs each backfill batch — both are rejected inside a transaction.      │
-- │                                                                            │
-- │ A single bulk `UPDATE … WHERE synced_at IS NULL` deadlocks against the     │
-- │ live /api/sync upserts (both lock books rows, in opposite orders). The     │
-- │ backfill below instead walks the table in small autocommitted batches and │
-- │ uses FOR UPDATE SKIP LOCKED so it never waits on a row the app holds.      │
-- └───────────────────────────────────────────────────────────────────────────┘

-- 1. Add the column (nullable, no default → metadata-only, instant) and set the
--    default up front so rows INSERTed during the backfill already get now().
ALTER TABLE public.books
  ADD COLUMN IF NOT EXISTS synced_at timestamp with time zone NULL;
ALTER TABLE public.books
  ALTER COLUMN synced_at SET DEFAULT now();

-- 2. Backfill in small, individually-committed batches. SKIP LOCKED steps over
--    rows currently locked by a concurrent push (they fall to a later pass), so
--    the backfill never deadlocks with live traffic. The trigger is installed
--    only AFTER this completes, so it can't clobber the updated_at backfill.
-- [Supabase Cloud] DB baru/kosong: backfill batch+COMMIT diganti UPDATE biasa
-- (prosedur dengan COMMIT ditolak di SQL Editor).
UPDATE public.books
  SET synced_at = COALESCE(updated_at, created_at, now())
  WHERE synced_at IS NULL;

-- 3. Index the cursor without blocking writes (CONCURRENTLY → no SHARE lock).
CREATE INDEX IF NOT EXISTS idx_books_user_synced
  ON public.books (user_id, synced_at);

-- 4. Install the trigger LAST, so from here every write is server-stamped.
CREATE OR REPLACE FUNCTION public.set_books_synced_at()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  -- Server-authoritative: ignore any client-supplied value and stamp the
  -- transaction time. transaction_timestamp() (= now()) is stable within a
  -- batch upsert, which is fine — a batch is a single pull delta.
  NEW.synced_at := now();
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS books_set_synced_at ON public.books;
CREATE TRIGGER books_set_synced_at
  BEFORE INSERT OR UPDATE ON public.books
  FOR EACH ROW
  EXECUTE FUNCTION public.set_books_synced_at();

-- 5. (Optional) Enforce NOT NULL without the full-table ACCESS EXCLUSIVE scan
--    that `ALTER COLUMN … SET NOT NULL` takes. A NOT VALID check skips existing
--    rows; VALIDATE then scans under a lighter SHARE UPDATE EXCLUSIVE lock that
--    still allows concurrent reads and writes. Safe to omit — the default, the
--    trigger and the backfill already keep the column populated, and the client
--    falls back to updated_at when synced_at is absent.
-- ALTER TABLE public.books
--   ADD CONSTRAINT books_synced_at_not_null CHECK (synced_at IS NOT NULL) NOT VALID;
-- ALTER TABLE public.books
--   VALIDATE CONSTRAINT books_synced_at_not_null;


-- ===== migrations/017_add_book_cover_version.sql =====
-- Migration 017: Add `cover_hash` / `cover_updated_at` to books
--
-- Cover-change sync (issue #4544). Editing a book's cover writes cover.png
-- locally but changes no hash (the cover is keyed by the file hash), so peers
-- had no signal to re-download it. Give the cover its own content-addressed
-- version:
--
--   cover_hash       = partial MD5 of cover.png. A peer re-downloads the cover
--                      iff its synced cover_hash differs from the local one.
--                      Content-addressed ⇒ a byte-identical (re-extracted /
--                      re-imported) cover yields the same hash ⇒ no re-sync
--                      churn (compatible with the metaHash dedupe mechanism).
--   cover_updated_at = field-level last-writer-wins timestamp so a page-turn
--                      that wins whole-row LWW on updated_at cannot clobber a
--                      cover edit — the same hazard the 015
--                      reading_status_updated_at fix addressed for #4634.
--
-- Both additive + nullable; NULL cover_updated_at is treated as epoch 0
-- (oldest) by the merge. Old clients ignore the columns, so they never break.

ALTER TABLE public.books
  ADD COLUMN IF NOT EXISTS cover_hash       text NULL,
  ADD COLUMN IF NOT EXISTS cover_updated_at timestamp with time zone NULL;


-- ===== migrations/018_add_metadata_updated_at.sql =====
-- Migration 018: Add `metadata_updated_at` to books
--
-- Field-level last-writer-wins for the metadata group (title, author, tags,
-- metadata). The books row's updated_at is dominated by page-turn progress,
-- so whole-row LWW lets a device that read the book after a metadata edit
-- push its stale copy back over the edit (issue #5438 — near-deterministic
-- for RSS feed books, which are read daily on every device). A dedicated
-- per-field timestamp lets the merge resolve the metadata group
-- independently — the same hazard the 015 reading_status_updated_at (#4634)
-- and 017 cover_updated_at (#4544) fixes addressed.
-- Additive + nullable; NULL is treated as epoch 0 (oldest) by the merge, and
-- unstamped-vs-unstamped falls back to whole-row LWW so legacy rows keep
-- their old behavior. Old clients ignore the column, so they never break.

ALTER TABLE public.books
  ADD COLUMN IF NOT EXISTS metadata_updated_at timestamp with time zone NULL;


-- ===== migrations/019_stat_pages_upsert_rpc.sql =====
-- Migration 019: merge-upsert RPC for stat_pages pushes.
--
-- The push handler used to SELECT the batch's existing rows
-- (user_id = ?, book_hash = ANY(...), start_time = ANY(...)), decide
-- "longer duration wins" in JS, then upsert in a second round trip. On PG 15
-- that lookup re-walks the whole (user_id, book_hash) primary-key range once
-- per start_time array element, because start_time sits after the
-- unconstrained `page` column of the PK; it was also half of all stats push
-- traffic. One INSERT ... ON CONFLICT does the same merge with exact PK probes.
--
-- Semantics (KOReader-compatible union merge): new keys are inserted; an
-- existing key is overwritten only when the incoming duration is strictly
-- longer. Duplicate keys inside one batch collapse to the longest duration so
-- the statement never hits "ON CONFLICT DO UPDATE command cannot affect row a
-- second time". user_id and updated_at are stamped here, never trusted from
-- the payload. SECURITY INVOKER keeps the stat_pages RLS policies in force.

CREATE OR REPLACE FUNCTION public.upsert_stat_pages(p_rows jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
  v_count integer;
BEGIN
  INSERT INTO public.stat_pages
    (user_id, book_hash, page, start_time, duration, total_pages, ext, updated_at, deleted_at)
  SELECT DISTINCT ON (r.book_hash, r.page, r.start_time)
    auth.uid(), r.book_hash, r.page, r.start_time,
    coalesce(r.duration, 0), coalesce(r.total_pages, 0), r.ext, now(), r.deleted_at
  FROM jsonb_to_recordset(p_rows) AS r(
    book_hash text, page integer, start_time bigint, duration integer,
    total_pages integer, ext jsonb, deleted_at timestamptz)
  ORDER BY r.book_hash, r.page, r.start_time, r.duration DESC NULLS LAST
  ON CONFLICT (user_id, book_hash, page, start_time) DO UPDATE
    SET duration = EXCLUDED.duration,
        total_pages = EXCLUDED.total_pages,
        ext = EXCLUDED.ext,
        updated_at = EXCLUDED.updated_at,
        deleted_at = EXCLUDED.deleted_at
    WHERE EXCLUDED.duration > stat_pages.duration;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.upsert_stat_pages(jsonb) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.upsert_stat_pages(jsonb) TO authenticated;


-- ===== migrations/020_stat_archives.sql =====
-- Migration 020: reading-statistics archive (stat_pages history tiered out of
-- Postgres into immutable per-user segment objects).
--
-- stat_pages keeps a hot window; a compaction job moves older rows into
-- object storage and records each segment in stat_archives. The stats pull
-- composes pages from segments + hot rows server-side, so clients never change.
--
-- Invariant: a committed segment covers (updated_from, updated_to] exactly and
-- the same transaction deletes those hot rows; every push stamps
-- updated_at = now(). Every hot row of a user is therefore newer than every
-- segment of that user.
--
-- All functions below run as service_role (the compaction job) and are
-- SECURITY INVOKER with a fixed search_path; EXECUTE is revoked from every
-- other role.

CREATE TABLE IF NOT EXISTS public.stat_archives (
  user_id       uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  id            bigint GENERATED ALWAYS AS IDENTITY,
  updated_from  timestamp with time zone NOT NULL,  -- exclusive
  updated_to    timestamp with time zone NOT NULL,  -- inclusive
  row_count     integer NOT NULL,
  bytes         integer NOT NULL,
  object_key    text NOT NULL,                      -- stats/v1/{user_id}/{updated_to_ms}.json
  created_at    timestamp with time zone NOT NULL DEFAULT now(),
  CONSTRAINT stat_archives_pkey PRIMARY KEY (user_id, id),
  CONSTRAINT stat_archives_object_key_key UNIQUE (object_key)
);
CREATE INDEX IF NOT EXISTS idx_stat_archives_user_to ON public.stat_archives (user_id, updated_to);

ALTER TABLE public.stat_archives ENABLE ROW LEVEL SECURITY;
-- Users may list their own manifest (the stats pull runs as the user); only
-- service_role writes, so there are no insert/update/delete policies.
DROP POLICY IF EXISTS stat_archives_select ON public.stat_archives;
CREATE POLICY stat_archives_select ON public.stat_archives FOR SELECT TO authenticated
  USING ((SELECT auth.uid()) = user_id);

-- Single-row sweep cursor for the compaction job. Service-role only: RLS with
-- no policies denies every other role, and the REVOKE keeps PostgREST from
-- exposing it through Supabase's default table privileges.
CREATE TABLE IF NOT EXISTS public.stat_archive_state (
  id          smallint PRIMARY KEY DEFAULT 1 CHECK (id = 1),
  user_cursor uuid,
  updated_at  timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.stat_archive_state ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.stat_archive_state FROM PUBLIC, anon, authenticated;
INSERT INTO public.stat_archive_state (id) VALUES (1) ON CONFLICT (id) DO NOTHING;

-- Users whose account was deleted while archive objects may still exist under
-- stats/v1/{user_id}/ (the account-deletion handler queues every deleted user;
-- the compaction job sweeps the prefix and removes the row once it lists
-- empty). No foreign key: the auth user is already gone. Service-role only.
CREATE TABLE IF NOT EXISTS public.stat_archive_orphans (
  user_id     uuid PRIMARY KEY,
  created_at  timestamp with time zone NOT NULL DEFAULT now()
);
ALTER TABLE public.stat_archive_orphans ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.stat_archive_orphans FROM PUBLIC, anon, authenticated;

-- Next batch of users in stat_pages PK order after the saved cursor (loose
-- index scan: one PK probe per user), advancing the cursor in the same
-- statement. The cursor becomes NULL when fewer than p_n users remained, so the
-- sweep is a ring over every user who currently has any hot row. Serialized by
-- an advisory lock so overlapping runs receive disjoint batches.
CREATE OR REPLACE FUNCTION public.stat_archive_claim_users(p_n integer)
RETURNS SETOF uuid
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_cursor uuid;
  v_users uuid[];
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('stat_archive_claim'));
  SELECT user_cursor INTO v_cursor FROM public.stat_archive_state WHERE id = 1 FOR UPDATE;
  -- (no min(uuid) aggregate in PG 15: ORDER BY ... LIMIT 1 probes the PK)
  WITH RECURSIVE t(u) AS (
    SELECT (SELECT user_id FROM public.stat_pages
            WHERE v_cursor IS NULL OR user_id > v_cursor
            ORDER BY user_id LIMIT 1)
    UNION ALL
    SELECT (SELECT user_id FROM public.stat_pages WHERE user_id > t.u
            ORDER BY user_id LIMIT 1)
    FROM t WHERE t.u IS NOT NULL
  )
  SELECT coalesce(array_agg(u ORDER BY u), '{}') INTO v_users
  FROM (SELECT u FROM t WHERE u IS NOT NULL LIMIT p_n) s;
  UPDATE public.stat_archive_state
     SET user_cursor = CASE WHEN cardinality(v_users) < p_n THEN NULL
                            ELSE v_users[cardinality(v_users)] END,
         updated_at = now()
   WHERE id = 1;
  RETURN QUERY SELECT unnest(v_users);
END;
$$;

-- Eligibility numbers for one user (index range scans on (user_id, updated_at)).
CREATE OR REPLACE FUNCTION public.stat_archive_candidate(p_user uuid, p_window interval)
RETURNS TABLE(eligible integer, oldest timestamp with time zone, hot_total integer,
              archived_to timestamp with time zone)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT
    (SELECT count(*)::int FROM public.stat_pages
      WHERE user_id = p_user AND updated_at <= now() - p_window),
    (SELECT min(updated_at) FROM public.stat_pages
      WHERE user_id = p_user AND updated_at <= now() - p_window),
    (SELECT count(*)::int FROM public.stat_pages WHERE user_id = p_user),
    (SELECT coalesce(max(updated_to), 'epoch'::timestamptz) FROM public.stat_archives
      WHERE user_id = p_user);
$$;

-- Rows for the next segment: everything after p_from up to the window cutoff,
-- in updated_at order; the first p_limit rows EXTENDED with every row of the
-- user that falls in the same MILLISECOND as the last one. Clients page on a
-- millisecond cursor (updated_at_ms) and segments are keyed by updated_to_ms,
-- so a segment never splits a millisecond; one push chunk shares one
-- updated_at, so the extension is bounded by concurrent pushes.
CREATE OR REPLACE FUNCTION public.stat_archive_rows(
  p_user uuid, p_from timestamp with time zone, p_window interval, p_limit integer)
RETURNS SETOF public.stat_pages
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  WITH page AS (
    SELECT * FROM public.stat_pages
    WHERE user_id = p_user AND updated_at > p_from AND updated_at <= now() - p_window
    ORDER BY updated_at LIMIT p_limit
  ), edge AS (SELECT date_trunc('milliseconds', max(updated_at)) AS ms FROM page)
  SELECT * FROM page
  UNION
  SELECT s.* FROM public.stat_pages s, edge
  WHERE s.user_id = p_user
    AND s.updated_at >= edge.ms AND s.updated_at < edge.ms + interval '1 millisecond'
  ORDER BY updated_at, book_hash, page, start_time;
$$;

-- Atomic commit: compare-and-set on the user's archived_to, manifest insert,
-- hot-row delete of exactly (p_from, p_to]. The CAS makes a concurrent second
-- run for the same user fail with 40001 instead of double-archiving; callers
-- must leave the already-written object alone on any error.
CREATE OR REPLACE FUNCTION public.stat_archive_commit(
  p_user uuid, p_key text, p_from timestamp with time zone, p_to timestamp with time zone,
  p_rows integer, p_bytes integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_archived_to timestamptz;
  v_deleted integer;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('stat_archive_user:' || p_user::text));
  SELECT coalesce(max(updated_to), 'epoch'::timestamptz) INTO v_archived_to
    FROM public.stat_archives WHERE user_id = p_user;
  IF v_archived_to <> p_from THEN
    RAISE EXCEPTION 'stat_archive_commit: archived_to % <> p_from % for user %',
      v_archived_to, p_from, p_user USING ERRCODE = '40001';
  END IF;
  INSERT INTO public.stat_archives (user_id, updated_from, updated_to, row_count, bytes, object_key)
    VALUES (p_user, p_from, p_to, p_rows, p_bytes, p_key);
  DELETE FROM public.stat_pages
    WHERE user_id = p_user AND updated_at > p_from AND updated_at <= p_to;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  RETURN v_deleted;
END;
$$;

-- Same merge as upsert_stat_pages (migration 019) for an explicit user: the
-- restore tool runs as service_role, whose auth.uid() is NULL.
CREATE OR REPLACE FUNCTION public.upsert_stat_pages_as(p_user uuid, p_rows jsonb)
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_count integer;
BEGIN
  INSERT INTO public.stat_pages
    (user_id, book_hash, page, start_time, duration, total_pages, ext, updated_at, deleted_at)
  SELECT DISTINCT ON (r.book_hash, r.page, r.start_time)
    p_user, r.book_hash, r.page, r.start_time,
    coalesce(r.duration, 0), coalesce(r.total_pages, 0), r.ext, now(), r.deleted_at
  FROM jsonb_to_recordset(p_rows) AS r(
    book_hash text, page integer, start_time bigint, duration integer,
    total_pages integer, ext jsonb, deleted_at timestamptz)
  ORDER BY r.book_hash, r.page, r.start_time, r.duration DESC NULLS LAST
  ON CONFLICT (user_id, book_hash, page, start_time) DO UPDATE
    SET duration = EXCLUDED.duration,
        total_pages = EXCLUDED.total_pages,
        ext = EXCLUDED.ext,
        updated_at = EXCLUDED.updated_at,
        deleted_at = EXCLUDED.deleted_at
    WHERE EXCLUDED.duration > stat_pages.duration;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END;
$$;

REVOKE EXECUTE ON FUNCTION public.stat_archive_claim_users(integer) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.stat_archive_candidate(uuid, interval) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.stat_archive_rows(uuid, timestamp with time zone, interval, integer) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.stat_archive_commit(uuid, text, timestamp with time zone, timestamp with time zone, integer, integer) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.upsert_stat_pages_as(uuid, jsonb) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.stat_archive_claim_users(integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.stat_archive_candidate(uuid, interval) TO service_role;
GRANT EXECUTE ON FUNCTION public.stat_archive_rows(uuid, timestamp with time zone, interval, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.stat_archive_commit(uuid, text, timestamp with time zone, timestamp with time zone, integer, integer) TO service_role;
GRANT EXECUTE ON FUNCTION public.upsert_stat_pages_as(uuid, jsonb) TO service_role;

-- Compaction deletes rows continuously; reclaim them for reuse without waiting
-- for 20% of a 50M-row table to die first.
ALTER TABLE public.stat_pages SET (autovacuum_vacuum_scale_factor = 0.01, autovacuum_analyze_scale_factor = 0.02);


-- ===== migrations/021_stat_archive_row_cap.sql =====
-- Migration 021: harden the reading-statistics archive RPCs against the
-- PostgREST response row cap (Supabase db-max-rows = 1000).
--
-- stat_archive_rows is called through PostgREST, whose row cap silently
-- truncates SETOF results. Migration 020's version extended the page to the end
-- of its last millisecond; under truncation the cut could land inside a run of
-- rows sharing one updated_at (a push chunk shares one now()), and the
-- subsequent range delete in stat_archive_commit then removed rows that were
-- never archived. Two changes make that class of bug impossible:
--
-- 1. stat_archive_rows becomes a plain KEYSET pager over
--    (updated_at, book_hash, page, start_time). A keyset page is
--    truncation-proof by construction: any proxy cap only shortens the page,
--    and the caller's cursor comes from rows it actually received, so progress
--    is always monotonic and no row can be skipped -- including inside a
--    millisecond that holds more rows than any single response can carry.
--    The millisecond-boundary policy (segments must end at complete
--    milliseconds, because clients page on a millisecond cursor) moves to the
--    caller, which trims or keeps the trailing millisecond of the rows it
--    assembled and never derives a boundary from a page edge.
-- 2. stat_archive_commit REFUSES (raises, rolling back the manifest insert and
--    the delete) when the range's delete count differs from the declared
--    segment row count, so any future counting bug fails loud and lossless.

-- The signature changes (three cursor parameters), so the 020 version must go:
-- CREATE OR REPLACE would create an overload next to it.
DROP FUNCTION IF EXISTS public.stat_archive_rows(uuid, timestamp with time zone, interval, integer);

CREATE FUNCTION public.stat_archive_rows(
  p_user uuid, p_from timestamp with time zone, p_window interval, p_limit integer,
  p_tie_book text DEFAULT NULL, p_tie_page integer DEFAULT NULL, p_tie_start bigint DEFAULT NULL)
RETURNS SETOF public.stat_pages
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
  SELECT * FROM public.stat_pages
  WHERE user_id = p_user
    AND updated_at <= now() - p_window
    AND (updated_at > p_from
         OR (p_tie_book IS NOT NULL
             AND updated_at = p_from
             AND (book_hash, page, start_time) > (p_tie_book, p_tie_page, p_tie_start)))
  ORDER BY updated_at, book_hash, page, start_time
  LIMIT p_limit;
$$;

CREATE OR REPLACE FUNCTION public.stat_archive_commit(
  p_user uuid, p_key text, p_from timestamp with time zone, p_to timestamp with time zone,
  p_rows integer, p_bytes integer)
RETURNS integer
LANGUAGE plpgsql
SECURITY INVOKER
SET search_path = public
AS $$
DECLARE
  v_archived_to timestamptz;
  v_deleted integer;
BEGIN
  PERFORM pg_advisory_xact_lock(hashtext('stat_archive_user:' || p_user::text));
  SELECT coalesce(max(updated_to), 'epoch'::timestamptz) INTO v_archived_to
    FROM public.stat_archives WHERE user_id = p_user;
  IF v_archived_to <> p_from THEN
    RAISE EXCEPTION 'stat_archive_commit: archived_to % <> p_from % for user %',
      v_archived_to, p_from, p_user USING ERRCODE = '40001';
  END IF;
  INSERT INTO public.stat_archives (user_id, updated_from, updated_to, row_count, bytes, object_key)
    VALUES (p_user, p_from, p_to, p_rows, p_bytes, p_key);
  DELETE FROM public.stat_pages
    WHERE user_id = p_user AND updated_at > p_from AND updated_at <= p_to;
  GET DIAGNOSTICS v_deleted = ROW_COUNT;
  IF v_deleted <> p_rows THEN
    -- The segment does not hold exactly the rows of (p_from, p_to]: refuse and
    -- roll back (manifest insert and delete both undone) instead of losing the
    -- difference. The already-written object is harmless: deterministic key,
    -- overwritten on the next attempt.
    RAISE EXCEPTION 'stat_archive_commit: segment holds % rows but range (%,%] would delete % for user %',
      p_rows, p_from, p_to, v_deleted, p_user USING ERRCODE = 'P0001';
  END IF;
  RETURN v_deleted;
END;
$$;

-- Grants for the new signature; the commit function keeps its privileges across
-- CREATE OR REPLACE but a fresh self-hosted database applying 020+021 must end
-- tight either way.
REVOKE EXECUTE ON FUNCTION public.stat_archive_rows(uuid, timestamp with time zone, interval, integer, text, integer, bigint) FROM PUBLIC, anon, authenticated;
REVOKE EXECUTE ON FUNCTION public.stat_archive_commit(uuid, text, timestamp with time zone, timestamp with time zone, integer, integer) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.stat_archive_rows(uuid, timestamp with time zone, interval, integer, text, integer, bigint) TO service_role;
GRANT EXECUTE ON FUNCTION public.stat_archive_commit(uuid, text, timestamp with time zone, timestamp with time zone, integer, integer) TO service_role;


-- ===== migrations/022_add_group_updated_at.sql =====
-- Migration 022: Add `group_updated_at` to books
--
-- Field-level last-writer-wins for group membership (group_id + group_name).
-- The books row's updated_at is stamped by operations that have nothing to do
-- with grouping — most importantly an UPLOAD, which bumps updated_at so the
-- new uploaded_at reaches peers — so whole-row LWW let a device holding a
-- never-grouped copy of a row win and erase the group for the whole fleet
-- (issue #5911: a clean install restored stale ungrouped cloud rows, then a
-- WebDAV Full Sync published them over the grouped ones and every other device
-- pulled the emptied rows). A dedicated per-field timestamp lets the merge
-- resolve group membership independently — the same hazard the 015
-- reading_status_updated_at (#4634), 017 cover_updated_at (#4544) and 018
-- metadata_updated_at (#5438) fixes addressed.
--
-- Additive + nullable. NULL is treated as epoch 0 (oldest) by the merge, but
-- unlike the three above, an unstamped TIE does NOT fall back to the row
-- winner: the side that actually has a group wins. On a tie an absent group is
-- ambiguous — "never grouped" and "ungrouped by a client too old to stamp" are
-- indistinguishable, and every legacy row is unstamped — so preserving the
-- group is the only safe reading. Erasing a real group is unrecoverable;
-- losing an un-group is not, and the next stamped edit resolves it.
-- Old clients ignore the column, so they never break.

-- DELIBERATELY NOT BACKFILLED. Two reasons, and the second is the load-bearing
-- one:
--
--   * `updated_at` is not when the group was set. It is bumped by page turns and
--     by uploads (that is the whole defect), so copying it into group_updated_at
--     would fabricate a grouping edit that never happened. Backfilling EVERY row
--     that way is actively harmful: an ungrouped row an upload pushed to `now`
--     would outrank a genuinely grouped peer and re-create #5911 permanently,
--     with a stamp the merge now trusts. Migrations 015 / 017 / 018 added their
--     clocks the same way — nullable, unfilled, NULL read as epoch 0.
--   * A server backfill cannot reach the copy that actually broke. #5911 was
--     reported against WebDAV, whose rows live in library.json on each device
--     and in the provider's own storage; no migration touches those. Legacy data
--     has to be safe under the MERGE, not under a one-off UPDATE, or it is only
--     safe for Readest Cloud users.
--
-- The unstamped-tie rule above is what makes the legacy fleet safe, and it works
-- identically on both backends: two unstamped rows tie, so the side that has a
-- group wins and the group survives. Rows only ever gain a stamp from a real
-- grouping edit, which is the only event that should set one.

ALTER TABLE public.books
  ADD COLUMN IF NOT EXISTS group_updated_at timestamp with time zone NULL;


-- ===== migrations/023_replica_bookshelf.sql =====
-- Deploy this migration and the bookshelf API validator before releasing clients.
-- Definitions are one atomic LWW field; display positions are separate fields.
ALTER TABLE public.replicas
  DROP CONSTRAINT IF EXISTS replicas_kind_allowlist,
  ADD CONSTRAINT replicas_kind_allowlist
    CHECK (kind IN ('dictionary', 'font', 'texture', 'opds_catalog', 'abs_server', 'settings', 'bookshelf')) NOT VALID;

-- The migration runner commits the metadata change above before this scan,
-- allowing normal reads and writes while existing rows are validated.
ALTER TABLE public.replicas VALIDATE CONSTRAINT replicas_kind_allowlist;


-- ===== migrations/024_crosspoint_devices.sql =====
-- Migration 024: CrossPoint e-readers linked to a Readest account (the
-- CrossPoint SD plugin). A reader signs in with a device code its owner
-- approves on the Readest web app, then authenticates every request (library,
-- downloads, reading sessions, KOReader Sync progress) with its own key. Only
-- the /api/crosspoint routes touch these tables, as the service role.

CREATE TABLE IF NOT EXISTS public.crosspoint_devices (
  id          uuid NOT NULL DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id     uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  -- sha256 hex of the key's md5 hex (what KOSync clients send as x-auth-key);
  -- the key itself is never stored.
  key_hash    text NOT NULL UNIQUE,
  created_at  timestamp with time zone NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS idx_crosspoint_devices_user ON public.crosspoint_devices (user_id);

-- Pending sign-ins. The reader shows user_code and polls with its device code
-- until the owner approves (user_id set); the first poll after that claims the
-- row and mints the device key.
CREATE TABLE IF NOT EXISTS public.crosspoint_device_codes (
  device_code_hash  text PRIMARY KEY,  -- sha256 hex
  user_code         text NOT NULL UNIQUE,
  user_id           uuid NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  username          text NULL,         -- the approver's email, a label for the reader
  expires_at        timestamp with time zone NOT NULL
);
CREATE INDEX IF NOT EXISTS idx_crosspoint_device_codes_expires
  ON public.crosspoint_device_codes (expires_at);

-- Service-role only: RLS with no policies denies every other role, and the
-- REVOKE keeps PostgREST from exposing them through default table privileges.
ALTER TABLE public.crosspoint_devices ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.crosspoint_device_codes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.crosspoint_devices FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.crosspoint_device_codes FROM PUBLIC, anon, authenticated;


-- ===== migrations/025_crosspoint_documents.sql =====
-- Copies of Readest books on CrossPoint readers that hash differently from the
-- book: CrossPoint's "Optimize EPUB" upload rewrites the file, so the KOSync
-- document id (the file's partial MD5) matches no book_hash. The first progress
-- upload links the copy to the library book by title and author; later syncs
-- follow the link. Only the service role reads or writes it.
CREATE TABLE IF NOT EXISTS public.crosspoint_documents (
  user_id     uuid NOT NULL REFERENCES auth.users (id) ON DELETE CASCADE,
  document    text NOT NULL,  -- partial MD5 of the file on the reader
  book_hash   text NOT NULL,  -- the library book it is a copy of
  created_at  timestamp with time zone NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, document)
);

ALTER TABLE public.crosspoint_documents ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.crosspoint_documents FROM PUBLIC, anon, authenticated;


-- ===== migrations/025_replica_custom_translators.sql =====
-- Deploy this migration and the replica API validator before releasing clients.
-- Custom translators (apiKey is client-encrypted) and their prompt library.
ALTER TABLE public.replicas
  DROP CONSTRAINT IF EXISTS replicas_kind_allowlist,
  ADD CONSTRAINT replicas_kind_allowlist
    CHECK (kind IN ('dictionary', 'font', 'texture', 'opds_catalog', 'abs_server', 'settings', 'bookshelf', 'custom_translator', 'translation_prompt')) NOT VALID;

-- The migration runner commits the metadata change above before this scan,
-- allowing normal reads and writes while existing rows are validated.
ALTER TABLE public.replicas VALIDATE CONSTRAINT replicas_kind_allowlist;

