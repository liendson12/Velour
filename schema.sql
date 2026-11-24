-- Supabase: cola no SQL Editor e executa.

create table profiles (
  id uuid primary key references auth.users on delete cascade,
  role text not null default 'viewer' check (role in ('viewer','model','admin')),
  display_name text,
  created_at timestamptz default now()
);

create table models (
  id uuid primary key references profiles(id) on delete cascade,
  slug text unique not null,
  stage_name text not null,
  country text,
  birth_date date not null,
  bio text,
  price_per_minute int not null default 30,          -- em créditos
  status text not null default 'pending'             -- pending | approved | rejected
    check (status in ('pending','approved','rejected')),
  kyc_status text not null default 'not_started'     -- ligar a Veriff/Sumsub
    check (kyc_status in ('not_started','in_review','verified','failed')),
  referred_by uuid references models(id),
  is_live boolean not null default false,
  created_at timestamptz default now(),
  constraint adult_only check (birth_date <= (current_date - interval '18 years'))
);

create table videos (
  id uuid primary key default gen_random_uuid(),
  model_id uuid not null references models(id) on delete cascade,
  title text not null,
  hls_url text,
  thumbnail_url text,
  is_published boolean not null default false,
  created_at timestamptz default now()
);

create table wallets (
  user_id uuid primary key references profiles(id) on delete cascade,
  credits int not null default 0 check (credits >= 0)
);

create table private_sessions (
  id uuid primary key default gen_random_uuid(),
  model_id uuid not null references models(id),
  viewer_id uuid not null references profiles(id),
  started_at timestamptz default now(),
  ended_at timestamptz,
  credits_charged int not null default 0
);

alter table profiles enable row level security;
alter table models enable row level security;
alter table videos enable row level security;
alter table wallets enable row level security;
alter table private_sessions enable row level security;

-- Visitantes (sem login) só vêem modelos aprovadas e vídeos publicados
create policy "public sees approved models" on models for select
  using (status = 'approved' and kyc_status = 'verified');
create policy "public sees published videos" on videos for select
  using (is_published and exists (select 1 from models m where m.id = model_id and m.status = 'approved'));

-- Modelo gere o próprio perfil e vídeos
create policy "model reads self" on models for select using (auth.uid() = id);
create policy "model updates self" on models for update using (auth.uid() = id);
create policy "model inserts self" on models for insert with check (auth.uid() = id);
create policy "model manages videos" on videos for all using (auth.uid() = model_id);

-- Utilizador vê só o seu perfil e carteira
create policy "own profile" on profiles for select using (auth.uid() = id);
create policy "own wallet" on wallets for select using (auth.uid() = user_id);
create policy "own sessions" on private_sessions for select
  using (auth.uid() = viewer_id or auth.uid() = model_id);
-- Créditos e sessões só se alteram por funções no servidor (service role), nunca pelo cliente.
