/*
================================================================================
Manual steps equivalent to dbo.sp_load_gold — run each block separately in order.
Database: DW_AdventureWorks
Adjust @SourceDatabase if your OLTP database name differs.
================================================================================
*/

USE [DW_AdventureWorks];
GO

/* ------------------------------------------------------------------ */
/* PREREQ: clear fact then dimensions (respect FK on FactSales)      */
/* ------------------------------------------------------------------ */
DELETE FROM [gold].[FactSales];
DELETE FROM [gold].[DimCustomer];
DBCC CHECKIDENT ('[gold].[DimCustomer]', RESEED, 0);
DELETE FROM [gold].[DimProduct];
DBCC CHECKIDENT ('[gold].[DimProduct]', RESEED, 0);
DELETE FROM [gold].[DimTerritory];
DBCC CHECKIDENT ('[gold].[DimTerritory]', RESEED, 0);
DELETE FROM [gold].[DimSalesPerson];
DBCC CHECKIDENT ('[gold].[DimSalesPerson]', RESEED, 0);
GO

/* ------------------------------------------------------------------ */
/* 1) DimDate — populated by procedure (MERGE), not INSERT in sp_load_gold */
/* ------------------------------------------------------------------ */
EXEC [dbo].[sp_populate_dim_date] @StartYear = 2010, @EndYear = 2030;
GO

/* ------------------------------------------------------------------ */
/* 2) DimTerritory — sentinel row, then territories from silver        */
/* ------------------------------------------------------------------ */
INSERT INTO [gold].[DimTerritory] (
    [TerritoryID], [TerritoryName], [CountryRegionCode], [CountryName], [RegionGroup]
)
VALUES (-1, N'Unknown', N'UNK', N'Unknown', N'Unknown');
GO

INSERT INTO [gold].[DimTerritory] (
    [TerritoryID], [TerritoryName], [CountryRegionCode], [CountryName], [RegionGroup]
)
SELECT
    t.[TerritoryID], t.[TerritoryName], t.[CountryRegionCode], cr.[Name], t.[RegionGroup]
FROM [silver].[Territory] AS t
LEFT JOIN [bronze].[CountryRegion] AS cr ON t.[CountryRegionCode] = cr.[CountryRegionCode];
GO

/* ------------------------------------------------------------------ */
/* 3) DimSalesPerson — unknown member first, then active salespeople */
/* ------------------------------------------------------------------ */
INSERT INTO [gold].[DimSalesPerson] (
    [BusinessEntityID], [SalesQuota], [Bonus], [CommissionPct], [HireDate], [TerritoryID], [TerritoryName]
)
VALUES (-1, NULL, 0, 0, NULL, NULL, N'Unknown / Not assigned');
GO

DECLARE @SourceDatabase sysname = N'AdventureWorks2022';
DECLARE @dbq nvarchar(260) = QUOTENAME(@SourceDatabase);
DECLARE @sql nvarchar(max) = N'
INSERT INTO [gold].[DimSalesPerson] ([BusinessEntityID], [SalesQuota], [Bonus], [CommissionPct], [HireDate], [TerritoryID], [TerritoryName])
SELECT sp.[BusinessEntityID], sp.[SalesQuota], sp.[Bonus], sp.[CommissionPct], CAST(e.[HireDate] AS date),
       sp.[TerritoryID], ter.[Name]
FROM [silver].[SalesPerson] AS sp
LEFT JOIN ' + @dbq + N'.[HumanResources].[Employee] AS e ON sp.[BusinessEntityID] = e.[BusinessEntityID]
LEFT JOIN ' + @dbq + N'.[Sales].[SalesTerritory] AS ter ON sp.[TerritoryID] = ter.[TerritoryID];';

EXEC sp_executesql @sql;
GO

/* ------------------------------------------------------------------ */
/* 4) DimProduct — from silver (current product rows)                */
/* ------------------------------------------------------------------ */
INSERT INTO [gold].[DimProduct] (
    [ProductID], [ProductName], [ProductNumber], [Color], [ProductCategoryID], [CategoryName],
    [ProductSubcategoryID], [SubcategoryName], [ListPrice], [StandardCost], [ValidFrom], [ValidTo], [IsCurrent]
)
SELECT
    p.[ProductID], p.[ProductName], p.[ProductNumber], p.[Color], p.[ProductCategoryID], p.[CategoryName],
    p.[ProductSubcategoryID], p.[SubcategoryName], p.[ListPrice], p.[StandardCost], p.[valid_from], p.[valid_to], 1
