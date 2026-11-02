-- Schéma d'Opti (PostgreSQL / Supabase), généré depuis la base de production le 02/11/2026.
--
-- Avant de lancer ce fichier dans le SQL Editor d'un projet Supabase neuf :
--   remplace 00000000-0000-0000-0000-000000000000 par l'identifiant (UUID) de ton compte
--   (Authentication › Users). Les règles d'accès n'autorisent que ce compte, et seulement avec
--   une session validée par le code à 6 chiffres (aal2). Le backend utilise la clé secrète.

create table public.bank_accounts (
  id uuid default gen_random_uuid() not null,
  bank text not null,
  account_label text not null,
  account_type text default 'checking'::text,
  iban_last4 text,
  card_last4 text,
  currency text default 'EUR'::text not null,
  balance numeric(12,2),
  balance_at timestamp with time zone,
  color text,
  active boolean default true,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now(),
  connection_id uuid,
  eb_account_uid text,
  identification_hash text,
  last_sync_at timestamp with time zone,
  constraint bank_accounts_bank_label_uniq UNIQUE (bank, account_label),
  constraint bank_accounts_eb_account_uid_key UNIQUE (eb_account_uid),
  constraint bank_accounts_pkey PRIMARY KEY (id)
);

create table public.bank_auth_requests (
  state text not null,
  aspsp_name text not null,
  created_at timestamp with time zone default now() not null,
  expires_at timestamp with time zone default (now() + '00:15:00'::interval) not null,
  used_at timestamp with time zone,
  constraint bank_auth_requests_pkey PRIMARY KEY (state)
);

create table public.bank_connections (
  id uuid default gen_random_uuid() not null,
  aspsp_name text not null,
  aspsp_country text default 'FR'::text not null,
  session_id text not null,
  valid_until timestamp with time zone not null,
  status text default 'active'::text not null,
  created_at timestamp with time zone default now() not null,
  last_sync_at timestamp with time zone,
  last_sync_status text,
  last_error text,
  last_success_at timestamp with time zone,
  constraint bank_connections_session_id_key UNIQUE (session_id),
  constraint bank_connections_pkey PRIMARY KEY (id),
  constraint bank_connections_status_check CHECK ((status = ANY (ARRAY['active'::text, 'expired'::text, 'revoked'::text, 'error'::text])))
);

create table public.bons_plans (
  id text not null,
  titre text not null,
  lien text not null,
  enseigne text,
  prix text,
  publie_le timestamp with time zone not null,
  type text not null,
  suivie text not null,
  created_at timestamp with time zone default now() not null,
  constraint bons_plans_pkey PRIMARY KEY (id),
  constraint bons_plans_type_check CHECK ((type = ANY (ARRAY['enseigne'::text, 'essai'::text])))
);

create table public.budgets (
  id uuid default gen_random_uuid() not null,
  category text not null,
  monthly_limit numeric(10,2) not null,
  alert_threshold numeric(3,2) default 0.80,
  created_at timestamp with time zone default now(),
  constraint budgets_category_key UNIQUE (category),
  constraint budgets_pkey PRIMARY KEY (id)
);

create table public.catalog_events (
  id uuid default gen_random_uuid() not null,
  nom text not null,
  debut date not null,
  fin date not null,
  source_url text,
  verifie_le date,
  constraint catalog_events_nom_debut_key UNIQUE (nom, debut),
  constraint catalog_events_pkey PRIMARY KEY (id)
);

