-- ######################################################## INFO ############################################################

---- Hive Case Study: New York City Taxi & Limousine Commission (TLC)
---- The purpose of this dataset is to get a better understanding of the taxi system so that the city of New York can improve the efficiency of
---- in-city commutes.
---- Authors : Ashutosh Kumar, Nikita Gupta
---- Data source: http://upgrad-labs.cloudenablers.com:50003/filebrowser/download=/common_folder/nyc_taxi_data/yellow_tripdata_2017.csv


-- ################################################### Environment Setup #####################################################:

-- Adding the required JAR file to the class path :
ADD JAR /opt/cloudera/parcels/CDH/lib/hive/lib/hive-hcatalog-core-1.1.0-cdh5.11.2.jar;

-- Defining the partition sizes: 
SET hive.exec.max.dynamic.partitions=100000;
SET hive.exec.max.dynamic.partitions.pernode=100000;

-- Creating database to be used for the case study :

create database if not exists hive_casestudy;
use  hive_casestudy;

-- ############################################# Load the Data ################################################################

-- The dataset has been placed in the HDFS storage of the lab. The path to the data files is as follows: '/common_folder/nyc_taxi_data/'
-- As per the case study instruction using double for float values and int for integers as data types

-- Creating external table to load the data :
create external table if not exists hive_casestudy.tlc_hive_main(
VendorID int,
tpep_pickup_datetime timestamp,
tpep_dropoff_datetime timestamp,
passenger_count int,
trip_distance double,
RatecodeID int,
store_and_fwd_flag string,
PULocationID int,
DOLocationID int,
payment_type int,
fare_amount double,
extra double,
mta_tax double,
tip_amount double,
tolls_amount double,
improvement_surcharge double,
total_amount double

)
ROW FORMAT DELIMITED FIELDS TERMINATED BY ','
LOCATION '/common_folder/nyc_taxi_data/'
tblproperties ("skip.header.line.count"="2"); 
-- skipping the header and blank row while reading 

-- Basic understanding of the data in table:
select * from hive_casestudy.tlc_hive_main limit 10;


select count(*) from hive_casestudy.tlc_hive_main;
-- 1174568 records are there in this table 


-- ################################################# Basic Data Quality Checks ####################################################

-- Ques1 : How many records has each TPEP provider provided? Write a query that summarises the number of records of each provider.

-- If we refer the data dictionary :TPEP provider coresponds to vendor_id.we have 2 vendors : 1= Creative Mobile Technologies, LLC;2= VeriFone Inc.

select vendorid, count(*) as Num_records, 
case 
when vendorid=1 then 'VeriFone Inc.' 
else 'Creative Mobile Technologies' 
end as Vendor_Name
from hive_casestudy.tlc_hive_main 
group by vendorid;
-- Vendor 1 : Creative Mobile Technologies: 527385 records
-- Vendor 2 : VeriFone Inc. : 647183

select 647183/1174568;
-- Around 55% records are from Vendor 2 and rest 45 % will be from Vendor 1.


-- Ques 2 : The data provided is for months November and December only. Check whether the data is consistent, and if not, identify the data 
-- quality issues. Mention all data quality issues in comments.

-- From the data dictionary 'tpep_pickup_datetime' means the The date and time when the meter was engaged and 'tpep_dropoff_datetime' means
-- that 'The date and time when the meter was disengaged'. These two are important columns for determining the valid time which is only 
-- between 01 Nov 2017 till 31st Dec 2017.

-- Hence we can conclude that the invalid trip range will be where 'tpep_pickup_datetime'<01-Nov-2017 and 'tpep_pickup_datetime'>=01-Jan-2018 :
select  vendorid, count(*) from  hive_casestudy.tlc_hive_main 
where tpep_pickup_datetime < '2017-11-1 00:00:00.0' or tpep_pickup_datetime>='2018-01-01 00:00:00.0'
group by vendorid;
-- Looks like vendor 2 is having inconsistent data for 14 records 

