/*
================================================================================
Script : create_bronze_etl_log.sql
Purpose: Operational log table for SSIS package executions (Deliverable 2).
Prereq: USE DW_AdventureWorks; schema bronze exists.
================================================================================
*/

USE [DW_AdventureWorks];
GO

IF OBJECT_ID(N'bronze.etl_log', N'U') IS NOT NULL
    DROP TABLE [bronze].[etl_log];
GO

CREATE TABLE [bronze].[etl_log]
(
    [log_id]          BIGINT         IDENTITY(1, 1) NOT NULL,
    [batch_id]        UNIQUEIDENTIFIER NOT NULL,
    [package_name]    NVARCHAR(128)  NOT NULL,
    [start_time]      DATETIME2(3)   NOT NULL,
    [end_time]        DATETIME2(3)   NULL,
    [rows_processed]  BIGINT         NULL,
    [status]          NVARCHAR(20)   NOT NULL, /* Running, Success, Failed */
    [error_message]   NVARCHAR(4000) NULL,
    CONSTRAINT [PK_bronze_etl_log] PRIMARY KEY CLUSTERED ([log_id])
);
GO

CREATE NONCLUSTERED INDEX [IX_etl_log_batch]
    ON [bronze].[etl_log] ([batch_id], [package_name]);
GO
