/*
================================================================================
Script : 01_bronze_tables.sql
Purpose: Create RAW staging tables in [bronze] mirroring AdventureWorks2022
         structures (materialized computed columns; no IDENTITY on natural keys).
Source reference: Microsoft AdventureWorks OLTP sample (Sales, Production, Person).
Adds: bronze_load_date, bronze_source on every table.
Prereq: USE DW_AdventureWorks; schemas bronze exists (00_create_database.sql).
================================================================================
*/

USE [DW_AdventureWorks];
GO

SET NOCOUNT ON;
GO

/* ------------------------------------------------------------------ */
/* Sales.SalesOrderHeader (computed columns stored as base types)    */
/* ------------------------------------------------------------------ */
IF OBJECT_ID(N'bronze.SalesOrderHeader', N'U') IS NOT NULL
    DROP TABLE [bronze].[SalesOrderHeader];
GO

CREATE TABLE [bronze].[SalesOrderHeader]
(
    [SalesOrderID]           INT              NOT NULL,
    [RevisionNumber]         TINYINT          NOT NULL,
    [OrderDate]              DATETIME         NOT NULL,
    [DueDate]                DATETIME         NOT NULL,
    [ShipDate]               DATETIME         NULL,
    [Status]                 TINYINT          NOT NULL,
    [OnlineOrderFlag]        BIT              NOT NULL,
    [SalesOrderNumber]       NVARCHAR(25)   NOT NULL, /* persisted from source */
    [PurchaseOrderNumber]    NVARCHAR(25)   NULL,
    [AccountNumber]          NVARCHAR(15)   NULL,
    [CustomerID]             INT              NOT NULL,
    [SalesPersonID]          INT              NULL,
    [TerritoryID]            INT              NULL,
    [BillToAddressID]        INT              NOT NULL,
    [ShipToAddressID]        INT              NOT NULL,
    [ShipMethodID]           INT              NOT NULL,
    [CreditCardID]           INT              NULL,
    [CreditCardApprovalCode] VARCHAR(15)    NULL,
    [CurrencyRateID]         INT              NULL,
    [SubTotal]               MONEY            NOT NULL,
    [TaxAmt]                 MONEY            NOT NULL,
    [Freight]                MONEY            NOT NULL,
    [TotalDue]               MONEY            NOT NULL, /* materialized */
    [Comment]                NVARCHAR(128)  NULL,
    [rowguid]                UNIQUEIDENTIFIER NOT NULL,
    [ModifiedDate]           DATETIME         NOT NULL,
    [bronze_load_date]       DATETIME         NOT NULL,
    [bronze_source]          NVARCHAR(100)    NOT NULL,
    CONSTRAINT [PK_bronze_SalesOrderHeader] PRIMARY KEY CLUSTERED ([SalesOrderID])
);
GO

/* ------------------------------------------------------------------ */
/* Sales.SalesOrderDetail                                              */
/* ------------------------------------------------------------------ */
IF OBJECT_ID(N'bronze.SalesOrderDetail', N'U') IS NOT NULL
    DROP TABLE [bronze].[SalesOrderDetail];
GO

CREATE TABLE [bronze].[SalesOrderDetail]
(
    [SalesOrderID]          INT              NOT NULL,
    [SalesOrderDetailID]    INT              NOT NULL,
    [CarrierTrackingNumber] NVARCHAR(25)   NULL,
    [OrderQty]              SMALLINT         NOT NULL,
    [ProductID]             INT              NOT NULL,
    [SpecialOfferID]        INT              NOT NULL,
    [UnitPrice]             MONEY            NOT NULL,
    [UnitPriceDiscount]     MONEY            NOT NULL,
    [LineTotal]             MONEY            NOT NULL, /* materialized */
    [rowguid]               UNIQUEIDENTIFIER NOT NULL,
    [ModifiedDate]          DATETIME         NOT NULL,
    [bronze_load_date]      DATETIME         NOT NULL,
    [bronze_source]         NVARCHAR(100)    NOT NULL,
    CONSTRAINT [PK_bronze_SalesOrderDetail] PRIMARY KEY CLUSTERED ([SalesOrderDetailID])
);
GO

CREATE NONCLUSTERED INDEX [IX_bronze_SOD_SalesOrderID]
    ON [bronze].[SalesOrderDetail] ([SalesOrderID]);
CREATE NONCLUSTERED INDEX [IX_bronze_SOD_ProductID]
    ON [bronze].[SalesOrderDetail] ([ProductID]);
GO

/* ------------------------------------------------------------------ */
/* Sales.Customer (AccountNumber materialized)                       */
/* ------------------------------------------------------------------ */
IF OBJECT_ID(N'bronze.Customer', N'U') IS NOT NULL
    DROP TABLE [bronze].[Customer];
GO

