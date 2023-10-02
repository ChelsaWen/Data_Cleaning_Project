USE Club_member;
RENAME TABLE club_member_info TO clubmember;

-- STEP 1. Find the dirt

-- 1.1 Data Overview --
Select * FROM clubmember; 
-- 1) full name is not consistent in format with extra spaces, special charaters "?"/"-", different cases
-- 2) missing values in martial_status 
-- 3) address with city and state combined


-- 1.2 Check Nulls/Empty Values --
SELECT * FROM clubmember
WHERE full_name = "" OR age = "" OR martial_status = "" OR
		email = "" OR phone = "" OR full_address = "" OR job_title = "" OR membership_date = "";
-- 1) 67 rows contains empty values in martial_status, phone and job_title columns
-- 2) Members chose not to reveal those personal information during registration 


-- 1.3 Check duplicates --
## Duplicate name
SELECT * FROM clubmember
WHERE full_name IN (
	SELECT full_name FROM clubmember
	GROUP BY full_name
	HAVING COUNT(*)>1);

## Duplicate email address
SELECT * FROM clubmember
WHERE email IN (
	SELECT email FROM clubmember
	GROUP BY email
	HAVING COUNT(*)>1);
-- 1) 9 members have duplicate records 
-- 2) Duplicates have differences in martial_status and age, the rest of other information are the same


-- 1.4 Check Outliers --
## Age Range
SELECT MIN(age), MAX(age)
FROM clubmember;
-- Age has values that is out of the normal range: 677

## Date Range
SELECT MIN(str_to_date(membership_date, '%m/%d/%Y')) AS minDate, MAX(str_to_date(membership_date, '%m/%d/%Y')) AS maxDate
FROM clubmember;
-- 1912 is not expected in the record, all the years should be after 2000


-- 1.5 Check impossible values --
## Age
SELECT * FROM clubmember 
WHERE age > 80
ORDER BY age ASC;
-- 15 rows with 3-digits age

## Martial_status 
SELECT DISTINCT martial_status FROM clubmember;
-- Typo "divored"

## Email
SELECT * FROM clubmember
WHERE email NOT LIKE '%@%';
-- No error found in email

## Phone
SELECT * FROM clubmember
WHERE LENGTH(phone) <> 12;
-- Wrong number(e.g. "814-2985") and empty value found in phone


-- 1.6 Check consistency --
-- 1) Uppercase/Lower case in full_name
-- 2) leading or trailing spaces in full_name
-- 3) unexpected characters "?/-" in full_name


-- STEP 2. Scrub the dirt

-- 2.1 Create a new cleaned data table to keep the original raw data --
DROP TABLE IF EXISTS cleaned_clubmember;
CREATE TABLE cleaned_clubmember AS(
SELECT TRIM(BOTH ' ' FROM REGEXP_REPLACE(full_name, '[^a-zA-Z ]', '')) AS fullName, ## remove extra spaces/special characters in name
		IF(LENGTH(age)>2, CONCAT(SUBSTRING(age, 1, LENGTH(age) - 1)), age) AS age, ## remove the 3rd digit in age
		IF(martial_status = "divored", "divorced", martial_status) AS maritalStatus, ## correct typo "divored" to "divorced"
        email, ## keep email column
		IF(LENGTH(phone) <> 12, NULL, phone) AS phone, ## delete invalid phone number
		SUBSTRING_INDEX(full_address, ',', 1) AS address, ## separate address
		SUBSTRING_INDEX(SUBSTRING_INDEX(full_address, ',', -2), ',',1) AS city, ## separate city
		SUBSTRING_INDEX(full_address, ',', -1) AS state, ## separate state
        job_title, ## keep job_title column
        IF(YEAR(STR_TO_DATE(membership_date, '%m/%d/%Y'))<2000, DATE_ADD(STR_TO_DATE(membership_date, '%m/%d/%Y'), INTERVAL 100 YEAR), 
        STR_TO_DATE(membership_date, '%m/%d/%Y')) AS membershipDate ## correct year 19XX to 20XX in date
        FROM clubmember);

-- 2.2 Separate the first name and last name, and capitalize each name, add id column as primary key --
ALTER TABLE cleaned_clubmember
ADD COLUMN id INT AUTO_INCREMENT PRIMARY KEY,
ADD COLUMN firstName VARCHAR(50),
ADD COLUMN lastName VARCHAR(50);

