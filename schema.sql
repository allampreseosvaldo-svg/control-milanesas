-- ============================================================
-- Control de Milanesas — Esquema de base de datos (Supabase / Postgres)
-- ============================================================
-- Modelo COMPARTIDO por equipo: todos los usuarios autenticados ven y
-- cargan sobre los MISMOS datos. Cada registro guarda quién lo cargó
-- (creado_por) y cuándo (created_at).
--
-- Correr TODO este archivo en Supabase → SQL Editor, de arriba a abajo.
-- Es idempotente: se puede correr en una base nueva o sobre una existente
-- para migrarla (agrega lo que falte sin borrar datos).
-- ============================================================

create extension if not exists pgcrypto;

-- ────────────────────────────────────────────────────────────
-- 0) Personas (perfiles) — una fila por usuario, con su nombre
-- ────────────────────────────────────────────────────────────
create table if not exists profiles (
  id         uuid primary key references auth.users(id) on delete cascade,
  nombre     text,
  email      text,
  created_at timestamptz not null default now()
);

-- Cuando se crea un usuario en Auth, se crea su perfil automáticamente.
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email)
  values (new.id, new.email)
  on conflict (id) do nothing;
  return new;
end; $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ────────────────────────────────────────────────────────────
-- 1) Tablas maestras y de movimientos
-- ────────────────────────────────────────────────────────────
create table if not exists carnes (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  receta     jsonb not null default '[]'::jsonb,   -- [[producto_id, cantidad], ...]
  created_at timestamptz not null default now(),
  creado_por uuid default auth.uid() references auth.users(id) on delete set null
);

create table if not exists tamanos (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  created_at timestamptz not null default now(),
  creado_por uuid default auth.uid() references auth.users(id) on delete set null
);

create table if not exists locales (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  created_at timestamptz not null default now(),
  creado_por uuid default auth.uid() references auth.users(id) on delete set null
);

create table if not exists productos (
  id         uuid primary key default gen_random_uuid(),
  name       text not null,
  unit       text not null default 'u',
  created_at timestamptz not null default now(),
  creado_por uuid default auth.uid() references auth.users(id) on delete set null
);

create table if not exists producciones (
  id         uuid primary key default gen_random_uuid(),
  fecha      date not null default current_date,
  carne_id   uuid references carnes(id) on delete set null,
  tam_id     uuid references tamanos(id) on delete set null,
  kg         numeric(12,2) not null default 0,
  mila       integer not null default 0,
  items      jsonb not null default '[]'::jsonb,    -- [[producto_id, cantidad], ...]
  created_at timestamptz not null default now(),
  creado_por uuid default auth.uid() references auth.users(id) on delete set null
);

create table if not exists salidas (
  id         uuid primary key default gen_random_uuid(),
  fecha      date not null default current_date,
  local_id   uuid references locales(id) on delete set null,
  carne_id   uuid references carnes(id) on delete set null,
  mila       integer not null default 0,
  nota       text,
  created_at timestamptz not null default now(),
  creado_por uuid default auth.uid() references auth.users(id) on delete set null
);

-- ────────────────────────────────────────────────────────────
-- 2) Migración suave: agregar columnas si la base ya existía
--    (si venías de un esquema por-usuario con user_id, esto suma
--     lo que falta sin borrar nada)
-- ────────────────────────────────────────────────────────────
alter table carnes       add column if not exists created_at timestamptz not null default now();
alter table carnes       add column if not exists creado_por uuid default auth.uid();
alter table tamanos      add column if not exists created_at timestamptz not null default now();
alter table tamanos      add column if not exists creado_por uuid default auth.uid();
alter table locales      add column if not exists created_at timestamptz not null default now();
alter table locales      add column if not exists creado_por uuid default auth.uid();
alter table productos    add column if not exists created_at timestamptz not null default now();
alter table productos    add column if not exists creado_por uuid default auth.uid();
alter table producciones add column if not exists created_at timestamptz not null default now();
alter table producciones add column if not exists creado_por uuid default auth.uid();
alter table salidas      add column if not exists created_at timestamptz not null default now();
alter table salidas      add column if not exists creado_por uuid default auth.uid();

-- ────────────────────────────────────────────────────────────
-- 3) Seguridad (RLS) — MODELO COMPARTIDO
--    Todos los usuarios autenticados ven y editan todo.
--    La anon key es pública por diseño; RLS es lo que protege:
--    sin sesión iniciada, nadie ve ni escribe nada.
-- ────────────────────────────────────────────────────────────
do $$
declare t text;
begin
  foreach t in array array['carnes','tamanos','locales','productos','producciones','salidas'] loop
    execute format('alter table %I enable row level security;', t);
    -- borra políticas viejas conocidas (por-usuario) si existieran
    execute format('drop policy if exists %I on %I;', t||'_select', t);
    execute format('drop policy if exists %I on %I;', t||'_insert', t);
    execute format('drop policy if exists %I on %I;', t||'_update', t);
    execute format('drop policy if exists %I on %I;', t||'_delete', t);
    execute format('drop policy if exists %I on %I;', t||'_all', t);
    -- política compartida: cualquier usuario autenticado, acceso total
    execute format(
      'create policy %I on %I for all to authenticated using (true) with check (true);',
      t||'_all', t);
  end loop;
end $$;

-- profiles: todos los autenticados pueden VER a todos (para mostrar nombres);
-- cada uno solo puede crear/editar SU propia ficha.
alter table profiles enable row level security;
drop policy if exists "profiles_select" on profiles;
drop policy if exists "profiles_upsert" on profiles;
drop policy if exists "profiles_update" on profiles;
create policy "profiles_select" on profiles for select to authenticated using (true);
create policy "profiles_upsert" on profiles for insert to authenticated with check (id = auth.uid());
create policy "profiles_update" on profiles for update to authenticated using (id = auth.uid()) with check (id = auth.uid());

-- Cargar perfiles de usuarios que ya existían antes del trigger:
insert into public.profiles (id, email)
select u.id, u.email from auth.users u
on conflict (id) do nothing;

-- ============================================================
-- Listo. Índices útiles (opcional pero recomendado):
-- ============================================================
create index if not exists idx_prod_fecha on producciones(fecha desc);
create index if not exists idx_sal_fecha  on salidas(fecha desc);
create index if not exists idx_prod_creador on producciones(creado_por);
create index if not exists idx_sal_creador  on salidas(creado_por);