create table public.catalog_offers (
  id uuid default gen_random_uuid() not null,
  service_id uuid not null,
  nom text not null,
  prix numeric(10,2) not null,
  frequence text default 'mensuel'::text not null,
  go integer,
  essai text,
  conditions text[],
  engagement text,
  source_url text not null,
  verifie_le date not null,
  created_at timestamp with time zone default now() not null,
  prix_promo numeric(10,2),
  promo_duree text,
  inclut text[],
  constraint catalog_offers_service_id_nom_key UNIQUE (service_id, nom),
  constraint catalog_offers_pkey PRIMARY KEY (id),
  constraint catalog_offers_conditions_check CHECK ((conditions <@ ARRAY['etudiant'::text, 'moins_26'::text, 'age_18_24'::text])),
  constraint catalog_offers_frequence_check CHECK ((frequence = ANY (ARRAY['mensuel'::text, 'annuel'::text, 'hebdomadaire'::text, 'quatre_semaines'::text]))),
  constraint catalog_offers_prix_check CHECK ((prix >= (0)::numeric))
);

create table public.catalog_services (
  id uuid default gen_random_uuid() not null,
  nom text not null,
  famille text not null,
  page_url text not null,
  page_montants numeric[],
  page_lue_le timestamp with time zone,
  page_etat text default 'ok'::text not null,
  page_modifiee_le timestamp with time zone,
  created_at timestamp with time zone default now() not null,
  page_montants_avant numeric[],
  constraint catalog_services_nom_key UNIQUE (nom),
  constraint catalog_services_pkey PRIMARY KEY (id),
  constraint catalog_services_famille_check CHECK ((famille = ANY (ARRAY['mobile'::text, 'sport'::text, 'ia'::text, 'amazon'::text]))),
  constraint catalog_services_page_etat_check CHECK ((page_etat = ANY (ARRAY['ok'::text, 'modifiee'::text, 'illisible'::text])))
);

create table public.followed_merchants (
  nom text not null,
  suivie boolean not null,
  created_at timestamp with time zone default now() not null,
  constraint followed_merchants_pkey PRIMARY KEY (nom)
);

create table public.goal_movements (
  id uuid default gen_random_uuid() not null,
  goal_id uuid not null,
  amount numeric not null,
  status text default 'en_attente'::text not null,
  created_at timestamp with time zone default now() not null,
  confirmed_at timestamp with time zone,
  transaction_id uuid,
  note text,
  rejected_transaction_ids uuid[] default '{}'::uuid[] not null,
  constraint goal_movements_pkey PRIMARY KEY (id),
  constraint goal_movements_amount_check CHECK ((amount <> (0)::numeric)),
  constraint goal_movements_status_check CHECK ((status = ANY (ARRAY['en_attente'::text, 'confirme'::text])))
);

create table public.goals (
  id uuid default gen_random_uuid() not null,
  name text not null,
  target_amount numeric not null,
  deadline date,
  created_at timestamp with time zone default timezone('utc'::text, now()),
  status text default 'active'::text not null,
  kind text default 'projet'::text not null,
  icon text,
  constraint goals_pkey PRIMARY KEY (id),
  constraint goals_kind_check CHECK ((kind = ANY (ARRAY['projet'::text, 'imprevus'::text]))),
  constraint goals_status_check CHECK ((status = ANY (ARRAY['active'::text, 'archive'::text])))
);

create table public.merchant_categories (
  cle text not null,
  categorie text not null,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint merchant_categories_pkey PRIMARY KEY (cle)
);

create table public.notifications_envoyees (
  cle text not null,
  type text not null,
  envoyee_at timestamp with time zone default now() not null,
  constraint notifications_envoyees_pkey PRIMARY KEY (cle)
);

create table public.push_tokens (
  id uuid default gen_random_uuid() not null,
  token text not null,
  device_name text,
  platform text,
  enabled boolean default true,
  notify_card boolean default true,
  notify_transfer boolean default true,
  notify_subscription boolean default true,
  notify_threshold numeric(10,2) default 0,
  created_at timestamp with time zone default now(),
  updated_at timestamp with time zone default now(),
  last_used_at timestamp with time zone,
  constraint push_tokens_token_key UNIQUE (token),
  constraint push_tokens_pkey PRIMARY KEY (id)
);