-- Considering the drop time 'tpep_dropoff_datetime' now. The drop would have happended next day of last day i.e. 1st Jan 2018, so the invalid
-- drop date would be >=02 Jan 2019:
select  vendorid, count(*) from  hive_casestudy.tlc_hive_main
where tpep_dropoff_datetime < '2017-11-1 00:00:00.0' or tpep_dropoff_datetime>='2018-01-02 00:00:00.0'
group by vendorid;
-- Here also we have vendor2 having 6 inconsidtent data and vendor 1 is having only 1 incorrect data.


select max(tpep_dropoff_datetime), max (tpep_pickup_datetime), min(tpep_pickup_datetime), min(tpep_dropoff_datetime)
from hive_casestudy.tlc_hive_main;
-- Definitely data needs cleansing as we have drop off dates in year 2019 and pickup dates from year 2003.

select vendorid, count(*) from hive_casestudy.tlc_hive_main
where tpep_dropoff_datetime<tpep_pickup_datetime
group by vendorid;
-- So we 73 records for vendor id 1 where the drop time is less than the pickup time, which is logically incorrect for sure.

select vendorid, count(*) from hive_casestudy.tlc_hive_main
where tpep_dropoff_datetime=tpep_pickup_datetime
group by vendorid;
-- We have 3419 records for vendor 1 and 3063 records for vendor 2 where pickup time and drop time are same, this might be valid data where
-- the passenger or driver would have cancelled the ride and hence this data. but since time is same, it can not match in precision of seconds
-- We will eliminate these records.


-- Ques 3: You might have encountered unusual or erroneous rows in the dataset. Can you conclude which vendor is doing a bad job in
-- providing the records using different columns of the dataset? Summarise your conclusions based on every column where these errors are present.
-- For example,  There are unusual passenger count, i.e. 0 which is unusual.

-- Apart from the datetime columns, lets validate the data with the data dictinary to ensure we have correct data :

-- passenger_count : The number of passengers in the vehicle#####################################################################

select passenger_count, count(*) as count_passenger
from  hive_casestudy.tlc_hive_main  
group by passenger_count
order by passenger_count;


--0	6824
--1	827498
--2	176872
--3	50693
--4	24951
--5	54568
--6	33146
--7	12
--8	3
--9	1

-- This is a basic validation where the passenger count >0 , otherwise there should not be a trip data. 
-- So we will eliminate such records during data cleanup.

select vendorid,passenger_count, count(*) 
from  hive_casestudy.tlc_hive_main
where passenger_count in  (0,7,8,9) group by vendorid,passenger_count
order by passenger_count,vendorid;
-- We do have the passenger count more than 6 for 15 records but it can be a valid case where car taken type is bigger car like SUV or limousine.
-- Or there might be kids in the car with family sitting on the parents laps. So , wew will keep this data as data is very small(15).

select  vendorid,count(*)
from  hive_casestudy.tlc_hive_main 
where passenger_count<=0 
group by vendorid;
-- Vendor 1 is having 6813 records and Vendor 2 is having just 11 records.

-- trip_distance:The elapsed trip distance in miles reported by the taximeter.#########################################################

select min(trip_distance), max(trip_distance) from hive_casestudy.tlc_hive_main;
-- min = 0, max = 126.41 miles 

-- 126.41 miles looks to be valid distance considering the huge size of New York city.

select  count(*) from  
hive_casestudy.tlc_hive_main 
where trip_distance<=0;
-- 7402 records where trip distance is 0.

select 7402/1174568;
-- we will ignore this data as zero or negative trip distance does not seems to be valid. This is just 0.006 percent of data.


select  vendorid,count(*)
from  hive_casestudy.tlc_hive_main 
where trip_distance<=0 
group by vendorid;
-- Vendor 1 is having 4217 records and vendor 1 is having 3185 records, so Vendor 1 is more contributing for incorrect data for trip distance.

-- RateCodeID: The final rate code in effect at the end of the trip.###########################################################
-- The valid values here are from 1 to 6 as per the data dictionar.

