/*
================================================================================
Script : 03_gold_tables.sql
Purpose: Star schema in [gold] for sales analysis (date, customer SCD2, product,
         territory, salesperson + fact at order-line grain).
Includes nonclustered COLUMNSTORE index on FactSales for analytical scan perf.
Prereq: schemas gold; run 04_stored_procedures after to load data.
================================================================================
*/

USE [DW_AdventureWorks];
GO

SET NOCOUNT ON;
GO

/* ------------------------------------------------------------------ */
/* gold.DimDate                                                        */
/* ------------------------------------------------------------------ */
IF OBJECT_ID(N'gold.FactSales', N'U') IS NOT NULL
    DROP TABLE [gold].[FactSales];
GO
IF OBJECT_ID(N'gold.DimCustomer', N'U') IS NOT NULL
    DROP TABLE [gold].[DimCustomer];
GO
IF OBJECT_ID(N'gold.DimProduct', N'U') IS NOT NULL
    DROP TABLE [gold].[DimProduct];
GO
IF OBJECT_ID(N'gold.DimTerritory', N'U') IS NOT NULL
    DROP TABLE [gold].[DimTerritory];
GO
IF OBJECT_ID(N'gold.DimSalesPerson', N'U') IS NOT NULL
    DROP TABLE [gold].[DimSalesPerson];
GO
IF OBJECT_ID(N'gold.DimDate', N'U') IS NOT NULL
    DROP TABLE [gold].[DimDate];
GO

CREATE TABLE [gold].[DimDate]
(
    [DateKey]        INT          NOT NULL, /* YYYYMMDD */
    [FullDate]       DATE         NOT NULL,
    [Date]           DATE         NOT NULL, /* synonym for calendar tools (e.g. Power BI time intelligence) */
    [CalendarYear]   SMALLINT     NOT NULL,
    [CalendarQuarter] TINYINT     NOT NULL,
    [CalendarMonth]  TINYINT      NOT NULL,
    [MonthName]      NVARCHAR(15) NOT NULL,
    [WeekOfYear]     TINYINT      NOT NULL,
    [DayOfMonth]     TINYINT      NOT NULL,
    [DayOfWeek]      TINYINT      NOT NULL, /* 1=Monday .. 7=Sunday */
    [DayName]        NVARCHAR(15) NOT NULL,
    [IsWeekend]      BIT          NOT NULL,
    [IsHoliday]      BIT          NOT NULL, /* placeholder: extend with calendar */
    CONSTRAINT [PK_gold_DimDate] PRIMARY KEY CLUSTERED ([DateKey])
);
GO

CREATE NONCLUSTERED INDEX [IX_gold_DimDate_FullDate]
    ON [gold].[DimDate] ([FullDate]);
GO

/* ------------------------------------------------------------------ */
/* gold.DimCustomer — SCD Type 2                                     */
/* ------------------------------------------------------------------ */
CREATE TABLE [gold].[DimCustomer]
(
    [CustomerKey]     INT            IDENTITY(1, 1) NOT NULL,
    [CustomerID]      INT            NOT NULL,
    [AccountNumber]   NVARCHAR(15) NOT NULL,
    [PersonType]      NCHAR(2)     NULL,
    [CustomerName]    NVARCHAR(101) NOT NULL,
    [EmailPromotion]  INT            NOT NULL,
    [TerritoryID]     INT            NULL,
    [TerritoryName]   NVARCHAR(50)   NULL,
    [CountryRegionCode] NVARCHAR(3)  NULL,
    [CountryName]     NVARCHAR(50)   NULL,
    [SilverCustomerSK] INT           NULL, /* traceability to silver version */
    [ValidFrom]       DATE           NOT NULL,
    [ValidTo]         DATE           NOT NULL,
    [IsCurrent]       BIT            NOT NULL,
    CONSTRAINT [PK_gold_DimCustomer] PRIMARY KEY CLUSTERED ([CustomerKey])
);
GO

CREATE NONCLUSTERED INDEX [IX_gold_DimCustomer_Natural]
    ON [gold].[DimCustomer] ([CustomerID], [IsCurrent]);
GO

/* ------------------------------------------------------------------ */
/* gold.DimProduct                                                     */
/* ------------------------------------------------------------------ */
CREATE TABLE [gold].[DimProduct]
(
    [ProductKey]          INT            IDENTITY(1, 1) NOT NULL,
    [ProductID]           INT            NOT NULL,
    [ProductName]         NVARCHAR(50)   NOT NULL,
    [ProductNumber]       NVARCHAR(25)   NOT NULL,
    [Color]               NVARCHAR(15)   NULL,
    [ProductCategoryID]   INT            NULL,
    [CategoryName]        NVARCHAR(50)   NULL,
    [ProductSubcategoryID] INT           NULL,
    [SubcategoryName]     NVARCHAR(50)   NULL,
    [ListPrice]           MONEY          NOT NULL,
    [StandardCost]        MONEY          NOT NULL,
    [ValidFrom]           DATE           NOT NULL,
    [ValidTo]             DATE           NOT NULL,
    [IsCurrent]           BIT            NOT NULL,
    CONSTRAINT [PK_gold_DimProduct] PRIMARY KEY CLUSTERED ([ProductKey])
);
GO

