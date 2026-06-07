-- Migration: 001_initial_schema
-- Contextual v1 database schema
-- Postgres + PostGIS (for geo queries)

-- Enable PostGIS extension
CREATE EXTENSION IF NOT EXISTS postgis;

-- Users table (managed by Supabase Auth; this adds app-specific fields)
CREATE TABLE IF NOT EXISTS public.profiles (
    id UUID REFERENCES auth.users(id) ON DELETE CASCADE PRIMARY KEY,
    display_name TEXT,
    avatar_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Locations table (reusable place definitions)
CREATE TABLE IF NOT EXISTS public.locations (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL,
    address TEXT,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    geog GEOGRAPHY(POINT,4326),
    place_id TEXT, -- Google Places / Mapbox place ID
    created_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create spatial index
CREATE INDEX IF NOT EXISTS idx_locations_geog ON public.locations USING GIST (geog);

-- Tasks table
CREATE TABLE IF NOT EXISTS public.tasks (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    notes TEXT,
    location_id UUID REFERENCES public.locations(id) ON DELETE SET NULL,
    status TEXT DEFAULT 'active' CHECK (status IN ('active','completed','archived')),
    priority TEXT DEFAULT 'normal' CHECK (priority IN ('low','normal','high','urgent')),
    due_date TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    reminder_radius_meters INT DEFAULT 200, -- geofence radius
    is_hard_to_get BOOLEAN DEFAULT FALSE,
    list_id UUID, -- FK added after lists table creation
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Lists table (task lists, including shared ones)
CREATE TABLE IF NOT EXISTS public.lists (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    name TEXT NOT NULL,
    owner_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    is_shared BOOLEAN DEFAULT FALSE,
    sync_policy TEXT DEFAULT 'realtime' CHECK (sync_policy IN ('realtime','batched')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Add list_id FK to tasks
ALTER TABLE public.tasks
    ADD CONSTRAINT fk_tasks_list_id FOREIGN KEY (list_id) REFERENCES public.lists(id) ON DELETE SET NULL;

-- Shared list memberships
CREATE TABLE IF NOT EXISTS public.list_members (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    list_id UUID NOT NULL REFERENCES public.lists(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    role TEXT DEFAULT 'member' CHECK (role IN ('owner','member','viewer')),
    invited_by UUID REFERENCES public.profiles(id) ON DELETE SET NULL,
    invited_at TIMESTAMPTZ DEFAULT NOW(),
    accepted_at TIMESTAMPTZ,
    UNIQUE(list_id, user_id)
);

-- Invitations (for deep link tracking)
CREATE TABLE IF NOT EXISTS public.invitations (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    list_id UUID NOT NULL REFERENCES public.lists(id) ON DELETE CASCADE,
    invited_by UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    invitee_email TEXT,
    invitee_phone TEXT,
    token TEXT NOT NULL UNIQUE, -- deep link token
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending','accepted','expired')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '7 days')
);

-- Geofence monitoring log (for debugging / analytics)
CREATE TABLE IF NOT EXISTS public.geofence_events (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    task_id UUID REFERENCES public.tasks(id) ON DELETE SET NULL,
    location_id UUID REFERENCES public.locations(id) ON DELETE SET NULL,
    event_type TEXT NOT NULL CHECK (event_type IN ('enter','exit','dwell')),
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    accuracy_meters INT,
    triggered_at TIMESTAMPTZ DEFAULT NOW()
);

-- Habit suggestions (rule-based for v1)
CREATE TABLE IF NOT EXISTS public.habit_suggestions (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    location_id UUID REFERENCES public.locations(id) ON DELETE SET NULL,
    suggested_title TEXT NOT NULL,
    frequency_pattern TEXT, -- e.g., "weekly", "weekdays", "saturday"
    confidence_score REAL DEFAULT 0.0,
    accepted BOOLEAN,
    dismissed BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Sync queue (for offline-first conflict tracking)
CREATE TABLE IF NOT EXISTS public.sync_queue (
    id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
    table_name TEXT NOT NULL,
    record_id UUID NOT NULL,
    operation TEXT NOT NULL CHECK (operation IN ('insert','update','delete')),
    payload JSONB,
    client_timestamp TIMESTAMPTZ DEFAULT NOW(),
    server_timestamp TIMESTAMPTZ,
    resolved BOOLEAN DEFAULT FALSE
);

-- Indexes
CREATE INDEX idx_tasks_user_id ON public.tasks(user_id);
CREATE INDEX idx_tasks_location_id ON public.tasks(location_id);
CREATE INDEX idx_tasks_status ON public.tasks(status);
CREATE INDEX idx_tasks_list_id ON public.tasks(list_id);
CREATE INDEX idx_lists_owner_id ON public.lists(owner_id);
CREATE INDEX idx_list_members_user_id ON public.list_members(user_id);
CREATE INDEX idx_list_members_list_id ON public.list_members(list_id);
CREATE INDEX idx_geofence_events_user_id ON public.geofence_events(user_id);
CREATE INDEX idx_geofence_events_triggered_at ON public.geofence_events(triggered_at);
CREATE INDEX idx_sync_queue_user_id ON public.sync_queue(user_id);
CREATE INDEX idx_sync_queue_resolved ON public.sync_queue(resolved);

-- ==========================================
-- Row Level Security Policies
-- ==========================================

-- Profiles: users can read all profiles, update only their own
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Profiles are viewable by everyone"
    ON public.profiles FOR SELECT USING (true);

CREATE POLICY "Users can update own profile"
    ON public.profiles FOR UPDATE USING (auth.uid() = id);

-- Locations: viewable by anyone who has a task referencing it, or creator
ALTER TABLE public.locations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Locations viewable by task owners or members"
    ON public.locations FOR SELECT
    USING (
        created_by = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.tasks t
            WHERE t.location_id = locations.id AND t.user_id = auth.uid()
        )
        OR EXISTS (
            SELECT 1 FROM public.tasks t
            JOIN public.lists l ON t.list_id = l.id
            JOIN public.list_members lm ON l.id = lm.list_id
            WHERE t.location_id = locations.id AND lm.user_id = auth.uid()
        )
    );

CREATE POLICY "Users can insert locations"
    ON public.locations FOR INSERT WITH CHECK (created_by = auth.uid());

-- Tasks: viewable/editable by owner or list members
ALTER TABLE public.tasks ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Tasks viewable by owner or list members"
    ON public.tasks FOR SELECT
    USING (
        user_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.list_members lm
            WHERE lm.list_id = tasks.list_id AND lm.user_id = auth.uid()
        )
    );

CREATE POLICY "Tasks insertable by owner or list members"
    ON public.tasks FOR INSERT
    WITH CHECK (
        user_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.list_members lm
            WHERE lm.list_id = tasks.list_id AND lm.user_id = auth.uid()
        )
    );

CREATE POLICY "Tasks updatable by owner or list members"
    ON public.tasks FOR UPDATE
    USING (
        user_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.list_members lm
            WHERE lm.list_id = tasks.list_id AND lm.user_id = auth.uid()
        )
    );

CREATE POLICY "Tasks deletable by owner"
    ON public.tasks FOR DELETE USING (user_id = auth.uid());

-- Lists: viewable/editable by owner or members
ALTER TABLE public.lists ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Lists viewable by owner or members"
    ON public.lists FOR SELECT
    USING (
        owner_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.list_members lm
            WHERE lm.list_id = lists.id AND lm.user_id = auth.uid()
        )
    );

CREATE POLICY "Lists insertable by authenticated users"
    ON public.lists FOR INSERT WITH CHECK (owner_id = auth.uid());

CREATE POLICY "Lists updatable by owner"
    ON public.lists FOR UPDATE USING (owner_id = auth.uid());

CREATE POLICY "Lists deletable by owner"
    ON public.lists FOR DELETE USING (owner_id = auth.uid());

-- List members: viewable by list participants; insertable by list owner
ALTER TABLE public.list_members ENABLE ROW LEVEL SECURITY;

CREATE POLICY "List members viewable by participants"
    ON public.list_members FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.lists l
            WHERE l.id = list_members.list_id
              AND (l.owner_id = auth.uid()
                   OR EXISTS (SELECT 1 FROM public.list_members lm2
                              WHERE lm2.list_id = l.id AND lm2.user_id = auth.uid()))
        )
    );

