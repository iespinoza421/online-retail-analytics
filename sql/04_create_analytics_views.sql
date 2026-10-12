USE OnlineRetailAnalytics;
GO

SET NOCOUNT ON;
GO

/* =========================================================
   DETAILED ANALYTICAL VIEW
   ========================================================= */

CREATE OR ALTER VIEW dw.vwSalesDetail
AS
SELECT
    fact.SalesKey,
    fact.SourceAnalyticalLineID,
    fact.Invoice,
    fact.InvoiceDateTime,
    date_dimension.FullDate,
    date_dimension.CalendarYear,
    date_dimension.CalendarQuarter,
    date_dimension.MonthNumber,
    date_dimension.MonthName,
    date_dimension.YearMonth,
    date_dimension.DayOfMonth,
    date_dimension.DayOfWeekName,
    date_dimension.IsWeekend,
    product.StockCode,
    product.ProductDescription,
    customer.CustomerID,
    customer.IsIdentified AS IsCustomerIdentified,
    country.CountryName,
    transaction_type.TransactionTypeCode,
    transaction_type.TransactionTypeName,
    transaction_type.RevenueEffect,
    fact.UnitPrice,
    fact.Quantity,
    fact.LineAmount,
    CASE
        WHEN transaction_type.TransactionTypeCode = 'SALE'
            THEN fact.LineAmount
        ELSE CONVERT(DECIMAL(19, 2), 0)
    END AS GrossSalesAmount,
    CASE
        WHEN transaction_type.TransactionTypeCode
            = 'CANCELLATION'
            THEN -fact.LineAmount
        ELSE CONVERT(DECIMAL(19, 2), 0)
    END AS CancellationAmount,
    fact.SourcePeriod,
    fact.SourceLineCount,
    fact.DuplicateCandidateLineCount,
    fact.FirstSourceRowNumber,
    fact.HasMultipleSourceLines
FROM dw.FactSales AS fact
INNER JOIN dw.DimDate AS date_dimension
    ON date_dimension.DateKey = fact.DateKey
INNER JOIN dw.DimProduct AS product
    ON product.ProductKey = fact.ProductKey
INNER JOIN dw.DimCustomer AS customer
    ON customer.CustomerKey = fact.CustomerKey
INNER JOIN dw.DimCountry AS country
    ON country.CountryKey = fact.CountryKey
INNER JOIN dw.DimTransactionType AS transaction_type
    ON transaction_type.TransactionTypeKey
        = fact.TransactionTypeKey;
GO

/* =========================================================
   MONTHLY PERFORMANCE
   ========================================================= */

CREATE OR ALTER VIEW dw.vwMonthlySales
AS
SELECT
    date_dimension.CalendarYear,
    date_dimension.CalendarQuarter,
    date_dimension.MonthNumber,
    date_dimension.MonthName,
    date_dimension.YearMonth,
    COUNT(DISTINCT fact.Invoice) AS InvoiceCount,
    SUM(
        CASE
            WHEN transaction_type.TransactionTypeCode
                = 'SALE'
                THEN fact.Quantity
            ELSE 0
        END
    ) AS UnitsSold,
    SUM(
        CASE
            WHEN transaction_type.TransactionTypeCode
                = 'CANCELLATION'
                THEN -fact.Quantity
            ELSE 0
        END
    ) AS UnitsCancelled,
    SUM(
        CASE
            WHEN transaction_type.TransactionTypeCode
                = 'SALE'
                THEN fact.LineAmount
            ELSE 0
        END
    ) AS GrossSalesAmount,
    SUM(
        CASE
            WHEN transaction_type.TransactionTypeCode
                = 'CANCELLATION'
                THEN -fact.LineAmount
            ELSE 0
        END
    ) AS CancellationAmount,
    SUM(fact.LineAmount) AS NetRevenue
FROM dw.FactSales AS fact
INNER JOIN dw.DimDate AS date_dimension
    ON date_dimension.DateKey = fact.DateKey
INNER JOIN dw.DimTransactionType AS transaction_type
    ON transaction_type.TransactionTypeKey
        = fact.TransactionTypeKey
GROUP BY
    date_dimension.CalendarYear,
    date_dimension.CalendarQuarter,
    date_dimension.MonthNumber,
    date_dimension.MonthName,
    date_dimension.YearMonth;
GO

/* =========================================================
   PRODUCT PERFORMANCE
   ========================================================= */

