USE OnlineRetailAnalytics;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

/* =========================================================
   AUDIT TABLE
   ========================================================= */

IF OBJECT_ID(N'audit.ETLRun', N'U') IS NULL
BEGIN
    CREATE TABLE audit.ETLRun
    (
        ETLRunID BIGINT IDENTITY(1, 1) NOT NULL,
        ProcessName NVARCHAR(100) NOT NULL,
        StartedAtUTC DATETIME2(0) NOT NULL,
        CompletedAtUTC DATETIME2(0) NULL,
        RunStatus VARCHAR(20) NOT NULL,
        SourceRowCount INT NULL,
        StagingRowCount INT NULL,
        FactRowCount INT NULL,
        ErrorMessage NVARCHAR(4000) NULL,

        CONSTRAINT PK_ETLRun
            PRIMARY KEY (ETLRunID),

        CONSTRAINT CK_ETLRun_Status
            CHECK (
                RunStatus IN (
                    'STARTED',
                    'COMPLETED',
                    'FAILED'
                )
            )
    );

    PRINT N'Created audit.ETLRun';
END;
GO

/* =========================================================
   STAGING TABLE
   ========================================================= */

IF OBJECT_ID(N'stg.InvoiceProduct', N'U') IS NULL
BEGIN
    CREATE TABLE stg.InvoiceProduct
    (
        AnalyticalLineID INT NOT NULL,
        Invoice NVARCHAR(20) NOT NULL,
        StockCode NVARCHAR(20) NOT NULL,
        Description NVARCHAR(255) NULL,
        InvoiceDate DATETIME2(0) NOT NULL,
        UnitPrice DECIMAL(19, 4) NOT NULL,
        CustomerID NVARCHAR(20) NULL,
        Country NVARCHAR(100) NOT NULL,
        SourcePeriod NVARCHAR(50) NOT NULL,
        TransactionType VARCHAR(30) NOT NULL,
        Quantity INT NOT NULL,
        LineAmount DECIMAL(19, 2) NOT NULL,
        SourceLineCount INT NOT NULL,
        DuplicateCandidateLineCount INT NOT NULL,
        FirstSourceRowNumber INT NOT NULL,
        SourceRowNumbers NVARCHAR(MAX) NOT NULL,
        HasMultipleSourceLines BIT NOT NULL,
        LoadedAtUTC DATETIME2(0) NOT NULL
            CONSTRAINT DF_InvoiceProduct_LoadedAtUTC
            DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_StagingInvoiceProduct
            PRIMARY KEY (AnalyticalLineID),

        CONSTRAINT CK_StagingInvoiceProduct_SourceLineCount
            CHECK (SourceLineCount > 0),

        CONSTRAINT CK_StagingInvoiceProduct_DuplicateCount
            CHECK (
                DuplicateCandidateLineCount >= 0
                AND DuplicateCandidateLineCount <= SourceLineCount
            )
    );

    PRINT N'Created stg.InvoiceProduct';
END;
GO

/* =========================================================
   DATE DIMENSION
   ========================================================= */

IF OBJECT_ID(N'dw.DimDate', N'U') IS NULL
BEGIN
    CREATE TABLE dw.DimDate
    (
        DateKey INT NOT NULL,
        FullDate DATE NOT NULL,
        CalendarYear SMALLINT NOT NULL,
        CalendarQuarter TINYINT NOT NULL,
        MonthNumber TINYINT NOT NULL,
        MonthName VARCHAR(20) NOT NULL,
        YearMonth CHAR(7) NOT NULL,
        DayOfMonth TINYINT NOT NULL,
        DayOfWeekNumber TINYINT NOT NULL,
        DayOfWeekName VARCHAR(20) NOT NULL,
        IsWeekend BIT NOT NULL,

        CONSTRAINT PK_DimDate
            PRIMARY KEY (DateKey),

        CONSTRAINT UQ_DimDate_FullDate
            UNIQUE (FullDate)
    );

    PRINT N'Created dw.DimDate';
END;
GO

/* =========================================================
   PRODUCT DIMENSION
   ========================================================= */

IF OBJECT_ID(N'dw.DimProduct', N'U') IS NULL
BEGIN
    CREATE TABLE dw.DimProduct
    (
        ProductKey INT IDENTITY(1, 1) NOT NULL,
        StockCode NVARCHAR(20) NOT NULL,
        ProductDescription NVARCHAR(255) NOT NULL,
        CreatedAtUTC DATETIME2(0) NOT NULL
            CONSTRAINT DF_DimProduct_CreatedAtUTC
            DEFAULT SYSUTCDATETIME(),
        UpdatedAtUTC DATETIME2(0) NOT NULL
            CONSTRAINT DF_DimProduct_UpdatedAtUTC
            DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_DimProduct
            PRIMARY KEY (ProductKey),

        CONSTRAINT UQ_DimProduct_StockCode
            UNIQUE (StockCode)
    );

    PRINT N'Created dw.DimProduct';