select  
ratecodeid,count(*) 
from  hive_casestudy.tlc_hive_main 
group by ratecodeid
order by ratecodeid;
-- There are total 9 records where we have invalid rate code id "99". We wil eliminate these records.

select vendorid , count(*) 
from  hive_casestudy.tlc_hive_main 
where ratecodeid=99
group by vendorid;
-- So we have more invalid data for rate id from the vendor 1.


-- Store_and_fwd_flag: This flag indicates whether the trip record was held in vehicle memory before sending to the vendor, 
-- aka “store and forward,” because the vehicle did not have a connection to the server.###########################################
select  
Store_and_fwd_flag,count(*) 
from  hive_casestudy.tlc_hive_main 
group by Store_and_fwd_flag
order by Store_and_fwd_flag;
-- Y = 3951, N = 1170617

select 3951/1174568;
-- So we have 0.0033 percenatge of data where flag is Y, this might be due to temporary network issue or trip where vehicle was not in good
-- mobile network, we will keep this data.


-- Payment_type : A numeric code signifying how the passenger paid for the trip. ###################################################
-- Valid values are between 1 to 6

select Payment_type, count(*) as count_passenger
from  hive_casestudy.tlc_hive_main  
group by Payment_type
order by Payment_type;
-- There are no invalid records and most preferred mode of paymet is 1 (credit card)


-- Fare_amount: The time-and-distance fare calculated by the meter ##################################################################

select max(fare_amount), min(fare_amount) from hive_casestudy.tlc_hive_main;
--  Max fare 650 seems to be valid fare(peak hours, surge in demand, long distance, premier cab etc) but negative fare is not correct , 
-- lets check

select count(*)
from hive_casestudy.tlc_hive_main
where fare_amount <0;
-- We have 558 records where the fare amount is in negative , so this must be due to faulty meter and we will eliminate these records.

select vendorid ,count(*)
from hive_casestudy.tlc_hive_main
where fare_amount <0
group by vendorid;
-- Vendor 2 is the sole contributor for negative fare amount here.


-- Extra: Miscellaneous extras and surcharges. Currently, this only includes the $0.50 and $1 rush hour and overnight charges. So the valid
-- values are 0,0.5 and 1 only. ####################################################################################################

select count(*)
from hive_casestudy.tlc_hive_main
where extra not in(0,0.5,1);
-- 4856 values can be ignored as these are incorrect data.

select vendorid ,count(*)
from hive_casestudy.tlc_hive_main
where extra not in(0,0.5,1)
group by vendorid;
-- Vendor 2 is major contributor with 3033 records and vendor 1 is having 1823 records



-- mta_tax : $0.50 MTA tax that is automatically triggered based on the metered rate in use.######################################
select count(*)
from hive_casestudy.tlc_hive_main
where mta_tax not in(0,0.5);
-- Very small number 548 records are having incorrect values.

select vendorid ,count(*)
from hive_casestudy.tlc_hive_main
where mta_tax not in(0,0.5)
group by vendorid;
-- Vendor 2 is major contributor for incorrect mta_tax with 547 out of 548 records.


-- tip_amount :This field is automatically populated for credit card tips. Cash tips are not included.#############################

select count(*)
from hive_casestudy.tlc_hive_main
where tip_amount<0;
-- 4 records where tip amount is in negative 

select vendorid ,count(*)
from hive_casestudy.tlc_hive_main
where tip_amount<0
group by vendorid;
-- All 4 incorrect records wrt tip amount belongs to vendor 2 here. We will eliminate these records also.


-- tolls_amount : Total amount of all tolls paid in trip #########################################################################
select count(*)
from hive_casestudy.tlc_hive_main
where tolls_amount<0;
-- 3 records where toll amount is in negative 

select vendorid ,count(*)
from hive_casestudy.tlc_hive_main
where tolls_amount<0
group by vendorid;
-- All 3 incorrect records wrt tip amount belongs to vendor 2 here. We will eliminate these records also.


