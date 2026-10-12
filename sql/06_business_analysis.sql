USE OnlineRetailAnalytics;
GO

SET NOCOUNT ON;
GO

/* =========================================================
   1. EXECUTIVE KPIs
   ========================================================= */

SELECT
    SUM(GrossSalesAmount)
        AS GrossSalesAmount,
    SUM(TotalCancellationAmount)
        AS TotalCancellationAmount,
    SUM(OperationalCancellationAmount)
        AS OperationalCancellationAmount,
    SUM(ExceptionalCancellationAmount)
        AS ExceptionalCancellationAmount,
    SUM(ObservedNetRevenue)
        AS ObservedNetRevenue,
    SUM(AdjustedNetRevenue)
        AS AdjustedNetRevenue,
    CAST(
        100.0
        * SUM(OperationalCancellationAmount)
        / NULLIF(SUM(GrossSalesAmount), 0)
        AS DECIMAL(10, 2)
    ) AS OperationalCancellationRate
FROM dw.vwMonthlySalesAdjusted;
GO

/* =========================================================
   2. BUSINESS SCOPE
   ========================================================= */

SELECT
    MIN(FullDate) AS MinimumDate,
    MAX(FullDate) AS MaximumDate,
    COUNT(DISTINCT Invoice) AS TotalInvoices,
    COUNT(
        DISTINCT CASE
            WHEN TransactionTypeCode = 'SALE'
                THEN Invoice
            ELSE NULL
        END
    ) AS SalesInvoices,
    COUNT(
        DISTINCT CASE
            WHEN TransactionTypeCode = 'CANCELLATION'
                THEN Invoice
            ELSE NULL
        END
    ) AS CancellationInvoices,
    COUNT(DISTINCT StockCode) AS Products,
    COUNT(
        DISTINCT CASE
            WHEN IsCustomerIdentified = 1
                THEN CustomerID
            ELSE NULL
        END
    ) AS IdentifiedCustomers,
    COUNT(DISTINCT CountryName) AS Countries
FROM dw.vwSalesDetail;
GO

/* =========================================================
   3. MONTHLY PERFORMANCE
   ========================================================= */

SELECT
    YearMonth,
    InvoiceCount,
    UnitsSold,
    OperationalUnitsCancelled,
    GrossSalesAmount,
    OperationalCancellationAmount,
    ExceptionalCancellationAmount,
    ObservedNetRevenue,
    AdjustedNetRevenue
FROM dw.vwMonthlySalesAdjusted
ORDER BY YearMonth;
GO

/* =========================================================
   4. TOP 10 PRODUCTS BY ADJUSTED NET REVENUE
   ========================================================= */

SELECT TOP (10)
    StockCode,
    ProductDescription,

    SUM(
        CASE
            WHEN TransactionTypeCode = 'SALE'
                THEN Quantity
            ELSE 0
        END
    ) AS UnitsSold,

    SUM(
        CASE
            WHEN TransactionTypeCode = 'CANCELLATION'
                AND ABS(Quantity) < 10000
                THEN -Quantity
            ELSE 0
        END
    ) AS OperationalUnitsCancelled,

    SUM(
        CASE
            WHEN TransactionTypeCode = 'SALE'
                THEN LineAmount
            ELSE 0
        END
    ) AS GrossSalesAmount,

    SUM(
        CASE
            WHEN TransactionTypeCode = 'CANCELLATION'
                AND ABS(Quantity) < 10000
                THEN -LineAmount
            ELSE 0
        END
    ) AS OperationalCancellationAmount,

    SUM(
        CASE
            WHEN TransactionTypeCode = 'CANCELLATION'
                AND ABS(Quantity) >= 10000
                THEN 0
            ELSE LineAmount
        END
    ) AS AdjustedNetRevenue

FROM dw.vwSalesDetail
GROUP BY
    StockCode,
    ProductDescription
ORDER BY
    AdjustedNetRevenue DESC;
GO

/* =========================================================
   5. TOP 10 IDENTIFIED CUSTOMERS
   ========================================================= */