create table public.settings (
  id uuid default gen_random_uuid() not null,
  key text not null,
  value text not null,
  updated_at timestamp with time zone default timezone('utc'::text, now()),
  constraint settings_key_key UNIQUE (key),
  constraint settings_pkey PRIMARY KEY (id)
);

create table public.subscription_candidates (
  id uuid default gen_random_uuid() not null,
  merchant text not null,
  category text,
  amount numeric(10,2),
  frequency_days integer,
  occurrences integer,
  confidence numeric(3,2),
  status text default 'pending'::text,
  rejected_reason text,
  detected_at timestamp with time zone default now(),
  last_seen_at timestamp with time zone default now(),
  notified_at timestamp with time zone,
  merchant_norm text not null,
  last_tx_date date,
  created_at timestamp with time zone default now() not null,
  updated_at timestamp with time zone default now() not null,
  constraint subscription_candidates_merchant_amount_key UNIQUE (merchant, amount),
  constraint subscription_candidates_pkey PRIMARY KEY (id)
);

create table public.subscription_lines (
  id uuid default gen_random_uuid() not null,
  subscription_id uuid not null,
  nom text not null,
  catalog_offer_id uuid,
  prix numeric(10,2),
  go integer,
  created_at timestamp with time zone default now() not null,
  constraint subscription_lines_pkey PRIMARY KEY (id)
);

create table public.subscriptions (
  id uuid default gen_random_uuid() not null,
  name text not null,
  amount numeric(10,2) not null,
  frequency text default 'mois'::text,
  category text default 'Autre'::text,
  created_at timestamp with time zone default now(),
  status text default 'active'::text,
  last_seen_at date,
  next_expected_at date,
  detection_status text default 'unknown'::text,
  trial_end_date date,
  is_trial boolean default false,
  previous_amount numeric(10,2),
  last_price_check_at timestamp with time zone,
  trial_reminded_j3_at timestamp with time zone,
  trial_reminded_j1_at timestamp with time zone,
  merchant_key text,
  usage text,
  libelles text[] default '{}'::text[] not null,
  montant_manuel boolean default false not null,
  mois_pause integer[] default '{}'::integer[] not null,
  montant_reference numeric,
  montant_max numeric(10,2),
  depassement_vu uuid,
  constraint subscriptions_pkey PRIMARY KEY (id),
  constraint subscriptions_montant_max_check CHECK ((montant_max > (0)::numeric)),
  constraint subscriptions_usage_check CHECK (((usage IS NULL) OR (usage = ANY (ARRAY['jamais'::text, 'parfois'::text, 'souvent'::text, 'toujours'::text]))))
);

create table public.transactions (
  id uuid default gen_random_uuid() not null,
  bank_name text not null,
  description text not null,
  amount numeric not null,
  category text default 'Autre'::text,
  date date default CURRENT_DATE,
  is_subscription boolean default false,
  created_at timestamp with time zone default timezone('utc'::text, now()),
  ignored boolean default false,
  ignore_reason text,
  bank_account_id uuid,
  source text default 'manual'::text,
  source_email_id text,
  merchant text,
  balance_after numeric(12,2),
  raw_payload jsonb,
  currency text default 'EUR'::text,
  is_internal boolean default false not null,
  status text default 'booked'::text not null,
  entry_reference text,
  goal_id uuid,
  reserve_annulee boolean default false not null,
  suggestion_ignoree boolean default false not null,
  constraint transactions_pkey PRIMARY KEY (id),
  constraint transactions_status_check CHECK ((status = ANY (ARRAY['booked'::text, 'pending'::text])))
);

alter table public.bank_accounts add constraint bank_accounts_connection_id_fkey FOREIGN KEY (connection_id) REFERENCES bank_connections(id) ON DELETE SET NULL;

alter table public.catalog_offers add constraint catalog_offers_service_id_fkey FOREIGN KEY (service_id) REFERENCES catalog_services(id) ON DELETE CASCADE;

