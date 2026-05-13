/*
================================================================================
Script : 06_analytical_queries.sql
Purpose: Ten optimized analytical queries against the gold star schema.
Notes:   Demonstration use of READ UNCOMMITTED isolation via NOLOCK hints and
         nonclustered index hints (see 05_indexes_and_views.sql for index names).
         Run after ETL load (sp_load_gold).
================================================================================
*/

USE [DW_AdventureWorks];
GO

SET NOCOUNT ON;

/* ------------------------------------------------------------------ */
/* 1. Total revenue by year and region                               */
/* ------------------------------------------------------------------ */
SELECT
    dd.[CalendarYear],
    dt.[RegionGroup],
    Revenue = SUM(f.[LineTotal])
FROM [gold].[FactSales] AS f WITH (NOLOCK, INDEX([IX_FactSales_OrderDateKey]))
INNER JOIN [gold].[DimDate] AS dd WITH (NOLOCK) ON f.[OrderDateKey] = dd.[DateKey]
INNER JOIN [gold].[DimTerritory] AS dt WITH (NOLOCK) ON f.[TerritoryKey] = dt.[TerritoryKey]
GROUP BY dd.[CalendarYear], dt.[RegionGroup]
ORDER BY dd.[CalendarYear], Revenue DESC;
GO

/* ------------------------------------------------------------------ */
/* 2. Top 10 products by revenue                                      */
/* ------------------------------------------------------------------ */
SELECT TOP (10)
    dp.[ProductName],
    dp.[CategoryName],
    Revenue = SUM(f.[LineTotal]),
    Units = SUM(f.[OrderQuantity])
FROM [gold].[FactSales] AS f WITH (NOLOCK, INDEX([IX_FactSales_ProductKey]))
INNER JOIN [gold].[DimProduct] AS dp WITH (NOLOCK) ON f.[ProductKey] = dp.[ProductKey] AND dp.[IsCurrent] = 1
GROUP BY dp.[ProductName], dp.[CategoryName]
ORDER BY Revenue DESC;
GO

/* ------------------------------------------------------------------ */
/* 3. Monthly sales trend (last 2 calendar years)                    */
/* ------------------------------------------------------------------ */
DECLARE @EndYear int = YEAR(GETDATE());
DECLARE @StartYear int = @EndYear - 1;

SELECT
    CalendarMonthLabel = CONCAT(dd.[CalendarYear], N'-', RIGHT(N'0' + CAST(dd.[CalendarMonth] AS nvarchar(2)), 2)),
    Revenue = SUM(f.[LineTotal]),
    GrossMargin = SUM(f.[GrossMargin])
FROM [gold].[FactSales] AS f WITH (NOLOCK, INDEX([IX_FactSales_Date_Product]))
INNER JOIN [gold].[DimDate] AS dd WITH (NOLOCK) ON f.[OrderDateKey] = dd.[DateKey]
WHERE dd.[CalendarYear] BETWEEN @StartYear AND @EndYear
GROUP BY dd.[CalendarYear], dd.[CalendarMonth]
ORDER BY dd.[CalendarYear], dd.[CalendarMonth];
GO

/* ------------------------------------------------------------------ */
/* 4. Customer segmentation by total spend (tiers)                   */
/* ------------------------------------------------------------------ */
WITH spend AS (
    SELECT
        dc.[CustomerID],
        cur.[CustomerName],
        TotalSpend = SUM(f.[LineTotal])
    FROM [gold].[FactSales] AS f WITH (NOLOCK, INDEX([IX_FactSales_CustomerKey]))
    INNER JOIN [gold].[DimCustomer] AS dc WITH (NOLOCK) ON f.[CustomerKey] = dc.[CustomerKey]
    INNER JOIN [gold].[DimCustomer] AS cur WITH (NOLOCK)
        ON dc.[CustomerID] = cur.[CustomerID] AND cur.[IsCurrent] = 1
    GROUP BY dc.[CustomerID], cur.[CustomerName]
)
SELECT
    SpendTier = CASE
        WHEN TotalSpend >= 100000 THEN N'Platinum'
        WHEN TotalSpend >= 25000 THEN N'Gold'
        WHEN TotalSpend >= 5000 THEN N'Silver'
        ELSE N'Bronze'
    END,
    Customers = COUNT(*),
    TierRevenue = SUM(TotalSpend)
FROM spend
GROUP BY CASE
        WHEN TotalSpend >= 100000 THEN N'Platinum'
        WHEN TotalSpend >= 25000 THEN N'Gold'
        WHEN TotalSpend >= 5000 THEN N'Silver'
        ELSE N'Bronze'
    END
ORDER BY TierRevenue DESC;
GO

/* ------------------------------------------------------------------ */
/* 5. Sales rep performance vs quota                                  */
/* ------------------------------------------------------------------ */
SELECT
    dsp.[BusinessEntityID],
    dsp.[TerritoryName],
    dsp.[SalesQuota],
    Revenue = SUM(f.[LineTotal]),
    AttainmentPct = CASE WHEN dsp.[SalesQuota] IS NULL OR dsp.[SalesQuota] = 0 THEN NULL
                         ELSE SUM(f.[LineTotal]) / dsp.[SalesQuota] END
FROM [gold].[DimSalesPerson] AS dsp WITH (NOLOCK)
LEFT JOIN [gold].[FactSales] AS f WITH (NOLOCK, INDEX([IX_FactSales_SalesPersonKey]))
    ON f.[SalesPersonKey] = dsp.[SalesPersonKey]
WHERE dsp.[BusinessEntityID] <> -1
GROUP BY dsp.[BusinessEntityID], dsp.[TerritoryName], dsp.[SalesQuota]
ORDER BY Revenue DESC;
GO

