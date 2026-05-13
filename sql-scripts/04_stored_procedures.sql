/*
================================================================================
Script : 04_stored_procedures.sql
Purpose: ETL stored procedures — Bronze full extract, Silver cleanse + SCD2
         Customer, Gold dimensional load + FactSales, DimDate generator.
Source : Same SQL Server instance database [AdventureWorks2022] (adjust name).
================================================================================
*/

USE [DW_AdventureWorks];
GO

SET NOCOUNT ON;
GO

IF OBJECT_ID(N'dbo.sp_populate_dim_date', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_populate_dim_date];
GO

CREATE PROCEDURE [dbo].[sp_populate_dim_date]
    @StartYear smallint = 2010,
    @EndYear   smallint = 2030
AS
BEGIN
    SET NOCOUNT ON;

    ;WITH n AS (
        SELECT 0 AS v UNION ALL SELECT 1 UNION ALL SELECT 2 UNION ALL SELECT 3 UNION ALL
        SELECT 4 UNION ALL SELECT 5 UNION ALL SELECT 6 UNION ALL SELECT 7 UNION ALL
        SELECT 8 UNION ALL SELECT 9
    ),
    Tally AS (
        SELECT n1.v + 10 * n2.v + 100 * n3.v + 1000 * n4.v AS d
        FROM n n1 CROSS JOIN n n2 CROSS JOIN n n3 CROSS JOIN n n4
    ),
    Dates AS (
        SELECT FullDate = DATEADD(DAY, t.d, CAST(CONCAT(@StartYear, '-01-01') AS date))
        FROM Tally t
        WHERE DATEADD(DAY, t.d, CAST(CONCAT(@StartYear, '-01-01') AS date)) <= CAST(CONCAT(@EndYear, '-12-31') AS date)
    )
    MERGE [gold].[DimDate] AS tgt
    USING (
        SELECT
            DateKey = (YEAR(FullDate) * 10000) + (MONTH(FullDate) * 100) + DAY(FullDate),
            FullDate,
            [Date] = FullDate,
            CalendarYear = CAST(YEAR(FullDate) AS smallint),
            CalendarQuarter = CAST(DATEPART(QUARTER, FullDate) AS tinyint),
            CalendarMonth = CAST(MONTH(FullDate) AS tinyint),
            MonthName = DATENAME(MONTH, FullDate),
            WeekOfYear = CAST(DATEPART(ISO_WEEK, FullDate) AS tinyint),
            DayOfMonth = CAST(DAY(FullDate) AS tinyint),
            DayOfWeek = CAST(CASE DATEPART(WEEKDAY, FullDate)
                                WHEN 1 THEN 7 ELSE DATEPART(WEEKDAY, FullDate) - 1 END AS tinyint),
            DayName = DATENAME(WEEKDAY, FullDate),
            IsWeekend = CASE WHEN DATEPART(WEEKDAY, FullDate) IN (1, 7) THEN 1 ELSE 0 END,
            IsHoliday = CAST(0 AS bit) /* placeholder — enrich with public holiday calendar */
        FROM Dates
    ) AS src
    ON tgt.[DateKey] = src.[DateKey]
    WHEN NOT MATCHED BY TARGET THEN
        INSERT ([DateKey], [FullDate], [Date], [CalendarYear], [CalendarQuarter], [CalendarMonth],
                [MonthName], [WeekOfYear], [DayOfMonth], [DayOfWeek], [DayName], [IsWeekend], [IsHoliday])
        VALUES (src.[DateKey], src.[FullDate], src.[Date], src.[CalendarYear], src.[CalendarQuarter], src.[CalendarMonth],
                src.[MonthName], src.[WeekOfYear], src.[DayOfMonth], src.[DayOfWeek], src.[DayName], src.[IsWeekend], src.[IsHoliday]);
END;
GO

IF OBJECT_ID(N'dbo.sp_load_bronze', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_load_bronze];
GO

