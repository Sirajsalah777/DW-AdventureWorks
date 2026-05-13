/*
================================================================================
Script : 02_silver_tables.sql
Purpose: Cleansed integration layer [silver] with temporal columns for SCD Type 2
         on Customer and audit columns on all entities.
Prereq: bronze tables (01_bronze_tables.sql).
================================================================================
*/

USE [DW_AdventureWorks];
GO

SET NOCOUNT ON;
GO

/* ------------------------------------------------------------------ */
/* silver.Customer — deduplicated customer + person conformed, SCD2  */
/* ------------------------------------------------------------------ */
IF OBJECT_ID(N'silver.Customer', N'U') IS NOT NULL
    DROP TABLE [silver].[Customer];
GO

CREATE TABLE [silver].[Customer]
(
    [SilverCustomerSK]   INT            IDENTITY(1, 1) NOT NULL,
    [CustomerID]         INT            NOT NULL,
    [PersonID]           INT            NULL,
    [StoreID]            INT            NULL,
    [TerritoryID]        INT            NULL,
    [AccountNumber]      NVARCHAR(15) NOT NULL,
    [PersonType]         NCHAR(2)     NULL,
    [Title]              NVARCHAR(8)  NULL,
    [FirstName]          NVARCHAR(50) NOT NULL,
    [MiddleName]         NVARCHAR(50) NULL,
    [LastName]           NVARCHAR(50) NOT NULL,
    [Suffix]             NVARCHAR(10) NULL,
    [EmailPromotion]     INT            NOT NULL,
    [CountryRegionCode]  NVARCHAR(3)  NULL,
    [CountryName]        NVARCHAR(50) NULL,
    [AttributeHash]      VARBINARY(32) NOT NULL, /* SHA2_256 for SCD compare */
    [silver_load_date]   DATETIME       NOT NULL,
    [is_active]          BIT            NOT NULL,
    [valid_from]         DATE           NOT NULL,
    [valid_to]           DATE           NOT NULL,
    CONSTRAINT [PK_silver_Customer] PRIMARY KEY CLUSTERED ([SilverCustomerSK])
);
GO

CREATE NONCLUSTERED INDEX [IX_silver_Customer_Business]
    ON [silver].[Customer] ([CustomerID], [valid_from], [valid_to]);
CREATE NONCLUSTERED INDEX [IX_silver_Customer_Active]
    ON [silver].[Customer] ([CustomerID], [is_active]);
GO

/* ------------------------------------------------------------------ */
/* silver.Product — product with category / subcategory hierarchy      */
/* ------------------------------------------------------------------ */
IF OBJECT_ID(N'silver.Product', N'U') IS NOT NULL
    DROP TABLE [silver].[Product];
GO

CREATE TABLE [silver].[Product]
(
    [ProductID]            INT            NOT NULL,
    [ProductName]          NVARCHAR(50)   NOT NULL,
    [ProductNumber]        NVARCHAR(25)   NOT NULL,
    [Color]                NVARCHAR(15)   NULL,
    [StandardCost]         MONEY          NOT NULL,
    [ListPrice]            MONEY          NOT NULL,
    [ProductSubcategoryID] INT            NULL,
    [SubcategoryName]    NVARCHAR(50)   NULL,
    [ProductCategoryID]    INT            NULL,
    [CategoryName]         NVARCHAR(50)   NULL,
    [SellStartDate]        DATE           NOT NULL,
    [SellEndDate]          DATE           NULL,
    [FinishedGoodsFlag]    BIT            NOT NULL,
    [silver_load_date]     DATETIME       NOT NULL,
    [is_active]            BIT            NOT NULL,
    [valid_from]           DATE           NOT NULL,
    [valid_to]             DATE           NOT NULL,
    CONSTRAINT [PK_silver_Product] PRIMARY KEY CLUSTERED ([ProductID])
);
GO

/* ------------------------------------------------------------------ */
/* silver.SalesOrder — header + detail at line grain                  */
/* ------------------------------------------------------------------ */
IF OBJECT_ID(N'silver.SalesOrder', N'U') IS NOT NULL
    DROP TABLE [silver].[SalesOrder];
GO