CREATE NONCLUSTERED INDEX [IX_gold_DimProduct_ID]
    ON [gold].[DimProduct] ([ProductID]);
GO

/* ------------------------------------------------------------------ */
/* gold.DimTerritory                                                   */
/* ------------------------------------------------------------------ */
CREATE TABLE [gold].[DimTerritory]
(
    [TerritoryKey]      INT            IDENTITY(1, 1) NOT NULL,
    [TerritoryID]       INT            NOT NULL,
    [TerritoryName]     NVARCHAR(50)   NOT NULL,
    [CountryRegionCode] NVARCHAR(3)    NOT NULL,
    [CountryName]       NVARCHAR(50)   NULL,
    [RegionGroup]       NVARCHAR(50)   NOT NULL,
    CONSTRAINT [PK_gold_DimTerritory] PRIMARY KEY CLUSTERED ([TerritoryKey]),
    CONSTRAINT [UQ_gold_DimTerritory_Natural] UNIQUE ([TerritoryID])
);
GO

/* ------------------------------------------------------------------ */
/* gold.DimSalesPerson                                                 */
/* ------------------------------------------------------------------ */
CREATE TABLE [gold].[DimSalesPerson]
(
    [SalesPersonKey]   INT            IDENTITY(1, 1) NOT NULL,
    [BusinessEntityID] INT            NOT NULL,
    [SalesQuota]       MONEY          NULL,
    [Bonus]            MONEY          NOT NULL,
    [CommissionPct]    SMALLMONEY     NOT NULL,
    [HireDate]         DATE           NULL,
    [TerritoryID]      INT            NULL,
    [TerritoryName]    NVARCHAR(50)   NULL,
    CONSTRAINT [PK_gold_DimSalesPerson] PRIMARY KEY CLUSTERED ([SalesPersonKey]),
    CONSTRAINT [UQ_gold_DimSalesPerson_BE] UNIQUE ([BusinessEntityID])
);
GO

/* ------------------------------------------------------------------ */
/* gold.FactSales — one row per order line                           */
/* ------------------------------------------------------------------ */
CREATE TABLE [gold].[FactSales]
(
    [FactSalesKey]      BIGINT         IDENTITY(1, 1) NOT NULL,
    [SalesOrderID]      INT            NOT NULL,
    [SalesOrderDetailID] INT           NOT NULL,
    [OrderDateKey]      INT            NOT NULL,
    [CustomerKey]       INT            NOT NULL,
    [ProductKey]        INT            NOT NULL,
    [TerritoryKey]      INT            NOT NULL,
    [SalesPersonKey]    INT            NOT NULL,
    [OrderQuantity]     INT            NOT NULL,
    [UnitPrice]         MONEY          NOT NULL,
    [UnitPriceDiscount] MONEY          NOT NULL,
    [LineTotal]         MONEY          NOT NULL,
    [StandardCost]      MONEY          NOT NULL,
    [TaxAmt]            MONEY          NOT NULL,
    [Freight]           MONEY          NOT NULL,
    [GrossMargin]       AS (CONVERT(MONEY, [LineTotal] - ([StandardCost] * CONVERT(MONEY, [OrderQuantity])))) PERSISTED,
    CONSTRAINT [PK_gold_FactSales] PRIMARY KEY NONCLUSTERED ([FactSalesKey]),
    CONSTRAINT [FK_FactSales_DimDate] FOREIGN KEY ([OrderDateKey]) REFERENCES [gold].[DimDate] ([DateKey]),
    CONSTRAINT [FK_FactSales_DimCustomer] FOREIGN KEY ([CustomerKey]) REFERENCES [gold].[DimCustomer] ([CustomerKey]),
    CONSTRAINT [FK_FactSales_DimProduct] FOREIGN KEY ([ProductKey]) REFERENCES [gold].[DimProduct] ([ProductKey]),
    CONSTRAINT [FK_FactSales_DimTerritory] FOREIGN KEY ([TerritoryKey]) REFERENCES [gold].[DimTerritory] ([TerritoryKey]),
    CONSTRAINT [FK_FactSales_DimSalesPerson] FOREIGN KEY ([SalesPersonKey]) REFERENCES [gold].[DimSalesPerson] ([SalesPersonKey])
);
GO

/* Clustered columnstore for warehouse-style aggregation performance */
CREATE CLUSTERED COLUMNSTORE INDEX [CCI_gold_FactSales]
    ON [gold].[FactSales];
GO

PRINT N'Gold star schema tables created (FactSales uses clustered columnstore).';
GO
