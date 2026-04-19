-- SECTION 1: Exploratory Data Analysis: Understanding the Data

-- Preview datasets
SELECT * 
FROM workspace.default.bright_tv_user_profile 
LIMIT 10;

SELECT * 
FROM workspace.default.bright_tv_viewership 
LIMIT 10;

-- Check data completeness (user profile)
SELECT 
    COUNT(*) AS total_users,
    SUM(CASE WHEN Age = 0 OR Age IS NULL THEN 1 ELSE 0 END) AS Missing_Age,
    SUM(CASE WHEN Gender IS NULL OR Gender = 'None' THEN 1 ELSE 0 END) AS Missing_Gender,
    SUM(CASE WHEN Province IS NULL OR Province = 'None' THEN 1 ELSE 0 END) AS Missing_Province,
    SUM(CASE WHEN Race IS NULL OR Race = 'None' THEN 1 ELSE 0 END) AS Missing_Race
FROM workspace.default.bright_tv_user_profile;

-- Distribution of demographics
SELECT Gender, COUNT(*) AS Users
FROM workspace.default.bright_tv_user_profile 
GROUP BY Gender
ORDER BY Users DESC;

SELECT Race, COUNT(*) AS Users
FROM workspace.default.bright_tv_user_profile 
GROUP BY Race
ORDER BY Users DESC;


-- Viewership overview
SELECT 
    COUNT(*) AS Total_Sessions,
    COUNT(DISTINCT UserID) AS Active_Users
FROM workspace.default.bright_tv_viewership;

-- Sessions per user (engagement)
SELECT 
    UserID,
    COUNT(*) AS Total_Sessions
FROM workspace.default.bright_tv_viewership
GROUP BY UserID
ORDER BY Total_Sessions DESC;

-- Daily usage trend (raw UTC)
SELECT 
    DATE(`Duration 2`) AS View_Date,
    COUNT(*) AS Sessions
FROM workspace.default.bright_tv_viewership
GROUP BY DATE(`Duration 2`)
ORDER BY View_Date;

-- Hourly usage trend
SELECT 
    HOUR(`Duration 2`) AS Hour_utc,
    COUNT(*) AS Sessions
FROM workspace.default.bright_tv_viewership
GROUP BY HOUR(`Duration 2`)
ORDER BY Hour_utc;


-- SECTION 2: This section: Main Code
WITH joined AS (
  SELECT 
    V.UserID,
    COALESCE(U.GENDER, 'No_Gender') AS Gender,
    COALESCE(U.RACE, 'No_Race') AS Race,
    COALESCE(U.AGE, 0) AS Age,
    COALESCE(U.PROVINCE, 'No_Province') AS Province,
    COALESCE(V.CHANNEL2, 'No_Channel') AS Channel2,
    V.RecordDate2,
    V.`Duration 2` AS Duration_2,

    -- Try multiple formats: with seconds, without seconds, ISO format
    COALESCE(
      TRY_TO_TIMESTAMP(V.RecordDate2, 'M/d/yyyy H:mm:ss'),
      TRY_TO_TIMESTAMP(V.RecordDate2, 'M/d/yyyy H:mm'),
      TRY_TO_TIMESTAMP(V.RecordDate2, 'M/d/yyyy'),
      TRY_TO_TIMESTAMP(V.RecordDate2, 'yyyy-MM-dd HH:mm:ss')
    ) AS Parsed_TS
  FROM workspace.default.bright_tv_viewership V
  LEFT JOIN workspace.default.bright_tv_user_profile  U 
    ON V.UserID = U.UserID
),
parsed AS (
  SELECT *, 
    COALESCE(
      TRY_TO_TIMESTAMP(Duration_2, 'yyyy-MM-dd HH:mm:ss'),
      TRY_TO_TIMESTAMP(Duration_2, 'HH:mm:ss'),
      TRY_TO_TIMESTAMP(Duration_2, 'H:mm:ss'),
      TRY_TO_TIMESTAMP(Duration_2, 'H:mm')
    ) AS Duration_TS,
   
    -- Convert UTC to SAST
    CONVERT_TIMEZONE('UTC', 'Africa/Johannesburg', Parsed_TS) AS SAST_Time
  FROM joined
),
enhanced AS (
  SELECT 
    UserID,
    TO_DATE(SAST_Time) AS Record_Date,
    DATE_FORMAT(SAST_Time, 'HH:mm:ss') AS Record_Time,
    
    -- Use SAST_Time for time buckets
    CASE 
      WHEN HOUR(SAST_Time) BETWEEN 5 AND 11 THEN 'Morning_Viewing'
      WHEN HOUR(SAST_Time) BETWEEN 12 AND 17 THEN 'Afternoon_Viewing'
      WHEN HOUR(SAST_Time) BETWEEN 18 AND 23 THEN 'Evening_Viewing'
      WHEN HOUR(SAST_Time) BETWEEN 0 AND 4 THEN 'Midnight_Viewing'
      ELSE 'Other'
    END AS Time_Buckets,
    
    -- Age groups
    CASE 
      WHEN Age IS NULL OR Age = 0 THEN 'No Age'
      WHEN Age < 12 THEN 'Child'
      WHEN Age BETWEEN 12 AND 18 THEN 'Teenager'
      WHEN Age BETWEEN 19 AND 30 THEN 'Young Adult'
      WHEN Age BETWEEN 31 AND 50 THEN 'Adult'
      WHEN Age > 50 THEN 'Senior Citizen'
      ELSE 'Other'
    END AS Age_Group,
    Gender,
    Race,
    Province,
    Channel2,
    
    -- Duration formatting
    COALESCE(DATE_FORMAT(Duration_TS, 'HH:mm:ss'), '00:00:00') AS Duration,
    COALESCE(
      HOUR(Duration_TS) * 60 + MINUTE(Duration_TS) + SECOND(Duration_TS) / 60.0,
      0
    ) AS Duration_Minutes,
    -- Month and Day
    MONTHNAME(TO_DATE(SAST_Time)) AS Month_Name,
    DAYNAME(TO_DATE(SAST_Time)) AS Day_Name
  FROM parsed
)
SELECT DISTINCT 
  UserID,
  Record_Date,
  Record_Time,
  Month_Name,
  Day_Name,
  Time_Buckets,
  Age_Group,
  Gender,
  Race,
  Province,
  Channel2,
  Duration,
  CASE 
    WHEN Duration_Minutes BETWEEN 0 AND 30 THEN 'Low Consumption'
    WHEN Duration_Minutes BETWEEN 31 AND 179 THEN 'Medium Consumption'
    WHEN Duration_Minutes BETWEEN 180 AND 359 THEN 'High Consumption'
    ELSE 'High Consumption'
  END AS Engagement_Bucket
FROM enhanced
ORDER BY 
  Record_Date, 
  Month_Name, 
  Day_Name, 
  Record_Time, 
  Time_Buckets, 
  Age_Group, 
  Province, 
  Channel2;