CREATE TABLE [silver].[SalesOrder]
(
    [SalesOrderID]           INT            NOT NULL,
    [SalesOrderDetailID]     INT            NOT NULL,
    [OrderDate]              DATETIME       NOT NULL,
    [DueDate]                DATETIME       NOT NULL,
    [ShipDate]               DATETIME       NULL,
    [Status]                 TINYINT        NOT NULL,
    [OnlineOrderFlag]        BIT            NOT NULL,
    [CustomerID]             INT            NOT NULL,
    [SalesPersonID]          INT            NULL,
    [TerritoryID]            INT            NULL,
    [BillToAddressID]        INT            NOT NULL,
    [ShipToAddressID]        INT            NOT NULL,
    [ProductID]              INT            NOT NULL,
    [SpecialOfferID]         INT            NOT NULL,
    [OrderQty]               SMALLINT       NOT NULL,
    [UnitPrice]              MONEY          NOT NULL,
    [UnitPriceDiscount]      MONEY          NOT NULL,
    [LineTotal]              MONEY          NOT NULL,
    [HeaderSubTotal]         MONEY          NOT NULL,
    [HeaderTaxAmt]           MONEY          NOT NULL,
    [HeaderFreight]          MONEY          NOT NULL,
    [AllocatedTaxAmt]        MONEY          NOT NULL, /* prorated to line */
    [AllocatedFreight]       MONEY          NOT NULL,
    [CarrierTrackingNumber]  NVARCHAR(25) NULL,
    [CurrencyRateID]         INT            NULL,
    [ModifiedDate]           DATETIME       NOT NULL,
    [silver_load_date]       DATETIME       NOT NULL,
    [is_active]              BIT            NOT NULL,
    [valid_from]             DATE           NOT NULL,
    [valid_to]               DATE           NOT NULL,
    CONSTRAINT [PK_silver_SalesOrder] PRIMARY KEY CLUSTERED ([SalesOrderID], [SalesOrderDetailID])
);
GO

CREATE NONCLUSTERED INDEX [IX_silver_SO_OrderDate]
    ON [silver].[SalesOrder] ([OrderDate]);
CREATE NONCLUSTERED INDEX [IX_silver_SO_Customer]
    ON [silver].[SalesOrder] ([CustomerID]);
GO

/* ------------------------------------------------------------------ */
/* silver.Territory                                                    */
/* ------------------------------------------------------------------ */
IF OBJECT_ID(N'silver.Territory', N'U') IS NOT NULL
    DROP TABLE [silver].[Territory];
GO

CREATE TABLE [silver].[Territory]
(
    [TerritoryID]       INT            NOT NULL,
    [TerritoryName]     NVARCHAR(50)   NOT NULL,
    [CountryRegionCode] NVARCHAR(3)    NOT NULL,
    [RegionGroup]       NVARCHAR(50)   NOT NULL,
    [SalesYTD]          MONEY          NOT NULL,
    [SalesLastYear]     MONEY          NOT NULL,
    [silver_load_date]  DATETIME       NOT NULL,
    [is_active]         BIT            NOT NULL,
    [valid_from]        DATE           NOT NULL,
    [valid_to]          DATE           NOT NULL,
    CONSTRAINT [PK_silver_Territory] PRIMARY KEY CLUSTERED ([TerritoryID])
);
GO

/* ------------------------------------------------------------------ */
/* silver.SalesPerson                                                  */
/* ------------------------------------------------------------------ */
IF OBJECT_ID(N'silver.SalesPerson', N'U') IS NOT NULL
    DROP TABLE [silver].[SalesPerson];
GO

CREATE TABLE [silver].[SalesPerson]
(
    [BusinessEntityID] INT            NOT NULL,
    [TerritoryID]      INT            NULL,
    [SalesQuota]       MONEY          NULL,
    [Bonus]            MONEY          NOT NULL,
    [CommissionPct]    SMALLMONEY     NOT NULL,
    [SalesYTD]         MONEY          NOT NULL,
    [SalesLastYear]    MONEY          NOT NULL,
    [silver_load_date] DATETIME       NOT NULL,
    [is_active]        BIT            NOT NULL,
    [valid_from]       DATE           NOT NULL,
    [valid_to]         DATE           NOT NULL,
    CONSTRAINT [PK_silver_SalesPerson] PRIMARY KEY CLUSTERED ([BusinessEntityID])
);
GO

PRINT N'Silver integration tables created successfully.';
GO
