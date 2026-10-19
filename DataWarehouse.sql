-- ============================================================================
-- PROYECTO: Data Mart Parroquia Nuestra Señora de la Paz
-- CURSO: Base de Datos Avanzadas y Big Data (UPN 2026-2)
-- AUTOR: Felipo (Ingeniero de Datos)
-- EVIDENCIA OBLIGATORIA: Script DDL del Data Warehouse (T2)
-- ============================================================================

USE master;
GO

IF NOT EXISTS (SELECT name FROM sys.databases WHERE name = 'Parroquia_DW')
BEGIN
    CREATE DATABASE Parroquia_DW;
END
GO

USE Parroquia_DW;
GO

-- 1. CREACIÓN DE ESQUEMAS
IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'staging')
    EXEC('CREATE SCHEMA staging');
GO

IF NOT EXISTS (SELECT * FROM sys.schemas WHERE name = 'dw')
    EXEC('CREATE SCHEMA dw');
GO

-- 2. TABLA DE LOG Y AUDITORÍA DE CARGAS ETL
IF OBJECT_ID('dw.Log_Ejecucion_ETL', 'U') IS NOT NULL
    DROP TABLE dw.Log_Ejecucion_ETL;
GO

CREATE TABLE dw.Log_Ejecucion_ETL (
    LogID INT IDENTITY(1,1) PRIMARY KEY,
    Proceso VARCHAR(100) NOT NULL,
    FechaInicio DATETIME NOT NULL DEFAULT GETDATE(),
    FechaFin DATETIME NULL,
    Estado VARCHAR(20) NOT NULL, -- 'INICIADO', 'EXITOSO', 'ERROR'
    RegistrosProcesados INT DEFAULT 0,
    MensajeError VARCHAR(MAX) NULL
);
GO

-- 3. TABLA DE CUARENTENA PARA DATOS INCONSISTENTES
IF OBJECT_ID('staging.Cuarentena_Inconsistencias', 'U') IS NOT NULL
    DROP TABLE staging.Cuarentena_Inconsistencias;
GO

CREATE TABLE staging.Cuarentena_Inconsistencias (
    CuarentenaID INT IDENTITY(1,1) PRIMARY KEY,
    OrigenDatos VARCHAR(50) NOT NULL,
    FilaOrigen VARCHAR(MAX) NOT NULL,
    ReglaIncumplida VARCHAR(200) NOT NULL,
    FechaDeteccion DATETIME DEFAULT GETDATE()
);
GO

-- ============================================================================
-- 4. TABLAS DIMENSIONALES
-- ============================================================================

-- Dimensión Tiempo
IF OBJECT_ID('dw.Dim_Tiempo', 'U') IS NOT NULL
    DROP TABLE dw.Dim_Tiempo;
GO

CREATE TABLE dw.Dim_Tiempo (
    TiempoKey INT PRIMARY KEY, -- Formato YYYYMMDD
    Fecha DATE NOT NULL,
    Anio SMALLINT NOT NULL,
    Semestre TINYINT NOT NULL,
    Trimestre TINYINT NOT NULL,
    Mes TINYINT NOT NULL,
    NombreMes VARCHAR(15) NOT NULL,
    SemanaAnio TINYINT NOT NULL,
    DiaSemana TINYINT NOT NULL,
    NombreDia VARCHAR(15) NOT NULL,
    EsFinDeSemana BIT NOT NULL
);
GO

-- Dimensión Feligrés (Anonimizada según Ley N.° 29733)
IF OBJECT_ID('dw.Dim_Feligres', 'U') IS NOT NULL
    DROP TABLE dw.Dim_Feligres;
GO

CREATE TABLE dw.Dim_Feligres (
    FeligresKey INT IDENTITY(1,1) PRIMARY KEY,
    FeligresHash CHAR(64) NOT NULL UNIQUE, -- SHA-256 del DNI/ID original
    Genero CHAR(1) DEFAULT 'U',           -- 'M', 'F', 'U' (Indeterminado)
    RangoEtario VARCHAR(25) NOT NULL DEFAULT 'NO REGISTRADO',
    DistritoResidencia VARCHAR(80) NOT NULL DEFAULT 'NO REGISTRADO',
    EsPadrino BIT NOT NULL DEFAULT 0,
    FechaCarga DATETIME DEFAULT GETDATE()
);
GO

-- Dimensión Tipo de Sacramento
IF OBJECT_ID('dw.Dim_TipoSacramento', 'U') IS NOT NULL
    DROP TABLE dw.Dim_TipoSacramento;
GO

CREATE TABLE dw.Dim_TipoSacramento (
    TipoSacramentoKey INT IDENTITY(1,1) PRIMARY KEY,
    CodigoSacramento VARCHAR(10) NOT NULL UNIQUE,
    NombreSacramento VARCHAR(50) NOT NULL,
    RequierePadrinos BIT NOT NULL,
    EsDigitalizado BIT NOT NULL DEFAULT 1
);
GO

