USE master;
GO

IF DB_ID(N'OnlineRetailAnalytics') IS NULL
BEGIN
    PRINT N'Creating database OnlineRetailAnalytics';

    CREATE DATABASE OnlineRetailAnalytics;
END
ELSE
BEGIN
    PRINT N'Database OnlineRetailAnalytics already exists';
END;
GO

ALTER DATABASE OnlineRetailAnalytics
SET RECOVERY SIMPLE;
GO

ALTER DATABASE OnlineRetailAnalytics
SET READ_COMMITTED_SNAPSHOT ON;
GO

USE OnlineRetailAnalytics;
GO

IF SCHEMA_ID(N'stg') IS NULL
BEGIN
    EXEC(N'CREATE SCHEMA stg AUTHORIZATION dbo;');
    PRINT N'Created schema: stg';
END;
GO

IF SCHEMA_ID(N'dw') IS NULL
BEGIN
    EXEC(N'CREATE SCHEMA dw AUTHORIZATION dbo;');
    PRINT N'Created schema: dw';
END;
GO

IF SCHEMA_ID(N'audit') IS NULL
BEGIN
    EXEC(N'CREATE SCHEMA audit AUTHORIZATION dbo;');
    PRINT N'Created schema: audit';
END;
GO

PRINT N'OnlineRetailAnalytics database setup completed';
GO

SELECT
    DB_NAME() AS DatabaseName,
    name AS SchemaName
FROM sys.schemas
WHERE name IN (
    N'stg',
    N'dw',
    N'audit'
)
ORDER BY name;
GO