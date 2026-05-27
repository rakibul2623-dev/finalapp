-- Initial Supabase schema for Hajj Wallet
-- Note: Uses IF NOT EXISTS to stay safe if objects already exist in your project

-- Enable required extensions
create extension if not exists pgcrypto;

-- Public users table mirroring auth.users with extra fields
create table if not exists public.users (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null unique references auth.users(id) on delete cascade,
  email text unique,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

-- Profiles table (app-level profile data)
create table if not exists public.profiles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  full_name text,
  avatar_url text,
  points integer not null default 0,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

-- Store: categories
create table if not exists public.product_categories (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  sort_order integer not null default 0,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

-- Store: products
create table if not exists public.products (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  category text,
  price numeric(12,2) not null default 0,
  stock integer not null default -1, -- -1 means unlimited
  rating numeric(3,2) not null default 0,
  is_limited boolean not null default false,
  image_url text,
  created_at timestamp with time zone not null default now(),
  updated_at timestamp with time zone not null default now()
);

-- Store: wishlists
create table if not exists public.wishlists (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  product_id uuid not null references public.products(id) on delete cascade,
  created_at timestamp with time zone not null default now(),
  unique(user_id, product_id)
);

-- Subscriptions (minimal for app use)
create table if not exists public.wallet_subscriptions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'inactive',
  plan text,
  started_at timestamp with time zone default now(),
  ends_at timestamp with time zone
);

-- Simple notifications placeholder
create table if not exists public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  title text not null,
  body text,
  read_at timestamp with time zone,
  created_at timestamp with time zone not null default now()
);

-- Indexes
create index if not exists idx_profiles_user_id on public.profiles(user_id);
create index if not exists idx_products_category on public.products(category);
create index if not exists idx_wishlists_user_id on public.wishlists(user_id);
create index if not exists idx_wallet_subscriptions_user_id on public.wallet_subscriptions(user_id);
create index if not exists idx_notifications_user_id on public.notifications(user_id);
