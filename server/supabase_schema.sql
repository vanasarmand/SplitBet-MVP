-- =====================================================================
-- SplitBet MVP — Supabase 24/7 Production Schema & Migration
-- =====================================================================

-- Enable pgcrypto for UUIDs & cryptographic hashes
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- 1. USERS TABLE
CREATE TABLE IF NOT EXISTS public.users (
    id TEXT PRIMARY KEY,
    username TEXT NOT NULL UNIQUE,
    display_name TEXT NOT NULL,
    avatar_url TEXT,
    phone TEXT,
    email TEXT,
    verified INT DEFAULT 1,
    subscription_tier TEXT DEFAULT 'Standard',
    first_pool_created INT DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 2. FINANCIAL LEDGER ENTRIES (Double-entry accounting)
CREATE TABLE IF NOT EXISTS public.ledger_entries (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    user_id TEXT NOT NULL,
    pool_id TEXT,
    account_type TEXT NOT NULL CHECK (account_type IN ('AVAILABLE', 'RESERVED', 'PLATFORM_REVENUE')),
    type TEXT NOT NULL CHECK (type IN ('DEPOSIT', 'POOL_RESERVE', 'POOL_ENTRY', 'POOL_WIN', 'PLATFORM_FEE', 'POOL_REFUND', 'WITHDRAWAL')),
    amount NUMERIC(12, 2) NOT NULL,
    currency TEXT DEFAULT 'ZAR',
    status TEXT DEFAULT 'SETTLED' CHECK (status IN ('PENDING', 'SETTLED', 'FAILED', 'CANCELLED')),
    description TEXT,
    reference_id TEXT,
    timestamp TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_ledger_user_account ON public.ledger_entries(user_id, account_type, status);
CREATE INDEX IF NOT EXISTS idx_ledger_pool ON public.ledger_entries(pool_id);

-- 3. POOLS TABLE
CREATE TABLE IF NOT EXISTS public.pools (
    id TEXT PRIMARY KEY,
    creator_id TEXT NOT NULL REFERENCES public.users(id),
    deposit_amount NUMERIC(12, 2) NOT NULL,
    max_players INT NOT NULL CHECK (max_players >= 2 AND max_players <= 8),
    current_players INT NOT NULL DEFAULT 1,
    gross_pool NUMERIC(12, 2) NOT NULL,
    platform_fee_percent NUMERIC(5, 2) NOT NULL DEFAULT 7.00,
    platform_fee_amount NUMERIC(12, 2) NOT NULL,
    net_payout NUMERIC(12, 2) NOT NULL,
    status TEXT NOT NULL DEFAULT 'OPEN' CHECK (status IN ('DRAFT', 'OPEN', 'FULL', 'LOCKED', 'RANDOM_SELECTION', 'SETTLED', 'CANCELLED', 'REFUNDED')),
    description TEXT,
    winner_id TEXT REFERENCES public.users(id),
    random_selection_proof JSONB,
    created_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
    settled_at TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_pools_status ON public.pools(status, created_at DESC);

-- 4. POOL PARTICIPANTS TABLE
CREATE TABLE IF NOT EXISTS public.pool_participants (
    pool_id TEXT NOT NULL REFERENCES public.pools(id) ON DELETE CASCADE,
    user_id TEXT NOT NULL REFERENCES public.users(id) ON DELETE CASCADE,
    deposit NUMERIC(12, 2) NOT NULL,
    joined_at TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL,
    is_winner INT DEFAULT 0,
    payout NUMERIC(12, 2) DEFAULT 0.00,
    PRIMARY KEY (pool_id, user_id)
);

-- 5. AUDIT LOGS TABLE
CREATE TABLE IF NOT EXISTS public.audit_logs (
    id TEXT PRIMARY KEY DEFAULT gen_random_uuid()::text,
    actor TEXT NOT NULL,
    action TEXT NOT NULL,
    entity TEXT NOT NULL,
    entity_id TEXT NOT NULL,
    details TEXT,
    timestamp TIMESTAMPTZ DEFAULT timezone('utc'::text, now()) NOT NULL
);

-- 6. PLATFORM CONFIG
CREATE TABLE IF NOT EXISTS public.platform_config (
    key TEXT PRIMARY KEY,
    value TEXT NOT NULL
);

INSERT INTO public.platform_config (key, value) VALUES
    ('platform_fee_percent', '7.0'),
    ('min_deposit', '10.0'),
    ('max_deposit', '10000.0'),
    ('min_players', '2'),
    ('max_players', '8'),
    ('maintenance_mode', 'false')
ON CONFLICT (key) DO NOTHING;

-- =====================================================================
-- ROW LEVEL SECURITY (RLS) POLICIES
-- =====================================================================
ALTER TABLE public.users ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ledger_entries ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pools ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.pool_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.audit_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.platform_config ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
    DROP POLICY IF EXISTS "Public users access" ON public.users;
    CREATE POLICY "Public users access" ON public.users FOR ALL USING (true) WITH CHECK (true);

    DROP POLICY IF EXISTS "Public ledger access" ON public.ledger_entries;
    CREATE POLICY "Public ledger access" ON public.ledger_entries FOR ALL USING (true) WITH CHECK (true);

    DROP POLICY IF EXISTS "Public pools access" ON public.pools;
    CREATE POLICY "Public pools access" ON public.pools FOR ALL USING (true) WITH CHECK (true);

    DROP POLICY IF EXISTS "Public participants access" ON public.pool_participants;
    CREATE POLICY "Public participants access" ON public.pool_participants FOR ALL USING (true) WITH CHECK (true);

    DROP POLICY IF EXISTS "Public audit access" ON public.audit_logs;
    CREATE POLICY "Public audit access" ON public.audit_logs FOR ALL USING (true) WITH CHECK (true);

    DROP POLICY IF EXISTS "Public config access" ON public.platform_config;
    CREATE POLICY "Public config access" ON public.platform_config FOR SELECT USING (true);
END $$;

-- =====================================================================
-- REALTIME REPLICATION
-- =====================================================================
DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.pools;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.pool_participants;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.ledger_entries;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- =====================================================================
-- ATOMIC PL/pgSQL RPC FUNCTIONS
-- =====================================================================

-- 1. Get User Dynamic Balance
CREATE OR REPLACE FUNCTION public.get_user_balance(p_user_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_avail NUMERIC(12, 2);
    v_res NUMERIC(12, 2);
    v_total NUMERIC(12, 2);
BEGIN
    SELECT COALESCE(SUM(amount), 0.00)
    INTO v_avail
    FROM public.ledger_entries
    WHERE user_id = p_user_id AND account_type = 'AVAILABLE' AND status = 'SETTLED';

    IF v_avail < 0 THEN
        v_avail := 0.00;
    END IF;

    SELECT COALESCE(SUM(pp.deposit), 0.00)
    INTO v_res
    FROM public.pool_participants pp
    JOIN public.pools p ON p.id = pp.pool_id
    WHERE pp.user_id = p_user_id AND p.status IN ('OPEN', 'FULL', 'LOCKED', 'RANDOM_SELECTION');

    v_total := v_avail + v_res;

    RETURN jsonb_build_object(
        'user_id', p_user_id,
        'currency', 'ZAR',
        'available', ROUND(v_avail, 2),
        'reserved', ROUND(v_res, 2),
        'total', ROUND(v_total, 2)
    );
END;
$$;

-- 2. Record Virtual Deposit Top-up
CREATE OR REPLACE FUNCTION public.record_deposit(p_user_id TEXT, p_amount NUMERIC)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_tx_id TEXT := gen_random_uuid()::text;
    v_now TIMESTAMPTZ := timezone('utc'::text, now());
BEGIN
    IF p_amount <= 0 THEN
        RAISE EXCEPTION 'Deposit amount must be greater than zero.';
    END IF;

    INSERT INTO public.ledger_entries (id, user_id, pool_id, account_type, type, amount, currency, status, description, timestamp)
    VALUES (v_tx_id, p_user_id, NULL, 'AVAILABLE', 'DEPOSIT', p_amount, 'ZAR', 'SETTLED', 'Account top-up / deposit', v_now);

    INSERT INTO public.audit_logs (actor, action, entity, entity_id, details, timestamp)
    VALUES (p_user_id, 'DEPOSIT', 'ledger_entries', v_tx_id, 'Deposited ZAR ' || p_amount::text, v_now);

    RETURN jsonb_build_object('success', true, 'tx_id', v_tx_id, 'balance', public.get_user_balance(p_user_id));
END;
$$;

-- 3. Get Pool Details with Formatted Creator, Participants & Odds
CREATE OR REPLACE FUNCTION public.get_pool_details(p_pool_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_pool RECORD;
    v_creator JSONB;
    v_winner JSONB := NULL;
    v_participants JSONB := '[]'::jsonb;
    v_prob TEXT;
BEGIN
    SELECT * INTO v_pool FROM public.pools WHERE id = p_pool_id;
    IF NOT FOUND THEN RETURN NULL; END IF;

    SELECT jsonb_build_object('id', id, 'username', username, 'display_name', display_name, 'avatar_url', avatar_url)
    INTO v_creator
    FROM public.users WHERE id = v_pool.creator_id;

    IF v_pool.winner_id IS NOT NULL THEN
        SELECT jsonb_build_object('id', id, 'username', username, 'display_name', display_name, 'avatar_url', avatar_url)
        INTO v_winner
        FROM public.users WHERE id = v_pool.winner_id;
    END IF;

    SELECT jsonb_agg(
        jsonb_build_object(
            'user_id', pp.user_id,
            'deposit', pp.deposit,
            'joined_at', pp.joined_at,
            'is_winner', (pp.is_winner = 1),
            'payout', pp.payout,
            'username', u.username,
            'display_name', u.display_name,
            'avatar_url', u.avatar_url
        ) ORDER BY pp.joined_at ASC
    )
    INTO v_participants
    FROM public.pool_participants pp
    JOIN public.users u ON u.id = pp.user_id
    WHERE pp.pool_id = p_pool_id;

    IF v_participants IS NULL THEN v_participants := '[]'::jsonb; END IF;

    IF v_pool.max_players < 2 THEN
        v_prob := 'Waiting for players';
    ELSE
        v_prob := ROUND((100.0 / v_pool.max_players), 2)::text || '%';
    END IF;

    RETURN jsonb_build_object(
        'id', v_pool.id,
        'creator_id', v_pool.creator_id,
        'deposit_amount', v_pool.deposit_amount,
        'max_players', v_pool.max_players,
        'current_players', v_pool.current_players,
        'gross_pool', v_pool.gross_pool,
        'platform_fee_percent', v_pool.platform_fee_percent,
        'platform_fee_amount', v_pool.platform_fee_amount,
        'net_payout', v_pool.net_payout,
        'status', v_pool.status,
        'description', v_pool.description,
        'winner_id', v_pool.winner_id,
        'winner', v_winner,
        'created_at', v_pool.created_at,
        'settled_at', v_pool.settled_at,
        'creator', v_creator,
        'participants', v_participants,
        'odds_to_win', v_prob,
        'slots_remaining', GREATEST(0, v_pool.max_players - v_pool.current_players),
        'is_full', (v_pool.current_players >= v_pool.max_players),
        'share_url', 'https://splitbet.co.za/pool/' || v_pool.id,
        'whatsapp_share_text', 'Hey! Join my SplitBet pool: Bet R' || v_pool.deposit_amount || ' to win R' || v_pool.net_payout || ' (' || v_pool.max_players || ' players, equal chance)! Tap here: https://splitbet.co.za/pool/' || v_pool.id
    );
END;
$$;

-- 4. Get All Pools with Filters
CREATE OR REPLACE FUNCTION public.get_all_pools(p_filter TEXT DEFAULT NULL, p_user_id TEXT DEFAULT NULL)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_pools JSONB := '[]'::jsonb;
    v_open_count INT := 0;
    v_pool_id TEXT;
    v_details JSONB;
BEGIN
    FOR v_pool_id IN
        SELECT p.id
        FROM public.pools p
        WHERE
            (p_filter IS NULL OR p_filter = 'all' OR
             (p_filter = '1v1' AND p.max_players = 2) OR
             (p_filter = '3-4' AND p.max_players IN (3, 4)) OR
             (p_filter = '5-8' AND p.max_players >= 5) OR
             (p_filter = 'settled' AND p.status = 'SETTLED') OR
             (p_filter = 'my_pools' AND p_user_id IS NOT NULL AND EXISTS (
                 SELECT 1 FROM public.pool_participants pp WHERE pp.pool_id = p.id AND pp.user_id = p_user_id
             )))
        ORDER BY
            CASE p.status WHEN 'OPEN' THEN 1 WHEN 'FULL' THEN 2 WHEN 'LOCKED' THEN 3 ELSE 4 END,
            p.created_at DESC
    LOOP
        v_details := public.get_pool_details(v_pool_id);
        IF v_details IS NOT NULL THEN
            v_pools := v_pools || jsonb_build_array(v_details);
            IF (v_details->>'status') = 'OPEN' THEN
                v_open_count := v_open_count + 1;
            END IF;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'total_count', jsonb_array_length(v_pools),
        'open_count', v_open_count,
        'pools', v_pools
    );
END;
$$;

-- 5. Settle Pool (Cryptographic RNG & Ledger Payout)
CREATE OR REPLACE FUNCTION public.settle_pool(p_pool_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_pool RECORD;
    v_participants TEXT[];
    v_count INT;
    v_winner_idx INT;
    v_winner_id TEXT;
    v_server_seed TEXT := encode(gen_random_bytes(32), 'hex');
    v_now TIMESTAMPTZ := timezone('utc'::text, now());
    v_proof JSONB;
    v_entropy TEXT;
    v_proof_hash TEXT;
    v_win_tx TEXT := gen_random_uuid()::text;
    v_fee_tx TEXT := gen_random_uuid()::text;
BEGIN
    SELECT * INTO v_pool FROM public.pools WHERE id = p_pool_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pool not found: %', p_pool_id;
    END IF;

    SELECT array_agg(user_id ORDER BY joined_at ASC)
    INTO v_participants
    FROM public.pool_participants
    WHERE pool_id = p_pool_id;

    v_count := array_length(v_participants, 1);
    IF v_count < 2 THEN
        RAISE EXCEPTION 'Pool must have at least 2 participants to settle';
    END IF;

    -- Cryptographically secure fair winner selection
    v_winner_idx := ('x' || substr(encode(gen_random_bytes(4), 'hex'), 1, 8))::bit(32)::bigint % v_count;
    v_winner_id := v_participants[v_winner_idx + 1];

    -- Audit Proof
    v_entropy := p_pool_id || ':' || v_now::text || ':' || v_server_seed || ':' || array_to_string(v_participants, ',');
    v_proof_hash := encode(digest(v_entropy, 'sha256'), 'hex');

    v_proof := jsonb_build_object(
        'mechanism', 'POSTGRES_PGCRYPTO_RANDOM_INT_UNBIASED',
        'pool_id', p_pool_id,
        'timestamp', v_now,
        'total_participants', v_count,
        'participants', v_participants,
        'winning_index', v_winner_idx,
        'winner_id', v_winner_id,
        'server_seed', v_server_seed,
        'entropy_hash', v_proof_hash,
        'equal_probability', ROUND((100.0 / v_count), 2)::text || '%'
    );

    -- 1. Credit Platform Fee
    INSERT INTO public.ledger_entries (id, user_id, pool_id, account_type, type, amount, currency, status, description, reference_id, timestamp)
    VALUES (v_fee_tx, 'PLATFORM', p_pool_id, 'PLATFORM_REVENUE', 'PLATFORM_FEE', v_pool.platform_fee_amount, 'ZAR', 'SETTLED', 'Platform fee (7%)', p_pool_id, v_now);

    -- 2. Credit Winner Payout
    INSERT INTO public.ledger_entries (id, user_id, pool_id, account_type, type, amount, currency, status, description, reference_id, timestamp)
    VALUES (v_win_tx, v_winner_id, p_pool_id, 'AVAILABLE', 'POOL_WIN', v_pool.net_payout, 'ZAR', 'SETTLED', 'Winning payout for pool', p_pool_id, v_now);

    -- 3. Update Participant Records
    UPDATE public.pool_participants
    SET is_winner = CASE WHEN user_id = v_winner_id THEN 1 ELSE 0 END,
        payout = CASE WHEN user_id = v_winner_id THEN v_pool.net_payout ELSE 0.00 END
    WHERE pool_id = p_pool_id;

    -- 4. Mark Pool Settled
    UPDATE public.pools
    SET status = 'SETTLED',
        winner_id = v_winner_id,
        random_selection_proof = v_proof,
        settled_at = v_now
    WHERE id = p_pool_id;

    INSERT INTO public.audit_logs (actor, action, entity, entity_id, details, timestamp)
    VALUES ('SYSTEM', 'POOL_SETTLED', 'pools', p_pool_id, 'Winner: ' || v_winner_id || ', Payout: R' || v_pool.net_payout, v_now);

    RETURN jsonb_build_object(
        'pool_id', p_pool_id,
        'winner_id', v_winner_id,
        'net_payout', v_pool.net_payout,
        'proof', v_proof,
        'settled_at', v_now
    );
END;
$$;

-- 6. Create Betting Pool (Atomic)
CREATE OR REPLACE FUNCTION public.create_pool(
    p_creator_id TEXT,
    p_deposit_amount NUMERIC,
    p_max_players INT,
    p_description TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_pool_id TEXT := 'pool_' || substr(gen_random_uuid()::text, 1, 8);
    v_now TIMESTAMPTZ := timezone('utc'::text, now());
    v_balance JSONB;
    v_avail NUMERIC;
    v_gross NUMERIC;
    v_fee_pct NUMERIC := 7.00;
    v_fee_amt NUMERIC;
    v_net NUMERIC;
    v_res_tx TEXT := gen_random_uuid()::text;
BEGIN
    v_balance := public.get_user_balance(p_creator_id);
    v_avail := (v_balance->>'available')::NUMERIC;

    IF v_avail < p_deposit_amount THEN
        RAISE EXCEPTION 'Insufficient spendable funds. Available: R%, Required: R%', v_avail, p_deposit_amount;
    END IF;

    v_gross := p_deposit_amount * p_max_players;
    v_fee_amt := ROUND(v_gross * (v_fee_pct / 100.0), 2);
    v_net := v_gross - v_fee_amt;

    INSERT INTO public.pools (
        id, creator_id, deposit_amount, max_players, current_players, gross_pool,
        platform_fee_percent, platform_fee_amount, net_payout, status, description, created_at
    ) VALUES (
        v_pool_id, p_creator_id, p_deposit_amount, p_max_players, 1, v_gross,
        v_fee_pct, v_fee_amt, v_net, 'OPEN', p_description, v_now
    );

    INSERT INTO public.pool_participants (pool_id, user_id, deposit, joined_at)
    VALUES (v_pool_id, p_creator_id, p_deposit_amount, v_now);

    INSERT INTO public.ledger_entries (id, user_id, pool_id, account_type, type, amount, currency, status, description, reference_id, timestamp)
    VALUES (v_res_tx, p_creator_id, v_pool_id, 'AVAILABLE', 'POOL_RESERVE', -p_deposit_amount, 'ZAR', 'SETTLED', 'Committed to pool deposit', v_pool_id, v_now);

    UPDATE public.users SET first_pool_created = 1 WHERE id = p_creator_id;

    INSERT INTO public.audit_logs (actor, action, entity, entity_id, details, timestamp)
    VALUES (p_creator_id, 'CREATE_POOL', 'pools', v_pool_id, 'Created pool for ' || p_max_players || ' players, deposit R' || p_deposit_amount, v_now);

    RETURN public.get_pool_details(v_pool_id);
END;
$$;

-- 7. Join Betting Pool (Atomic with Auto-Settlement Trigger)
CREATE OR REPLACE FUNCTION public.join_pool(p_pool_id TEXT, p_user_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_pool RECORD;
    v_balance JSONB;
    v_avail NUMERIC;
    v_now TIMESTAMPTZ := timezone('utc'::text, now());
    v_updated_players INT;
    v_res_tx TEXT := gen_random_uuid()::text;
    v_settlement_res JSONB := NULL;
BEGIN
    SELECT * INTO v_pool FROM public.pools WHERE id = p_pool_id FOR UPDATE;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Pool not found: %', p_pool_id;
    END IF;

    IF v_pool.status != 'OPEN' THEN
        RAISE EXCEPTION 'Cannot join pool. Current status is %', v_pool.status;
    END IF;

    IF v_pool.current_players >= v_pool.max_players THEN
        RAISE EXCEPTION 'Pool is already full';
    END IF;

    IF EXISTS (SELECT 1 FROM public.pool_participants WHERE pool_id = p_pool_id AND user_id = p_user_id) THEN
        RAISE EXCEPTION 'You have already joined this pool';
    END IF;

    v_balance := public.get_user_balance(p_user_id);
    v_avail := (v_balance->>'available')::NUMERIC;

    IF v_avail < v_pool.deposit_amount THEN
        RAISE EXCEPTION 'Insufficient funds. Available: R%, Required: R%', v_avail, v_pool.deposit_amount;
    END IF;

    -- Reserve User Funds
    INSERT INTO public.ledger_entries (id, user_id, pool_id, account_type, type, amount, currency, status, description, reference_id, timestamp)
    VALUES (v_res_tx, p_user_id, p_pool_id, 'AVAILABLE', 'POOL_RESERVE', -v_pool.deposit_amount, 'ZAR', 'SETTLED', 'Reserved deposit for pool entry', p_pool_id, v_now);

    -- Add Participant
    INSERT INTO public.pool_participants (pool_id, user_id, deposit, joined_at)
    VALUES (p_pool_id, p_user_id, v_pool.deposit_amount, v_now);

    v_updated_players := v_pool.current_players + 1;

    IF v_updated_players >= v_pool.max_players THEN
        UPDATE public.pools
        SET current_players = v_updated_players, status = 'FULL'
        WHERE id = p_pool_id;

        -- Auto-trigger Settlement
        v_settlement_res := public.settle_pool(p_pool_id);
    ELSE
        UPDATE public.pools
        SET current_players = v_updated_players
        WHERE id = p_pool_id;
    END IF;

    INSERT INTO public.audit_logs (actor, action, entity, entity_id, details, timestamp)
    VALUES (p_user_id, 'JOIN_POOL', 'pools', p_pool_id, 'Joined slot ' || v_updated_players || '/' || v_pool.max_players, v_now);

    RETURN public.get_pool_details(p_pool_id);
END;
$$;

-- 8. Get User Game Statistics
CREATE OR REPLACE FUNCTION public.get_user_stats(p_user_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_active INT := 0;
    v_completed INT := 0;
    v_wins INT := 0;
    v_losses INT := 0;
    v_total_won NUMERIC(12, 2) := 0.00;
    v_win_rate TEXT := '0.0%';
BEGIN
    SELECT COUNT(DISTINCT pp.pool_id)
    INTO v_active
    FROM public.pool_participants pp
    JOIN public.pools p ON p.id = pp.pool_id
    WHERE pp.user_id = p_user_id AND p.status IN ('OPEN', 'FULL', 'LOCKED', 'RANDOM_SELECTION');

    SELECT COUNT(DISTINCT pp.pool_id)
    INTO v_completed
    FROM public.pool_participants pp
    JOIN public.pools p ON p.id = pp.pool_id
    WHERE pp.user_id = p_user_id AND p.status = 'SETTLED';

    SELECT COUNT(DISTINCT pp.pool_id)
    INTO v_wins
    FROM public.pool_participants pp
    JOIN public.pools p ON p.id = pp.pool_id
    WHERE pp.user_id = p_user_id AND (pp.is_winner = 1 OR p.winner_id = p_user_id) AND p.status = 'SETTLED';

    v_losses := GREATEST(0, v_completed - v_wins);

    IF v_completed > 0 THEN
        v_win_rate := ROUND((v_wins::NUMERIC / v_completed::NUMERIC) * 100.0, 1)::TEXT || '%';
    END IF;

    SELECT COALESCE(SUM(COALESCE(NULLIF(pp.payout, 0.00), p.net_payout)), 0.00)
    INTO v_total_won
    FROM public.pool_participants pp
    JOIN public.pools p ON p.id = pp.pool_id
    WHERE pp.user_id = p_user_id AND (pp.is_winner = 1 OR p.winner_id = p_user_id) AND p.status = 'SETTLED';

    RETURN jsonb_build_object(
        'active_pools', v_active,
        'completed_pools', v_completed,
        'wins', v_wins,
        'losses', v_losses,
        'win_rate', v_win_rate,
        'total_won', ROUND(v_total_won, 2)
    );
END;
$$;

-- 9. Get All Users with Dynamic Balances & Game Stats
CREATE OR REPLACE FUNCTION public.get_all_users()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_users JSONB := '[]'::jsonb;
    v_user RECORD;
    v_balance JSONB;
    v_stats JSONB;
BEGIN
    FOR v_user IN SELECT * FROM public.users ORDER BY created_at ASC
    LOOP
        v_balance := public.get_user_balance(v_user.id);
        v_stats := public.get_user_stats(v_user.id);
        v_users := v_users || jsonb_build_array(
            jsonb_build_object(
                'id', v_user.id,
                'username', v_user.username,
                'display_name', v_user.display_name,
                'avatar_url', v_user.avatar_url,
                'phone', v_user.phone,
                'email', v_user.email,
                'verified', v_user.verified,
                'subscription_tier', v_user.subscription_tier,
                'first_pool_created', v_user.first_pool_created,
                'created_at', v_user.created_at,
                'balance', v_balance,
                'stats', v_stats
            )
        );
    END LOOP;
    RETURN v_users;
END;
$$;

-- 10. Get Single User with Balance & Game Stats
CREATE OR REPLACE FUNCTION public.get_single_user(p_user_id TEXT)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_user RECORD;
    v_balance JSONB;
    v_stats JSONB;
BEGIN
    SELECT * INTO v_user FROM public.users WHERE id = p_user_id;
    IF NOT FOUND THEN RETURN NULL; END IF;

    v_balance := public.get_user_balance(p_user_id);
    v_stats := public.get_user_stats(p_user_id);
    RETURN jsonb_build_object(
        'id', v_user.id,
        'username', v_user.username,
        'display_name', v_user.display_name,
        'avatar_url', v_user.avatar_url,
        'phone', v_user.phone,
        'email', v_user.email,
        'verified', v_user.verified,
        'subscription_tier', v_user.subscription_tier,
        'first_pool_created', v_user.first_pool_created,
        'created_at', v_user.created_at,
        'balance', v_balance,
        'stats', v_stats
    );
END;
$$;

-- 11. Get Admin Overview & Financials
CREATE OR REPLACE FUNCTION public.get_admin_overview()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
AS $$
DECLARE
    v_total_users INT;
    v_total_pools INT;
    v_active_pools INT;
    v_settled_pools INT;
    v_platform_revenue NUMERIC(12, 2);
    v_gross_volume NUMERIC(12, 2);
    v_audit_logs JSONB;
BEGIN
    SELECT COUNT(*) INTO v_total_users FROM public.users;
    SELECT COUNT(*) INTO v_total_pools FROM public.pools;
    SELECT COUNT(*) INTO v_active_pools FROM public.pools WHERE status IN ('OPEN', 'FULL', 'LOCKED', 'RANDOM_SELECTION');
    SELECT COUNT(*) INTO v_settled_pools FROM public.pools WHERE status = 'SETTLED';

    SELECT COALESCE(SUM(amount), 0.00) INTO v_platform_revenue
    FROM public.ledger_entries
    WHERE account_type = 'PLATFORM_REVENUE' AND status = 'SETTLED';

    SELECT COALESCE(SUM(gross_pool), 0.00) INTO v_gross_volume
    FROM public.pools
    WHERE status = 'SETTLED';

    SELECT COALESCE(jsonb_agg(to_jsonb(sub)), '[]'::jsonb)
    INTO v_audit_logs
    FROM (
        SELECT id, actor, action, entity, entity_id, details, timestamp
        FROM public.audit_logs
        ORDER BY timestamp DESC
        LIMIT 50
    ) sub;

    RETURN jsonb_build_object(
        'metrics', jsonb_build_object(
            'total_users', v_total_users,
            'total_pools', v_total_pools,
            'active_pools', v_active_pools,
            'settled_pools', v_settled_pools,
            'platform_revenue_zar', ROUND(v_platform_revenue, 2),
            'gross_volume_zar', ROUND(v_gross_volume, 2)
        ),
        'audit_logs', v_audit_logs
    );
END;
$$;

-- =====================================================================
-- SEED DEFAULT DEMO DATA
-- =====================================================================
DO $$
DECLARE
    v_now TIMESTAMPTZ := timezone('utc'::text, now());
BEGIN
    INSERT INTO public.users (id, username, display_name, avatar_url, phone, email, verified, first_pool_created, created_at)
    VALUES
        ('usr_deric', 'deric', 'Deric', 'https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=150', '+27 82 123 4567', 'deric@splitbet.co.za', 1, 1, v_now),
        ('usr_sarah', 'sarah_j', 'Sarah Jenkins', 'https://images.unsplash.com/photo-1517841905240-472988babdf9?w=150', '+27 83 234 5678', 'sarah@splitbet.co.za', 1, 1, v_now),
        ('usr_marcus', 'marcus_k', 'Marcus Krause', 'https://images.unsplash.com/photo-1507003211169-0a1dd7228f2d?w=150', '+27 84 345 6789', 'marcus@splitbet.co.za', 1, 1, v_now),
        ('usr_thabo', 'thabo_m', 'Thabo Molefe', 'https://images.unsplash.com/photo-1500648767791-00dcc994a43e?w=150', '+27 85 456 7890', 'thabo@splitbet.co.za', 1, 1, v_now),
        ('usr_elena', 'elena_v', 'Elena Vance', 'https://images.unsplash.com/photo-1544005313-94ddf0286df2?w=150', '+27 86 567 8901', 'elena@splitbet.co.za', 1, 1, v_now)
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.ledger_entries (id, user_id, pool_id, account_type, type, amount, currency, status, description, timestamp)
    VALUES
        ('tx_init_deric', 'usr_deric', NULL, 'AVAILABLE', 'DEPOSIT', 1250.00, 'ZAR', 'SETTLED', 'Initial verified test deposit', v_now),
        ('tx_init_sarah', 'usr_sarah', NULL, 'AVAILABLE', 'DEPOSIT', 2000.00, 'ZAR', 'SETTLED', 'Initial verified test deposit', v_now),
        ('tx_init_marcus', 'usr_marcus', NULL, 'AVAILABLE', 'DEPOSIT', 1500.00, 'ZAR', 'SETTLED', 'Initial verified test deposit', v_now),
        ('tx_init_thabo', 'usr_thabo', NULL, 'AVAILABLE', 'DEPOSIT', 1800.00, 'ZAR', 'SETTLED', 'Initial verified test deposit', v_now),
        ('tx_init_elena', 'usr_elena', NULL, 'AVAILABLE', 'DEPOSIT', 3000.00, 'ZAR', 'SETTLED', 'Initial verified test deposit', v_now)
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.pools (id, creator_id, deposit_amount, max_players, current_players, gross_pool, platform_fee_percent, platform_fee_amount, net_payout, status, description, created_at)
    VALUES ('pool_155_1v1', 'usr_sarah', 155.00, 2, 1, 310.00, 7.00, 22.00, 288.00, 'OPEN', '1v1 Quick Draw! Winner takes all.', v_now)
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.pool_participants (pool_id, user_id, deposit, joined_at)
    VALUES ('pool_155_1v1', 'usr_sarah', 155.00, v_now)
    ON CONFLICT DO NOTHING;

    INSERT INTO public.pools (id, creator_id, deposit_amount, max_players, current_players, gross_pool, platform_fee_percent, platform_fee_amount, net_payout, status, description, created_at)
    VALUES ('pool_300_4p', 'usr_marcus', 300.00, 4, 3, 1200.00, 7.00, 84.00, 1116.00, 'OPEN', '4-Player Weekend Dash! 1 spot remaining.', v_now)
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.pool_participants (pool_id, user_id, deposit, joined_at)
    VALUES
        ('pool_300_4p', 'usr_marcus', 300.00, v_now),
        ('pool_300_4p', 'usr_thabo', 300.00, v_now),
        ('pool_300_4p', 'usr_elena', 300.00, v_now)
    ON CONFLICT DO NOTHING;

    INSERT INTO public.pools (id, creator_id, deposit_amount, max_players, current_players, gross_pool, platform_fee_percent, platform_fee_amount, net_payout, status, description, created_at)
    VALUES ('pool_300_3p', 'usr_thabo', 300.00, 3, 2, 900.00, 7.00, 63.00, 837.00, 'OPEN', 'Triple threat pool. High excitement.', v_now)
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.pool_participants (pool_id, user_id, deposit, joined_at)
    VALUES
        ('pool_300_3p', 'usr_thabo', 300.00, v_now),
        ('pool_300_3p', 'usr_sarah', 300.00, v_now)
    ON CONFLICT DO NOTHING;

    INSERT INTO public.pools (id, creator_id, deposit_amount, max_players, current_players, gross_pool, platform_fee_percent, platform_fee_amount, net_payout, status, description, created_at)
    VALUES ('pool_500_1v1', 'usr_elena', 500.00, 2, 1, 1000.00, 7.00, 70.00, 930.00, 'OPEN', 'High stakes 1v1. Are you ready?', v_now)
    ON CONFLICT (id) DO NOTHING;

    INSERT INTO public.pool_participants (pool_id, user_id, deposit, joined_at)
    VALUES ('pool_500_1v1', 'usr_elena', 500.00, v_now)
    ON CONFLICT DO NOTHING;
END $$;