/* ------------------------------------------------------------------ */
/* 6. Product category revenue contribution (%)                      */
/* ------------------------------------------------------------------ */
WITH cat AS (
    SELECT
        dp.[CategoryName],
        Revenue = SUM(f.[LineTotal])
    FROM [gold].[FactSales] AS f WITH (NOLOCK)
    INNER JOIN [gold].[DimProduct] AS dp WITH (NOLOCK) ON f.[ProductKey] = dp.[ProductKey] AND dp.[IsCurrent] = 1
    GROUP BY dp.[CategoryName]
),
tot AS (SELECT TotalRev = SUM(Revenue) FROM cat)
SELECT
    c.[CategoryName],
    c.[Revenue],
    PctOfTotal = c.[Revenue] / NULLIF(t.[TotalRev], 0)
FROM cat AS c
CROSS JOIN tot AS t
ORDER BY c.[Revenue] DESC;
GO

/* ------------------------------------------------------------------ */
/* 7. Average order value by territory                               */
/* ------------------------------------------------------------------ */
SELECT
    dt.[TerritoryName],
    dt.[RegionGroup],
    OrderCount = COUNT(DISTINCT f.[SalesOrderID]),
    Revenue = SUM(f.[LineTotal]),
    AvgOrderValue = SUM(f.[LineTotal]) / NULLIF(COUNT(DISTINCT f.[SalesOrderID]), 0)
FROM [gold].[FactSales] AS f WITH (NOLOCK, INDEX([IX_FactSales_TerritoryKey]))
INNER JOIN [gold].[DimTerritory] AS dt WITH (NOLOCK) ON f.[TerritoryKey] = dt.[TerritoryKey]
GROUP BY dt.[TerritoryName], dt.[RegionGroup]
ORDER BY AvgOrderValue DESC;
GO

/* ------------------------------------------------------------------ */
/* 8. Year-over-year growth rate by product category                 */
/* ------------------------------------------------------------------ */
WITH y AS (
    SELECT
        dd.[CalendarYear],
        dp.[CategoryName],
        Revenue = SUM(f.[LineTotal])
    FROM [gold].[FactSales] AS f WITH (NOLOCK, INDEX([IX_FactSales_Date_Product]))
    INNER JOIN [gold].[DimDate] AS dd WITH (NOLOCK) ON f.[OrderDateKey] = dd.[DateKey]
    INNER JOIN [gold].[DimProduct] AS dp WITH (NOLOCK) ON f.[ProductKey] = dp.[ProductKey] AND dp.[IsCurrent] = 1
    GROUP BY dd.[CalendarYear], dp.[CategoryName]
)
SELECT
    cur.[CategoryName],
    cur.[CalendarYear] AS [Year],
    cur.[Revenue] AS [RevenueCurrentYear],
    prev.[Revenue] AS [RevenuePriorYear],
    YoYGrowthPct = CASE WHEN prev.[Revenue] IS NULL OR prev.[Revenue] = 0 THEN NULL
                        ELSE (cur.[Revenue] - prev.[Revenue]) / prev.[Revenue] END
FROM y AS cur
LEFT JOIN y AS prev
    ON cur.[CategoryName] = prev.[CategoryName]
   AND prev.[CalendarYear] = cur.[CalendarYear] - 1
ORDER BY cur.[CategoryName], cur.[CalendarYear];
GO

/* ------------------------------------------------------------------ */
/* 9. Customer retention rate by year (repeat purchase next year)    */
/* ------------------------------------------------------------------ */
WITH custyear AS (
    SELECT DISTINCT
        dc.[CustomerID],
        dd.[CalendarYear]
    FROM [gold].[FactSales] AS f WITH (NOLOCK, INDEX([IX_FactSales_CustomerKey]))
    INNER JOIN [gold].[DimCustomer] AS dc WITH (NOLOCK) ON f.[CustomerKey] = dc.[CustomerKey]
    INNER JOIN [gold].[DimDate] AS dd WITH (NOLOCK) ON f.[OrderDateKey] = dd.[DateKey]
),
pairs AS (
    SELECT
        cy.[CalendarYear] AS [CohortYear],
        Retained = CASE WHEN EXISTS (
            SELECT 1 FROM custyear AS nxt
            WHERE nxt.[CustomerID] = cy.[CustomerID]
              AND nxt.[CalendarYear] = cy.[CalendarYear] + 1
        ) THEN 1 ELSE 0 END
    FROM custyear AS cy
)
SELECT
    [CohortYear],
    Customers = COUNT(*),
    RetainedCustomers = SUM(Retained),
    RetentionRate = CAST(SUM(Retained) AS float) / NULLIF(COUNT(*), 0)
FROM pairs
GROUP BY [CohortYear]
ORDER BY [CohortYear];
GO

/* ------------------------------------------------------------------ */
/* 10. Gross margin by product subcategory                           */
/* ------------------------------------------------------------------ */
SELECT
    dp.[CategoryName],
    dp.[SubcategoryName],
    Revenue = SUM(f.[LineTotal]),
    GrossMargin = SUM(f.[GrossMargin]),
    MarginPct = CASE WHEN SUM(f.[LineTotal]) = 0 THEN NULL
                     ELSE SUM(f.[GrossMargin]) / SUM(f.[LineTotal]) END
FROM [gold].[FactSales] AS f WITH (NOLOCK, INDEX([IX_FactSales_ProductKey]))
INNER JOIN [gold].[DimProduct] AS dp WITH (NOLOCK) ON f.[ProductKey] = dp.[ProductKey] AND dp.[IsCurrent] = 1
GROUP BY dp.[CategoryName], dp.[SubcategoryName]
ORDER BY GrossMargin DESC;
GO
