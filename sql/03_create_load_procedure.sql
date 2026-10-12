USE OnlineRetailAnalytics;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF SCHEMA_ID(N'etl') IS NULL
BEGIN
    EXEC(N'CREATE SCHEMA etl AUTHORIZATION dbo;');
    PRINT N'Created schema: etl';
END;
GO

CREATE OR ALTER PROCEDURE etl.LoadWarehouse
AS
BEGIN
    SET NOCOUNT ON;
    SET XACT_ABORT ON;
    SET DATEFIRST 1;
    SET LANGUAGE English;

    DECLARE @StagingRowCount INT;
    DECLARE @FactRowCount INT;
    DECLARE @StagingQuantity BIGINT;
    DECLARE @FactQuantity BIGINT;
    DECLARE @StagingAmount DECIMAL(19, 2);
    DECLARE @FactAmount DECIMAL(19, 2);
    DECLARE @MinimumDate DATE;
    DECLARE @MaximumDate DATE;

    SELECT
        @StagingRowCount = COUNT(*),
        @StagingQuantity = SUM(
            CONVERT(BIGINT, Quantity)
        ),
        @StagingAmount = SUM(LineAmount),
        @MinimumDate = MIN(
            CONVERT(DATE, InvoiceDate)
        ),
        @MaximumDate = MAX(
            CONVERT(DATE, InvoiceDate)
        )
    FROM stg.InvoiceProduct;

    IF @StagingRowCount = 0
    BEGIN
        THROW 50001,
            'Staging table contains no records.',
            1;
    END;

    BEGIN TRY
        BEGIN TRANSACTION;

        /* =============================================
           DATE DIMENSION
           ============================================= */

        ;WITH CalendarDates AS
        (
            SELECT @MinimumDate AS CalendarDate

            UNION ALL

            SELECT DATEADD(
                DAY,
                1,
                CalendarDate
            )
            FROM CalendarDates
            WHERE CalendarDate < @MaximumDate
        )
        INSERT INTO dw.DimDate
        (
            DateKey,
            FullDate,
            CalendarYear,
            CalendarQuarter,
            MonthNumber,
            MonthName,
            YearMonth,
            DayOfMonth,
            DayOfWeekNumber,
            DayOfWeekName,
            IsWeekend
        )
        SELECT
            CONVERT(
                INT,
                CONVERT(
                    CHAR(8),
                    calendar.CalendarDate,
                    112
                )
            ),
            calendar.CalendarDate,
            DATEPART(
                YEAR,
                calendar.CalendarDate
            ),
            DATEPART(
                QUARTER,
                calendar.CalendarDate
            ),
            DATEPART(
                MONTH,
                calendar.CalendarDate
            ),
            DATENAME(
                MONTH,
                calendar.CalendarDate
            ),
            CONVERT(
                CHAR(7),
                calendar.CalendarDate,
                120
            ),
            DATEPART(
                DAY,
                calendar.CalendarDate
            ),
            DATEPART(
                WEEKDAY,
                calendar.CalendarDate
            ),
            DATENAME(
                WEEKDAY,
                calendar.CalendarDate
            ),
            CASE
                WHEN DATEPART(
                    WEEKDAY,
                    calendar.CalendarDate
                ) IN (6, 7)
                    THEN 1
                ELSE 0
            END
        FROM CalendarDates AS calendar
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dw.DimDate AS existing
            WHERE
                existing.FullDate
                = calendar.CalendarDate
        )
        OPTION (MAXRECURSION 0);

        /* =============================================
           PRODUCT DIMENSION
           ============================================= */

        ;WITH RankedProducts AS
        (
            SELECT
                staging.StockCode,
                COALESCE(
                    NULLIF(
                        LTRIM(
                            RTRIM(staging.Description)
                        ),
                        N''
                    ),
                    N'Unknown description'
                ) AS ProductDescription,
                ROW_NUMBER() OVER
                (
                    PARTITION BY staging.StockCode
                    ORDER BY
                        CASE
                            WHEN NULLIF(
                                LTRIM(
                                    RTRIM(
                                        staging.Description
                                    )
                                ),
                                N''
                            ) IS NULL
                                THEN 1
                            ELSE 0
                        END,
                        staging.InvoiceDate DESC,
                        staging.AnalyticalLineID DESC
                ) AS ProductRank
            FROM stg.InvoiceProduct AS staging
        )
        INSERT INTO dw.DimProduct
        (
            StockCode,
            ProductDescription
        )
        SELECT
            ranked.StockCode,
            ranked.ProductDescription
        FROM RankedProducts AS ranked
        WHERE
            ranked.ProductRank = 1
            AND NOT EXISTS
            (
                SELECT 1
                FROM dw.DimProduct AS existing
                WHERE
                    existing.StockCode
                    = ranked.StockCode
            );

        ;WITH RankedProducts AS
        (
            SELECT
                staging.StockCode,
                COALESCE(
                    NULLIF(
                        LTRIM(
                            RTRIM(staging.Description)
                        ),
                        N''
                    ),
                    N'Unknown description'
                ) AS ProductDescription,
                ROW_NUMBER() OVER
                (
                    PARTITION BY staging.StockCode
                    ORDER BY
                        CASE
                            WHEN NULLIF(
                                LTRIM(
                                    RTRIM(
                                        staging.Description
                                    )
                                ),
                                N''
                            ) IS NULL
                                THEN 1
                            ELSE 0
                        END,
                        staging.InvoiceDate DESC,
                        staging.AnalyticalLineID DESC
                ) AS ProductRank
            FROM stg.InvoiceProduct AS staging
        )
        UPDATE product
        SET
            product.ProductDescription
                = ranked.ProductDescription,
            product.UpdatedAtUTC
                = SYSUTCDATETIME()
        FROM dw.DimProduct AS product
        INNER JOIN RankedProducts AS ranked
            ON ranked.StockCode
                = product.StockCode
        WHERE
            ranked.ProductRank = 1
            AND product.ProductKey <> 0
            AND product.ProductDescription
                <> ranked.ProductDescription;

        /* =============================================
           CUSTOMER DIMENSION
           ============================================= */

        INSERT INTO dw.DimCustomer
        (
            CustomerID,
            IsIdentified
        )
        SELECT DISTINCT
            staging.CustomerID,
            1
        FROM stg.InvoiceProduct AS staging
        WHERE
            staging.CustomerID IS NOT NULL
            AND NOT EXISTS
            (
                SELECT 1
                FROM dw.DimCustomer AS existing
                WHERE
                    existing.CustomerID
                    = staging.CustomerID
            );

        /* =============================================
           COUNTRY DIMENSION
           ============================================= */

        INSERT INTO dw.DimCountry
        (
            CountryName
        )
        SELECT DISTINCT
            staging.Country
        FROM stg.InvoiceProduct AS staging
        WHERE NOT EXISTS
        (
            SELECT 1
            FROM dw.DimCountry AS existing
            WHERE
                existing.CountryName
                = staging.Country
        );

        /* =============================================
           FACT TABLE
           Full refresh from the reconciled staging data.
           ============================================= */

        DELETE FROM dw.FactSales;

        INSERT INTO dw.FactSales
        (
            SourceAnalyticalLineID,
            Invoice,
            DateKey,
            ProductKey,
            CustomerKey,
            CountryKey,
            TransactionTypeKey,
            InvoiceDateTime,
            UnitPrice,
            Quantity,
            LineAmount,
            SourcePeriod,
            SourceLineCount,
            DuplicateCandidateLineCount,
            FirstSourceRowNumber,
            HasMultipleSourceLines
        )
        SELECT
            staging.AnalyticalLineID,
            staging.Invoice,
            date_dimension.DateKey,
            product.ProductKey,
            COALESCE(
                customer.CustomerKey,
                0
            ),
            country.CountryKey,
            transaction_type.TransactionTypeKey,
            staging.InvoiceDate,
            staging.UnitPrice,
            staging.Quantity,
            staging.LineAmount,
            staging.SourcePeriod,
            staging.SourceLineCount,
            staging.DuplicateCandidateLineCount,
            staging.FirstSourceRowNumber,
            staging.HasMultipleSourceLines
        FROM stg.InvoiceProduct AS staging
        INNER JOIN dw.DimDate AS date_dimension
            ON date_dimension.FullDate
                = CONVERT(
                    DATE,
                    staging.InvoiceDate
                )
        INNER JOIN dw.DimProduct AS product
            ON product.StockCode
                = staging.StockCode
        LEFT JOIN dw.DimCustomer AS customer
            ON customer.CustomerID
                = staging.CustomerID
        INNER JOIN dw.DimCountry AS country
            ON country.CountryName
                = staging.Country
        INNER JOIN dw.DimTransactionType
            AS transaction_type
            ON transaction_type.TransactionTypeCode
                = staging.TransactionType;

        /* =============================================
           RECONCILIATION
           ============================================= */

        SELECT
            @FactRowCount = COUNT(*),
            @FactQuantity = SUM(
                CONVERT(BIGINT, Quantity)
            ),
            @FactAmount = SUM(LineAmount)
        FROM dw.FactSales;

        IF @FactRowCount <> @StagingRowCount
        BEGIN
            THROW 50002,
                'Fact row-count reconciliation failed.',
                1;
        END;

        IF @FactQuantity <> @StagingQuantity
        BEGIN
            THROW 50003,
                'Fact quantity reconciliation failed.',
                1;
        END;

        IF @FactAmount <> @StagingAmount
        BEGIN
            THROW 50004,
                'Fact amount reconciliation failed.',
                1;
        END;

        COMMIT TRANSACTION;

        SELECT
            @StagingRowCount AS StagingRowCount,
            @FactRowCount AS FactRowCount,
            @FactQuantity AS TotalQuantity,
            @FactAmount AS TotalLineAmount,
            CAST(1 AS BIT) AS ReconciliationPassed;
    END TRY
    BEGIN CATCH
        IF @@TRANCOUNT > 0
        BEGIN
            ROLLBACK TRANSACTION;
        END;

        THROW;
    END CATCH;
END;
GO

PRINT N'Created or updated etl.LoadWarehouse';
GO

SELECT
    schema_name(schema_id) AS SchemaName,
    name AS ProcedureName
FROM sys.procedures
WHERE
    schema_name(schema_id) = N'etl'
    AND name = N'LoadWarehouse';
GO