CREATE POLICY "List members insertable by list owner"
    ON public.list_members FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.lists l
            WHERE l.id = list_members.list_id AND l.owner_id = auth.uid()
        )
    );

CREATE POLICY "List members deletable by list owner or self"
    ON public.list_members FOR DELETE
    USING (
        user_id = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.lists l
            WHERE l.id = list_members.list_id AND l.owner_id = auth.uid()
        )
    );

-- Invitations: viewable by inviter or list owner
ALTER TABLE public.invitations ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Invitations viewable by inviter or list owner"
    ON public.invitations FOR SELECT
    USING (
        invited_by = auth.uid()
        OR EXISTS (
            SELECT 1 FROM public.lists l
            WHERE l.id = invitations.list_id AND l.owner_id = auth.uid()
        )
    );

CREATE POLICY "Invitations insertable by list owner"
    ON public.invitations FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1 FROM public.lists l
            WHERE l.id = invitations.list_id AND l.owner_id = auth.uid()
        )
    );

-- Geofence events: viewable by user only
ALTER TABLE public.geofence_events ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Geofence events viewable by owner"
    ON public.geofence_events FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Geofence events insertable by owner"
    ON public.geofence_events FOR INSERT WITH CHECK (user_id = auth.uid());

-- Habit suggestions: viewable/editable by owner
ALTER TABLE public.habit_suggestions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Habit suggestions viewable by owner"
    ON public.habit_suggestions FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Habit suggestions insertable by system only"
    ON public.habit_suggestions FOR INSERT WITH CHECK (false); -- via RPC / edge function

