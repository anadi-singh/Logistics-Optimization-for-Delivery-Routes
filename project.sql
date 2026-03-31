-- Task 1: Data Cleaning & Preparation

-- Identify and delete duplicate Order_ID records

SELECT Order_ID, COUNT(*) AS duplicate_count
FROM orders
GROUP BY Order_ID
HAVING COUNT(*) > 1;

-- (0 rows affected - no duplicates found)

-- Replace null Traffic_Delay_Min with the average delay for that route

UPDATE routes 
SET 
    Traffic_Delay_Min = (SELECT 
            AVG(Traffic_Delay_Min)
        FROM
            routes)
WHERE
    Traffic_Delay_Min IS NULL;
    
-- 0 rows affected - no nulls found

-- No action needed; dates are already in format

-- Ensure that no Actual_Delivery_Date is before Order_Date (flag such records)

ALTER TABLE orders ADD COLUMN flag TEXT;
UPDATE orders SET flag = 'Invalid' WHERE Actual_Delivery_Date < Order_Date;
SELECT * FROM orders WHERE flag = 'Invalid';

-- (0 rows affected - no invalid records found)

-- Task 2: Delivery Delay Analysis

-- Calculate delivery delay (in days) for each order

SELECT 
    Order_ID,
    Expected_Delivery_Date,
    Actual_Delivery_Date,
    DATEDIFF(Actual_Delivery_Date,
            Expected_Delivery_Date) AS delay_days
FROM
    orders;

-- Find Top 10 delayed routes based on average delay days

SELECT 
    Route_ID,
    AVG(DATEDIFF(Actual_Delivery_Date,
            Expected_Delivery_Date)) AS avg_delay_days
FROM
    orders
GROUP BY Route_ID
ORDER BY avg_delay_days DESC
LIMIT 10;


-- Use window functions to rank all orders by delay within each warehouse

SELECT 
    Order_ID, 
    Warehouse_ID, 
    DATEDIFF(Actual_Delivery_Date, Expected_Delivery_Date) AS delay_days,
    ROW_NUMBER() OVER (PARTITION BY Warehouse_ID ORDER BY DATEDIFF(Actual_Delivery_Date, Expected_Delivery_Date) DESC) AS rank_
FROM orders
ORDER BY Warehouse_ID, delay_days DESC;

-- task 3

-- Average delivery time (in days)

SELECT 
    Route_ID,
    ROUND(AVG(DATEDIFF(Actual_Delivery_Date, Order_Date)),
            4) AS avg_delivery_days
FROM
    orders
GROUP BY Route_ID
ORDER BY Route_ID;

-- Average traffic delay

SELECT 
    Route_ID, Traffic_Delay_Min AS avg_traffic_delay_min
FROM
    routes
ORDER BY Route_ID;

-- Distance-to-time efficiency ratio

SELECT 
    Route_ID, 
    ROUND(Distance_KM / Average_Travel_Time_Min, 4) AS efficiency_ratio
FROM routes
ORDER BY efficiency_ratio ASC;

-- Identify 3 routes with the WORST efficiency ratio

SELECT 
    Route_ID,
    ROUND(Distance_KM / Average_Travel_Time_Min, 4) AS efficiency_ratio
FROM
    routes
ORDER BY efficiency_ratio ASC
LIMIT 3;

-- Find routes with >20% delayed shipments

SELECT 
    Route_ID,
    ROUND((COUNT(CASE
                WHEN Delivery_Status = 'Delayed' THEN 1
            END) * 100.0 / COUNT(*)),
            2) AS delayed_percent
FROM
    orders
GROUP BY Route_ID
HAVING delayed_percent > 20
ORDER BY delayed_percent DESC;

-- RECOMMEND ROUTES FOR OPTIMIZATION

-- Routes with HIGH delay % (>50%) + LOW efficiency (<0.5) + HIGH traffic (>40 min)
-- TOP 5 routes needing optimization (BEST for presentation)
SELECT 
    r.Route_ID,
    r.Traffic_Delay_Min,
    ROUND(r.Distance_KM / r.Average_Travel_Time_Min, 4) AS efficiency,
    ROUND((COUNT(CASE WHEN o.Delivery_Status = 'Delayed' THEN 1 END) * 100.0 / COUNT(*)), 2) AS delayed_percent,
    COUNT(*) AS order_count
FROM routes r
JOIN orders o ON r.Route_ID = o.Route_ID
GROUP BY r.Route_ID, r.Traffic_Delay_Min, r.Distance_KM, r.Average_Travel_Time_Min
HAVING delayed_percent > 50 OR efficiency < 0.5 OR Traffic_Delay_Min > 40
ORDER BY delayed_percent DESC, efficiency ASC
LIMIT 5;


-- Task 4: Warehouse Performance

-- Top 3 warehouses with the highest average processing time