-- improvement_surcharge : $0.30 improvement surcharge assessed trips at the flag drop. The improvement surcharge began being levied in 2015
--                                                                                         #########################################

select max(improvement_surcharge), min(improvement_surcharge) from hive_casestudy.tlc_hive_main;
 -- max =1 , min = -0.3
 
select count(*) 
from  hive_casestudy.tlc_hive_main 
where improvement_surcharge not in (0,0.3); 
-- 562 records in total with invalid data 

select vendorid ,count(*)
from hive_casestudy.tlc_hive_main
where improvement_surcharge not in (0,0.3)
group by vendorid;
-- Again vendor 2 is repsonsible solely for incorrect improvement_surcharge data.


-- total_amount: The total amount charged to passengers. Does not include cash tips.################################################

select min(total_amount), max(total_amount)
from hive_casestudy.tlc_hive_main;
-- Max value seems ok 928 considering the surge in demand, premier rides etc , but min value is negative which is incorrect.


select count(*) from 
hive_casestudy.tlc_hive_main
where total_amount<0;
-- 558 records are having incorrect data.

select vendorid,count(*) 
from hive_casestudy.tlc_hive_main 
where total_amount<0 
group by vendorid;
-- Again vendor 2 is solely responsible for incorrect total amount of bill.


-- Bivariate Analyis of the columns/features ##########################################################################################

-- Scenario1 : When passenger count is 1 , it can not be a group ride (ratecodeId=6) :

select vendorid,count(*) from 
hive_casestudy.tlc_hive_main
where passenger_count=1 
and ratecodeId= 6
group by vendorid;
-- We have total 3 such invalid records and 2 belongs to vendor1 and 1 belong to vendor2.
-- We will remove such erronous data.

-- Scenario2 : Tip Amount is greater than total amount:

select vendorid,count(*) from 
hive_casestudy.tlc_hive_main
where tip_amount > total_amount
group by vendorid;
-- We have total 558 such invalid records and belongs to vendor 2, this has asbe removed.

-- Scenario3 : Tip amount having payment type as Cash: 
-- As per data definition the cash tip is excluded for the tip amount , so mode of payment should not be cash when tip amount >0

select vendorid,count(*) from 
hive_casestudy.tlc_hive_main
where tip_amount > 0
and payment_type =2
group by vendorid;
-- No rrecords so we are good


-- Comprehension/Conclusion : Data Qauality Checks: ##################################################################################
-- We need to identify which vendor is contributing to more erronous data in the given dataset.

-- For following fields/columns Vendor1 (Creative Mobile Technologies) is major contributor for incorrect data :
-- passenger_count
-- trip_distance
-- ratecodeid

-- On the other hand Vendor2(VeriFone Inc.) is major contributor for more number of columns incorrect data :
-- Fare_amount
-- Extra
-- mta_tax
-- tip_amount
-- tolls_amount
-- improvement_surcharge
-- total_amount

-- CONCLUSION : Vendor2(VeriFone Inc.) needs to improvise and work on improving its billing systems to provide reliable data as most of erronous
-- data for the billing related columns are from vendor 2.
-- On the flip side Vendor1 (Creative Mobile Technologies) needs to work with its taxi partners to record the data correctly for the passenger
-- and their trips information.
-- Overall Vendor 2 is majorly contributing to incorrect data.
-- #####################################################################################################################################

-- ##################################### CREATING A CLEAN, ORC PARTITIONED TABLE FOR ANALYSIS ##########################################
-- Before answering the below questions, you need to create a clean, ORC partitioned table for analysis.
-- Remove all the erroneous rows.

--IMPORTANT: Before partitioning any table, make sure you run the below commands.
 
SET hive.exec.max.dynamic.partitions=100000;
SET hive.exec.max.dynamic.partitions.pernode=100000;

-- Selecting required database as default that we have created initially:
use hive_casestudy;


-- Dropping the table if it already exists with same name:
drop table hive_casestudy.tlc_hive_partitioned_orc;

-- As per the assignment instruction we will be using month and year for the partition only:

