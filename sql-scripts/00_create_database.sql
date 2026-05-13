/*
================================================================================
Script : 00_create_database.sql
Purpose: Create the analytical database DW_AdventureWorks and Medallion schemas
         (bronze, silver, gold) for the Adventure Works sales data warehouse.
Database: DW_AdventureWorks (new)
================================================================================
*/

SET NOCOUNT ON;
GO

IF DB_ID(N'DW_AdventureWorks') IS NULL
BEGIN
    CREATE DATABASE [DW_AdventureWorks];
END
GO

USE [DW_AdventureWorks];
GO

/* Bronze: raw landing zone mirroring operational tables */
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'bronze')
    EXEC(N'CREATE SCHEMA [bronze] AUTHORIZATION [dbo];');
GO

/* Silver: cleansed, conformed, historized (SCD2) integration layer */
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'silver')
    EXEC(N'CREATE SCHEMA [silver] AUTHORIZATION [dbo];');
GO

/* Gold: dimensional model (star schema) for BI consumption */
IF NOT EXISTS (SELECT 1 FROM sys.schemas WHERE name = N'gold')
    EXEC(N'CREATE SCHEMA [gold] AUTHORIZATION [dbo];');
GO

PRINT N'DW_AdventureWorks created or verified with schemas bronze, silver, gold.';
GO
