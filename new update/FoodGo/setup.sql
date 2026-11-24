-- FoodGo SETUP (ek-i file, jotobar khushi run korle kono khoti nei)
-- Supabase > SQL Editor > New query > shob paste kore RUN. Ar kono SQL file lagbe na.

create table if not exists public.profiles(
  id uuid primary key references auth.users on delete cascade,
  email text, full_name text, phone text, address text,
  role text not null default 'customer' check (role in ('customer','admin','rider')),
  created_at timestamptz default now());
create table if not exists public.restaurants(
  id uuid primary key default gen_random_uuid(),
  name text not null, cuisine text, emoji text default '🍽️',
  is_active boolean default true, created_at timestamptz default now());
create table if not exists public.products(
  id uuid primary key default gen_random_uuid(),
  restaurant_id uuid not null references public.restaurants on delete cascade,
  name text not null, description text,
  price numeric(10,2) not null check (price>=0),
  emoji text default '🍔', is_available boolean default true,
  created_at timestamptz default now());
create table if not exists public.orders(
  id uuid primary key default gen_random_uuid(),
  customer_id uuid not null references public.profiles,
  restaurant_id uuid references public.restaurants,
  customer_name text, phone text, address text, note text,
  total numeric(10,2) not null default 0,
  status text not null default 'placed' check (status in ('placed','accepted','picked_up','delivered','cancelled')),
  rider_id uuid references public.profiles, rider_name text,
  created_at timestamptz default now());
create table if not exists public.order_items(
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders on delete cascade,
  product_id uuid references public.products on delete set null,
  name text, price numeric(10,2), qty int check (qty>0));

-- helper
create or replace function public.my_role() returns text language sql stable security definer set search_path=public as
$$ select role from public.profiles where id=auth.uid() $$;

-- new signup => customer profile
create or replace function public.handle_new_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  -- Shudhu ei email ta signup korle ADMIN hobe, baki shob customer.
  -- Onno admin chaile niche list e email add koro: lower(new.email) in ('a@x.com','b@x.com')
  insert into public.profiles(id,email,full_name,role) values(new.id,new.email,new.raw_user_meta_data->>'full_name',
    case when lower(new.email) in ('nuren@gmail.com') then 'admin' else 'customer' end) on conflict (id) do nothing;
  return new;
end $$;
drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users for each row execute function public.handle_new_user();

-- place order (price server-e calculate hoy)
create or replace function public.place_order(p_items jsonb,p_address text,p_phone text,p_note text) returns uuid
language plpgsql security definer set search_path=public as $$
declare oid uuid; rid uuid; pr public.profiles; n int; v int;
begin
  if auth.uid() is null then raise exception 'login required'; end if;
  if p_items is null or jsonb_typeof(p_items)<>'array' or jsonb_array_length(p_items)=0 then raise exception 'cart empty'; end if;
  if coalesce(trim(p_address),'')='' or coalesce(trim(p_phone),'')='' then raise exception 'address and phone required'; end if;
  select * into pr from public.profiles where id=auth.uid();
  -- shob item available, active restaurant er, ar ek-i restaurant er hote hobe
  select count(distinct p.restaurant_id), min(p.restaurant_id::text)::uuid, count(*) into n, rid, v
    from jsonb_array_elements(p_items) i
    join public.products p on p.id=(i->>'id')::uuid and p.is_available
    join public.restaurants r on r.id=p.restaurant_id and r.is_active;
  if n<>1 or v<>jsonb_array_length(p_items) then raise exception 'invalid items (ek restaurant er available item lagbe)'; end if;
  insert into public.orders(customer_id,restaurant_id,customer_name,phone,address,note)
    values(auth.uid(),rid,coalesce(pr.full_name,pr.email),trim(p_phone),trim(p_address),p_note) returning id into oid;
  insert into public.order_items(order_id,product_id,name,price,qty)
    select oid,p.id,p.name,p.price,least(greatest((i->>'qty')::int,1),50)
    from jsonb_array_elements(p_items) i join public.products p on p.id=(i->>'id')::uuid;
  update public.orders set total=(select coalesce(sum(price*qty),0) from public.order_items where order_id=oid) where id=oid;
  return oid;
end $$;

-- admin dashboard numbers
create or replace function public.admin_stats() returns json language plpgsql security definer set search_path=public as $$
begin
  if public.my_role()<>'admin' then raise exception 'admin only'; end if;
  return json_build_object(
    'total_sales',(select coalesce(sum(total),0) from orders where status='delivered'),
    'today_sales',(select coalesce(sum(total),0) from orders where status='delivered' and created_at>=date_trunc('day',now())),
    'orders',(select count(*) from orders),
    'pending',(select count(*) from orders where status in ('placed','accepted','picked_up')),
    'customers',(select count(*) from profiles where role='customer'),
    'riders',(select count(*) from profiles where role='rider'));