CREATE OR ALTER VIEW dw.vwProductPerformance
AS
SELECT
    product.ProductKey,
    product.StockCode,
    product.ProductDescription,
    COUNT(DISTINCT fact.Invoice) AS InvoiceCount,
    SUM(
        CASE
            WHEN transaction_type.TransactionTypeCode
                = 'SALE'
                THEN fact.Quantity
            ELSE 0
        END
    ) AS UnitsSold,
    SUM(
        CASE
            WHEN transaction_type.TransactionTypeCode
                = 'CANCELLATION'
                THEN -fact.Quantity
            ELSE 0
        END
    ) AS UnitsCancelled,
    SUM(
        CASE
            WHEN transaction_type.TransactionTypeCode
                = 'SALE'
                THEN fact.LineAmount
            ELSE 0
        END
    ) AS GrossSalesAmount,
    SUM(
        CASE
            WHEN transaction_type.TransactionTypeCode
                = 'CANCELLATION'
                THEN -fact.LineAmount
            ELSE 0
        END
    ) AS CancellationAmount,
    SUM(fact.LineAmount) AS NetRevenue
FROM dw.FactSales AS fact
INNER JOIN dw.DimProduct AS product
    ON product.ProductKey = fact.ProductKey
INNER JOIN dw.DimTransactionType AS transaction_type
    ON transaction_type.TransactionTypeKey
        = fact.TransactionTypeKey
GROUP BY
    product.ProductKey,
    product.StockCode,
    product.ProductDescription;
GO

/* =========================================================
   CUSTOMER PERFORMANCE
   ========================================================= */

CREATE OR ALTER VIEW dw.vwCustomerPerformance
AS
SELECT
    customer.CustomerKey,
    customer.CustomerID,
    COUNT(DISTINCT fact.Invoice) AS InvoiceCount,
    MIN(date_dimension.FullDate) AS FirstTransactionDate,
    MAX(date_dimension.FullDate) AS LastTransactionDate,
    SUM(
        CASE
            WHEN transaction_type.TransactionTypeCode
                = 'SALE'
                THEN fact.Quantity
            ELSE 0
        END
    ) AS UnitsPurchased,
    SUM(
        CASE
            WHEN transaction_type.TransactionTypeCode
                = 'CANCELLATION'
                THEN -fact.Quantity
            ELSE 0
        END
    ) AS UnitsCancelled,
    SUM(
        CASE
            WHEN transaction_type.TransactionTypeCode
                = 'SALE'
                THEN fact.LineAmount
            ELSE 0
        END
    ) AS GrossSalesAmount,
    SUM(
        CASE
            WHEN transaction_type.TransactionTypeCode
                = 'CANCELLATION'
                THEN -fact.LineAmount
            ELSE 0
        END
    ) AS CancellationAmount,
    SUM(fact.LineAmount) AS NetRevenue
FROM dw.FactSales AS fact
INNER JOIN dw.DimCustomer AS customer
    ON customer.CustomerKey = fact.CustomerKey
INNER JOIN dw.DimDate AS date_dimension
    ON date_dimension.DateKey = fact.DateKey
INNER JOIN dw.DimTransactionType AS transaction_type
    ON transaction_type.TransactionTypeKey
        = fact.TransactionTypeKey
WHERE customer.IsIdentified = 1
GROUP BY
    customer.CustomerKey,
    customer.CustomerID;
GO

/* =========================================================
   COUNTRY PERFORMANCE
   ========================================================= */

CREATE OR ALTER VIEW dw.vwCountryPerformance
AS
SELECT
    country.CountryKey,
    country.CountryName,
    COUNT(DISTINCT fact.Invoice) AS InvoiceCount,
    COUNT(
        DISTINCT CASE
            WHEN customer.IsIdentified = 1
                THEN customer.CustomerID
            ELSE NULL
        END
    ) AS IdentifiedCustomerCount,
    SUM(
        CASE
            WHEN transaction_type.TransactionTypeCode
                = 'SALE'
                THEN fact.LineAmount
            ELSE 0
        END
    ) AS GrossSalesAmount,
    SUM(
        CASE
            WHEN transaction_type.TransactionTypeCode
                = 'CANCELLATION'
                THEN -fact.LineAmount
            ELSE 0
        END
    ) AS CancellationAmount,
    SUM(fact.LineAmount) AS NetRevenue
FROM dw.FactSales AS fact
INNER JOIN dw.DimCountry AS country
    ON country.CountryKey = fact.CountryKey
INNER JOIN dw.DimCustomer AS customer
    ON customer.CustomerKey = fact.CustomerKey
INNER JOIN dw.DimTransactionType AS transaction_type
    ON transaction_type.TransactionTypeKey
        = fact.TransactionTypeKey
GROUP BY
    country.CountryKey,
    country.CountryName;
GO

PRINT N'Analytics views created successfully';
GO

SELECT
    schema_name(schema_id) AS SchemaName,
    name AS ViewName
FROM sys.views
WHERE schema_name(schema_id) = N'dw'
ORDER BY name;
GO