-- Creating partitioned extrrnal table with compression:
Create external table if not exists hive_casestudy.tlc_hive_partitioned_orc(
vendorid int,
tpep_pickup_datetime timestamp,
tpep_dropoff_datetime timestamp,
passenger_count int,
trip_distance double,
RatecodeID int,
store_and_fwd_flag string,
PULocationID int,
DOLocationID int,
payment_type int,
fare_amount double,
extra double,
mta_tax double,
tip_amount double,
tolls_amount double,
improvement_surcharge double,
total_amount double
)
partitioned by (yr int, mnth int)
stored as orc location '/user/ashutoshind2017_outlook'
tblproperties ("orc.compress"="SNAPPY");

-- Inserting the data in orc table with filter conditions:
insert overwrite table hive_casestudy.tlc_hive_partitioned_orc partition(yr,mnth)
select 
vendorid,
tpep_pickup_datetime,
tpep_dropoff_datetime,
passenger_count,
trip_distance,
RatecodeID,
store_and_fwd_flag,
PULocationID,
DOLocationID,
payment_type,
fare_amount,
extra,
mta_tax,
tip_amount,
tolls_amount,
improvement_surcharge,
total_amount,
year(tpep_pickup_datetime) yr,
month(tpep_pickup_datetime) mnth
from  hive_casestudy.tlc_hive_main
where  (tpep_pickup_datetime >='2017-11-1 00:00:00.0' and tpep_pickup_datetime<'2018-01-01 00:00:00.0') and
(tpep_dropoff_datetime >= '2017-11-1 00:00:00.0' and tpep_dropoff_datetime<'2018-01-02 00:00:00.0') and
(tpep_dropoff_datetime>tpep_pickup_datetime) and
-- and YEAR(tpep_pickup_datetime)= 2017 and MONTH(tpep_pickup_datetime) in (11,12)
(passenger_count >0) and
(trip_distance>0) and 
(ratecodeid!=99) and
(fare_amount>0 ) and
 (extra in (0,0.5,1)) and
 (mta_tax  in (0,0.5)) and 
((tip_amount >=0 and Payment_type=1) or (Payment_type!=1 and tip_amount=0)) and
(tolls_amount >=0) and
(improvement_surcharge in (0,0.3)) and
(total_amount > tip_amount)and
(total_amount>0);

---Checking for data in table
SELECT * FROM hive_casestudy.tlc_hive_partitioned_orc LIMIT 10;

---Checking for total records available
SELECT COUNT(1) FROM hive_casestudy.tlc_hive_partitioned_orc;
-- 1153586

select 1174568-1153586;
-- 20982
select 20982/1174568;
-- 0.017 percentage of the data was removed post data cleaning (20982 records)


-- #####################################################################################################################################

-- ########################################################## ANALYSIS 1 ###############################################################

-- Ques 1 : Compare the overall average fare per trip for November and December: #####################################################

select mnth,round(avg(total_amount),2) as average_total_amount,round(avg(fare_amount),2) as average_total_fare
from hive_casestudy.tlc_hive_partitioned_orc  
group by mnth;

---------------------- OUTPUT ------------------------------

-- 	mnth	average_total_amount	average_total_fare
--	11	          16.19	                12.91
--	12	          15.89	                12.7

------------------------------------------------------------
-- This means that the fare is higher in the month of November 2017 compared to December 2017


-- Ques 2 : Explore the ‘number of passengers per trip’ - how many trips are made by each level of ‘Passenger_count’? Do most people travel
-- solo or with other people? ##########################################################################################################

select passenger_count,round((count(*)*100/1153586),2) as count_percenatge
from hive_casestudy.tlc_hive_partitioned_orc    
group by passenger_count
order by count_percenatge desc;
-- Here 1153586 is total record count in cleaned table 

-- Below are the details of each level of passenger count:

--	passenger_count	count_percenatge
--	    1	            70.82
--      2	            15.15
--	    5	            4.68
--	    3	            4.35
--	    6	            2.85
--	    4	            2.14
--	    7	            0