END;
GO

/* =========================================================
   CUSTOMER DIMENSION
   ========================================================= */

IF OBJECT_ID(N'dw.DimCustomer', N'U') IS NULL
BEGIN
    CREATE TABLE dw.DimCustomer
    (
        CustomerKey INT IDENTITY(1, 1) NOT NULL,
        CustomerID NVARCHAR(20) NOT NULL,
        IsIdentified BIT NOT NULL,
        CreatedAtUTC DATETIME2(0) NOT NULL
            CONSTRAINT DF_DimCustomer_CreatedAtUTC
            DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_DimCustomer
            PRIMARY KEY (CustomerKey),

        CONSTRAINT UQ_DimCustomer_CustomerID
            UNIQUE (CustomerID)
    );

    PRINT N'Created dw.DimCustomer';
END;
GO

/* =========================================================
   COUNTRY DIMENSION
   ========================================================= */

IF OBJECT_ID(N'dw.DimCountry', N'U') IS NULL
BEGIN
    CREATE TABLE dw.DimCountry
    (
        CountryKey INT IDENTITY(1, 1) NOT NULL,
        CountryName NVARCHAR(100) NOT NULL,

        CONSTRAINT PK_DimCountry
            PRIMARY KEY (CountryKey),

        CONSTRAINT UQ_DimCountry_CountryName
            UNIQUE (CountryName)
    );

    PRINT N'Created dw.DimCountry';
END;
GO

/* =========================================================
   TRANSACTION-TYPE DIMENSION
   ========================================================= */

IF OBJECT_ID(N'dw.DimTransactionType', N'U') IS NULL
BEGIN
    CREATE TABLE dw.DimTransactionType
    (
        TransactionTypeKey TINYINT NOT NULL,
        TransactionTypeCode VARCHAR(30) NOT NULL,
        TransactionTypeName VARCHAR(50) NOT NULL,
        RevenueEffect VARCHAR(20) NOT NULL,

        CONSTRAINT PK_DimTransactionType
            PRIMARY KEY (TransactionTypeKey),

        CONSTRAINT UQ_DimTransactionType_Code
            UNIQUE (TransactionTypeCode),

        CONSTRAINT CK_DimTransactionType_RevenueEffect
            CHECK (
                RevenueEffect IN (
                    'POSITIVE',
                    'NEGATIVE',
                    'ZERO',
                    'UNKNOWN'
                )
            )
    );

    PRINT N'Created dw.DimTransactionType';
END;
GO

/* =========================================================
   SALES FACT
   ========================================================= */

IF OBJECT_ID(N'dw.FactSales', N'U') IS NULL
BEGIN
    CREATE TABLE dw.FactSales
    (
        SalesKey BIGINT IDENTITY(1, 1) NOT NULL,
        SourceAnalyticalLineID INT NOT NULL,
        Invoice NVARCHAR(20) NOT NULL,
        DateKey INT NOT NULL,
        ProductKey INT NOT NULL,
        CustomerKey INT NOT NULL,
        CountryKey INT NOT NULL,
        TransactionTypeKey TINYINT NOT NULL,
        InvoiceDateTime DATETIME2(0) NOT NULL,
        UnitPrice DECIMAL(19, 4) NOT NULL,
        Quantity INT NOT NULL,
        LineAmount DECIMAL(19, 2) NOT NULL,
        SourcePeriod NVARCHAR(50) NOT NULL,
        SourceLineCount INT NOT NULL,
        DuplicateCandidateLineCount INT NOT NULL,
        FirstSourceRowNumber INT NOT NULL,
        HasMultipleSourceLines BIT NOT NULL,
        LoadedAtUTC DATETIME2(0) NOT NULL
            CONSTRAINT DF_FactSales_LoadedAtUTC
            DEFAULT SYSUTCDATETIME(),

        CONSTRAINT PK_FactSales
            PRIMARY KEY (SalesKey),

        CONSTRAINT UQ_FactSales_SourceAnalyticalLineID
            UNIQUE (SourceAnalyticalLineID),

        CONSTRAINT FK_FactSales_DimDate
            FOREIGN KEY (DateKey)
            REFERENCES dw.DimDate (DateKey),

        CONSTRAINT FK_FactSales_DimProduct
            FOREIGN KEY (ProductKey)
            REFERENCES dw.DimProduct (ProductKey),

        CONSTRAINT FK_FactSales_DimCustomer
            FOREIGN KEY (CustomerKey)
            REFERENCES dw.DimCustomer (CustomerKey),

        CONSTRAINT FK_FactSales_DimCountry
            FOREIGN KEY (CountryKey)
            REFERENCES dw.DimCountry (CountryKey),

        CONSTRAINT FK_FactSales_DimTransactionType
            FOREIGN KEY (TransactionTypeKey)
            REFERENCES dw.DimTransactionType (
                TransactionTypeKey
            )
    );

    PRINT N'Created dw.FactSales';
