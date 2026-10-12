USE OnlineRetailAnalytics;
GO

SET NOCOUNT ON;
SET XACT_ABORT ON;
GO

IF EXISTS
(
    SELECT 1
    FROM dw.FactSales
    WHERE DateKey = 0
)
BEGIN
    THROW 50005,
        'DateKey 0 is referenced by FactSales.',
        1;
END;
GO

DELETE FROM dw.DimDate
WHERE DateKey = 0;
GO

PRINT N'Unknown date member removed successfully';
GO

SELECT
    COUNT(*) AS DateCount,
    MIN(FullDate) AS MinimumDate,
    MAX(FullDate) AS MaximumDate
FROM dw.DimDate;
GO