-- Most of the travellers are solo traveller (71 %), followed by trips having 2 passengers (15%).
-- rest all modes are negligable

-- Ques 3: Which is the most preferred mode of payment? ##############################################################################
select payment_type,
case 
when payment_type=1 then 'Credit card'
when payment_type=2 then 'Cash'
when payment_type=3 then 'No charge'
when payment_type=4 then 'Dispute'
when payment_type=5 then 'Unknown'
else 'Voided trip'
end as payment_method
,round((count(*)*100/1153586),4) as count_percenatge
from hive_casestudy.tlc_hive_partitioned_orc
group by payment_type
order by count_percenatge desc;

------------------- OUTPUT ------------------------

 	payment_type	payment_method	count_percenatge
--          1	        Credit card	67.5418
--          2	        Cash	    31.9576
--          3	        No charge	0.3884
--          4	        Dispute	    0.1123
---------------------------------------------------
-- Rest all modes are negligable
-- Credit card (Payment type =1 is most preferred mode of payment) with 67.5% followed by Cash as second most mode of payment with 32%.


-- Ques 4: What is the average tip paid per trip? Compare the average tip with the 25th, 50th and 75th percentiles and comment whether the 
-- ‘average tip’ is a representative statistic (of the central tendency) of ‘tip amount paid’. Hint: You may use percentile_approx(DOUBLE col, p): 
-- Returns an approximate pth percentile of a numeric column (including floating point types) in the group. ############################


-- Let's first find the average tip paid per trip
select round(avg(tip_amount),2)  
from hive_casestudy.tlc_hive_partitioned_orc;
-- 1.83 dollars is avergae tip paid for the trips.


select percentile_approx(tip_amount,array(0.10,0.25,0.50,0.75,0.90))  
from hive_casestudy.tlc_hive_partitioned_orc;
--  (0.10,0.25,0.50,0.75,0.90)
--   OUTPUT:
-- 	[0.0,0.0,1.3596558779761905,2.45,4.15]

-- From above data we can see that the data is skewed in nature for tip_amount 
-- Here median 1.36 is much lower then the average 1.83 due to the skewness towards higher values
-- Hence mean is not representative statistic of centeral tendency here for tip amount paid.


-- Ques 5:	Explore the ‘Extra’ (charge) variable - what fraction of total trips have an extra charge is levied?
select extra,round((count(*)*100/1153586),4) cnt_precent from (
select case when extra>0 then 1 else 0 end  extra
from hive_casestudy.tlc_hive_partitioned_orc ) T
group by extra
order by cnt_precent desc;

--extra	cnt
--0	    53.8546
--1	    46.1454

-- So around 46% of trips have extra charges. This result is comparable with no extra charge for trips.


-- ########################################################## ANALYSIS 2 ###############################################################

-- Ques 1 :What is the correlation between the number of passengers on any given trip, and the tip paid per trip? Do multiple travellers tip 
-- more compared to solo travellers? Hint: Use CORR(Col_1, Col_2) ######################################################################

select round(corr(passenger_count, tip_amount),4) 
from hive_casestudy.tlc_hive_partitioned_orc;
-- '-0.0053' is the correlation between the passenger count and tip amount.
-- This can be inferred as very weak negative correlation.

--- Verifying correlation by Correlation Coefficient(r)=Cov(x,y)/Sx*Sy

SELECT round(covar_pop(tip_amount, passenger_count)/(stddev_pop(tip_amount)*stddev_pop(passenger_count)),4)
	from hive_casestudy.tlc_hive_partitioned_orc;
-- '-0.0053'
-- The results are comparable for the correlation and Correlation Coefficient, hence verified.


select is_solo,round(avg(tip_amount),4) from 
(select case when passenger_count=1 then 1 else 0 end is_solo,tip_amount 
from hive_casestudy.tlc_hive_partitioned_orc) T 
group by is_solo;
--is_solo	_c1
--0	    1.8023
--1	    1.8354

-- The avergae tip amount for solo and group rides are also almost same.

