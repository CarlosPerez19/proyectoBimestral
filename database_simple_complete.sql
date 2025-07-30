-- =====================================================
-- BASE DE DATOS COMPLETA DESDE CERO - VERSION SIMPLE
-- =====================================================

-- =====================================================
-- 1. ELIMINAR TODO LO EXISTENTE
-- =====================================================

-- Eliminar políticas (solo si las tablas existen)
DO $$ 
BEGIN
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'user_profiles') THEN
        DROP POLICY IF EXISTS "user_profiles_all" ON user_profiles;
    END IF;
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'user_locations') THEN
        DROP POLICY IF EXISTS "user_locations_all" ON user_locations;
    END IF;
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'projects') THEN
        DROP POLICY IF EXISTS "projects_all" ON projects;
    END IF;
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'positions') THEN
        DROP POLICY IF EXISTS "positions_all" ON positions;
    END IF;
    IF EXISTS (SELECT FROM information_schema.tables WHERE table_name = 'user_roles') THEN
        DROP POLICY IF EXISTS "user_roles_all" ON user_roles;
    END IF;
END $$;

-- Eliminar tablas
DROP TABLE IF EXISTS positions CASCADE;
DROP TABLE IF EXISTS user_locations CASCADE;
DROP TABLE IF EXISTS projects CASCADE;
DROP TABLE IF EXISTS user_profiles CASCADE;
DROP TABLE IF EXISTS user_roles CASCADE;

-- =====================================================
-- 2. CREAR TODAS LAS TABLAS NECESARIAS
-- =====================================================

-- Tabla de roles de usuarios
CREATE TABLE user_roles (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL DEFAULT 'user' CHECK (role IN ('admin', 'user')),
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Tabla de perfiles de usuarios
CREATE TABLE user_profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    username TEXT NOT NULL,
    device_info TEXT,
    is_online BOOLEAN DEFAULT false,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Tabla de proyectos
CREATE TABLE projects (
    id SERIAL PRIMARY KEY,
    name TEXT NOT NULL,
    description TEXT,
    created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Tabla de ubicaciones de usuarios en tiempo real
CREATE TABLE user_locations (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION,
    longitude DOUBLE PRECISION,
    accuracy DOUBLE PRECISION,
    speed DOUBLE PRECISION,
    heading DOUBLE PRECISION,
    is_online BOOLEAN DEFAULT false,
    last_seen TIMESTAMP WITH TIME ZONE DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- Tabla de puntos GPS marcados en proyectos
CREATE TABLE positions (
    id SERIAL PRIMARY KEY,
    project_id INTEGER REFERENCES projects(id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    accuracy DOUBLE PRECISION,
    altitude DOUBLE PRECISION,
    created_by UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    timestamp TIMESTAMP WITH TIME ZONE DEFAULT NOW()
);

-- =====================================================
-- 3. HABILITAR RLS Y CREAR POLÍTICAS SIMPLES
-- =====================================================

-- Habilitar RLS
ALTER TABLE user_roles ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE projects ENABLE ROW LEVEL SECURITY;
ALTER TABLE user_locations ENABLE ROW LEVEL SECURITY;
ALTER TABLE positions ENABLE ROW LEVEL SECURITY;

-- Políticas simples - todos pueden ver y modificar todo (sin restricciones)
CREATE POLICY "user_roles_all" ON user_roles FOR ALL USING (true);
CREATE POLICY "user_profiles_all" ON user_profiles FOR ALL USING (true);
CREATE POLICY "projects_all" ON projects FOR ALL USING (true);
CREATE POLICY "user_locations_all" ON user_locations FOR ALL USING (true);
CREATE POLICY "positions_all" ON positions FOR ALL USING (true);

-- =====================================================
-- 4. VERIFICAR ESTRUCTURA
-- =====================================================

-- Mostrar todas las tablas creadas
SELECT 
    table_name,
    column_name,
    data_type,
    is_nullable
FROM information_schema.columns 
WHERE table_name IN ('user_roles', 'user_profiles', 'projects', 'user_locations', 'positions')
ORDER BY table_name, ordinal_position;

-- =====================================================
-- LISTO - BASE DE DATOS SIMPLE Y FUNCIONAL (TABLAS VACÍAS)
-- =====================================================