end $$;

-- RLS
alter table public.profiles enable row level security;
alter table public.restaurants enable row level security;
alter table public.products enable row level security;
alter table public.orders enable row level security;
alter table public.order_items enable row level security;

drop policy if exists p_sel on public.profiles;
create policy p_sel on public.profiles for select using (id=auth.uid() or public.my_role()='admin');
drop policy if exists p_upd on public.profiles;
create policy p_upd on public.profiles for update using (id=auth.uid()) with check (id=auth.uid() and role=public.my_role());
drop policy if exists p_adm on public.profiles;
create policy p_adm on public.profiles for update using (public.my_role()='admin');

drop policy if exists r_sel on public.restaurants;
create policy r_sel on public.restaurants for select to authenticated using (is_active or public.my_role()='admin');
drop policy if exists r_adm on public.restaurants;
create policy r_adm on public.restaurants for all using (public.my_role()='admin') with check (public.my_role()='admin');
drop policy if exists g_sel on public.products;
create policy g_sel on public.products for select to authenticated using (is_available or public.my_role()='admin');
drop policy if exists g_adm on public.products;
create policy g_adm on public.products for all using (public.my_role()='admin') with check (public.my_role()='admin');

drop policy if exists o_sel on public.orders;
create policy o_sel on public.orders for select using (
  customer_id=auth.uid() or public.my_role()='admin'
  or (public.my_role()='rider' and (rider_id=auth.uid() or (rider_id is null and status='placed'))));
drop policy if exists o_adm on public.orders;
create policy o_adm on public.orders for update using (public.my_role()='admin');
drop policy if exists o_cus on public.orders;
create policy o_cus on public.orders for update using (customer_id=auth.uid() and status='placed') with check (status='cancelled');
drop policy if exists o_rid on public.orders;
create policy o_rid on public.orders for update
  using (public.my_role()='rider' and (rider_id is null or rider_id=auth.uid())) with check (rider_id=auth.uid());
drop policy if exists i_sel on public.order_items;
create policy i_sel on public.order_items for select using (exists(select 1 from public.orders o where o.id=order_id));

-- order update er niyom (RLS column dekhte pare na, tai trigger): customer shudhu cancel,
-- rider shudhu status age barate pare, total/address/phone keu (admin chhara) bodlate parbe na.
create or replace function public.guard_order_update() returns trigger language plpgsql security definer set search_path=public as $$
declare r text := public.my_role();
begin
  if auth.uid() is null or r='admin' then return new; end if;
  if new.total is distinct from old.total or new.customer_id is distinct from old.customer_id
     or new.restaurant_id is distinct from old.restaurant_id or new.customer_name is distinct from old.customer_name
     or new.phone is distinct from old.phone or new.address is distinct from old.address
     or new.note is distinct from old.note or new.created_at is distinct from old.created_at then
    raise exception 'not allowed';
  end if;
  if r='customer' then
    if old.status<>'placed' or new.status<>'cancelled'
       or new.rider_id is distinct from old.rider_id or new.rider_name is distinct from old.rider_name then
      raise exception 'not allowed'; end if;
  elsif r='rider' then
    if old.rider_id is null then
      if old.status<>'placed' or new.status<>'accepted' or new.rider_id is distinct from auth.uid() then
        raise exception 'not allowed'; end if;
    else
      if old.rider_id is distinct from auth.uid() or new.rider_id is distinct from old.rider_id
         or new.rider_name is distinct from old.rider_name
         or not ((old.status='accepted' and new.status='picked_up') or (old.status='picked_up' and new.status='delivered')) then
        raise exception 'not allowed'; end if;
    end if;
  else
    raise exception 'not allowed';
  end if;
  return new;
end $$;
drop trigger if exists orders_guard on public.orders;
create trigger orders_guard before update on public.orders for each row execute function public.guard_order_update();

-- login chhara keu RPC chalate parbe na
revoke execute on function public.place_order(jsonb,text,text,text) from public, anon;
revoke execute on function public.admin_stats() from public, anon;
grant execute on function public.place_order(jsonb,text,text,text) to authenticated;
grant execute on function public.admin_stats() to authenticated;

-- email confirm lagbe na: notun user ke auto-confirm kora hoy (Supabase e "Confirm email" off korar jhamela nei)
create or replace function public.auto_confirm_user() returns trigger language plpgsql security definer set search_path=public as $$
begin
  new.email_confirmed_at := coalesce(new.email_confirmed_at, now());
  return new;
