# 📚 Gravity Bookstore — End-to-End Data Warehouse

> A complete Data Warehouse solution built on the **Gravity Bookstore** transactional database.  
> Covers dimensional modeling (Star Schema), ETL, SSAS Cube, and Power BI dashboards.

---

## 📋 Table of Contents

- [Project Overview](#project-overview)
- [Source Database Analysis](#source-database-analysis)
- [Star Schema Design](#star-schema-design)
- [Table Definitions](#table-definitions)
- [Project Structure](#project-structure)
- [ETL Pipeline](#etl-pipeline)
- [SSAS Cube Design](#ssas-cube-design)
- [Power BI Dashboards](#power-bi-dashboards)
- [How to Run](#how-to-run)
- [Tech Stack](#tech-stack)

---

## Project Overview

This project transforms the **Gravity Bookstore** OLTP database (3NF) into a fully functional Star Schema Data Warehouse using the Microsoft BI stack.

| Layer | Technology |
|---|---|
| Source Database | SQL Server (restored from `.bak`) |
| Data Warehouse | SQL Server — Star Schema |
| ETL | SSIS (SQL Server Integration Services) |
| OLAP Cube | SSAS (SQL Server Analysis Services) |
| Reporting | Power BI |

**Business Process modeled:** Book sales — tracking what books were ordered, by which customers, on what date, via which shipping method, and what the final order status was.

---

## Source Database Analysis

### Source Tables (GravityBooks OLTP — 3NF)

| Table | Description |
|---|---|
| `book` | Book catalog with title, ISBN, pages, publication date |
| `author` | Author names |
| `book_author` | M:N bridge — one book can have many authors |
| `book_language` | Language codes and names |
| `publisher` | Publisher names |
| `customer` | Customer accounts (name, email) |
| `customer_address` | Links customers to addresses with a status flag |
| `address` | Street-level address details |
| `address_status` | Current / Old address flag |
| `country` | Country reference table |
| `cust_order` | Order headers (date, customer, shipping method) |
| `order_line` | Line items — one row per book per order |
| `shipping_method` | Shipping options and their cost |
| `order_history` | Status change events per order |
| `order_status` | Status reference (Pending, Shipped, Delivered…) |

---

## Star Schema Design

![DWH Star Schema](docs/DWH-Schema.png)

```
                         ┌──────────────────────┐
                         │       DimDate         │
                         │──────────────────────│
                         │ DateSK (PK)           │
                         │ Date, Day, DaySuffix  │
                         │ DayOfWeek, DOWInMonth │
                         │ DayOfYear, WeekOfYear │
                         │ WeekOfMonth           │
                         │ Month, MonthName      │
                         │ Quarter, QuarterName  │
                         │ Year, StandardDate    │
                         └───────────┬──────────┘
                                     │ date_sk
                                     │
┌──────────────────┐    ┌────────────┴───────────────┐    ┌──────────────────────┐
│    dim_book      │    │      fact_book_sales        │    │     dim_customer      │
│──────────────────│    │────────────────────────────│    │──────────────────────│
│ book_sk (PK) ────┼────┤ order_id_sk (PK)            ├────┤ customer_sk (PK)     │
│ book_id          │    │ order_id  (degenerate dim)  │    │ customer_id          │
│ title            │    │ customer_sk (FK)            │    │ first_name           │
│ isbn13           │    │ book_sk (FK)                │    │ last_name            │
│ num_pages        │    │ shipping_sk (FK)            │    │ email                │
│ publication_date │    │ date_sk (FK)                │    │ address_status       │
│ language_code    │    │ status_sk (FK)              │    │ city                 │
│ language_name    │    │ total_price   [MEASURE]     │    │ country              │
│ publisher_name   │    │ shipping_cost [MEASURE]     │    │ start_date           │
│ author_name      │    │ quantity_sold [MEASURE]     │    │ end_date             │
│ start_date       │    └────────────┬───────────────┘    │ is_current           │
│ end_date         │                 │                    └──────────────────────┘
│ is_current       │    ┌────────────┴──────┐
└──────────────────┘    │                   │
                        ▼                   ▼
           ┌─────────────────────┐  ┌──────────────────┐
           │    dim_shipping     │  │    dim_status     │
           │─────────────────────│  │──────────────────│
           │ method_sk (PK)      │  │ status_sk (PK)   │
           │ method_id           │  │ order_status_id  │
           │ shipping_method     │  │ order_status     │
           │ start_date          │  └──────────────────┘
           │ end_date            │
           │ is_current          │
           └─────────────────────┘
```

---

## Table Definitions

### ⭐ fact_book_sales
**Grain:** One row per order line item (one book in one customer order).

| Column | Type | Description |
|---|---|---|
| `order_id_sk` | INT (PK) | Surrogate key |
| `order_id` | INT | Degenerate dimension — original order ID from source |
| `customer_sk` | INT (FK) | → dim_customer |
| `book_sk` | INT (FK) | → dim_book |
| `shipping_sk` | INT (FK) | → dim_shipping |
| `date_sk` | INT (FK) | → DimDate |
| `status_sk` | INT (FK) | → dim_status |
| `total_price` | DECIMAL | Line total (unit price × quantity) |
| `shipping_cost` | DECIMAL | Shipping cost for this order |
| `quantity_sold` | INT | Number of copies sold |

---

### 📅 DimDate
Pre-generated calendar dimension. Covers the full range of order dates.

| Column | Description |
|---|---|
| `DateSK` | Surrogate PK — integer in YYYYMMDD format |
| `Date` | Full date value |
| `Day` | Day number (1–31) |
| `DaySuffix` | Ordinal label: 1st, 2nd, 3rd… |
| `DayOfWeek` | 1 = Sunday … 7 = Saturday |
| `DOWInMonth` | Week-of-occurrence within the month (e.g., 2nd Monday) |
| `DayOfYear` | Day number in the year (1–366) |
| `WeekOfYear` | ISO week number (1–53) |
| `WeekOfMonth` | Week number within the month |
| `Month` | Month number (1–12) |
| `MonthName` | January, February … December |
| `Quarter` | 1–4 |
| `QuarterName` | Q1, Q2, Q3, Q4 |
| `Year` | 4-digit year |
| `StandardDate` | Formatted display string (e.g., "January 01, 2024") |

---

### 👤 dim_customer — SCD Type 2
Tracks historical changes to customer details. When name, email, or address changes, the old record is expired and a new current record is inserted — preserving full history.

| Column | Description |
|---|---|
| `customer_sk` | Surrogate PK |
| `customer_id` | Natural key from OLTP source |
| `first_name` | Customer first name |
| `last_name` | Customer last name |
| `email` | Contact email address |
| `address_status` | Current / Old address indicator |
| `city` | Customer city (denormalized from address) |
| `country` | Customer country (denormalized from address) |
| `start_date` | Date this version became active |
| `end_date` | Date this version was replaced (`NULL` = currently active) |
| `is_current` | `1` = active record · `0` = historical |

---

### 📖 dim_book — SCD Type 2
Tracks historical changes to book records (e.g., publisher reassignment, author corrections). Denormalizes language, publisher, and author into a single wide table.

| Column | Description |
|---|---|
| `book_sk` | Surrogate PK |
| `book_id` | Natural key from OLTP source |
| `title` | Book title |
| `isbn13` | 13-digit ISBN |
| `num_pages` | Number of pages |
| `publication_date` | Original publication date |
| `language_code` | e.g., `eng`, `fre`, `ara` |
| `language_name` | e.g., English, French, Arabic |
| `publisher_name` | Denormalized publisher name |
| `author_name` | Denormalized author name(s) |
| `start_date` | SCD2 effective start date |
| `end_date` | SCD2 expiry date (`NULL` = current) |
| `is_current` | `1` = active · `0` = historical |

---

### 🚚 dim_shipping — SCD Type 2
Tracks changes to shipping methods and pricing over time — ensures historical orders reflect the cost at the time of purchase.

| Column | Description |
|---|---|
| `method_sk` | Surrogate PK |
| `method_id` | Natural key from OLTP source |
| `shipping_method` | Method name (e.g., Standard, Express, Overnight) |
| `start_date` | SCD2 effective start date |
| `end_date` | SCD2 expiry date (`NULL` = current) |
| `is_current` | `1` = active · `0` = historical |

---

### 📦 dim_status
Small static reference dimension for order status values. No history needed.

| Column | Description |
|---|---|
| `status_sk` | Surrogate PK |
| `order_status_id` | Natural key from OLTP source |
| `order_status` | e.g., Pending, Shipped, Delivered, Cancelled |

---

### SCD Strategy Summary

| Dimension | SCD Type | Rationale |
|---|---|---|
| `dim_customer` | **Type 2** | Name, email, city can change — order history must reflect who the customer was at time of purchase |
| `dim_book` | **Type 2** | Publisher/author corrections need to be traceable historically |
| `dim_shipping` | **Type 2** | Shipping costs change over time — historical accuracy required |
| `dim_status` | **Type 1** | Status labels are static reference data; no history needed |
| `DimDate` | **Static** | Pre-generated once, never changes |

---

## Project Structure

```
gravity-bookstore-dwh/
│
├── README.md
│
├── sql/
│   ├── 01_Create_DWH_Database.sql        # Creates GravityBooks_DW + schemas
│   ├── 02_Create_Dimension_Tables.sql    # All DIM tables + default (-1) members
│   ├── 03_Create_Fact_Tables.sql         # fact_book_sales + indexes
│   ├── 04_Populate_DimDate.sql           # Generates calendar dimension
│   ├── 05_ETL_Load_Dimensions.sql        # ETL for all dimension tables
│   └── 06_ETL_Load_Facts.sql             # Incremental ETL for fact table
│
├── ssis/
│   └── GravityBooks_ETL.dtsx             # SSIS package (Visual Studio)
│
├── ssas/
│   └── GravityBooks_Cube.bim             # SSAS tabular model definition
│
├── powerbi/
│   └── GravityBooks_Dashboard.pbix       # Power BI report file
│
└── docs/
    ├── DWH-Schema.png                    # Star schema diagram (this image)
    └── source_erd.png                    # OLTP source ERD
```

---

## ETL Pipeline

### Execution Order

```
01_Create_DWH_Database.sql
        ↓
02_Create_Dimension_Tables.sql
        ↓
03_Create_Fact_Tables.sql
        ↓
04_Populate_DimDate.sql
        ↓
05_ETL_Load_Dimensions.sql    ← Must run before fact load
        ↓
06_ETL_Load_Facts.sql         ← Incremental load by order_id
```

### SSIS Control Flow

```
[Execute SQL: Truncate Staging]
        ↓
[DFT: Load DimDate]           — Static, one-time load
        ↓
[DFT: Load dim_customer]      — SCD2 component
        ↓
[DFT: Load dim_book]          — SCD2 component
        ↓
[DFT: Load dim_shipping]      — SCD2 component
        ↓
[DFT: Load dim_status]        — Simple upsert (SCD1)
        ↓
[DFT: Load fact_book_sales]   — Incremental: MAX(order_id_sk)
        ↓
[Execute SQL: Update ETL Log]
```

### SCD Type 2 — Logic per Step

For `dim_customer`, `dim_book`, and `dim_shipping`:

| Step | Action |
|---|---|
| 1 | **Lookup** existing record by natural key where `is_current = 1` |
| 2 | **Compare** source vs current record on tracked columns |
| 3 | **No match** → Insert new row (`is_current=1`, `start_date=today`, `end_date=NULL`) |
| 4 | **Match + changed** → UPDATE old: `end_date=yesterday`, `is_current=0` · INSERT new version |
| 5 | **Match + unchanged** → Skip, no action needed |

---

## SSAS Cube Design

### Measures (from fact_book_sales)

| Measure | Aggregation | Description |
|---|---|---|
| Total Revenue | SUM(`total_price`) | Total sales revenue |
| Total Shipping Cost | SUM(`shipping_cost`) | Total shipping fees collected |
| Total Units Sold | SUM(`quantity_sold`) | Total books sold |
| Total Orders | COUNT DISTINCT(`order_id`) | Unique orders placed |
| Avg Order Value | Revenue ÷ Orders | Average basket size |
| Avg Units per Order | Units ÷ Orders | Average books per order |

### Dimension Hierarchies

| Dimension | Hierarchy |
|---|---|
| DimDate | Year → Quarter → Month → Date |
| dim_customer | Country → City → Customer Name |
| dim_book | Publisher → Book Title |
| dim_shipping | Shipping Method (leaf) |
| dim_status | Order Status (leaf) |

---

## Power BI Dashboards

### Page 1 — Sales Overview
- **KPI Cards:** Total Revenue · Total Orders · Units Sold · Avg Order Value
- **Line Chart:** Monthly revenue trend with Year-over-Year comparison
- **Bar Chart:** Revenue by Quarter
- **Slicers:** Year · Country · Shipping Method · Order Status

### Page 2 — Book Performance
- **Table:** Top 20 Books by Revenue
- **Bar Chart:** Top 10 Authors by Sales
- **Treemap:** Revenue breakdown by Publisher
- **Donut Chart:** Sales split by Language

### Page 3 — Customer Analysis
- **Map Visual:** Orders by Country
- **Bar Chart:** Top 10 Customers by Lifetime Value
- **Line Chart:** New vs Returning customers over time
- **Drill-through Table:** Customer order history

### Page 4 — Shipping & Order Status
- **Bar Chart:** Orders by Shipping Method
- **Stacked Bar:** Order Status distribution by Month
- **Funnel:** Order lifecycle (Pending → Shipped → Delivered)
- **KPI:** Percentage of orders successfully delivered

---

## How to Run

### Prerequisites

- SQL Server 2019+ (Developer or Standard Edition)
- SQL Server Management Studio (SSMS 18+)
- Visual Studio 2019+ with SSIS & SSAS extensions installed
- Power BI Desktop (latest version)

### Step 1 — Restore the Source Database

```sql
RESTORE DATABASE GravityBooks
FROM DISK = 'C:\Backups\gravity_books.bak'
WITH
  MOVE 'GravityBooks'     TO 'C:\SQL_Data\GravityBooks.mdf',
  MOVE 'GravityBooks_log' TO 'C:\SQL_Data\GravityBooks.ldf',
  REPLACE, RECOVERY;
```

### Step 2 — Build the Data Warehouse

Open SSMS and run the scripts in order:

```
01 → 02 → 03 → 04 → 05 → 06
```

### Step 3 — Deploy SSIS Package

1. Open `ssis/GravityBooks_ETL.dtsx` in Visual Studio
2. Update **Connection Managers** with your server name
3. Right-click project → **Deploy**
4. Schedule nightly via **SQL Server Agent**

### Step 4 — Deploy SSAS Cube

1. Open `ssas/GravityBooks_Cube.bim` in Visual Studio
2. Set data source to `GravityBooks_DW`
3. **Build → Deploy**
4. Run **Process Full** to load the cube

### Step 5 — Open Power BI Report

1. Open `powerbi/GravityBooks_Dashboard.pbix` in Power BI Desktop
2. Update data source to your `GravityBooks_DW` server
3. Click **Refresh All**
4. Optionally **Publish** to Power BI Service for sharing

---

## Tech Stack

![SQL Server](https://img.shields.io/badge/SQL_Server-2019-CC2927?logo=microsoftsqlserver&logoColor=white)
![SSIS](https://img.shields.io/badge/SSIS-ETL-0078D4?logo=microsoft&logoColor=white)
![SSAS](https://img.shields.io/badge/SSAS-OLAP_Cube-0078D4?logo=microsoft&logoColor=white)
![Power BI](https://img.shields.io/badge/Power_BI-Dashboard-F2C811?logo=powerbi&logoColor=black)

---

*Built as a graduation Data Warehouse project — full Star Schema design on a real-world bookstore OLTP database.*
