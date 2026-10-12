USE OnlineRetailAnalytics;
GO

SET NOCOUNT ON;
GO

CREATE OR ALTER VIEW dw.vwCancellationAnalysis
AS
SELECT
    fact.SalesKey,
    fact.Invoice,
    fact.InvoiceDateTime,
    customer.CustomerID,
    product.StockCode,
    product.ProductDescription,
    country.CountryName,
    fact.Quantity,
    fact.UnitPrice,
    fact.LineAmount,
    -fact.LineAmount AS CancellationAmount,
    CASE
        WHEN ABS(fact.Quantity) >= 10000
            THEN CAST(1 AS BIT)
        ELSE CAST(0 AS BIT)
    END AS IsExceptionalCancellation,
    CASE
        WHEN EXISTS
        (
            SELECT 1
            FROM dw.FactSales AS possible_sale
            INNER JOIN dw.DimTransactionType
                AS possible_sale_type
                ON possible_sale_type.TransactionTypeKey
                    = possible_sale.TransactionTypeKey
            WHERE
                possible_sale_type.TransactionTypeCode
                    = 'SALE'
                AND possible_sale.ProductKey
                    = fact.ProductKey
                AND possible_sale.CustomerKey
                    = fact.CustomerKey
                AND possible_sale.UnitPrice
                    = fact.UnitPrice
                AND possible_sale.Quantity
                    = -fact.Quantity
                AND possible_sale.InvoiceDateTime
                    <= fact.InvoiceDateTime
        )
            THEN CAST(1 AS BIT)
        ELSE CAST(0 AS BIT)
    END AS HasMatchingSaleInDataset
FROM dw.FactSales AS fact
INNER JOIN dw.DimProduct AS product
    ON product.ProductKey = fact.ProductKey
INNER JOIN dw.DimCustomer AS customer
    ON customer.CustomerKey = fact.CustomerKey
INNER JOIN dw.DimCountry AS country
    ON country.CountryKey = fact.CountryKey
INNER JOIN dw.DimTransactionType AS transaction_type
    ON transaction_type.TransactionTypeKey
        = fact.TransactionTypeKey
WHERE
    transaction_type.TransactionTypeCode
        = 'CANCELLATION';
GO

CREATE OR ALTER VIEW dw.vwMonthlySalesAdjusted
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
    ) AS TotalUnitsCancelled,

    SUM(
        CASE
            WHEN transaction_type.TransactionTypeCode
                = 'CANCELLATION'
                AND ABS(fact.Quantity) < 10000
                THEN -fact.Quantity
            ELSE 0
        END
    ) AS OperationalUnitsCancelled,

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
    ) AS TotalCancellationAmount,

    SUM(
        CASE
            WHEN transaction_type.TransactionTypeCode
                = 'CANCELLATION'
                AND ABS(fact.Quantity) < 10000
                THEN -fact.LineAmount
            ELSE 0
        END
    ) AS OperationalCancellationAmount,

    SUM(
        CASE
            WHEN transaction_type.TransactionTypeCode
                = 'CANCELLATION'
                AND ABS(fact.Quantity) >= 10000
                THEN -fact.LineAmount
            ELSE 0
        END
    ) AS ExceptionalCancellationAmount,

    SUM(fact.LineAmount) AS ObservedNetRevenue,

    SUM(
        CASE
            WHEN transaction_type.TransactionTypeCode
                = 'CANCELLATION'
                AND ABS(fact.Quantity) >= 10000
                THEN 0
            ELSE fact.LineAmount
        END
    ) AS AdjustedNetRevenue
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

PRINT N'Exception-analysis views created successfully';
GO