SELECT Warehouse_ID, Processing_Time_Min
FROM warehouses
ORDER BY Processing_Time_Min DESC
LIMIT 3;

-- Total vs. delayed shipments for each warehouse

SELECT 
    Warehouse_ID,
    COUNT(*) AS total,
    COUNT(CASE
        WHEN Delivery_Status = 'Delayed' THEN 1
    END) AS delayed_
FROM
    orders
GROUP BY Warehouse_ID;

-- Use CTEs to find bottleneck warehouses where processing time > global average

WITH global_avg AS (SELECT AVG(Processing_Time_Min) AS avg FROM warehouses)
SELECT w.Warehouse_ID, w.Processing_Time_Min
FROM warehouses w, global_avg g
WHERE w.Processing_Time_Min > g.avg;

-- Rank warehouses based on on-time delivery percentage

SELECT Warehouse_ID, (COUNT(CASE WHEN Delivery_Status = 'On Time' THEN 1 END) * 100.0 / COUNT(*)) AS on_time_percent,
ROW_NUMBER() OVER (ORDER BY (COUNT(CASE WHEN Delivery_Status = 'On Time' THEN 1 END) * 100.0 / COUNT(*)) DESC) AS rank_
FROM orders
GROUP BY Warehouse_ID;

-- insights 
-- W010, W009, W007 have high processing times and are bottlenecks. W008 has the best on-time performance (66%).

-- Task 5: Delivery Agent Performance

-- Rank agents (per route) by on-time delivery percentage

SELECT Agent_ID, Route_ID, On_Time_Percentage, ROW_NUMBER() OVER (PARTITION BY Route_ID ORDER BY On_Time_Percentage DESC) AS rank_
FROM deliveryagents;

-- Find agents with on-time % < 80%

SELECT 
    Agent_ID, Route_ID, On_Time_Percentage
FROM
    deliveryagents
WHERE
    On_Time_Percentage < 80;
    
-- Compare average speed of top 5 vs bottom 5 agents using subqueries

-- STEP 1: Get TOP 5 agents (highest on-time %)
SELECT 'TOP 5 Agents' AS category, 
       ROUND(AVG(Avg_Speed_KM_HR), 2) AS avg_speed_kmh
FROM (
    SELECT Avg_Speed_KM_HR
    FROM deliveryagents
    ORDER BY On_Time_Percentage DESC
    LIMIT 5
) top_agents

UNION ALL


SELECT 'BOTTOM 5 Agents' AS category, 
       ROUND(AVG(Avg_Speed_KM_HR), 2) AS avg_speed_kmh
FROM (
    SELECT Avg_Speed_KM_HR
    FROM deliveryagents
    ORDER BY On_Time_Percentage ASC
    LIMIT 5
) bottom_agents;

-- Task 6: Shipment Tracking Analytics

-- For each order, list the last checkpoint and time

SELECT 
    Order_ID, Checkpoint, Checkpoint_Time
FROM
    shipmenttracking
WHERE
    Checkpoint_Time = (SELECT 
            MAX(Checkpoint_Time)
        FROM
            shipmenttracking s2
        WHERE
            s2.Order_ID = shipmenttracking.Order_ID);
            
-- Find the most common delay reasons (excluding None)

SELECT 
    Delay_Reason, COUNT(*) AS count
FROM
    shipmenttracking
WHERE
    Delay_Reason != 'None'
        AND Delay_Reason IS NOT NULL
GROUP BY Delay_Reason
ORDER BY count DESC
LIMIT 1;

-- Identify orders with >2 delayed checkpoints

SELECT 
    Order_ID, COUNT(*) AS delayed_count
FROM
    shipmenttracking
WHERE
    Delay_Reason != 'None'
        AND Delay_Reason IS NOT NULL
GROUP BY Order_ID
HAVING delayed_count > 2;

-- Task 7: Advanced KPI Reporting

-- Average Delivery Delay per Region (Start_Location

SELECT 
    r.Start_Location,
    ROUND(AVG(DATEDIFF(o.Actual_Delivery_Date,
                    o.Expected_Delivery_Date)),
            2) AS avg_delay_days
FROM
    orders o
        JOIN
    routes r ON o.Route_ID = r.Route_ID
GROUP BY r.Start_Location
ORDER BY avg_delay_days DESC;

-- On-Time Delivery % (Overall)

SELECT 
    ROUND((COUNT(CASE
                WHEN Delivery_Status = 'On Time' THEN 1
            END) * 100.0 / COUNT(*)),
            2) AS on_time_percent
FROM
    orders;
    
-- Average Traffic Delay per Route 

SELECT 
    r.Route_ID, 
    r.Traffic_Delay_Min AS avg_traffic_delay_min
FROM routes r
ORDER BY r.Traffic_Delay_Min DESC;