FROM [silver].[Product] AS p;
GO

/* ------------------------------------------------------------------ */
/* 5) DimCustomer — all SCD versions from silver                       */
/* ------------------------------------------------------------------ */
INSERT INTO [gold].[DimCustomer] (
    [CustomerID], [AccountNumber], [PersonType], [CustomerName], [EmailPromotion], [TerritoryID], [TerritoryName],
    [CountryRegionCode], [CountryName], [SilverCustomerSK], [ValidFrom], [ValidTo], [IsCurrent]
)
SELECT
    c.[CustomerID], c.[AccountNumber], c.[PersonType],
    LTRIM(RTRIM(CONCAT(c.[FirstName], N' ', c.[LastName]))),
    c.[EmailPromotion], c.[TerritoryID], t.[TerritoryName], c.[CountryRegionCode], c.[CountryName],
    c.[SilverCustomerSK], c.[valid_from], c.[valid_to], CASE WHEN c.[is_active] = 1 THEN 1 ELSE 0 END
FROM [silver].[Customer] AS c
LEFT JOIN [silver].[Territory] AS t ON c.[TerritoryID] = t.[TerritoryID];
GO

/* ------------------------------------------------------------------ */
/* 6) FactSales — requires DimDate + all dimension keys + @UnknownSP */
/* ------------------------------------------------------------------ */
DECLARE @UnknownSP int = (SELECT [SalesPersonKey] FROM [gold].[DimSalesPerson] WHERE [BusinessEntityID] = -1);

INSERT INTO [gold].[FactSales] (
    [SalesOrderID], [SalesOrderDetailID], [OrderDateKey], [CustomerKey], [ProductKey], [TerritoryKey], [SalesPersonKey],
    [OrderQuantity], [UnitPrice], [UnitPriceDiscount], [LineTotal], [StandardCost], [TaxAmt], [Freight]
)
SELECT
    so.[SalesOrderID], so.[SalesOrderDetailID],
    (YEAR(CAST(so.[OrderDate] AS date)) * 10000) + (MONTH(CAST(so.[OrderDate] AS date)) * 100) + DAY(CAST(so.[OrderDate] AS date)),
    dc.[CustomerKey], dp.[ProductKey],
    COALESCE(dt.[TerritoryKey], dtu.[TerritoryKey]),
    CASE WHEN so.[SalesPersonID] IS NULL THEN @UnknownSP ELSE COALESCE(dsp.[SalesPersonKey], @UnknownSP) END,
    CAST(so.[OrderQty] AS int), so.[UnitPrice], so.[UnitPriceDiscount], so.[LineTotal], pr.[StandardCost],
    so.[AllocatedTaxAmt], so.[AllocatedFreight]
FROM [silver].[SalesOrder] AS so
INNER JOIN [gold].[DimDate] AS dd
    ON dd.[DateKey] = (YEAR(CAST(so.[OrderDate] AS date)) * 10000) + (MONTH(CAST(so.[OrderDate] AS date)) * 100) + DAY(CAST(so.[OrderDate] AS date))
INNER JOIN [gold].[DimCustomer] AS dc
    ON dc.[CustomerID] = so.[CustomerID]
   AND CAST(so.[OrderDate] AS date) BETWEEN dc.[ValidFrom] AND dc.[ValidTo]
INNER JOIN [gold].[DimProduct] AS dp
    ON dp.[ProductID] = so.[ProductID] AND dp.[IsCurrent] = 1
LEFT JOIN [gold].[DimTerritory] AS dt
    ON dt.[TerritoryID] = so.[TerritoryID]
CROSS JOIN (SELECT TOP (1) [TerritoryKey] FROM [gold].[DimTerritory] WHERE [TerritoryID] = -1) AS dtu ([TerritoryKey])
INNER JOIN [silver].[Product] AS pr ON pr.[ProductID] = so.[ProductID]
LEFT JOIN [gold].[DimSalesPerson] AS dsp
    ON dsp.[BusinessEntityID] = so.[SalesPersonID];
GO
