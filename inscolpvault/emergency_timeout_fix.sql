-- ========================================
-- EMERGENCY TIMEOUT FIX FOR PVAULT
-- Run this script to immediately address timeout issues
-- ========================================

USE PaperlessEnvironments;
GO

-- ========================================
-- STEP 1: Update Statistics (Quick Fix)
-- ========================================
PRINT 'Updating statistics on all tables...';

-- Update all statistics in the database
EXEC sp_updatestats;
GO

-- ========================================
-- STEP 2: Clear Query Plan Cache
-- This forces SQL Server to create new, optimized plans
-- ========================================
PRINT 'Clearing query plan cache...';

-- Clear cached plans for this database only
DECLARE @dbid INT = DB_ID();
DBCC FLUSHPROCINDB(@dbid);
GO

-- ========================================
-- STEP 3: Find and Kill Blocking Sessions
-- ========================================
PRINT 'Checking for blocking sessions...';

SELECT
    blocking_session_id AS BlockingSession,
    session_id AS BlockedSession,
    wait_time / 1000 AS WaitTimeSec,
    wait_type,
    DB_NAME(database_id) AS DatabaseName
FROM sys.dm_exec_requests
WHERE blocking_session_id > 0
    AND database_id = DB_ID('PaperlessEnvironments');

-- To kill a blocking session (replace ### with actual session ID):
-- KILL ###;

-- ========================================
-- STEP 4: Identify Missing Indexes
-- ========================================
PRINT 'Identifying missing indexes...';

SELECT TOP 5
    CONVERT(decimal(18,2), user_seeks * avg_total_user_cost * (avg_user_impact * 0.01)) AS IndexAdvantage,
    mid.statement AS TableName,
    'CREATE INDEX IX_' +
    REPLACE(REPLACE(REPLACE(OBJECT_NAME(mid.object_id), '[', ''), ']', ''), ' ', '_') + '_' +
    CAST(mig.index_group_handle AS VARCHAR(10)) +
    ' ON ' + mid.statement + ' (' +
    ISNULL(mid.equality_columns, '') +
    CASE WHEN mid.equality_columns IS NOT NULL AND mid.inequality_columns IS NOT NULL
        THEN ',' ELSE '' END +
    ISNULL(mid.inequality_columns, '') + ')' +
    CASE WHEN mid.included_columns IS NOT NULL
        THEN ' INCLUDE (' + mid.included_columns + ')' ELSE '' END AS CreateIndexStatement
FROM sys.dm_db_missing_index_group_stats AS migs
INNER JOIN sys.dm_db_missing_index_groups AS mig
    ON migs.group_handle = mig.index_group_handle
INNER JOIN sys.dm_db_missing_index_details AS mid
    ON mig.index_handle = mid.index_handle
WHERE mid.database_id = DB_ID()
ORDER BY IndexAdvantage DESC;

-- ========================================
-- STEP 5: Find Large Tables Without Proper Indexes
-- ========================================
PRINT 'Finding large tables that may cause timeouts...';

SELECT TOP 10
    s.name AS SchemaName,
    t.name AS TableName,
    p.rows AS RowCnt,
    COUNT(DISTINCT i.index_id) AS IndexCount,
    CASE
        WHEN p.rows > 10000000 THEN 'CRITICAL - Needs optimization'
        WHEN p.rows > 1000000 THEN 'WARNING - Monitor performance'
        WHEN p.rows > 100000 THEN 'MEDIUM - May need indexing'
        ELSE 'OK'
    END AS Status
FROM sys.tables t
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
INNER JOIN sys.indexes i ON t.object_id = i.object_id
INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
WHERE t.is_ms_shipped = 0
GROUP BY s.name, t.name, p.rows
HAVING p.rows > 100000
ORDER BY p.rows DESC;

-- ========================================
-- STEP 6: Find Fragmented Indexes
-- ========================================
PRINT 'Finding fragmented indexes...';

SELECT
    s.name AS SchemaName,
    t.name AS TableName,
    i.name AS IndexName,
    ps.avg_fragmentation_in_percent AS FragmentationPercent,
    ps.page_count AS PageCount,
    CASE
        WHEN ps.avg_fragmentation_in_percent > 70 THEN 'REBUILD IMMEDIATELY'
        WHEN ps.avg_fragmentation_in_percent > 30 THEN 'REBUILD SOON'
        ELSE 'OK'
    END AS Action
FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ps
INNER JOIN sys.indexes i ON ps.object_id = i.object_id AND ps.index_id = i.index_id
INNER JOIN sys.tables t ON i.object_id = t.object_id
INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
WHERE ps.avg_fragmentation_in_percent > 30
    AND ps.page_count > 1000
    AND i.name IS NOT NULL
ORDER BY ps.avg_fragmentation_in_percent DESC;

-- ========================================
-- STEP 7: Quick Index Rebuild for Critical Tables
-- ========================================
PRINT 'Rebuilding indexes on invoice-related tables...';

-- Rebuild all indexes on tables with 'invoice' in the name
DECLARE @TableName NVARCHAR(256)
DECLARE @SQL NVARCHAR(MAX)

DECLARE table_cursor CURSOR FOR
    SELECT SCHEMA_NAME(schema_id) + '.' + name
    FROM sys.tables
    WHERE name LIKE '%invoice%' OR name LIKE '%status%'

OPEN table_cursor
FETCH NEXT FROM table_cursor INTO @TableName

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @SQL = 'ALTER INDEX ALL ON ' + @TableName + ' REBUILD WITH (ONLINE = ON)'

    BEGIN TRY
        EXEC sp_executesql @SQL
        PRINT 'Rebuilt indexes on ' + @TableName
    END TRY
    BEGIN CATCH
        -- If online rebuild fails, try offline
        SET @SQL = 'ALTER INDEX ALL ON ' + @TableName + ' REBUILD'
        EXEC sp_executesql @SQL
        PRINT 'Rebuilt indexes on ' + @TableName + ' (offline)'
    END CATCH

    FETCH NEXT FROM table_cursor INTO @TableName
END

CLOSE table_cursor
DEALLOCATE table_cursor

-- ========================================
-- STEP 8: Show Current Long-Running Queries
-- ========================================
PRINT 'Current long-running queries...';

SELECT
    r.session_id,
    r.status,
    r.command,
    r.total_elapsed_time / 1000 AS ElapsedSec,
    r.wait_type,
    t.text AS QueryText,
    DB_NAME(r.database_id) AS DatabaseName
FROM sys.dm_exec_requests r
CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
WHERE r.session_id > 50
    AND r.total_elapsed_time > 10000  -- Queries running > 10 seconds
ORDER BY r.total_elapsed_time DESC;

-- ========================================
-- COMPLETION MESSAGE
-- ========================================
PRINT '';
PRINT '========================================';
PRINT 'EMERGENCY FIX COMPLETED';
PRINT '========================================';
PRINT 'Next Steps:';
PRINT '1. Review and create the missing indexes shown above';
PRINT '2. Monitor query performance over the next hour';
PRINT '3. Consider increasing application timeout settings';
PRINT '4. Schedule regular index maintenance';
PRINT '========================================';