alter table public.goal_movements add constraint goal_movements_goal_id_fkey FOREIGN KEY (goal_id) REFERENCES goals(id) ON DELETE CASCADE;

alter table public.goal_movements add constraint goal_movements_transaction_id_fkey FOREIGN KEY (transaction_id) REFERENCES transactions(id) ON DELETE SET NULL;

alter table public.subscription_lines add constraint subscription_lines_catalog_offer_id_fkey FOREIGN KEY (catalog_offer_id) REFERENCES catalog_offers(id) ON DELETE SET NULL;

alter table public.subscription_lines add constraint subscription_lines_subscription_id_fkey FOREIGN KEY (subscription_id) REFERENCES subscriptions(id) ON DELETE CASCADE;

alter table public.subscriptions add constraint subscriptions_depassement_vu_fkey FOREIGN KEY (depassement_vu) REFERENCES transactions(id) ON DELETE SET NULL;

alter table public.transactions add constraint transactions_bank_account_id_fkey FOREIGN KEY (bank_account_id) REFERENCES bank_accounts(id) ON DELETE SET NULL;

alter table public.transactions add constraint transactions_goal_id_fkey FOREIGN KEY (goal_id) REFERENCES goals(id) ON DELETE SET NULL;

CREATE INDEX bank_accounts_active_idx ON public.bank_accounts USING btree (active);

CREATE INDEX bons_plans_publie_le ON public.bons_plans USING btree (publie_le DESC);

CREATE UNIQUE INDEX goal_movements_transaction_unique ON public.goal_movements USING btree (transaction_id) WHERE (transaction_id IS NOT NULL);

CREATE INDEX push_tokens_enabled_idx ON public.push_tokens USING btree (enabled) WHERE (enabled = true);

CREATE UNIQUE INDEX push_tokens_token_unique ON public.push_tokens USING btree (token);

CREATE UNIQUE INDEX subscription_candidates_unique ON public.subscription_candidates USING btree (merchant_norm, round(amount));

CREATE INDEX transactions_bank_account_idx ON public.transactions USING btree (bank_account_id);

CREATE UNIQUE INDEX transactions_compte_reference_unique ON public.transactions USING btree (bank_account_id, entry_reference) WHERE (entry_reference IS NOT NULL);

CREATE INDEX transactions_date_idx ON public.transactions USING btree (date DESC);

CREATE UNIQUE INDEX transactions_source_email_id_uidx ON public.transactions USING btree (source_email_id) WHERE (source_email_id IS NOT NULL);

CREATE INDEX transactions_source_idx ON public.transactions USING btree (source);

CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$

begin

  new.updated_at = now();

  return new;

end;

$function$
;

CREATE OR REPLACE FUNCTION public.tg_set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
AS $function$

begin

  new.updated_at = now();

  return new;

end;

$function$
;

CREATE TRIGGER bank_accounts_updated_at BEFORE UPDATE ON public.bank_accounts FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER push_tokens_updated_at BEFORE UPDATE ON public.push_tokens FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER subscription_candidates_set_updated_at BEFORE UPDATE ON public.subscription_candidates FOR EACH ROW EXECUTE FUNCTION tg_set_updated_at();

create view public.v_transactions_enriched with (security_invoker = true) as
 SELECT t.id,
    t.description,
    t.merchant,
    t.amount,
    t.currency,
    t.category,
    t.date,
    t.source,
    t.balance_after,
    t.ignored,
    t.ignore_reason,
    t.created_at,
    ba.id AS account_id,
    ba.bank AS account_bank,
    ba.account_label,
    ba.color AS account_color,
    ba.card_last4
   FROM transactions t
     LEFT JOIN bank_accounts ba ON ba.id = t.bank_account_id
  WHERE t.ignored = false
  ORDER BY t.date DESC, t.created_at DESC;

alter table public.bank_accounts enable row level security;

alter table public.bank_auth_requests enable row level security;

alter table public.bank_connections enable row level security;

alter table public.bons_plans enable row level security;