-- Hence, we can not conclude that if multiple travellers tip more than solo from the data.


-- Ques 2: Segregate the data into five segments of ‘tip paid’: [0-5), [5-10), [10-15) , [15-20) and >=20. Calculate the percentage share of each
-- bucket (i.e. the fraction of trips falling in each bucket). #########################################################################


select tip_range, round((count(*)*100/1153586),4) cnt_percentage
from (select
case when (tip_amount>=0 and tip_amount<5)   then '[0-5)' 
     when (tip_amount>=5 and tip_amount<10)  then '[5-10)' 
     when (tip_amount>=10 and tip_amount<15) then '[10-15)'
     when (tip_amount>=15 and tip_amount<20) then '[15-20)'
     when (tip_amount>=20)                   then '>=20' end Tip_range
     from hive_casestudy.tlc_hive_partitioned_orc) T 
     group by tip_range
     order by cnt_percentage desc;
     
-- OUTPUT :
--	tip_range	cnt_percentage
--1	[0-5)	92.4038
--2	[5-10)	5.638
--3	[10-15)	1.6829
--4	[15-20)	0.1872
--5	>=20	0.0881

-- So, around 92 percentage of tip comes from less than 5 dollars tip range.


-- Ques 3: Which month has a greater average ‘speed’ - November or December? Note that the variable ‘speed’ will have to be derived from 
-- other metrics. Hint: You have columns for distance and time. #######################################################################

-- We know that (Speed = Distance/Time), this can be derived from the data given.
-- Also the datetime is unixtime , so difference will return in seconds, so we will divide it by 3600 to convert seconds difference into 
-- hour difference.


select mnth , round(avg(trip_distance/((unix_timestamp(tpep_dropoff_datetime)-unix_timestamp(tpep_pickup_datetime) )/3600) ),2) avg_speed
from hive_casestudy.tlc_hive_partitioned_orc
group by mnth
order by avg_speed desc;

-- OUTPUT :
-- 	mnth	avg_speed
--1	 12	    11.07
--2  11	    10.97

-- Based on above data we have average speed of 10.97 miles/hour for November month and 11.07 miles/hour for December month.
-- We can conclude that average speed is higher in December month by 0.1 miles/hour may be due to holiday season in December causing less
-- traffic on road due to holiday in multiple offices.


-- Ques 4: Analyse the average speed of the most happening days of the year, i.e. 31st December (New year’s eve) and 25th December (Christmas) 
-- and compare it with the overall average. 


SELECT FROM_UNIXTIME(UNIX_TIMESTAMP(tpep_pickup_datetime), 'dd-MMM-yyyy') as Happening_Day, 
       ROUND(AVG(trip_distance/((UNIX_TIMESTAMP(tpep_dropoff_datetime) - UNIX_TIMESTAMP(tpep_pickup_datetime))/3600)),4) as Avg_Speed_MPH
FROM hive_casestudy.tlc_hive_partitioned_orc
WHERE trip_distance >= 0
AND mnth = 12
AND DAY(tpep_pickup_datetime) IN (25,31)
AND YEAR(tpep_dropoff_datetime) IN (2017)
GROUP BY FROM_UNIXTIME(UNIX_TIMESTAMP(tpep_pickup_datetime), 'dd-MMM-yyyy');
-- OUTPUT :

--  happening_day	avg_speed_mph
--	25-Dec-2017	    15.2655
--  31-Dec-2017	    13.2685

-- So if we compare the December Average speed which was 11.07 Mph is less than the avergae speed on christmans and New Year's eve. 
-- Amongst the Christmas and New Years eve, the average speed is higher on Christmas which is 15.26 Mph which is highest amongst all 3.
-- Average speed on Christmas is around 2 Mph higher than the New Years eve and 4.19 Mph higher than avergae December speed.
-- The higher average speed on happening days clearly suggest that the traffic is less on road may be due to preference of people spending 
-- time with family back at home and also offices are usually closed on these days.

-- ######################################################## End of Hive Case Study ######################################################3