-- =====================================================================
-- Project: MegaMart Retail Sales Data Warehouse & Analytics Pipeline
-- Platform: Google BigQuery
-- Author: Hasna Ait Boui (BI Analyst)
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. TRANSFORM: DIMENSION TABLES
-- ---------------------------------------------------------------------

-- 1.1 Store Dimension Table
-- Cleans headers from raw uploaded stores dataset
CREATE OR REPLACE TABLE `megamart.dim_stores` AS
SELECT
  string_field_0 AS StoreID,
  string_field_1 AS StoreName,
  string_field_2 AS City,
  string_field_3 AS Region
FROM `megamart.stores`
WHERE string_field_0 != 'StoreID';


-- 1.2 Customer Dimension Table
-- PII-minimised: Excludes sensitive personal fields and calculates Age, Tenure, and Demographic Cohorts
CREATE OR REPLACE TABLE `megamart.dim_customer` AS
SELECT
  CustomerID,
  Gender,
  City,
  JoinDate,
  
  -- Calculated Fields
  DATE_DIFF(CURRENT_DATE(), BirthDate, YEAR) AS CustomerAge,
  DATE_DIFF(CURRENT_DATE(), JoinDate, MONTH) AS CustomerTenureMonths,
  
  -- Age Group Binning
  CASE
    WHEN DATE_DIFF(CURRENT_DATE(), BirthDate, YEAR) BETWEEN 18 AND 25 THEN '18-25'
    WHEN DATE_DIFF(CURRENT_DATE(), BirthDate, YEAR) BETWEEN 26 AND 35 THEN '26-35'
    WHEN DATE_DIFF(CURRENT_DATE(), BirthDate, YEAR) BETWEEN 36 AND 50 THEN '36-50'
    WHEN DATE_DIFF(CURRENT_DATE(), BirthDate, YEAR) BETWEEN 51 AND 65 THEN '51-65'
    ELSE '65+'
  END AS AgeGroup
FROM `megamart.customers`;


-- 1.3 Product Dimension Table
CREATE OR REPLACE TABLE `megamart.dim_products` AS
SELECT
  ProductID,
  ProductName,
  Category,
  SubCategory,
  UnitPrice,
  CostPrice
FROM `megamart.products`;


-- ---------------------------------------------------------------------
-- 2. TRANSFORM: FACT TABLE
-- ---------------------------------------------------------------------

-- 2.1 Fact Transactions Table
-- Integrates transactional records with product pricing and derives core revenue, cost, and profit metrics
CREATE OR REPLACE TABLE `megamart.fact_transactions` AS
SELECT
  -- Primary & Foreign Keys
  t.TransactionID,
  t.CustomerID,
  t.ProductID,
  t.StoreID,
  
  -- Attributes & Dates
  PARSE_DATE('%Y-%m-%d', CAST(t.Date AS STRING)) AS TransactionDate,
  t.PaymentMethod,
  
  -- Raw Metrics
  t.Quantity,
  t.Discount,
  p.UnitPrice,
  p.CostPrice,
  
  -- Required Calculated Fields
  ROUND(t.Quantity * p.UnitPrice * (1 - t.Discount), 2) AS TotalRevenue,
  ROUND(t.Quantity * p.CostPrice, 2) AS TotalCost,
  ROUND((t.Quantity * p.UnitPrice * (1 - t.Discount)) - (t.Quantity * p.CostPrice), 2) AS TotalProfit,
  ROUND((p.UnitPrice * (1 - t.Discount)) - p.CostPrice, 2) AS ProfitPerUnit
FROM `megamart.transactions` AS t
LEFT JOIN `megamart.dim_products` AS p
  ON t.ProductID = p.ProductID;


-- ---------------------------------------------------------------------
-- 3. DATA QUALITY & INTEGRITY VALIDATION
-- ---------------------------------------------------------------------

-- 3.1 Duplicate Checks across Dimension and Fact Tables
-- Dimension Stores
SELECT StoreID, COUNT(*) AS count
FROM `megamart.dim_stores`
GROUP BY StoreID
HAVING count > 1;

-- Dimension Products
SELECT ProductID, COUNT(*) AS count
FROM `megamart.dim_products`
GROUP BY ProductID
HAVING count > 1;

-- Dimension Customers
SELECT CustomerID, COUNT(*) AS occurrence_count
FROM `megamart.dim_customer`
GROUP BY CustomerID
HAVING occurrence_count > 1;

-- Fact Transactions
SELECT TransactionID, COUNT(*) AS count
FROM `megamart.fact_transactions`
GROUP BY TransactionID
HAVING count > 1;


-- 3.2 Null & Missing Value Audits
-- Fact Transactions Audit
SELECT
  COUNT(*) AS total_rows,
  COUNTIF(TransactionID IS NULL) AS null_transaction_id,
  COUNTIF(CustomerID IS NULL)    AS null_customer_id,
  COUNTIF(ProductID IS NULL)     AS null_product_id,
  COUNTIF(StoreID IS NULL)       AS null_store_id,
  COUNTIF(TransactionDate IS NULL) AS null_date,
  COUNTIF(PaymentMethod IS NULL)   AS null_payment_method,
  COUNTIF(Quantity IS NULL)      AS null_quantity,
  COUNTIF(Discount IS NULL)      AS null_discount,
  COUNTIF(UnitPrice IS NULL)     AS null_unit_price,
  COUNTIF(CostPrice IS NULL)     AS null_cost_price,
  COUNTIF(TotalRevenue IS NULL)  AS null_total_revenue,
  COUNTIF(TotalCost IS NULL)     AS null_total_cost,
  COUNTIF(TotalProfit IS NULL)   AS null_total_profit,
  COUNTIF(ProfitPerUnit IS NULL) AS null_profit_per_unit