end $$;
drop trigger if exists auto_confirm_before_insert on auth.users;
create trigger auto_confirm_before_insert before insert on auth.users for each row execute function public.auto_confirm_user();
update auth.users set email_confirmed_at=now() where email_confirmed_at is null;

-- DEMO DATA: restaurant + khabar (jotobar run koro, duplicate hobe na; jeta nai shudhu seta add hobe)
insert into public.restaurants(name,cuisine,emoji)
select v.n,v.c,v.e from (values
 ('Kacchi Ghar','Biryani & Kacchi','🍛'),
 ('Burger Barn','Burgers & Fries','🍔'),
 ('Dhaka Pizza Co.','Pizza & Pasta','🍕'),
 ('Bhaat Ghor','Bengali Home Meals','🍚'),
 ('Dragon Wok','Chinese & Thai','🥡'),
 ('Chai & Snacks Corner','Tea, Fuchka & Snacks','☕'),
 ('Sweet Tooth','Desserts & Sweets','🍰'),
 ('Healthy Bowl','Salads & Wraps','🥗')
) v(n,c,e) where not exists(select 1 from public.restaurants r where r.name=v.n);

insert into public.products(restaurant_id,name,description,price,emoji)
select r.id,v.n,v.d,v.p,v.e from public.restaurants r join (values
 ('Kacchi Ghar','Mutton Kacchi','Full plate with borhani',420,'🍛'),
 ('Kacchi Ghar','Chicken Roast','Polao er sathe',180,'🍗'),
 ('Kacchi Ghar','Chicken Biryani','Half plate, egg shoho',250,'🍚'),
 ('Kacchi Ghar','Beef Tehari','Spicy, salad shoho',220,'🍲'),
 ('Kacchi Ghar','Borhani','Ek glass',50,'🥛'),
 ('Burger Barn','Classic Beef Burger','Cheese, lettuce, sauce',320,'🍔'),
 ('Burger Barn','Crispy Chicken Burger','Spicy mayo',280,'🍔'),
 ('Burger Barn','French Fries','Large',120,'🍟'),
 ('Burger Barn','Chicken Nuggets','8 pieces',200,'🍗'),
 ('Burger Barn','Chocolate Shake','Thick and cold',180,'🥤'),
 ('Dhaka Pizza Co.','Margherita Pizza','10 inch',550,'🍕'),
 ('Dhaka Pizza Co.','BBQ Chicken Pizza','10 inch',650,'🍕'),
 ('Dhaka Pizza Co.','Creamy Pasta','Chicken alfredo',390,'🍝'),
 ('Dhaka Pizza Co.','Garlic Bread','4 pieces',150,'🥖'),
 ('Bhaat Ghor','Bhaat + Dal + Alu Bhorta','Shorshe ilish er alada',160,'🍚'),
 ('Bhaat Ghor','Shorshe Ilish','2 piece, bhaat shoho',450,'🐟'),
 ('Bhaat Ghor','Beef Bhuna','Khichuri er sathe',300,'🥘'),
 ('Bhaat Ghor','Khichuri + Egg','Borar din er special',180,'🍲'),
 ('Bhaat Ghor','Mixed Vegetables','Seasonal sobji',90,'🥬'),
 ('Dragon Wok','Chicken Fried Rice','Egg shoho',240,'🍚'),
 ('Dragon Wok','Chicken Chowmein','Veg mix',220,'🍜'),
 ('Dragon Wok','Chilli Chicken','Dry, spicy',320,'🌶️'),
 ('Dragon Wok','Thai Soup','Chicken, large bowl',200,'🍲'),
 ('Dragon Wok','Spring Rolls','4 pieces',160,'🥟'),
 ('Chai & Snacks Corner','Doodh Cha','Ek cup',30,'☕'),
 ('Chai & Snacks Corner','Fuchka','10 pieces',80,'🥟'),
 ('Chai & Snacks Corner','Chotpoti','Egg shoho',70,'🥣'),
 ('Chai & Snacks Corner','Samosa','4 pieces',60,'🥟'),
 ('Chai & Snacks Corner','Jhalmuri','Mosholadar',40,'🥜'),
 ('Sweet Tooth','Rasmalai','4 pieces',200,'🍮'),
 ('Sweet Tooth','Chocolate Cake','1 slice',150,'🍰'),
 ('Sweet Tooth','Mishti Doi','Ek bati',80,'🍨'),
 ('Sweet Tooth','Ice Cream Sundae','Vanilla, chocolate sauce',180,'🍨'),
 ('Healthy Bowl','Chicken Caesar Salad','Grilled chicken',290,'🥗'),
 ('Healthy Bowl','Veggie Wrap','Hummus, fresh veg',210,'🌯'),
 ('Healthy Bowl','Fruit Bowl','Seasonal fruits',150,'🍓'),
 ('Healthy Bowl','Fresh Orange Juice','Chini chhara',100,'🍊')
) as v(rn,n,d,p,e) on v.rn=r.name
where not exists(select 1 from public.products x where x.restaurant_id=r.id and x.name=v.n);

