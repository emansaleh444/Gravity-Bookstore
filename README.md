# 📚 Gravity Bookstore — End-to-End Data Warehouse

> A complete Data Warehouse solution built on the **Gravity Bookstore** transactional database.  
> Covers dimensional modeling, ETL, OLAP cube design, and Power BI dashboards.

---

## 📋 Table of Contents

- [Project Overview](#project-overview)
- [Source Database Analysis](#source-database-analysis)
- [Dimensional Model (Star Schema)](#dimensional-model-star-schema)
- [Project Structure](#project-structure)
- [ETL Pipeline](#etl-pipeline)
- [SSAS Cube Design](#ssas-cube-design)
- [Power BI Dashboards](#power-bi-dashboards)
- [How to Run](#how-to-run)
- [Tech Stack](#tech-stack)

---

## Project Overview

This project transforms the **Gravity Bookstore** OLTP database (3NF) into a fully functional Data Warehouse using industry-standard tools and best practices.

| Layer | Technology |
|---|---|
| Source Database | SQL Server (.bak restore) |
| Data Warehouse | SQL Server — Star Schema |
| ETL | SSIS (SQL Server Integration Services) |
| OLAP Cube | SSAS (SQL Server Analysis Services) |
| Reporting | Power BI |

**Business Process modeled:** Book sales — tracking what books were ordered, by which customers, when, how they were shipped, and the full lifecycle of each order.

---

## Source Database Analysis

### Tables in the Source (GravityBooks OLTP)

| Table | Description | Key Columns |
|---|---|---|
| `book` | Book catalog | `book_id`, `title`, `isbn13`, `language_id`, `publisher_id`, `num_pages`, `publication_date` |
| `author` | Author records | `author_id`, `author_name` |
| `book_author` | **M:N bridge** — books ↔ authors | `book_id`, `author_id` |
| `book_language` | Languages | `language_id`, `language_code`, `language_name` |
| `publisher` | Publishers | `publisher_id`, `publisher_name` |
| `customer` | Customer accounts | `customer_id`, `first_name`, `last_name`, `email` |
| `customer_address` | Customer shipping addresses | `customer_id`, `address_id`, `status_id` |
| `address` | Physical addresses | `address_id`, `street_number`, `street_name`, `city`, `country_id` |
| `address_status` | Current / Old status | `status_id`, `address_status` |
| `country` | Countries | `country_id`, `country_name` |
| `cust_order` | Order headers | `order_id`, `order_date`, `customer_id`, `shipping_method_id`, `dest_address_id` |
| `order_line` | Order line items (one per book) | `line_id`, `order_id`, `book_id`, `price` |
| `shipping_method` | Shipping options | `method_id`, `method_name`, `cost` |
| `order_history` | Order status change events | `history_id`, `order_id`, `status_id`, `status_date` |
| `order_status` | Status reference | `status_id`, `status` |

### Key Relationships

```
customer ──< cust_order >── order_line >── book
                                            │
                                         book_author >── author
                                            │
                                         book_language
                                         publisher

cust_order ──< order_history >── order_status
cust_order ──── shipping_method
cust_order ──── address ──── country
```

### Many-to-Many: book_author
A book can have multiple authors, and an author can write multiple books.  
This is resolved in the DWH using a **Bridge Table** (`BridgeBookAuthor`) with a `WeightFactor` column, enabling accurate author-level sales aggregation.

---

## Dimensional Model (Star Schema)

### Fact Tables

#### `fact.FactSales` — Core Sales Fact
**Grain:** One row per order line item (one book per order).

| Column | Type | Description |
|---|---|---|
| `SalesKey` | BIGINT (PK) | Surrogate key |
| `DateKey` | INT (FK) | Order date → DimDate |
| `CustomerKey` | INT (FK) | → DimCustomer |
| `BookKey` | INT (FK) | → DimBook |
| `ShippingMethodKey` | INT (FK) | → DimShippingMethod |
| `OrderStatusKey` | INT (FK) | Latest status → DimOrderStatus |
| `AddressKey` | INT (FK) | Shipping address → DimAddress |
| `OrderID` | INT | Degenerate dimension |
| `OrderLineID` | INT | Degenerate dimension |
| `Quantity` | INT | Number of copies |
| `UnitPrice` | DECIMAL(10,2) | Price at time of sale |
| `LineTotal` | DECIMAL (computed) | Quantity × UnitPrice |
| `ShippingCost` | DECIMAL(6,2) | From shipping_method |

#### `fact.FactOrderHistory` — Order Status Snapshot
**Grain:** One row per order status change event.  
Used for order lifecycle analysis and SLA reporting.

#### `fact.BridgeBookAuthor` — M:N Bridge
Connects `DimBook` to `DimAuthor` with a `WeightFactor` for proportional author credit.

---

### Dimension Tables

#### `dim.DimDate`
Auto-generated calendar from 2000–2030.

| Column | Description |
|---|---|
| `DateKey` | YYYYMMDD integer (PK) |
| `FullDate` | Actual date |
| `DayName`, `MonthName` | Human-readable labels |
| `Quarter`, `QuarterName` | Q1–Q4 |
| `Year`, `MonthNumber` | Numeric breakdowns |
| `IsWeekend`, `IsHoliday` | Boolean flags |

#### `dim.DimCustomer` — SCD Type 2
Tracks historical changes. When a customer updates their name or email, the old record is expired and a new current record is inserted.

| Column | Description |
|---|---|
| `CustomerKey` | Surrogate PK |
| `CustomerID` | Natural key from OLTP |
| `FullName`, `Email` | Customer details |
| `EffectiveDate` | When this version became active |
| `ExpirationDate` | When this version was replaced (NULL = current) |
| `IsCurrent` | 1 = active record |

#### `dim.DimBook` — SCD Type 1
Book details overwrite on change (no history kept for book attributes).

| Column | Description |
|---|---|
| `BookKey` | Surrogate PK |
| `BookID` | Natural key |
| `Title`, `ISBN13` | Book identifiers |
| `LanguageName`, `LanguageCode` | From book_language |
| `PublisherName` | Denormalized from publisher |
| `NumPages`, `PublicationDate` | Book metadata |
| `AuthorNames` | Pipe-separated list: `"Author A \| Author B"` |

#### `dim.DimAuthor`
Separate author dimension for author-level sales analysis.

#### `dim.DimShippingMethod` — SCD Type 1
| Column | Description |
|---|---|
| `ShippingMethodKey` | Surrogate PK |
| `MethodName` | e.g., "Standard", "Express" |
| `Cost` | Shipping fee |

#### `dim.DimOrderStatus`
Small reference dimension. Values: Pending, Shipped, Delivered, Cancelled, etc.

#### `dim.DimAddress`
Geographic dimension combining `address` + `country`.

---

### Star Schema Diagram

```
                        ┌─────────────┐
                        │  DimDate    │
                        └──────┬──────┘
                               │
        ┌──────────────────────┼──────────────────────┐
        │                      │                      │
┌───────┴──────┐    ┌──────────┴──────────┐   ┌───────┴──────┐
│ DimCustomer  │    │     FactSales        │   │   DimBook    │
│  (SCD2)      ├────┤  (Grain: OrderLine) ├───┤  (SCD1)      │
└──────────────┘    │                     │   └──────┬───────┘
                    │  Measures:          │          │
┌──────────────┐    │  • Quantity         │   ┌──────┴───────────┐
│DimShipping   ├────┤  • UnitPrice        │   │ BridgeBookAuthor │
│ Method       │    │  • LineTotal        │   └──────┬───────────┘
└──────────────┘    │  • ShippingCost     │          │
                    │                     │   ┌──────┴───────┐
┌──────────────┐    │  Degenerate:        │   │  DimAuthor   │
│DimOrderStatus├────┤  • OrderID          │   └──────────────┘
└──────────────┘    │  • OrderLineID      │
                    └──────────┬──────────┘
┌──────────────┐               │
│  DimAddress  ├───────────────┘
└──────────────┘
```

---

## Project Structure

```
gravity-bookstore-dwh/
│
├── README.md
│
├── sql/
│   ├── 01_Create_DWH_Database.sql        # Creates GravityBooks_DW database & schemas
│   ├── 02_Create_Dimension_Tables.sql    # All DIM tables + default (-1) members
│   ├── 03_Create_Fact_Tables.sql         # FactSales, FactOrderHistory, Bridge
│   ├── 04_Populate_DimDate.sql           # Generates 2000–2030 calendar
│   ├── 05_ETL_Load_Dimensions.sql        # Full ETL for all dimension tables
│   └── 06_ETL_Load_Facts.sql             # Incremental ETL for fact tables
│
├── ssis/
│   └── GravityBooks_ETL.dtsx             # SSIS package (Visual Studio project)
│
├── ssas/
│   └── GravityBooks_Cube.bim             # SSAS tabular model definition
│
├── powerbi/
│   └── GravityBooks_Dashboard.pbix       # Power BI report file
│
└── docs/
    ├── source_schema.png                 # OLTP ERD
    ├── star_schema.png                   # DWH star schema diagram
    └── etl_flow.png                      # SSIS control flow diagram
```

---

## ETL Pipeline

### Run Order

```
01_Create_DWH_Database.sql
        ↓
02_Create_Dimension_Tables.sql
        ↓
03_Create_Fact_Tables.sql
        ↓
04_Populate_DimDate.sql
        ↓
05_ETL_Load_Dimensions.sql    ← Run BEFORE facts
        ↓
06_ETL_Load_Facts.sql         ← Incremental load
```

### SCD Strategy

| Dimension | SCD Type | Logic |
|---|---|---|
| DimCustomer | **Type 2** | Expire old row, insert new version when name/email changes |
| DimBook | **Type 1** | Overwrite in place (book details rarely change meaningfully) |
| DimAuthor | **Type 1** | Overwrite |
| DimShippingMethod | **Type 1** | Overwrite |
| DimAddress | **Type 1** | Overwrite |
| DimOrderStatus | **Type 1** | Overwrite |

### ETL Logging
Every ETL step writes to `dbo.ETLLog`:
- `StepName` — which dimension or fact was loaded
- `StartTime` / `EndTime`
- `RowsAffected`
- `Status` — Success / Failed
- `ErrorMsg` — captures exception details on failure

### SSIS Control Flow (described)

```
[Execute SQL: Truncate Staging]
        ↓
[DFT: Extract → Transform → Load DimDate]
        ↓
[DFT: Load DimCustomer]  ← SCD2 component
        ↓
[DFT: Load DimBook]      ← Lookup + Conditional Split
        ↓
[DFT: Load DimAuthor]
        ↓
[DFT: Load DimShippingMethod]
        ↓
[DFT: Load DimOrderStatus]
        ↓
[DFT: Load DimAddress]
        ↓
[DFT: Load BridgeBookAuthor]
        ↓
[DFT: Load FactSales]    ← Incremental: max(OrderID)
        ↓
[DFT: Load FactOrderHistory]
        ↓
[Execute SQL: Update ETL Log]
```

---

## SSAS Cube Design

### Measure Group: Sales

| Measure | Aggregation | Description |
|---|---|---|
| Total Revenue | SUM(LineTotal) | Sum of all line totals |
| Total Orders | COUNT DISTINCT(OrderID) | Unique orders |
| Total Units Sold | SUM(Quantity) | Books sold |
| Avg Order Value | Total Revenue / Total Orders | Average basket size |
| Avg Unit Price | AVG(UnitPrice) | Average selling price |
| Total Shipping Cost | SUM(ShippingCost) | Shipping revenue |

### Dimensions & Hierarchies

**DimDate**
```
Year → Quarter → Month → Date
```

**DimCustomer**
```
Customer Name (leaf level)
```

**DimBook**
```
Publisher → Book Title
Language → Book Title
```

**DimAuthor**
```
Author Name (via BridgeBookAuthor)
```

**DimAddress (Geography)**
```
Country → City
```

**DimShippingMethod**
```
Method Name (leaf)
```

**DimOrderStatus**
```
Status Value (leaf)
```

### Cube Relationships
- `FactSales` → all dimensions: **Regular** relationships
- `FactSales` → `DimAuthor` (via `BridgeBookAuthor`): **Many-to-Many** relationship

---

## Power BI Dashboards

### Page 1 — Sales Overview
- **KPI Cards:** Total Revenue · Total Orders · Total Books Sold · Avg Order Value
- **Line Chart:** Monthly Revenue Trend (Year-over-Year comparison)
- **Bar Chart:** Revenue by Quarter
- **Slicer:** Year, Country, Shipping Method

### Page 2 — Book & Author Performance
- **Table:** Top 20 Books by Revenue
- **Bar Chart:** Top 10 Authors by Sales (using bridge table weight)
- **Treemap:** Revenue by Publisher
- **Donut Chart:** Sales split by Language

### Page 3 — Customer Analysis
- **Map Visual:** Orders by Country
- **Bar Chart:** Top 10 Customers by Lifetime Value
- **Line Chart:** New vs Returning customers over time
- **Table:** Customer order history (drill-through enabled)

### Page 4 — Shipping & Operations
- **Bar Chart:** Orders by Shipping Method
- **Stacked Bar:** Order Status distribution by Month
- **Line Chart:** Average days to fulfillment (from order date to Delivered status)
- **Funnel:** Order status flow (Pending → Shipped → Delivered)

---

## How to Run

### Prerequisites
- SQL Server 2019+ (Developer or Standard Edition)
- SQL Server Management Studio (SSMS)
- Visual Studio 2019+ with SSIS / SSAS extensions *(for cube and SSIS)*
- Power BI Desktop *(for dashboard)*

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

Run the SQL scripts in order from SSMS:

```bash
01_Create_DWH_Database.sql
02_Create_Dimension_Tables.sql
03_Create_Fact_Tables.sql
04_Populate_DimDate.sql
05_ETL_Load_Dimensions.sql
06_ETL_Load_Facts.sql
```

### Step 3 — Deploy the SSIS Package
1. Open `ssis/GravityBooks_ETL.dtsx` in Visual Studio
2. Update connection strings in `Connection Managers` to point to your server
3. Right-click the project → **Deploy**
4. Schedule via SQL Server Agent for nightly refresh

### Step 4 — Deploy the SSAS Cube
1. Open `ssas/GravityBooks_Cube.bim` in Visual Studio
2. Set the data source to `GravityBooks_DW`
3. **Build → Deploy**
4. Process the cube (Process Full)

### Step 5 — Open Power BI Dashboard
1. Open `powerbi/GravityBooks_Dashboard.pbix` in Power BI Desktop
2. Update the data source to your `GravityBooks_DW` server
3. Refresh the dataset
4. Optionally publish to Power BI Service

---

## Tech Stack

![SQL Server](https://img.shields.io/badge/SQL_Server-2019-CC2927?logo=microsoftsqlserver&logoColor=white)
![SSIS](https://img.shields.io/badge/SSIS-ETL-0078D4?logo=microsoft&logoColor=white)
![SSAS](https://img.shields.io/badge/SSAS-OLAP_Cube-0078D4?logo=microsoft&logoColor=white)
![Power BI](https://img.shields.io/badge/Power_BI-Dashboard-F2C811?logo=powerbi&logoColor=black)

---

## Author

Built as a graduation project demonstrating end-to-end Data Warehouse engineering on a real-world bookstore transactional database.

---

*Star this repo ⭐ if it helped you understand Data Warehouse design!*



