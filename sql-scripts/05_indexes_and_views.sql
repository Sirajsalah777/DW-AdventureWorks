/*
================================================================================
Script : 05_indexes_and_views.sql
Purpose: Nonclustered indexes on FactSales foreign keys (rowstore NC indexes on
         clustered columnstore fact) and analytical views for sales reporting.
Prereq: gold.FactSales populated (03 + 04).
================================================================================
*/

USE [DW_AdventureWorks];
GO

SET NOCOUNT ON;
GO

/* Filtered unique: one current row per natural product key */
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE name = N'UX_gold_DimProduct_Current' AND object_id = OBJECT_ID(N'gold.DimProduct')
)
BEGIN
    CREATE UNIQUE NONCLUSTERED INDEX [UX_gold_DimProduct_Current]
        ON [gold].[DimProduct] ([ProductID])
        WHERE [IsCurrent] = 1;
END
GO

/* Nonclustered indexes on fact FK columns (supported on columnstore fact table) */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_FactSales_OrderDateKey' AND object_id = OBJECT_ID(N'gold.FactSales'))
    CREATE NONCLUSTERED INDEX [IX_FactSales_OrderDateKey] ON [gold].[FactSales] ([OrderDateKey]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_FactSales_CustomerKey' AND object_id = OBJECT_ID(N'gold.FactSales'))
    CREATE NONCLUSTERED INDEX [IX_FactSales_CustomerKey] ON [gold].[FactSales] ([CustomerKey]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_FactSales_ProductKey' AND object_id = OBJECT_ID(N'gold.FactSales'))
    CREATE NONCLUSTERED INDEX [IX_FactSales_ProductKey] ON [gold].[FactSales] ([ProductKey]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_FactSales_TerritoryKey' AND object_id = OBJECT_ID(N'gold.FactSales'))
    CREATE NONCLUSTERED INDEX [IX_FactSales_TerritoryKey] ON [gold].[FactSales] ([TerritoryKey]);
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_FactSales_SalesPersonKey' AND object_id = OBJECT_ID(N'gold.FactSales'))
    CREATE NONCLUSTERED INDEX [IX_FactSales_SalesPersonKey] ON [gold].[FactSales] ([SalesPersonKey]);
GO

/* Composite for common drill patterns */
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = N'IX_FactSales_Date_Product' AND object_id = OBJECT_ID(N'gold.FactSales'))
    CREATE NONCLUSTERED INDEX [IX_FactSales_Date_Product]
        ON [gold].[FactSales] ([OrderDateKey], [ProductKey])
        INCLUDE ([LineTotal], [OrderQuantity], [GrossMargin]);
GO

/* ------------------------------------------------------------------ */
/* Views                                                              */
/* ------------------------------------------------------------------ */
IF OBJECT_ID(N'gold.vw_SalesByRegion', N'V') IS NOT NULL DROP VIEW [gold].[vw_SalesByRegion];
GO

CREATE VIEW [gold].[vw_SalesByRegion]
AS
SELECT
    dt.[RegionGroup],
    dt.[CountryName],
    dt.[TerritoryName],
    SUM(f.[LineTotal]) AS [Revenue],
    SUM(f.[OrderQuantity]) AS [UnitsSold],
    SUM(f.[GrossMargin]) AS [GrossMargin],
    COUNT_BIG(*) AS [LineCount]
FROM [gold].[FactSales] AS f
INNER JOIN [gold].[DimTerritory] AS dt ON f.[TerritoryKey] = dt.[TerritoryKey]
GROUP BY dt.[RegionGroup], dt.[CountryName], dt.[TerritoryName];
GO

IF OBJECT_ID(N'gold.vw_TopProducts', N'V') IS NOT NULL DROP VIEW [gold].[vw_TopProducts];
GO

CREATE VIEW [gold].[vw_TopProducts]
AS
SELECT TOP (100)
    dp.[CategoryName],
    dp.[SubcategoryName],
    dp.[ProductName],
    SUM(f.[LineTotal]) AS [Revenue],
    SUM(f.[OrderQuantity]) AS [UnitsSold],
    SUM(f.[GrossMargin]) AS [GrossMargin]
FROM [gold].[FactSales] AS f
INNER JOIN [gold].[DimProduct] AS dp ON f.[ProductKey] = dp.[ProductKey] AND dp.[IsCurrent] = 1
GROUP BY dp.[CategoryName], dp.[SubcategoryName], dp.[ProductName]
ORDER BY SUM(f.[LineTotal]) DESC;
GO

IF OBJECT_ID(N'gold.vw_CustomerSegmentation', N'V') IS NOT NULL DROP VIEW [gold].[vw_CustomerSegmentation];
GO

CREATE VIEW [gold].[vw_CustomerSegmentation]
AS
WITH base AS (
    SELECT
        dc.[CustomerID],
        RecencyDays = DATEDIFF(DAY, MAX(dd.[FullDate]), CAST(GETDATE() AS date)),
        Frequency = COUNT(DISTINCT f.[SalesOrderID]),
        Monetary = SUM(f.[LineTotal])
    FROM [gold].[FactSales] AS f
    INNER JOIN [gold].[DimDate] AS dd ON f.[OrderDateKey] = dd.[DateKey]
    INNER JOIN [gold].[DimCustomer] AS dc ON f.[CustomerKey] = dc.[CustomerKey]
    GROUP BY dc.[CustomerID]
),
scored AS (
    SELECT
        *,
        NTILE(5) OVER (ORDER BY RecencyDays ASC) AS R_Score,
        NTILE(5) OVER (ORDER BY Frequency DESC) AS F_Score,
        NTILE(5) OVER (ORDER BY Monetary DESC) AS M_Score
    FROM base
)
SELECT
    cur.[CustomerKey],
    s.[CustomerID],
    cur.[CustomerName],
    cur.[CountryName],
    s.[RecencyDays],
    s.[Frequency],
    s.[Monetary],
    s.[R_Score],
    s.[F_Score],
    s.[M_Score],
    Segment = CASE
        WHEN s.[R_Score] >= 4 AND s.[F_Score] >= 4 THEN N'Champions'
        WHEN s.[R_Score] >= 3 AND s.[F_Score] >= 3 THEN N'Loyal'
        WHEN s.[R_Score] >= 4 AND s.[M_Score] <= 2 THEN N'At risk'
        WHEN s.[R_Score] <= 2 AND s.[M_Score] >= 4 THEN N'Cannot lose them'
        ELSE N'Standard'
    END
FROM scored AS s
INNER JOIN [gold].[DimCustomer] AS cur
    ON s.[CustomerID] = cur.[CustomerID] AND cur.[IsCurrent] = 1;
GO

IF OBJECT_ID(N'gold.vw_SalesRepPerformance', N'V') IS NOT NULL DROP VIEW [gold].[vw_SalesRepPerformance];
GO

CREATE VIEW [gold].[vw_SalesRepPerformance]
AS
SELECT
    dsp.[SalesPersonKey],
    dsp.[BusinessEntityID],
    dsp.[TerritoryName],
    dsp.[SalesQuota],
    RevenueYTD = SUM(CASE WHEN dd.[CalendarYear] = YEAR(GETDATE()) THEN f.[LineTotal] ELSE 0 END),
    RevenueAll = SUM(f.[LineTotal]),
    Orders = COUNT(DISTINCT f.[SalesOrderID]),
    MarginPct = CASE WHEN SUM(f.[LineTotal]) = 0 THEN NULL
                     ELSE SUM(f.[GrossMargin]) / SUM(f.[LineTotal]) END
FROM [gold].[DimSalesPerson] AS dsp
LEFT JOIN [gold].[FactSales] AS f ON f.[SalesPersonKey] = dsp.[SalesPersonKey]
LEFT JOIN [gold].[DimDate] AS dd ON f.[OrderDateKey] = dd.[DateKey]
WHERE dsp.[BusinessEntityID] <> -1
GROUP BY dsp.[SalesPersonKey], dsp.[BusinessEntityID], dsp.[TerritoryName], dsp.[SalesQuota];
GO

IF OBJECT_ID(N'gold.vw_MonthlySalesTrend', N'V') IS NOT NULL DROP VIEW [gold].[vw_MonthlySalesTrend];
GO

CREATE VIEW [gold].[vw_MonthlySalesTrend]
AS
SELECT
    dd.[CalendarYear],
    dd.[CalendarMonth],
    CalendarMonthLabel = CONCAT(dd.[CalendarYear], N'-', RIGHT(N'0' + CAST(dd.[CalendarMonth] AS nvarchar(2)), 2)),
    SUM(f.[LineTotal]) AS [Revenue],
    SUM(f.[GrossMargin]) AS [GrossMargin],
    COUNT(DISTINCT f.[SalesOrderID]) AS [OrderCount],
    COUNT(DISTINCT f.[CustomerKey]) AS [CustomerCount]
FROM [gold].[FactSales] AS f
INNER JOIN [gold].[DimDate] AS dd ON f.[OrderDateKey] = dd.[DateKey]
GROUP BY dd.[CalendarYear], dd.[CalendarMonth];
GO

PRINT N'Indexes and gold analytical views created.';
GO