CREATE TABLE [bronze].[Customer]
(
    [CustomerID]        INT                NOT NULL,
    [PersonID]          INT                NULL,
    [StoreID]           INT                NULL,
    [TerritoryID]       INT                NULL,
    [AccountNumber]     NVARCHAR(15)     NOT NULL, /* materialized AW + zeros */
    [rowguid]           UNIQUEIDENTIFIER   NOT NULL,
    [ModifiedDate]      DATETIME           NOT NULL,
    [bronze_load_date]  DATETIME           NOT NULL,
    [bronze_source]     NVARCHAR(100)      NOT NULL,
    CONSTRAINT [PK_bronze_Customer] PRIMARY KEY CLUSTERED ([CustomerID])
);
GO

/* ------------------------------------------------------------------ */
/* Sales.SalesTerritory                                                */
/* ------------------------------------------------------------------ */
IF OBJECT_ID(N'bronze.SalesTerritory', N'U') IS NOT NULL
    DROP TABLE [bronze].[SalesTerritory];
GO

CREATE TABLE [bronze].[SalesTerritory]
(
    [TerritoryID]       INT                NOT NULL,
    [Name]              NVARCHAR(50)       NOT NULL,
    [CountryRegionCode] NVARCHAR(3)        NOT NULL,
    [Group]             NVARCHAR(50)       NOT NULL,
    [SalesYTD]          MONEY              NOT NULL,
    [SalesLastYear]     MONEY              NOT NULL,
    [CostYTD]           MONEY              NOT NULL,
    [CostLastYear]      MONEY              NOT NULL,
    [rowguid]           UNIQUEIDENTIFIER   NOT NULL,
    [ModifiedDate]      DATETIME           NOT NULL,
    [bronze_load_date]  DATETIME           NOT NULL,
    [bronze_source]     NVARCHAR(100)      NOT NULL,
    CONSTRAINT [PK_bronze_SalesTerritory] PRIMARY KEY CLUSTERED ([TerritoryID])
);
GO

/* ------------------------------------------------------------------ */
/* Sales.SalesPerson                                                   */
/* ------------------------------------------------------------------ */
IF OBJECT_ID(N'bronze.SalesPerson', N'U') IS NOT NULL
    DROP TABLE [bronze].[SalesPerson];
GO

CREATE TABLE [bronze].[SalesPerson]
(
    [BusinessEntityID] INT                NOT NULL,
    [TerritoryID]      INT                NULL,
    [SalesQuota]       MONEY              NULL,
    [Bonus]            MONEY              NOT NULL,
    [CommissionPct]    SMALLMONEY         NOT NULL,
    [SalesYTD]         MONEY              NOT NULL,
    [SalesLastYear]    MONEY              NOT NULL,
    [rowguid]          UNIQUEIDENTIFIER   NOT NULL,
    [ModifiedDate]     DATETIME           NOT NULL,
    [bronze_load_date] DATETIME           NOT NULL,
    [bronze_source]    NVARCHAR(100)      NOT NULL,
    CONSTRAINT [PK_bronze_SalesPerson] PRIMARY KEY CLUSTERED ([BusinessEntityID])
);
GO

/* ------------------------------------------------------------------ */
/* Production.Product                                                  */
/* ------------------------------------------------------------------ */
IF OBJECT_ID(N'bronze.Product', N'U') IS NOT NULL
    DROP TABLE [bronze].[Product];
GO

CREATE TABLE [bronze].[Product]
(
    [ProductID]             INT                NOT NULL,
    [Name]                  NVARCHAR(50)       NOT NULL,
    [ProductNumber]         NVARCHAR(25)       NOT NULL,
    [MakeFlag]              BIT                NOT NULL,
    [FinishedGoodsFlag]     BIT                NOT NULL,
    [Color]                 NVARCHAR(15)       NULL,
    [SafetyStockLevel]      SMALLINT           NOT NULL,
    [ReorderPoint]          SMALLINT           NOT NULL,
    [StandardCost]          MONEY              NOT NULL,
    [ListPrice]             MONEY              NOT NULL,
    [Size]                  NVARCHAR(5)        NULL,
    [SizeUnitMeasureCode]   NCHAR(3)           NULL,
    [WeightUnitMeasureCode] NCHAR(3)           NULL,
    [Weight]                DECIMAL(8, 2)      NULL,
    [DaysToManufacture]     INT                NOT NULL,
    [ProductLine]           NCHAR(2)           NULL,
    [Class]                 NCHAR(2)           NULL,
    [Style]                 NCHAR(2)           NULL,
    [ProductSubcategoryID]  INT                NULL,
    [ProductModelID]        INT                NULL,
    [SellStartDate]         DATETIME           NOT NULL,
    [SellEndDate]           DATETIME           NULL,
    [DiscontinuedDate]      DATETIME           NULL,
    [rowguid]               UNIQUEIDENTIFIER   NOT NULL,
    [ModifiedDate]          DATETIME           NOT NULL,
    [bronze_load_date]      DATETIME           NOT NULL,
    [bronze_source]         NVARCHAR(100)      NOT NULL,
    CONSTRAINT [PK_bronze_Product] PRIMARY KEY CLUSTERED ([ProductID])
);
GO

/* ------------------------------------------------------------------ */
/* Production.ProductCategory                                          */
/* ------------------------------------------------------------------ */
IF OBJECT_ID(N'bronze.ProductCategory', N'U') IS NOT NULL
    DROP TABLE [bronze].[ProductCategory];
