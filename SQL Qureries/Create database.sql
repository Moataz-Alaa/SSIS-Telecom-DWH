
/*
Make sure to run this script from the master database context, as it creates a new database.
This script deletes the database and creates a new one with the same name. It also creates the necessary tables for the SSIS_Telecom_DB database.
*/

IF EXISTS (SELECT 1 FROM sys.databases WHERE name = 'SSIS_Telecom_DB')
BEGIN
    ALTER DATABASE SSIS_Telecom_DB SET SINGLE_USER WITH ROLLBACK IMMEDIATE;
    DROP DATABASE SSIS_Telecom_DB;
END;
GO

CREATE DATABASE SSIS_Telecom_DB
GO

USE SSIS_Telecom_DB
GO

IF OBJECT_ID('fact_transaction', 'U') IS NOT NULL
	DROP TABLE fact_transaction;
CREATE TABLE fact_transaction (
	id int not null IDENTITY (1,1) PRIMARY KEY, -- surrogate key
	transaction_id int not null , 
	imsi varchar(9) not null,
	subscriber_id int,
	tac varchar(8) not null,
	snr varchar(6) not null,
	imei varchar(14) null,
	cell int not null,
	lac int not null,
	event_type varchar(1) null,
	event_ts datetime not null
);

IF OBJECT_ID('error_source_output', 'U') IS NOT NULL
	DROP TABLE error_source_output;
CREATE TABLE error_source_output (
	id int IDENTITY (1,1),
    [Flat File Source Error Output Column] varchar(max),
    ErrorCode int,
    ErrorColumn int
)

IF OBJECT_ID('error_destination_output', 'U') IS NOT NULL
	DROP TABLE error_destination_output;
CREATE TABLE error_destination_output (
    id int,
    imsi varchar(9),
    imei varchar(14),
    cell int,
    lac int,
    event_type varchar(1),
    event_ts datetime,
	tac varchar(8),
	snr varchar(6),
    ErrorCode int,
    ErrorColumn int
)


SELECT * FROM fact_transaction

SELECT * FROM error_source_output

SELECT * FROM error_destination_output