CREATE POLICY "Habit suggestions updatable by owner"
    ON public.habit_suggestions FOR UPDATE USING (user_id = auth.uid());

-- Sync queue: viewable by owner
ALTER TABLE public.sync_queue ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Sync queue viewable by owner"
    ON public.sync_queue FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "Sync queue insertable by owner"
    ON public.sync_queue FOR INSERT WITH CHECK (user_id = auth.uid());

-- ==========================================
-- Functions & Triggers
-- ==========================================

-- Auto-update updated_at
CREATE OR REPLACE FUNCTION public.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_profiles_updated_at
    BEFORE UPDATE ON public.profiles
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_tasks_updated_at
    BEFORE UPDATE ON public.tasks
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

CREATE TRIGGER set_lists_updated_at
    BEFORE UPDATE ON public.lists
    FOR EACH ROW EXECUTE FUNCTION public.set_updated_at();

-- Function: find nearby tasks for a user (used by mobile for geofence registration)
CREATE OR REPLACE FUNCTION public.nearby_tasks(
    p_user_id UUID,
    p_lat DOUBLE PRECISION,
    p_lng DOUBLE PRECISION,
    p_radius_meters INT DEFAULT 5000
)
RETURNS TABLE (
    task_id UUID,
    title TEXT,
    location_name TEXT,
    distance_meters DOUBLE PRECISION,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION
) AS $$
BEGIN
    RETURN QUERY
    SELECT
        t.id AS task_id,
        t.title,
        l.name AS location_name,
        ST_Distance(l.geog, ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography) AS distance_meters,
        l.latitude,
        l.longitude
    FROM public.tasks t
    JOIN public.locations l ON t.location_id = l.id
    WHERE t.user_id = p_user_id
      AND t.status = 'active'
      AND ST_DWithin(
          l.geog,
          ST_SetSRID(ST_MakePoint(p_lng, p_lat), 4326)::geography,
          p_radius_meters
      )
    ORDER BY distance_meters ASC;
END;
$$ LANGUAGE plpgsql;

-- Function: generate invite token
CREATE OR REPLACE FUNCTION public.generate_invite_token()
RETURNS TEXT AS $$
BEGIN
    RETURN encode(gen_random_bytes(16), 'hex');
END;
$$ LANGUAGE plpgsql;

-- Function: accept invitation by token (called from mobile deep link)
CREATE OR REPLACE FUNCTION public.accept_invite(p_token TEXT, p_user_id UUID)
RETURNS UUID AS $$
DECLARE
    v_list_id UUID;
    v_invitation_id UUID;
BEGIN
    SELECT id, list_id INTO v_invitation_id, v_list_id
    FROM public.invitations
    WHERE token = p_token AND status = 'pending' AND expires_at > NOW();

    IF v_list_id IS NULL THEN
        RETURN NULL;
    END IF;

    UPDATE public.invitations
    SET status = 'accepted'
    WHERE id = v_invitation_id;

    INSERT INTO public.list_members (list_id, user_id, role, invited_by, accepted_at)
    VALUES (v_list_id, p_user_id, 'member', (
        SELECT invited_by FROM public.invitations WHERE id = v_invitation_id
    ), NOW())
    ON CONFLICT (list_id, user_id) DO NOTHING;

    RETURN v_list_id;
END;
$$ LANGUAGE plpgsql;
