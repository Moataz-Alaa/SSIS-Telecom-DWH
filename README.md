# Telecom DWH — SSIS ETL Project

An end-to-end **ETL (Extract, Transform, Load) case study** for a telecom data warehouse. It demonstrates how to ingest large batches of pipe-delimited CSV transaction files into a SQL Server database using **SQL Server Integration Services (SSIS)**, including row-level error handling and file archiving.

---

## Table of Contents

- [Overview](#overview)
- [Repository Structure](#repository-structure)
- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Data Model](#data-model)
- [Source Data Format](#source-data-format)
- [The SSIS Package (`Load Data`)](#the-ssis-package-load-data)
- [Error Handling](#error-handling)
- [Useful Queries](#useful-queries)
- [Notes & Caveats](#notes--caveats)

---

## Overview

The project loads mobile network event/transaction records (identified by IMSI/IMEI, cell and LAC codes, event type and timestamp) from flat CSV files into the `fact_transaction` table of the `SSIS_Telecom_DB` database. A lookup dimension (`dim_imsi_reference`) maps IMSI numbers to subscriber IDs.

Key capabilities demonstrated:

- **ForEach File Enumerator loop** to iterate over all CSV files in a source folder
- **Flat File Source → OLE DB Destination** data flow with derived columns (IMSI split into TAC + SNR, subscriber lookup)
- **Row-level redirection** of bad rows (e.g., malformed IMSI values, nulls in required columns) into dedicated error tables
- **File System Task** that moves each processed file to an archive ("Processed") folder so files are never loaded twice

---

## Repository Structure

```
.
├── SQL Qureries/                     # T-SQL setup scripts
│   ├── Create database.sql           # Creates SSIS_Telecom_DB + fact/error tables
│   └── Create dim imsi reference.sql # Creates + seeds the IMSI→subscriber lookup
├── Source Files/                     # Sample input data (pipe-delimited "CSV" files)
│   ├── 01_clean_data.csv             # Clean test file
│   ├── 02_clean_data_with_null.csv   # File containing null values
│   ├── 03_sample_data.csv            # File with dirty data / bad IMSI lengths
│   ├── batch_01_file_01..05.csv      # Batch 1
│   └── batch_02_file_01..05.csv      # Batch 2
├── Telecom DWH/                      # Visual Studio SSIS-ISV solution
│   ├── Telecom DWH.sln
│   └── Telecom DWH/
│       ├── Telecom DWH.dtproj        # SSIS project file
│       ├── Telecom DWH.database      # Database project reference
│       ├── Load Data.dtsx            # The ETL package
│       └── Project.params            # SSIS project parameters
└── .gitignore
```

---

## Prerequisites

- **Windows** (SSIS tooling is Windows-only)
- **SQL Server** (2016 or later recommended) with the Database Engine running
- **SQL Server Data Tools (SSDT) / MSBuild** — install the *Integration Services project* workload in **Visual Studio 2019/2022** (the solution was saved with VS 17.x)
- Optional: *SQL Server Integration Services* service if you want to deploy the `.ispac` to the SSIS catalog

---

## Getting Started

1. **Create the database and tables.** Run the scripts in `SQL Qureries/` against your SQL Server instance (note: `Create database.sql` **drops and recreates** `SSIS_Telecom_DB` if it already exists):

   ```sql
   -- From the master database context
   :r "SQL Qureries/Create database.sql"
   :r "SQL Qureries/Create dim imsi reference.sql"
   ```

   This creates:
   - `fact_transaction` — target fact table
   - `error_source_output` / `error_destination_output` — error capture tables
   - `dim_imsi_reference` — IMSI → subscriber_id lookup table

2. **Open the solution** `Telecom DWH/Telecom DWH.sln` in Visual Studio with the SSIS workload installed.

3. **Configure connections & variables.** The package uses connection managers pointing at a local instance (`INBOOK_X1_PRO\engmo`, database `SSIS_Telecom_DB`) and file-path variables such as `User::ff_src_folder_path` and `ff_dest_archive`. Update them to match your machine and folders.

4. **Copy source files** from `Source Files/` into the package's input folder (keep `03_sample_data.csv` or similar dirty files to see error handling in action).

5. **Execute `Load Data.dtsx`** (F5 in BIDS/SSDT, or via `dtexec`).

6. **Verify results:**

   ```sql
   SELECT COUNT(*) FROM SSIS_Telecom_DB.dbo.fact_transaction;
   SELECT COUNT(*) FROM SSIS_Telecom_DB.dbo.error_source_output;
   SELECT COUNT(*) FROM SSIS_Telecom_DB.dbo.error_destination_output;
   ```

---

## Data Model

### `fact_transaction`

| Column | Type | Description |
|---|---|---|
| `id` | int (IDENTITY, PK) | Surrogate key |
| `transaction_id` | int | Transaction ID from source file |
| `imsi` | varchar(9) | International Mobile Subscriber Identity (9-digit part) |
| `subscriber_id` | int | Resolved via `dim_imsi_reference` lookup |
| `tac` | varchar(8) | Type Allocation Code — first 8 digits of IMEI |
| `snr` | varchar(6) | Serial Number — remaining 6 digits of IMEI |
| `imei` | varchar(14) | International Mobile Equipment Identity (nullable) |
| `cell` | int | Cell ID |
| `lac` | int | Location Area Code |
| `event_type` | varchar(1) | Event type code (nullable) |
| `event_ts` | datetime | Event timestamp |

### `dim_imsi_reference`

| Column | Type | Description |
|---|---|---|
| `id` | int (IDENTITY, PK) | Surrogate key |
| `imsi` | varchar(9) | IMSI number |
| `subscriber_id` | int | Corresponding subscriber ID |

### Error tables

- **`error_source_output`** — captures raw rows rejected at the Flat File Source (columns: `Flat File Source Error Output Column`, `ErrorCode`, `ErrorColumn`).
- **`error_destination_output`** — captures rows rejected at the OLE DB Destination, with full column detail plus `ErrorCode`/`ErrorColumn`.

---

## Source Data Format

Files are **pipe-delimited (`|`)** with no header row. Each record contains 7 fields:

```
transaction_id|imsi|imei|cell|lac|event_type|event_ts
```

Example (clean row):

```
9105|570476314|32094161834833|3944|24|||30/12/2020 15:47
```

The dataset intentionally includes real-world problems to exercise the ETL logic:

- **Nulls** in optional columns (`02_clean_data_with_null.csv`)
- **Invalid IMSI lengths**, e.g. a 15-digit value where only 9 digits are allowed (`03_sample_data.csv`)
- **Mixed date formats** (`d/m/yyyy H:mm:ss` and `d/m/yyyy H:mm`)
- Timestamps may be missing seconds

The package derives `tac` (first 8 chars of IMEI) and `snr` (last 6 chars) from the IMEI, and looks up `subscriber_id` from `dim_imsi_reference` by IMSI.

---

## The SSIS Package (`Load Data`)

Control flow:

1. **Foreach Loop Container** — `Microsoft.ForEachFileEnumerator` iterates over every `*.csv` file in the source folder.
2. **DFT - Load CSV File to Database** — Data Flow Task per file:
   - `FFSRC CM Transactions` (Flat File Source) reads the current file
   - Derived-column / lookup transformations split the IMEI into `tac` + `snr` and resolve `subscriber_id`
   - `OLEDB DEST CM SSIS_Telecom_DB` bulk-inserts rows into `fact_transaction`
   - Rows with conversion/validation errors are **redirected** to the error outputs feeding `error_source_output` and `error_destination_output`
3. **Move File to Processed** — `Microsoft.FileSystemTask` archives the completed file to the destination folder (variable `ff_dest_archive`), preventing duplicate loads on subsequent runs.

A pre-built deployment artifact is available at `Telecom DWH/Telecom DWH/bin/Development/Telecom DWH.ispac`; import it into the SSIS catalog (`SSISDB`) to deploy without Visual Studio.

---

## Error Handling

Both the source and destination components use **RedirectRow** error output dispositions:

- Rows that fail column conversion at the Flat File Source (e.g., non-numeric dates, oversized IMSI strings) land in **`error_source_output`**.
- Rows that violate destination constraints (e.g., NULL in a NOT NULL column such as `imsi`, `cell`, `lac`, or `event_ts`) land in **`error_destination_output`** along with their `ErrorCode` and `ErrorColumn`, which can be decoded with `map_error`-style lookups or `sys.dm_xe...`/`sp_ssis_*` helpers.

This keeps the main load uninterrupted while preserving a full audit trail of rejected records.

---

## Useful Queries

```sql
USE SSIS_Telecom_DB;

-- What was loaded?
SELECT TOP 100 * FROM fact_transaction ORDER BY id DESC;

-- What failed, and why?
SELECT * FROM error_source_output;
SELECT * FROM error_destination_output ORDER BY ErrorCode;

-- Row-count sanity check per event type
SELECT event_type, COUNT(*) AS cnt
FROM fact_transaction
GROUP BY event_type;
```

---

## Notes & Caveats

- ⚠️ **`Create database.sql` is destructive**: it drops any existing `SSIS_Telecom_DB` before recreating it. Do not run it against a populated environment.
- Connection strings and paths inside the `.dtsx` reference the original author's machine (`INBOOK_X1_PRO\engmo`) and must be reconfigured locally.
- Files under `Telecom DWH/Telecom DWH/obj/` and `bin/` are build artifacts and can be safely deleted/regenerated.