GO

CREATE TABLE [bronze].[ProductCategory]
(
    [ProductCategoryID] INT                NOT NULL,
    [Name]              NVARCHAR(50)       NOT NULL,
    [rowguid]           UNIQUEIDENTIFIER   NOT NULL,
    [ModifiedDate]      DATETIME           NOT NULL,
    [bronze_load_date]  DATETIME           NOT NULL,
    [bronze_source]     NVARCHAR(100)      NOT NULL,
    CONSTRAINT [PK_bronze_ProductCategory] PRIMARY KEY CLUSTERED ([ProductCategoryID])
);
GO

/* ------------------------------------------------------------------ */
/* Production.ProductSubcategory                                       */
/* ------------------------------------------------------------------ */
IF OBJECT_ID(N'bronze.ProductSubcategory', N'U') IS NOT NULL
    DROP TABLE [bronze].[ProductSubcategory];
GO

CREATE TABLE [bronze].[ProductSubcategory]
(
    [ProductSubcategoryID] INT                NOT NULL,
    [ProductCategoryID]    INT                NOT NULL,
    [Name]                 NVARCHAR(50)       NOT NULL,
    [rowguid]              UNIQUEIDENTIFIER   NOT NULL,
    [ModifiedDate]         DATETIME           NOT NULL,
    [bronze_load_date]     DATETIME           NOT NULL,
    [bronze_source]        NVARCHAR(100)      NOT NULL,
    CONSTRAINT [PK_bronze_ProductSubcategory] PRIMARY KEY CLUSTERED ([ProductSubcategoryID])
);
GO

/* ------------------------------------------------------------------ */
/* Person.Person                                                       */
/* ------------------------------------------------------------------ */
IF OBJECT_ID(N'bronze.Person', N'U') IS NOT NULL
    DROP TABLE [bronze].[Person];
GO

CREATE TABLE [bronze].[Person]
(
    [BusinessEntityID]      INT                NOT NULL,
    [PersonType]            NCHAR(2)           NOT NULL,
    [NameStyle]             BIT                NOT NULL,
    [Title]                 NVARCHAR(8)        NULL,
    [FirstName]             NVARCHAR(50)       NOT NULL,
    [MiddleName]            NVARCHAR(50)       NULL,
    [LastName]              NVARCHAR(50)       NOT NULL,
    [Suffix]                NVARCHAR(10)       NULL,
    [EmailPromotion]        INT                NOT NULL,
    [AdditionalContactInfo] XML                NULL,
    [Demographics]          XML                NULL,
    [rowguid]               UNIQUEIDENTIFIER   NOT NULL,
    [ModifiedDate]          DATETIME           NOT NULL,
    [bronze_load_date]      DATETIME           NOT NULL,
    [bronze_source]         NVARCHAR(100)      NOT NULL,
    CONSTRAINT [PK_bronze_Person] PRIMARY KEY CLUSTERED ([BusinessEntityID])
);
GO

/* ------------------------------------------------------------------ */
/* Person.Address                                                      */
/* ------------------------------------------------------------------ */
IF OBJECT_ID(N'bronze.Address', N'U') IS NOT NULL
    DROP TABLE [bronze].[Address];
GO

CREATE TABLE [bronze].[Address]
(
    [AddressID]        INT                NOT NULL,
    [AddressLine1]     NVARCHAR(60)       NOT NULL,
    [AddressLine2]     NVARCHAR(60)       NULL,
    [City]             NVARCHAR(30)       NOT NULL,
    [StateProvinceID]  INT                NOT NULL,
    [PostalCode]       NVARCHAR(15)       NOT NULL,
    [SpatialLocation]  GEOGRAPHY          NULL,
    [rowguid]          UNIQUEIDENTIFIER   NOT NULL,
    [ModifiedDate]     DATETIME           NOT NULL,
    [bronze_load_date] DATETIME           NOT NULL,
    [bronze_source]    NVARCHAR(100)      NOT NULL,
    CONSTRAINT [PK_bronze_Address] PRIMARY KEY CLUSTERED ([AddressID])
);
GO

/* ------------------------------------------------------------------ */
/* Person.CountryRegion                                                */
/* ------------------------------------------------------------------ */
IF OBJECT_ID(N'bronze.CountryRegion', N'U') IS NOT NULL
    DROP TABLE [bronze].[CountryRegion];
GO

CREATE TABLE [bronze].[CountryRegion]
(
    [CountryRegionCode] NVARCHAR(3)        NOT NULL,
    [Name]              NVARCHAR(50)       NOT NULL,
    [ModifiedDate]      DATETIME           NOT NULL,
    [bronze_load_date]  DATETIME           NOT NULL,
    [bronze_source]     NVARCHAR(100)      NOT NULL,
    CONSTRAINT [PK_bronze_CountryRegion] PRIMARY KEY CLUSTERED ([CountryRegionCode])
);
GO

PRINT N'Bronze staging tables created successfully.';
GO