-- ADMIN ACCOUNT shorasori toiri (kono email pathano lage na, "email rate limit" er jhamela nei)
-- Email: nuren@gmail.com   Password: Nuren@123   (password bodlate chaile niche pw er value bodlao, RUN korar age)
-- Account age theke thakle eta kichu bodlay na (password bodlate reset-admin-password.sql chalao).
do $$
declare uid uuid; pw text := 'Nuren@123';
begin
  select id into uid from auth.users where lower(email)='nuren@gmail.com';
  if uid is null then
    uid := gen_random_uuid();
    insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,
      created_at,updated_at,confirmation_token,recovery_token,email_change_token_new,email_change)
    values('00000000-0000-0000-0000-000000000000',uid,'authenticated','authenticated','nuren@gmail.com',
      extensions.crypt(pw,extensions.gen_salt('bf')),now(),'{"provider":"email","providers":["email"]}','{"full_name":"Admin"}',
      now(),now(),'','','','');
    insert into auth.identities(id,user_id,provider_id,provider,identity_data,created_at,updated_at,last_sign_in_at)
    values(gen_random_uuid(),uid,uid::text,'email',jsonb_build_object('sub',uid::text,'email','nuren@gmail.com','email_verified',true),now(),now(),now());
  end if;
end $$;

-- DEMO ACCOUNT (customer + rider)
--   Customer: customer@foodgo.com / Customer@123
--   Rider   : rider@foodgo.com    / Rider@123
do $$
declare uid uuid; d record;
begin
  for d in select * from (values
    ('customer@foodgo.com','Customer@123','Demo Customer'),
    ('rider@foodgo.com','Rider@123','Demo Rider')) t(em,pw,nm)
  loop
    select id into uid from auth.users where lower(email)=d.em;
    if uid is null then
      uid := gen_random_uuid();
      insert into auth.users(instance_id,id,aud,role,email,encrypted_password,email_confirmed_at,raw_app_meta_data,raw_user_meta_data,
        created_at,updated_at,confirmation_token,recovery_token,email_change_token_new,email_change)
      values('00000000-0000-0000-0000-000000000000',uid,'authenticated','authenticated',d.em,
        extensions.crypt(d.pw,extensions.gen_salt('bf')),now(),'{"provider":"email","providers":["email"]}',
        jsonb_build_object('full_name',d.nm),now(),now(),'','','','');
      insert into auth.identities(id,user_id,provider_id,provider,identity_data,created_at,updated_at,last_sign_in_at)
      values(gen_random_uuid(),uid,uid::text,'email',jsonb_build_object('sub',uid::text,'email',d.em,'email_verified',true),now(),now(),now());
    end if;
  end loop;
end $$;

-- age theke signup kora jara chilo tader profile banao (trigger age thakle jeta miss hoyechilo)
insert into public.profiles(id,email,full_name,role)
select u.id,u.email,u.raw_user_meta_data->>'full_name',case when lower(u.email) in ('nuren@gmail.com') then 'admin' else 'customer' end
from auth.users u on conflict (id) do nothing;

-- admin email gulo ke admin koro
update public.profiles set role='admin' where lower(email) in ('nuren@gmail.com');


-- profile na thakle nije toiri kore (app login er por automatic call kore)
create or replace function public.ensure_profile() returns void language plpgsql security definer set search_path=public as $$
begin
  if auth.uid() is null then return; end if;
  insert into public.profiles(id,email,full_name,role)
  select u.id,u.email,u.raw_user_meta_data->>'full_name',case when lower(u.email) in ('nuren@gmail.com') then 'admin' else 'customer' end
  from auth.users u where u.id=auth.uid() on conflict (id) do nothing;
end $$;
revoke execute on function public.ensure_profile() from public, anon;
grant execute on function public.ensure_profile() to authenticated;

-- Data API permission (notun Supabase project e table auto-expose hoy na, tai explicit grant)
grant usage on schema public to anon, authenticated;
grant select, insert, update, delete on all tables in schema public to authenticated;

-- demo rider ke rider role dao
update public.profiles set role='rider', full_name='Demo Rider' where lower(email)='rider@foodgo.com';
update public.profiles set full_name='Demo Customer' where lower(email)='customer@foodgo.com' and full_name is null;