CREATE PROCEDURE [dbo].[sp_load_bronze]
    @SourceDatabase sysname = N'AdventureWorks2022'
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @LoadDate datetime2(0) = SYSUTCDATETIME();
    DECLARE @Source nvarchar(100) = @SourceDatabase;
    DECLARE @sql nvarchar(max);

    /* Validate source database */
    IF DB_ID(@SourceDatabase) IS NULL
    BEGIN
        RAISERROR(N'Source database %s not found on this instance.', 16, 1, @SourceDatabase);
        RETURN;
    END

    /* Three-part names: QUOTENAME(@SourceDatabase) => [AdventureWorks2022], then + N'.[schema].[object]' */
    DECLARE @dbq nvarchar(260) = QUOTENAME(@SourceDatabase);

    SET @sql
        = N'
    TRUNCATE TABLE [bronze].[SalesOrderDetail];
    TRUNCATE TABLE [bronze].[SalesOrderHeader];
    TRUNCATE TABLE [bronze].[Customer];
    TRUNCATE TABLE [bronze].[SalesTerritory];
    TRUNCATE TABLE [bronze].[SalesPerson];
    TRUNCATE TABLE [bronze].[Product];
    TRUNCATE TABLE [bronze].[ProductCategory];
    TRUNCATE TABLE [bronze].[ProductSubcategory];
    TRUNCATE TABLE [bronze].[Person];
    TRUNCATE TABLE [bronze].[Address];
    TRUNCATE TABLE [bronze].[CountryRegion];

    INSERT INTO [bronze].[SalesOrderHeader]
    SELECT h.[SalesOrderID], h.[RevisionNumber], h.[OrderDate], h.[DueDate], h.[ShipDate], h.[Status], h.[OnlineOrderFlag],
           h.[SalesOrderNumber], h.[PurchaseOrderNumber], h.[AccountNumber], h.[CustomerID], h.[SalesPersonID], h.[TerritoryID],
           h.[BillToAddressID], h.[ShipToAddressID], h.[ShipMethodID], h.[CreditCardID], h.[CreditCardApprovalCode], h.[CurrencyRateID],
           h.[SubTotal], h.[TaxAmt], h.[Freight], h.[TotalDue], h.[Comment], h.[rowguid], h.[ModifiedDate], @pLoad, @pSrc
    FROM ' + @dbq + N'.[Sales].[SalesOrderHeader] AS h;

    INSERT INTO [bronze].[SalesOrderDetail]
    SELECT d.[SalesOrderID], d.[SalesOrderDetailID], d.[CarrierTrackingNumber], d.[OrderQty], d.[ProductID], d.[SpecialOfferID],
           d.[UnitPrice], d.[UnitPriceDiscount], d.[LineTotal], d.[rowguid], d.[ModifiedDate], @pLoad, @pSrc
    FROM ' + @dbq + N'.[Sales].[SalesOrderDetail] AS d;

    INSERT INTO [bronze].[Customer]
    SELECT c.[CustomerID], c.[PersonID], c.[StoreID], c.[TerritoryID], c.[AccountNumber], c.[rowguid], c.[ModifiedDate], @pLoad, @pSrc
    FROM ' + @dbq + N'.[Sales].[Customer] AS c;

    INSERT INTO [bronze].[SalesTerritory]
    SELECT t.[TerritoryID], t.[Name], t.[CountryRegionCode], t.[Group], t.[SalesYTD], t.[SalesLastYear], t.[CostYTD], t.[CostLastYear],
           t.[rowguid], t.[ModifiedDate], @pLoad, @pSrc
    FROM ' + @dbq + N'.[Sales].[SalesTerritory] AS t;

    INSERT INTO [bronze].[SalesPerson]
    SELECT sp.[BusinessEntityID], sp.[TerritoryID], sp.[SalesQuota], sp.[Bonus], sp.[CommissionPct], sp.[SalesYTD], sp.[SalesLastYear],
           sp.[rowguid], sp.[ModifiedDate], @pLoad, @pSrc
    FROM ' + @dbq + N'.[Sales].[SalesPerson] AS sp;

    INSERT INTO [bronze].[Product]
    SELECT p.[ProductID], p.[Name], p.[ProductNumber], p.[MakeFlag], p.[FinishedGoodsFlag], p.[Color], p.[SafetyStockLevel], p.[ReorderPoint],
           p.[StandardCost], p.[ListPrice], p.[Size], p.[SizeUnitMeasureCode], p.[WeightUnitMeasureCode], p.[Weight], p.[DaysToManufacture],
           p.[ProductLine], p.[Class], p.[Style], p.[ProductSubcategoryID], p.[ProductModelID], p.[SellStartDate], p.[SellEndDate],
           p.[DiscontinuedDate], p.[rowguid], p.[ModifiedDate], @pLoad, @pSrc
    FROM ' + @dbq + N'.[Production].[Product] AS p;

    INSERT INTO [bronze].[ProductCategory]
    SELECT pc.[ProductCategoryID], pc.[Name], pc.[rowguid], pc.[ModifiedDate], @pLoad, @pSrc
    FROM ' + @dbq + N'.[Production].[ProductCategory] AS pc;

    INSERT INTO [bronze].[ProductSubcategory]
    SELECT ps.[ProductSubcategoryID], ps.[ProductCategoryID], ps.[Name], ps.[rowguid], ps.[ModifiedDate], @pLoad, @pSrc
    FROM ' + @dbq + N'.[Production].[ProductSubcategory] AS ps;

    INSERT INTO [bronze].[Person]
    SELECT per.[BusinessEntityID], per.[PersonType], per.[NameStyle], per.[Title], per.[FirstName], per.[MiddleName], per.[LastName],
           per.[Suffix], per.[EmailPromotion], per.[AdditionalContactInfo], per.[Demographics], per.[rowguid], per.[ModifiedDate], @pLoad, @pSrc
    FROM ' + @dbq + N'.[Person].[Person] AS per;

    INSERT INTO [bronze].[Address]
    SELECT
        src.[AddressID],
        src.[AddressLine1],
        src.[AddressLine2],
        src.[City],
        src.[StateProvinceID],
        src.[PostalCode],
        src.[SpatialLocation],
        src.[rowguid],
        src.[ModifiedDate],
        @pLoad,
        @pSrc
    FROM (
        SELECT
            [AddressID],
            [AddressLine1],
            [AddressLine2],
            [City],
            [StateProvinceID],
            [PostalCode],
            [SpatialLocation],
            [rowguid],
            [ModifiedDate]
        FROM ' + @dbq + N'.[Person].[Address]
    ) AS src;

    INSERT INTO [bronze].[CountryRegion]
    SELECT cr.[CountryRegionCode], cr.[Name], cr.[ModifiedDate], @pLoad, @pSrc
    FROM ' + @dbq + N'.[Person].[CountryRegion] AS cr;