UPDATE cleaned_clubmember
SET  
	firstName =	CONCAT(
		UPPER(LEFT(SUBSTRING_INDEX(fullName, ' ', 1), 1)),
        LOWER(SUBSTRING(SUBSTRING_INDEX(fullName, ' ', 1), 2))
        ), ## capitalize first name
    lastName = CASE 
				WHEN CHAR_LENGTH(fullName) - CHAR_LENGTH(REPLACE(fullName, ' ', '')) <=1 
					THEN  CONCAT(UPPER(LEFT(SUBSTRING_INDEX(fullName, ' ', -1), 1)),
							LOWER(SUBSTRING(SUBSTRING_INDEX(fullName, ' ', -1), 2))) ## capitalize single last name  (e.g. Lush)
				ELSE
					CONCAT(
					UPPER(LEFT(SUBSTRING(fullName, CHAR_LENGTH(SUBSTRING_INDEX(fullName, ' ', 1))+2), 1)),
					LOWER(SUBSTRING(SUBSTRING(fullName, CHAR_LENGTH(SUBSTRING_INDEX(fullName, ' ', 1))+2), 2)) ## capitalize two or more last names (e.g. De la cruz)
					)END
                    LIMIT 5000;

-- 2.3 Convert empty value to NULL, reorganize the table --                    
DROP TABLE IF EXISTS cleanedClubmember;                    
CREATE TABLE cleanedClubmember AS(
	SELECT id, firstName, lastName, age, 
    IF(maritalStatus = '', NULL, maritalStatus) AS maritalStatus, 
    email,
    IF(phone = '', NULL, phone) AS phone,
    address, city, state, 
    IF(job_title = '', NULL, job_title) AS jobTitle, membershipDate 
    FROM cleaned_clubmember);

## Delete the messy cleaned data table
DROP TABLE cleaned_clubmember;

-- 2.4 Delete duplicates --
SET SQL_SAFE_UPDATES = 0; ## turn off safety mode to modify the table
DELETE c1
FROM cleanedClubmember c1
JOIN cleanedClubmember c2
	ON  c1.email = c2.email
    AND c1.id < c2.id;

## Six members with duplicate records had conflicting marital statuses, change their marital status as "uncertain"
UPDATE cleanedClubmember
SET maritalStatus = "uncertain"
WHERE email IN (
	"omaccaughen1o@naver.com", 
    "slamble81@amazon.co.uk", 
    "gprewettfl@mac.com", 
    "mmorralleemj@wordpress.com",
    "greglar4r@answers.com", 
    "ehuxterm0@marketwatch.com");
    

-- STEP 3. Review and check again

-- 3.1 Check new column: city, state --
SELECT city, COUNT(*) AS numCity
FROM cleanedClubmember
GROUP BY city
ORDER BY NumCity DESC;
-- Washington leads with 63 registered members, followed by Houston (45) and Dallas (34)
-- Members are from 385 different cities

SELECT state, COUNT(*) AS numState
FROM cleanedClubmember
GROUP BY state
ORDER BY numState DESC;
-- California has the most registered members (234), followed by Texas (219), Florida (152), New York (106)
-- However, it returns 58 states, which conflicts with the actual number of states in the US (50).
-- The "state" column contains some misspelled states and includes the country "Puerto Rico".

-- 3.2 Add new column "country" to the table, modify invalid values in "state" column --
ALTER TABLE cleanedClubmember
ADD COLUMN country VARCHAR(50);

UPDATE cleanedClubmember
SET country = IF(state = " Puerto Rico", "Puerto Rico", "United States"),
	state = IF(state = " Puerto Rico", "San Juan(PR)", state),
    state = IF(state = "Tej+F823as", "Texas", state),
    state = IF(state = "Tejas", "Texas", state),
    state = IF(state = "Tennesseeee", "Tennessee", state),
	state = IF(state = "Kalifornia", "California", state),
	state = IF(state = "NewYork", "New York", state),
	state = IF(state = "Districts of Columbia", "District of Columbia", state),
	state = IF(state = "South Dakotaaa", "South Dakota", state),
	state = IF(state = "Kansus", "Kansas", state),
	state = IF(state = "NorthCarolina", "North Carolina", state)
;

## Reorganize columns
DROP TABLE IF EXISTS cleaned_clubmember;                    
CREATE TABLE cleaned_clubmember AS(
	SELECT id, firstName, lastName, age, maritalStatus, email, phone, address, city, state, country, jobTitle, membershipDate
    FROM cleanedClubmember);

## Delete messy table
DROP TABLE cleanedClubmember;
