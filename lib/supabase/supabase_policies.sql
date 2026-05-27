-- Enable RLS
alter table if exists public.users enable row level security;
alter table if exists public.profiles enable row level security;
alter table if exists public.product_categories enable row level security;
alter table if exists public.products enable row level security;
alter table if exists public.wishlists enable row level security;
alter table if exists public.wallet_subscriptions enable row level security;
alter table if exists public.notifications enable row level security;

-- USERS table: allow inserts/updates with minimal checks so app can upsert on signup
drop policy if exists users_insert_any on public.users;
create policy users_insert_any on public.users for insert with check (true);

drop policy if exists users_update_any on public.users;
create policy users_update_any on public.users for update using (true) with check (true);

drop policy if exists users_select_authenticated on public.users;
create policy users_select_authenticated on public.users for select to authenticated using (true);

-- PROFILES: owners full access, authenticated can select
drop policy if exists profiles_owner_all on public.profiles;
create policy profiles_owner_all on public.profiles for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

drop policy if exists profiles_select_all_auth on public.profiles;
create policy profiles_select_all_auth on public.profiles for select to authenticated using (true);

-- PRODUCT CATEGORIES: authenticated read, restrict writes
drop policy if exists product_categories_select_auth on public.product_categories;
create policy product_categories_select_auth on public.product_categories for select to authenticated using (true);

-- PRODUCTS: authenticated read, restrict writes
drop policy if exists products_select_auth on public.products;
create policy products_select_auth on public.products for select to authenticated using (true);

-- WISHLISTS: owners only
drop policy if exists wishlists_owner_all on public.wishlists;
create policy wishlists_owner_all on public.wishlists for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- WALLET SUBSCRIPTIONS: owners only
drop policy if exists wallet_subscriptions_owner_all on public.wallet_subscriptions;
create policy wallet_subscriptions_owner_all on public.wallet_subscriptions for all to authenticated using (user_id = auth.uid()) with check (user_id = auth.uid());

-- NOTIFICATIONS: owners read, service writes (client won't write)
drop policy if exists notifications_owner_read on public.notifications;
create policy notifications_owner_read on public.notifications for select to authenticated using (user_id = auth.uid());