END;
GO

/* =========================================================
   DEFAULT DIMENSION MEMBERS
   ========================================================= */

IF NOT EXISTS (
    SELECT 1
    FROM dw.DimProduct
    WHERE ProductKey = 0
)
BEGIN
    SET IDENTITY_INSERT dw.DimProduct ON;

    INSERT INTO dw.DimProduct
    (
        ProductKey,
        StockCode,
        ProductDescription
    )
    VALUES
    (
        0,
        N'UNKNOWN',
        N'Unknown product'
    );

    SET IDENTITY_INSERT dw.DimProduct OFF;
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM dw.DimCustomer
    WHERE CustomerKey = 0
)
BEGIN
    SET IDENTITY_INSERT dw.DimCustomer ON;

    INSERT INTO dw.DimCustomer
    (
        CustomerKey,
        CustomerID,
        IsIdentified
    )
    VALUES
    (
        0,
        N'UNKNOWN',
        0
    );

    SET IDENTITY_INSERT dw.DimCustomer OFF;
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM dw.DimCountry
    WHERE CountryKey = 0
)
BEGIN
    SET IDENTITY_INSERT dw.DimCountry ON;

    INSERT INTO dw.DimCountry
    (
        CountryKey,
        CountryName
    )
    VALUES
    (
        0,
        N'Unknown'
    );

    SET IDENTITY_INSERT dw.DimCountry OFF;
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM dw.DimTransactionType
    WHERE TransactionTypeKey = 0
)
BEGIN
    INSERT INTO dw.DimTransactionType
    (
        TransactionTypeKey,
        TransactionTypeCode,
        TransactionTypeName,
        RevenueEffect
    )
    VALUES
    (
        0,
        'UNKNOWN',
        'Unknown transaction',
        'UNKNOWN'
    );
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM dw.DimTransactionType
    WHERE TransactionTypeCode = 'SALE'
)
BEGIN
    INSERT INTO dw.DimTransactionType
    VALUES
    (
        1,
        'SALE',
        'Sale',
        'POSITIVE'
    );
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM dw.DimTransactionType
    WHERE TransactionTypeCode = 'CANCELLATION'
)
BEGIN
    INSERT INTO dw.DimTransactionType
    VALUES
    (
        2,
        'CANCELLATION',
        'Cancellation or return',
        'NEGATIVE'
    );
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM dw.DimTransactionType
    WHERE TransactionTypeCode = 'FREE_ITEM'
)
BEGIN
    INSERT INTO dw.DimTransactionType
    VALUES
    (
        3,
        'FREE_ITEM',
        'Free or promotional item',
        'ZERO'
    );
END;
GO

/* =========================================================
   FACT INDEXES
   ========================================================= */

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE
        object_id = OBJECT_ID(N'dw.FactSales')
        AND name = N'IX_FactSales_DateKey'
)
BEGIN
    CREATE INDEX IX_FactSales_DateKey
        ON dw.FactSales (DateKey);
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE
        object_id = OBJECT_ID(N'dw.FactSales')
        AND name = N'IX_FactSales_ProductKey'
)
BEGIN
    CREATE INDEX IX_FactSales_ProductKey
        ON dw.FactSales (ProductKey);
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE
        object_id = OBJECT_ID(N'dw.FactSales')
        AND name = N'IX_FactSales_CustomerKey'
)
BEGIN
    CREATE INDEX IX_FactSales_CustomerKey
        ON dw.FactSales (CustomerKey);
END;
GO

IF NOT EXISTS (
    SELECT 1
    FROM sys.indexes
    WHERE
        object_id = OBJECT_ID(N'dw.FactSales')
        AND name = N'IX_FactSales_CountryKey'
)
BEGIN
    CREATE INDEX IX_FactSales_CountryKey
        ON dw.FactSales (CountryKey);
END;
GO

PRINT N'Star schema setup completed';
GO

SELECT
    schema_name(schema_id) AS SchemaName,
    name AS TableName
FROM sys.tables
WHERE schema_name(schema_id) IN (
    N'audit',
    N'stg',
    N'dw'
)
ORDER BY
    SchemaName,
    TableName;
GO