FROM `megamart.fact_transactions`;

-- Dimension Customers Audit
SELECT 
  COUNT(*) AS total_rows,
  COUNTIF(CustomerID IS NULL) AS null_customer_id,
  COUNTIF(Gender IS NULL) AS null_gender,
  COUNTIF(City IS NULL) AS null_city,
  COUNTIF(AgeGroup IS NULL) AS null_age_group,
  COUNTIF(CustomerAge IS NULL) AS null_customer_age,
  COUNTIF(CustomerTenureMonths IS NULL) AS null_customer_tenure_months,
  COUNTIF(JoinDate IS NULL) AS null_JoinDate
FROM `megamart.dim_customer`;

-- Dimension Products Audit
SELECT 
  COUNT(*) AS total_rows, 
  COUNTIF(ProductID IS NULL) AS null_ProductID,
  COUNTIF(ProductName IS NULL) AS null_ProductName,
  COUNTIF(Category IS NULL) AS null_Category,
  COUNTIF(SubCategory IS NULL) AS null_SubCategory,
  COUNTIF(UnitPrice IS NULL) AS null_UnitPrice,
  COUNTIF(CostPrice IS NULL) AS null_CostPrice
FROM `megamart.dim_products`;

-- Dimension Stores Audit
SELECT 
  COUNT(*) AS total_rows,
  COUNTIF(StoreID IS NULL) AS null_StoreID,
  COUNTIF(StoreName IS NULL) AS null_StoreName,
  COUNTIF(City IS NULL) AS null_City,
  COUNTIF(Region IS NULL) AS null_Region
FROM `megamart.dim_stores`;


-- 3.3 Referential Integrity & Orphan Record Check
SELECT
  COUNTIF(c.CustomerID IS NULL) AS orphan_customer_transactions,
  COUNTIF(p.ProductID IS NULL)  AS orphan_product_transactions,
  COUNTIF(s.StoreID IS NULL)    AS orphan_store_transactions
FROM `megamart.fact_transactions` AS f
LEFT JOIN `megamart.dim_customer` AS c ON f.CustomerID = c.CustomerID
LEFT JOIN `megamart.dim_products`  AS p ON f.ProductID  = p.ProductID
LEFT JOIN `megamart.dim_stores`    AS s ON f.StoreID    = s.StoreID;


-- ---------------------------------------------------------------------
-- 4. ANALYTICAL REPORTING LAYER & BI VIEWS
-- ---------------------------------------------------------------------

-- 4.1 Master Reporting View (Denormalized star schema for Tableau / BI tools)
CREATE OR REPLACE VIEW `megamart.vw_sales_reporting` AS
SELECT
  -- Fact Keys & Date
  f.TransactionID,
  f.TransactionDate,
  EXTRACT(YEAR FROM f.TransactionDate) AS TransactionYear,
  EXTRACT(MONTH FROM f.TransactionDate) AS TransactionMonth,
  f.PaymentMethod,
  
  -- Customer Demographics (PII-Minimised)
  c.CustomerID,
  c.Gender,
  c.City AS CustomerCity,
  c.CustomerAge,
  c.AgeGroup,
  c.CustomerTenureMonths,
  
  -- Product Attributes
  p.ProductID,
  p.ProductName,
  p.Category,
  p.SubCategory,
  
  -- Store / Location
  s.StoreID,
  s.StoreName,
  s.City AS StoreCity,
  s.Region AS StoreRegion,
  
  -- Core Financial Metrics
  f.Quantity,
  f.UnitPrice,
  f.CostPrice,
  f.Discount,
  f.TotalRevenue,
  f.TotalCost,
  f.TotalProfit,
  f.ProfitPerUnit
FROM `megamart.fact_transactions` AS f
INNER JOIN `megamart.dim_customer` AS c ON f.CustomerID = c.CustomerID
INNER JOIN `megamart.dim_products`  AS p ON f.ProductID  = p.ProductID
INNER JOIN `megamart.dim_stores`    AS s ON f.StoreID    = s.StoreID;


-- 4.2 Executive KPI Summary Reconciliation Query
SELECT
  -- Transaction & Customer Volume
  COUNT(*) AS total_transactions,
  COUNT(DISTINCT CustomerID) AS active_customers,
  SUM(Quantity) AS total_units_sold,
  
  -- Financial Metrics
  ROUND(SUM(TotalRevenue), 2) AS total_revenue,
  ROUND(SUM(TotalCost), 2) AS total_cost,
  ROUND(SUM(TotalProfit), 2) AS total_profit,
  
  -- Margin & Order Performance
  ROUND(SUM(TotalProfit) / SUM(TotalRevenue) * 100, 2) AS overall_profit_margin_pct,
  ROUND(SUM(TotalRevenue) / COUNT(*), 2) AS average_order_value
FROM `megamart.vw_sales_reporting`;


-- 4.3 Demographic & Age Cohort Performance Breakdown
SELECT
  AgeGroup,
  COUNT(*) AS customer_count,
  ROUND(COUNT(*) * 100.0 / SUM(COUNT(*)) OVER(), 1) AS percentage_share
FROM `megamart.vw_sales_reporting`
GROUP BY AgeGroup
ORDER BY AgeGroup;