alter table public.budgets enable row level security;

alter table public.catalog_events enable row level security;

alter table public.catalog_offers enable row level security;

alter table public.catalog_services enable row level security;

alter table public.followed_merchants enable row level security;

alter table public.goal_movements enable row level security;

alter table public.goals enable row level security;

alter table public.merchant_categories enable row level security;

alter table public.notifications_envoyees enable row level security;

alter table public.push_tokens enable row level security;

alter table public.settings enable row level security;

alter table public.subscription_candidates enable row level security;

alter table public.subscription_lines enable row level security;

alter table public.subscriptions enable row level security;

alter table public.transactions enable row level security;

create policy proprietaire_seulement on public.bank_accounts as PERMISSIVE for ALL to authenticated using (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text))) with check (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text)));

create policy proprietaire_lecture on public.bank_connections as PERMISSIVE for SELECT to authenticated using (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text)));

create policy proprietaire_seulement on public.bons_plans as PERMISSIVE for ALL to authenticated using (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text))) with check (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text)));

create policy proprietaire_seulement on public.budgets as PERMISSIVE for ALL to authenticated using (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text))) with check (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text)));

create policy proprietaire_seulement on public.catalog_events as PERMISSIVE for ALL to authenticated using (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text))) with check (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text)));

create policy proprietaire_seulement on public.catalog_offers as PERMISSIVE for ALL to authenticated using (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text))) with check (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text)));

create policy proprietaire_seulement on public.catalog_services as PERMISSIVE for ALL to authenticated using (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text))) with check (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text)));

create policy proprietaire_seulement on public.followed_merchants as PERMISSIVE for ALL to authenticated using (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text))) with check (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text)));

create policy proprietaire_seulement on public.goal_movements as PERMISSIVE for ALL to authenticated using (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text))) with check (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text)));

create policy proprietaire_seulement on public.goals as PERMISSIVE for ALL to authenticated using (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text))) with check (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text)));

create policy proprietaire_seulement on public.merchant_categories as PERMISSIVE for ALL to authenticated using (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text))) with check (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text)));

create policy proprietaire_seulement on public.notifications_envoyees as PERMISSIVE for ALL to authenticated using (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text))) with check (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text)));

create policy proprietaire_seulement on public.push_tokens as PERMISSIVE for ALL to authenticated using (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text))) with check (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text)));

create policy proprietaire_seulement on public.settings as PERMISSIVE for ALL to authenticated using (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text))) with check (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text)));

create policy proprietaire_seulement on public.subscription_candidates as PERMISSIVE for ALL to authenticated using (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text))) with check (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text)));

create policy proprietaire_seulement on public.subscription_lines as PERMISSIVE for ALL to authenticated using (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text))) with check (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text)));

create policy proprietaire_seulement on public.subscriptions as PERMISSIVE for ALL to authenticated using (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text))) with check (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text)));

create policy proprietaire_seulement on public.transactions as PERMISSIVE for ALL to authenticated using (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text))) with check (((( SELECT auth.uid() AS uid) = '00000000-0000-0000-0000-000000000000'::uuid) AND (( SELECT (auth.jwt() ->> 'aal'::text)) = 'aal2'::text)));

-- La clé publique (anon) ne lit, n'écrit et n'appelle rien ; les fonctions sont réservées au backend.
revoke all on all tables    in schema public from anon;
revoke all on all sequences in schema public from anon;
revoke execute on all functions in schema public from anon, authenticated, public;
grant  execute on all functions in schema public to service_role;
alter default privileges for role postgres in schema public revoke all on tables    from anon;
alter default privileges for role postgres in schema public revoke all on sequences from anon;
alter default privileges for role postgres in schema public revoke execute on functions from anon, authenticated, public;

-- Tables réservées au backend, ou en lecture seule pour la session.
revoke all on public.bank_auth_requests from authenticated;
revoke insert, update, delete on public.bank_connections from authenticated;