SELECT TOP (10)
    CustomerID,
    COUNT(DISTINCT Invoice) AS InvoiceCount,
    MIN(FullDate) AS FirstTransactionDate,
    MAX(FullDate) AS LastTransactionDate,

    SUM(
        CASE
            WHEN TransactionTypeCode = 'SALE'
                THEN LineAmount
            ELSE 0
        END
    ) AS GrossSalesAmount,

    SUM(
        CASE
            WHEN TransactionTypeCode = 'CANCELLATION'
                AND ABS(Quantity) < 10000
                THEN -LineAmount
            ELSE 0
        END
    ) AS OperationalCancellationAmount,

    SUM(
        CASE
            WHEN TransactionTypeCode = 'CANCELLATION'
                AND ABS(Quantity) >= 10000
                THEN 0
            ELSE LineAmount
        END
    ) AS AdjustedNetRevenue

FROM dw.vwSalesDetail
WHERE IsCustomerIdentified = 1
GROUP BY CustomerID
ORDER BY AdjustedNetRevenue DESC;
GO

/* =========================================================
   6. COUNTRY PERFORMANCE
   ========================================================= */

SELECT
    CountryName,
    COUNT(DISTINCT Invoice) AS InvoiceCount,

    COUNT(
        DISTINCT CASE
            WHEN IsCustomerIdentified = 1
                THEN CustomerID
            ELSE NULL
        END
    ) AS IdentifiedCustomers,

    SUM(
        CASE
            WHEN TransactionTypeCode = 'SALE'
                THEN LineAmount
            ELSE 0
        END
    ) AS GrossSalesAmount,

    SUM(
        CASE
            WHEN TransactionTypeCode = 'CANCELLATION'
                AND ABS(Quantity) < 10000
                THEN -LineAmount
            ELSE 0
        END
    ) AS OperationalCancellationAmount,

    SUM(
        CASE
            WHEN TransactionTypeCode = 'CANCELLATION'
                AND ABS(Quantity) >= 10000
                THEN 0
            ELSE LineAmount
        END
    ) AS AdjustedNetRevenue

FROM dw.vwSalesDetail
GROUP BY CountryName
ORDER BY AdjustedNetRevenue DESC;
GO

/* =========================================================
   7. CUSTOMER IDENTIFICATION COVERAGE
   ========================================================= */

SELECT
    CASE
        WHEN IsCustomerIdentified = 1
            THEN 'Identified customer'
        ELSE 'Missing customer ID'
    END AS CustomerIdentificationStatus,

    COUNT(*) AS AnalyticalRows,
    COUNT(DISTINCT Invoice) AS InvoiceCount,

    SUM(
        CASE
            WHEN TransactionTypeCode = 'CANCELLATION'
                AND ABS(Quantity) >= 10000
                THEN 0
            ELSE LineAmount
        END
    ) AS AdjustedNetRevenue,

    CAST(
        100.0 * COUNT(*)
        / SUM(COUNT(*)) OVER ()
        AS DECIMAL(10, 2)
    ) AS PercentageOfRows

FROM dw.vwSalesDetail
GROUP BY IsCustomerIdentified
ORDER BY IsCustomerIdentified DESC;
GO

/* =========================================================
   8. DAY-OF-WEEK PERFORMANCE
   ========================================================= */

SELECT
    DayOfWeekName,
    MIN(
        CASE DayOfWeekName
            WHEN 'Monday' THEN 1
            WHEN 'Tuesday' THEN 2
            WHEN 'Wednesday' THEN 3
            WHEN 'Thursday' THEN 4
            WHEN 'Friday' THEN 5
            WHEN 'Saturday' THEN 6
            WHEN 'Sunday' THEN 7
        END
    ) AS DayOrder,

    COUNT(DISTINCT Invoice) AS InvoiceCount,

    SUM(
        CASE
            WHEN TransactionTypeCode = 'CANCELLATION'
                AND ABS(Quantity) >= 10000
                THEN 0
            ELSE LineAmount
        END
    ) AS AdjustedNetRevenue

FROM dw.vwSalesDetail
GROUP BY DayOfWeekName
ORDER BY DayOrder;
GO