';

    EXEC sp_executesql @sql,
        N'@pLoad datetime2(0), @pSrc nvarchar(100)',
        @pLoad = @LoadDate, @pSrc = @Source;
END;
GO

IF OBJECT_ID(N'dbo.sp_load_silver', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_load_silver];
GO

CREATE PROCEDURE [dbo].[sp_load_silver]
AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @Today date = CAST(SYSUTCDATETIME() AS date);
    DECLARE @OpenEnd date = DATEFROMPARTS(9999, 12, 31);
    DECLARE @LoadTime datetime2(0) = SYSUTCDATETIME();

    /* ---------- Rebuild non-SCD silver tables ---------- */
    TRUNCATE TABLE [silver].[SalesOrder];
    TRUNCATE TABLE [silver].[Product];
    TRUNCATE TABLE [silver].[Territory];
    TRUNCATE TABLE [silver].[SalesPerson];

    INSERT INTO [silver].[Territory] (
        [TerritoryID], [TerritoryName], [CountryRegionCode], [RegionGroup], [SalesYTD], [SalesLastYear],
        [silver_load_date], [is_active], [valid_from], [valid_to]
    )
    SELECT
        t.[TerritoryID], t.[Name], t.[CountryRegionCode], t.[Group], t.[SalesYTD], t.[SalesLastYear],
        @LoadTime, 1, @Today, @OpenEnd
    FROM [bronze].[SalesTerritory] AS t;

    INSERT INTO [silver].[SalesPerson] (
        [BusinessEntityID], [TerritoryID], [SalesQuota], [Bonus], [CommissionPct], [SalesYTD], [SalesLastYear],
        [silver_load_date], [is_active], [valid_from], [valid_to]
    )
    SELECT
        sp.[BusinessEntityID], sp.[TerritoryID], sp.[SalesQuota], sp.[Bonus], sp.[CommissionPct], sp.[SalesYTD], sp.[SalesLastYear],
        @LoadTime, 1, @Today, @OpenEnd
    FROM [bronze].[SalesPerson] AS sp;

    INSERT INTO [silver].[Product] (
        [ProductID], [ProductName], [ProductNumber], [Color], [StandardCost], [ListPrice], [ProductSubcategoryID],
        [SubcategoryName], [ProductCategoryID], [CategoryName], [SellStartDate], [SellEndDate], [FinishedGoodsFlag],
        [silver_load_date], [is_active], [valid_from], [valid_to]
    )
    SELECT
        p.[ProductID], p.[Name], p.[ProductNumber], p.[Color], p.[StandardCost], p.[ListPrice], p.[ProductSubcategoryID],
        ps.[Name], ps.[ProductCategoryID], pc.[Name],
        CAST(p.[SellStartDate] AS date), CAST(p.[SellEndDate] AS date), p.[FinishedGoodsFlag],
        @LoadTime, 1, @Today, @OpenEnd
    FROM [bronze].[Product] AS p
    LEFT JOIN [bronze].[ProductSubcategory] AS ps ON p.[ProductSubcategoryID] = ps.[ProductSubcategoryID]
    LEFT JOIN [bronze].[ProductCategory] AS pc ON ps.[ProductCategoryID] = pc.[ProductCategoryID];

    ;WITH detail AS (
        /* d.* already includes ModifiedDate from SalesOrderDetail — do not repeat the column */
        SELECT d.*, h.[CustomerID], h.[SalesPersonID], h.[TerritoryID], h.[OrderDate], h.[DueDate], h.[ShipDate], h.[Status],
               h.[OnlineOrderFlag], h.[BillToAddressID], h.[ShipToAddressID], h.[CurrencyRateID],
               h.[SubTotal], h.[TaxAmt], h.[Freight],
               sumLine = SUM(d.[LineTotal]) OVER (PARTITION BY d.[SalesOrderID])
        FROM [bronze].[SalesOrderDetail] AS d
        INNER JOIN [bronze].[SalesOrderHeader] AS h ON d.[SalesOrderID] = h.[SalesOrderID]
    )
    INSERT INTO [silver].[SalesOrder] (
        [SalesOrderID], [SalesOrderDetailID], [OrderDate], [DueDate], [ShipDate], [Status], [OnlineOrderFlag],
        [CustomerID], [SalesPersonID], [TerritoryID], [BillToAddressID], [ShipToAddressID], [ProductID], [SpecialOfferID],
        [OrderQty], [UnitPrice], [UnitPriceDiscount], [LineTotal], [HeaderSubTotal], [HeaderTaxAmt], [HeaderFreight],
        [AllocatedTaxAmt], [AllocatedFreight], [CarrierTrackingNumber], [CurrencyRateID], [ModifiedDate],
        [silver_load_date], [is_active], [valid_from], [valid_to]
    )
    SELECT
        [SalesOrderID], [SalesOrderDetailID], [OrderDate], [DueDate], [ShipDate], [Status], [OnlineOrderFlag],
        [CustomerID], [SalesPersonID], [TerritoryID], [BillToAddressID], [ShipToAddressID], [ProductID], [SpecialOfferID],
        [OrderQty], [UnitPrice], [UnitPriceDiscount], [LineTotal], [SubTotal], [TaxAmt], [Freight],
        CASE WHEN [sumLine] = 0 THEN CAST(0 AS money)
             ELSE ([TaxAmt] * ([LineTotal] / [sumLine])) END,
        CASE WHEN [sumLine] = 0 THEN CAST(0 AS money)
             ELSE ([Freight] * ([LineTotal] / [sumLine])) END,
        [CarrierTrackingNumber], [CurrencyRateID], [ModifiedDate],
        @LoadTime, 1, @Today, @OpenEnd
    FROM detail;

    /* ---------- SCD Type 2 — Customer ---------- */
    IF OBJECT_ID('tempdb..#StageCustomer') IS NOT NULL DROP TABLE #StageCustomer;
    CREATE TABLE #StageCustomer
    (
        [CustomerID]        INT NOT NULL PRIMARY KEY,
        [PersonID]          INT NULL,
        [StoreID]           INT NULL,
        [TerritoryID]       INT NULL,
        [AccountNumber]     NVARCHAR(15) NOT NULL,
        [PersonType]        NCHAR(2) NULL,
        [Title]             NVARCHAR(8) NULL,
        [FirstName]         NVARCHAR(50) NOT NULL,
        [MiddleName]        NVARCHAR(50) NULL,
        [LastName]          NVARCHAR(50) NOT NULL,
        [Suffix]            NVARCHAR(10) NULL,
        [EmailPromotion]    INT NOT NULL,
        [CountryRegionCode] NVARCHAR(3) NULL,
        [CountryName]       NVARCHAR(50) NULL,
        [AttributeHash]     VARBINARY(32) NOT NULL
    );

    INSERT INTO #StageCustomer (
        [CustomerID], [PersonID], [StoreID], [TerritoryID], [AccountNumber], [PersonType], [Title], [FirstName], [MiddleName],
        [LastName], [Suffix], [EmailPromotion], [CountryRegionCode], [CountryName], [AttributeHash]
    )
    SELECT
        c.[CustomerID], c.[PersonID], c.[StoreID], c.[TerritoryID], c.[AccountNumber],
        p.[PersonType], p.[Title],
        COALESCE(p.[FirstName], N''),
        p.[MiddleName],
        COALESCE(p.[LastName], N''),
        p.[Suffix],
        COALESCE(p.[EmailPromotion], 0),
        t.[CountryRegionCode],
        cr.[Name],
        HASHBYTES(
            'SHA2_256',
            CONCAT(
                CAST(c.[CustomerID] AS varchar(11)), '|',
                ISNULL(c.[AccountNumber], N''), '|',
                ISNULL(CAST(c.[TerritoryID] AS varchar(11)), N''), '|',
                COALESCE(p.[FirstName], N''), '|',
                COALESCE(p.[LastName], N''), '|',
                COALESCE(CAST(p.[EmailPromotion] AS varchar(11)), N'0'), '|',
                ISNULL(t.[CountryRegionCode], N'')
            )
        )
    FROM [bronze].[Customer] AS c
    LEFT JOIN [bronze].[Person] AS p ON c.[PersonID] = p.[BusinessEntityID]
    LEFT JOIN [bronze].[SalesTerritory] AS t ON c.[TerritoryID] = t.[TerritoryID]
    LEFT JOIN [bronze].[CountryRegion] AS cr ON t.[CountryRegionCode] = cr.[CountryRegionCode];

    /* Close current version when attribute fingerprint changes */
    UPDATE sc
    SET [is_active] = 0,
        [valid_to] = DATEADD(DAY, -1, @Today)
    FROM [silver].[Customer] AS sc
    INNER JOIN #StageCustomer AS st ON sc.[CustomerID] = st.[CustomerID]
    WHERE sc.[is_active] = 1
      AND sc.[AttributeHash] <> st.[AttributeHash];

    /* Insert new current version for new customers or for customers whose version just closed */
    INSERT INTO [silver].[Customer] (
        [CustomerID], [PersonID], [StoreID], [TerritoryID], [AccountNumber], [PersonType], [Title], [FirstName], [MiddleName],
        [LastName], [Suffix], [EmailPromotion], [CountryRegionCode], [CountryName], [AttributeHash],
        [silver_load_date], [is_active], [valid_from], [valid_to]
    )
    SELECT
        st.[CustomerID], st.[PersonID], st.[StoreID], st.[TerritoryID], st.[AccountNumber], st.[PersonType], st.[Title],
        st.[FirstName], st.[MiddleName], st.[LastName], st.[Suffix], st.[EmailPromotion], st.[CountryRegionCode], st.[CountryName],
        st.[AttributeHash], @LoadTime, 1,
        CASE
            WHEN EXISTS (SELECT 1 FROM [silver].[Customer] AS z WHERE z.[CustomerID] = st.[CustomerID]) THEN @Today
            ELSE DATEFROMPARTS(2000, 1, 1)
        END,
        @OpenEnd
    FROM #StageCustomer AS st
    WHERE NOT EXISTS (
        SELECT 1
        FROM [silver].[Customer] AS x
        WHERE x.[CustomerID] = st.[CustomerID]
          AND x.[is_active] = 1
          AND x.[AttributeHash] = st.[AttributeHash]
    );

    /* Refresh audit timestamp on unchanged active rows */
    UPDATE sc
    SET [silver_load_date] = @LoadTime
    FROM [silver].[Customer] AS sc
    INNER JOIN #StageCustomer AS st ON sc.[CustomerID] = st.[CustomerID]
    WHERE sc.[is_active] = 1 AND sc.[AttributeHash] = st.[AttributeHash];
