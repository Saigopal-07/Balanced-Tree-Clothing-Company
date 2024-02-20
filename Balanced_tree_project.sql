-- Balanced Tree

-- Total quantity sold for all products:
select sum(qty) as Total_Quantity from balanced_tree.sales


-- The total generated revenue for all products before discounts:
select sum(qty * price) as Total_Revenue from balanced_tree.sales


-- The total discount amount for all products:
select round(sum(qty * price * discount::numeric/100),2)as Total_Discount FROM balanced_tree.sales


-- Unique Transactions:
select Count(distinct(txn_id)) as Unique_Transactions from balanced_tree.sales


-- Average Unique Products:
select round(avg(unique_products)) as Avg_Unique_products 
from (select txn_id, count(distinct(prod_id)) AS unique_products 
from balanced_tree.sales group by txn_id) as unique_products_per_txn;


-- 25th, 50th and 75th percentile values for the revenue per transaction:
with t as
(select txn_id, sum(qty * price) as transaction_revenue from balanced_tree.sales group by 1)
select percentile_cont(0.25)  within group (order by transaction_revenue) as revenue_25percentile,
       percentile_cont (0.50) within group (order by transaction_revenue) as revenue_50percentile,
	   percentile_cont (0.75) within group (order by transaction_revenue) as revenue_75percentile
from t;


-- Average discount value per transaction
with t as
(select txn_id, sum(qty * price * discount ::numeric/100) as Txn_discount from balanced_tree.sales group by txn_id)
select round(avg(Txn_discount),2) as Average_Discount from t;


-- Percentage split of all transactions for members vs non-members 
select
case when member = true then 'Member' else 'NonMember' 
end as Member_Status,
round(count(member) * 100::numeric/ (select Count(member) from balanced_tree.sales)) as member_percentage  
FROM balanced_tree.sales
group by 1;


-- Average revenue for member transactions and non-member transactions
select round(avg(total_revenue_before_discounts)) as Average_revenue_transaction,
case when member = true then 'Member' else 'NonMember' 
end as Member
from (select member, txn_id, SUM(qty * price) AS total_revenue_before_discounts 
from balanced_tree.sales group by txn_id, member) as subquery
group by member;


-- Top 3 products by total revenue before discount
Select s.prod_id, Sum(s.qty * s.price) as revenue_before_discount, pro.product_name
from balanced_tree.sales as s 
join balanced_tree.product_details as pro
on s.prod_id = pro.product_id
group by s.prod_id, pro.product_name
order by revenue_before_discount desc limit 3;


-- The total quantity, revenue, and discount for each segment
Select p.segment_name,  sum(s.qty) as total_quantity, sum(s.qty * s.price) as segment_revenue_before_discount,
sum (round(s.qty * s.price * s.discount ::numeric/100)) as Total_After_Discount
from balanced_tree.sales as s 
join balanced_tree.product_details as p
on s.prod_id = p.product_id
group by p.segment_name;


-- Top selling product for each segment
with t as ( select segment_id, segment_name, product_name, product_id, sum(qty) as Total_qty
from balanced_tree.sales
join balanced_tree.product_details 
on sales.prod_id = product_details.product_id
group by 1, 2, 3, 4
order by segment_id, Total_qty desc)
select distinct on (segment_id) segment_id, segment_name, product_id, product_name, Total_qty
FROM t;



-- Total quantity, revenue and discount for each category
Select p.category_name, sum(s.qty) as total_quantity, sum(s.qty * s.price) as category_revenue,
round(sum (s.qty * s.price * discount::numeric/100),2) AS Total_After_Discount 
from balanced_tree.sales as s 
join balanced_tree.product_details as p
on s.prod_id = p.product_id
group by p.category_name;


-- Top selling product for each category
with t as ( select category_id, category_name, product_name, product_id, sum(qty) as Total_qty,
ROW_NUMBER() over(partition by category_name order by sum(qty) desc) as rn
from balanced_tree.sales join balanced_tree.product_details 
on sales.prod_id = product_details.product_id
group by 1, 2, 3, 4)
select category_id, category_name, product_id, product_name, total_qty
from t
where
(category_name = 'Womens' AND rn = 1) OR
(category_name = 'Mens' AND rn = 1);


-- The percentage split of revenue by product for each segment
with t as ( select segment_id, segment_name, product_name, product_id, sum(qty * sales.price) AS total_revenue_before_discounts
from balanced_tree.sales join balanced_tree.product_details 
on sales.prod_id = product_details.product_id
group by 1, 2, 3, 4)
select *, 
round(100*total_revenue_before_discounts / (sum(total_revenue_before_discounts) over (partition by segment_id)),2) as revenue_percentage
from t
order by segment_id, revenue_percentage desc;

-- The percentage split of revenue by segment for each category
with t as ( select segment_id, segment_name, category_id, category_name, sum(qty * sales.price) as total_revenue_before_discounts
from balanced_tree.sales join balanced_tree.product_details
on sales.prod_id = product_details.product_id
group by 1, 2, 3, 4)
select *, round(100*total_revenue_before_discounts / (sum(total_revenue_before_discounts) over (partition by segment_id)),2) as revenue_percentage
from t
order by category_id, revenue_percentage desc;


-- The percentage split of total revenue by category
select rev.category_id, rev.category_name,
round((rev.TotalRevenue / Ot.Overall_Total::float) * 100)as PercentageSplit
from (select sum(sales.qty * sales.price) as Overall_Total from balanced_tree.sales) as Ot,
(select sum(sales.qty * sales.price) as TotalRevenue,category_id,category_name
from balanced_tree.sales join balanced_tree.product_details
on sales.prod_id = product_details.product_id
group by category_id, category_name) as rev
	

-- What is the total transaction “penetration” for each product? 
select product_id, 	product_name,
round(count(txn_id)::numeric / (select count(distinct txn_id) from balanced_tree.sales), 3) as txn_penetration
from balanced_tree.sales join balanced_tree.product_details
on sales.prod_id = product_details.product_id
group by 1,2 


-- What is the most common combination of at least 1 quantity of any 3 products in a 1 single transaction?
select s.prod_id, t1.prod_id, t2.prod_id, count(*) as combination_cnt       
from balanced_tree.sales s join balanced_tree.sales t1
on t1.txn_id = s.txn_id and s.prod_id < t1.prod_id
join balanced_tree.sales t2 on t2.txn_id = s.txn_id
and t1.prod_id < t2.prod_id
group by 1, 2, 3
order by 4 desc
limit 1;


--  Write a single SQL script that combines all of the previous questions into a scheduled report that the Balanced Tree team can run at the beginning of each month to calculate the previous month’s values
CREATE TEMP TABLE sales_monthly AS
(SELECT *
FROM balanced_tree.sales
WHERE EXTRACT(MONTH FROM start_txn_time) = 1   
AND EXTRACT(YEAR FROM start_txn_time) = 2021);