-- Dimensión Concepto Financiero
IF OBJECT_ID('dw.Dim_ConceptoFinanciero', 'U') IS NOT NULL
    DROP TABLE dw.Dim_ConceptoFinanciero;
GO

CREATE TABLE dw.Dim_ConceptoFinanciero (
    ConceptoKey INT IDENTITY(1,1) PRIMARY KEY,
    TipoMovimiento VARCHAR(10) NOT NULL, -- 'INGRESO' o 'EGRESO'
    Categoria VARCHAR(50) NOT NULL,      -- 'Estipendio', 'Donación', 'Servicio', etc.
    Procedencia VARCHAR(20) NOT NULL,    -- 'Nacional', 'Extranjera', 'Parroquial'
    MedioPago VARCHAR(30) NOT NULL DEFAULT 'Efectivo'
);
GO

-- Dimensión Ubicación / Sede
IF OBJECT_ID('dw.Dim_Ubicacion', 'U') IS NOT NULL
    DROP TABLE dw.Dim_Ubicacion;
GO

CREATE TABLE dw.Dim_Ubicacion (
    UbicacionKey INT IDENTITY(1,1) PRIMARY KEY,
    NombreSede VARCHAR(100) NOT NULL,
    TipoSede VARCHAR(30) NOT NULL,
    Zona VARCHAR(50) NOT NULL DEFAULT 'Sector Central'
);
GO

-- ============================================================================
-- 5. TABLAS DE HECHOS
-- ============================================================================

-- Tabla de Hechos: Emisión y Registro de Sacramentos
IF OBJECT_ID('dw.Fact_Sacramento', 'U') IS NOT NULL
    DROP TABLE dw.Fact_Sacramento;
GO

CREATE TABLE dw.Fact_Sacramento (
    SacramentoKey BIGINT IDENTITY(1,1) PRIMARY KEY,
    TiempoKey INT NOT NULL,
    FeligresKey INT NOT NULL,
    TipoSacramentoKey INT NOT NULL,
    UbicacionKey INT NOT NULL,
    NumeroLibro INT NULL,
    NumeroFolio INT NULL,
    NumeroActa INT NULL,
    TiempoEmisionSeg INT NOT NULL DEFAULT 120, -- Medición de eficiencia
    Cantidad INT NOT NULL DEFAULT 1,
    CONSTRAINT FK_FactSacramento_Tiempo FOREIGN KEY (TiempoKey) REFERENCES dw.Dim_Tiempo(TiempoKey),
    CONSTRAINT FK_FactSacramento_Feligres FOREIGN KEY (FeligresKey) REFERENCES dw.Dim_Feligres(FeligresKey),
    CONSTRAINT FK_FactSacramento_TipoSacramento FOREIGN KEY (TipoSacramentoKey) REFERENCES dw.Dim_TipoSacramento(TipoSacramentoKey),
    CONSTRAINT FK_FactSacramento_Ubicacion FOREIGN KEY (UbicacionKey) REFERENCES dw.Dim_Ubicacion(UbicacionKey)
);
GO

-- Índices non-clustered para acelerar consultas analíticas
CREATE NONCLUSTERED INDEX IX_FactSacramento_Tiempo ON dw.Fact_Sacramento(TiempoKey);
CREATE NONCLUSTERED INDEX IX_FactSacramento_Tipo ON dw.Fact_Sacramento(TipoSacramentoKey);
GO

-- Tabla de Hechos: Finanzas Parroquiales (Ingresos / Egresos)
IF OBJECT_ID('dw.Fact_Finanzas', 'U') IS NOT NULL
    DROP TABLE dw.Fact_Finanzas;
GO

CREATE TABLE dw.Fact_Finanzas (
    FinanzasKey BIGINT IDENTITY(1,1) PRIMARY KEY,
    TiempoKey INT NOT NULL,
    ConceptoKey INT NOT NULL,
    UbicacionKey INT NOT NULL,
    NumeroComprobante VARCHAR(30) NULL,
    MontoIngreso DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    MontoEgreso DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    MargenNeto DECIMAL(12,2) NOT NULL DEFAULT 0.00,
    CantidadOperaciones INT NOT NULL DEFAULT 1,
    CONSTRAINT FK_FactFinanzas_Tiempo FOREIGN KEY (TiempoKey) REFERENCES dw.Dim_Tiempo(TiempoKey),
    CONSTRAINT FK_FactFinanzas_Concepto FOREIGN KEY (ConceptoKey) REFERENCES dw.Dim_ConceptoFinanciero(ConceptoKey),
    CONSTRAINT FK_FactFinanzas_Ubicacion FOREIGN KEY (UbicacionKey) REFERENCES dw.Dim_Ubicacion(UbicacionKey)
);
GO

CREATE NONCLUSTERED INDEX IX_FactFinanzas_Tiempo ON dw.Fact_Finanzas(TiempoKey);
CREATE NONCLUSTERED INDEX IX_FactFinanzas_Concepto ON dw.Fact_Finanzas(ConceptoKey);
GO