END;
GO

IF OBJECT_ID(N'dbo.sp_load_gold', N'P') IS NOT NULL
    DROP PROCEDURE [dbo].[sp_load_gold];
GO

CREATE PROCEDURE [dbo].[sp_load_gold]
    @SourceDatabase sysname = N'AdventureWorks2022'
AS
BEGIN
    SET NOCOUNT ON;

    IF DB_ID(@SourceDatabase) IS NULL
    BEGIN
        RAISERROR(N'Source database %s not found.', 16, 1, @SourceDatabase);
        RETURN;
    END

    /* Ensure calendar exists */
    IF NOT EXISTS (SELECT 1 FROM [gold].[DimDate] WHERE [DateKey] = 20100101)
        EXEC [dbo].[sp_populate_dim_date] @StartYear = 2010, @EndYear = 2030;

    /* Clear fact first (FK order) */
    DELETE FROM [gold].[FactSales];

    DELETE FROM [gold].[DimCustomer];
    DBCC CHECKIDENT ('[gold].[DimCustomer]', RESEED, 0);

    DELETE FROM [gold].[DimProduct];
    DBCC CHECKIDENT ('[gold].[DimProduct]', RESEED, 0);

    DELETE FROM [gold].[DimTerritory];
    DBCC CHECKIDENT ('[gold].[DimTerritory]', RESEED, 0);

    DELETE FROM [gold].[DimSalesPerson];
    DBCC CHECKIDENT ('[gold].[DimSalesPerson]', RESEED, 0);

    /* Sentinel territory for NULL operational keys */
    INSERT INTO [gold].[DimTerritory] (
        [TerritoryID], [TerritoryName], [CountryRegionCode], [CountryName], [RegionGroup]
    )
    VALUES (-1, N'Unknown', N'UNK', N'Unknown', N'Unknown');

    INSERT INTO [gold].[DimTerritory] (
        [TerritoryID], [TerritoryName], [CountryRegionCode], [CountryName], [RegionGroup]
    )
    SELECT
        t.[TerritoryID], t.[TerritoryName], t.[CountryRegionCode], cr.[Name], t.[RegionGroup]
    FROM [silver].[Territory] AS t
    LEFT JOIN [bronze].[CountryRegion] AS cr ON t.[CountryRegionCode] = cr.[CountryRegionCode];

    /* Unknown salesperson bucket for internet / NULL rep rows — inserted first to reserve low surrogate */
    INSERT INTO [gold].[DimSalesPerson] (
        [BusinessEntityID], [SalesQuota], [Bonus], [CommissionPct], [HireDate], [TerritoryID], [TerritoryName]
    )
    VALUES (-1, NULL, 0, 0, NULL, NULL, N'Unknown / Not assigned');

    INSERT INTO [gold].[DimProduct] (
        [ProductID], [ProductName], [ProductNumber], [Color], [ProductCategoryID], [CategoryName],
        [ProductSubcategoryID], [SubcategoryName], [ListPrice], [StandardCost], [ValidFrom], [ValidTo], [IsCurrent]
    )
    SELECT
        p.[ProductID], p.[ProductName], p.[ProductNumber], p.[Color], p.[ProductCategoryID], p.[CategoryName],
        p.[ProductSubcategoryID], p.[SubcategoryName], p.[ListPrice], p.[StandardCost], p.[valid_from], p.[valid_to], 1
    FROM [silver].[Product] AS p;

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

    DECLARE @sql nvarchar(max) = CONCAT(N'
    INSERT INTO [gold].[DimSalesPerson] ([BusinessEntityID], [SalesQuota], [Bonus], [CommissionPct], [HireDate], [TerritoryID], [TerritoryName])
    SELECT sp.[BusinessEntityID], sp.[SalesQuota], sp.[Bonus], sp.[CommissionPct], CAST(e.[HireDate] AS date),
           sp.[TerritoryID], ter.[Name]
    FROM [silver].[SalesPerson] AS sp
    LEFT JOIN [', @SourceDatabase, N'].[HumanResources].[Employee] AS e ON sp.[BusinessEntityID] = e.[BusinessEntityID]
    LEFT JOIN [', @SourceDatabase, N'].[Sales].[SalesTerritory] AS ter ON sp.[TerritoryID] = ter.[TerritoryID];');

    EXEC sp_executesql @sql;

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
END;
GO

PRINT N'Stored procedures sp_populate_dim_date, sp_load_bronze, sp_load_silver, sp_load_gold created.';
GO
