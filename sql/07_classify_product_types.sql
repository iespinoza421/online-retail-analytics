USE OnlineRetailAnalytics;
GO

SET ANSI_NULLS ON;
SET QUOTED_IDENTIFIER ON;
SET ANSI_PADDING ON;
SET ANSI_WARNINGS ON;
SET ARITHABORT ON;
SET CONCAT_NULL_YIELDS_NULL ON;
SET NUMERIC_ROUNDABORT OFF;
SET NOCOUNT ON;
GO

IF COL_LENGTH(
    N'dw.DimProduct',
    N'ProductType'
) IS NULL
BEGIN
    ALTER TABLE dw.DimProduct
    ADD ProductType AS
    (
        CONVERT(
            VARCHAR(30),
            CASE
                WHEN StockCode IN (
                    N'DOT',
                    N'POST',
                    N'C2'
                )
                    THEN 'SHIPPING'

                WHEN StockCode IN (
                    N'M',
                    N'ADJUST'
                )
                    THEN 'MANUAL_ADJUSTMENT'

                WHEN StockCode IN (
                    N'BANK CHARGES',
                    N'CRUK',
                    N'AMAZONFEE'
                )
                    THEN 'FEE'

                WHEN StockCode LIKE N'gift[_]%'
                    THEN 'GIFT_VOUCHER'

                WHEN StockCode = N'D'
                    THEN 'DISCOUNT'

                ELSE 'MERCHANDISE'
            END
        )
    ) PERSISTED;

    PRINT N'Added ProductType to dw.DimProduct';
END;
GO

CREATE OR ALTER VIEW dw.vwMerchandiseProductPerformance
AS
SELECT
    product.ProductKey,
    product.StockCode,
    product.ProductDescription,
    product.ProductType,

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
                THEN 0
            ELSE fact.LineAmount
        END
    ) AS AdjustedNetRevenue

FROM dw.FactSales AS fact
INNER JOIN dw.DimProduct AS product
    ON product.ProductKey = fact.ProductKey
INNER JOIN dw.DimTransactionType AS transaction_type
    ON transaction_type.TransactionTypeKey
        = fact.TransactionTypeKey
WHERE product.ProductType = 'MERCHANDISE'
GROUP BY
    product.ProductKey,
    product.StockCode,
    product.ProductDescription,
    product.ProductType;
GO

CREATE OR ALTER VIEW dw.vwNonMerchandisePerformance
AS
SELECT
    product.ProductType,
    product.StockCode,
    product.ProductDescription,

    COUNT(DISTINCT fact.Invoice) AS InvoiceCount,

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
                THEN 0
            ELSE fact.LineAmount
        END
    ) AS AdjustedNetRevenue

FROM dw.FactSales AS fact
INNER JOIN dw.DimProduct AS product
    ON product.ProductKey = fact.ProductKey
INNER JOIN dw.DimTransactionType AS transaction_type
    ON transaction_type.TransactionTypeKey
        = fact.TransactionTypeKey
WHERE product.ProductType <> 'MERCHANDISE'
GROUP BY
    product.ProductType,
    product.StockCode,
    product.ProductDescription;
GO

PRINT N'Product-type classification created successfully';
GO