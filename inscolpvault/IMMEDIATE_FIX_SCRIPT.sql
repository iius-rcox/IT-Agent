-- ============================================================
-- IMMEDIATE TIMEOUT FIX FOR PVAULT
-- Run this NOW to resolve timeout issues
-- ============================================================

USE PaperlessEnvironments;
GO

PRINT '============================================================';
PRINT 'STARTING IMMEDIATE TIMEOUT FIX';
PRINT 'Time: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT '============================================================';

-- ============================================================
-- STEP 1: CREATE CRITICAL MISSING INDEXES
-- ============================================================
PRINT '';
PRINT 'STEP 1: Creating critical missing indexes...';

-- Index for ABFormRecognitionTask (Impact: 2299!)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ABFormRecognitionTask_DocumentID')
BEGIN
    CREATE NONCLUSTERED INDEX IX_ABFormRecognitionTask_DocumentID
    ON [dbo].[ABFormRecognitionTask] ([DocumentID]);
    PRINT '  ✓ Created index on ABFormRecognitionTask.DocumentID';
END
ELSE
    PRINT '  → Index on ABFormRecognitionTask.DocumentID already exists';

-- Index for Invoice table (Fixes invoice timeout!)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Invoice_VaultID_Exported_InvoiceTotal')
BEGIN
    CREATE NONCLUSTERED INDEX IX_Invoice_VaultID_Exported_InvoiceTotal
    ON [dbo].[Invoice] ([VaultID], [Exported])
    INCLUDE ([InvoiceTotal]);
    PRINT '  ✓ Created index on Invoice for VaultID, Exported';
END
ELSE
    PRINT '  → Index on Invoice already exists';

-- Index for Batch table
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Batch_VaultID')
BEGIN
    CREATE NONCLUSTERED INDEX IX_Batch_VaultID
    ON [dbo].[Batch] ([VaultID])
    INCLUDE ([Name], [Description], [ScannedByUserID], [AssignedToUserID],
             [CreationDate], [Path], [Notes], [RestrictAccess],
             [BatchStatusID], [DocumentClassID]);
    PRINT '  ✓ Created index on Batch.VaultID';
END
ELSE
    PRINT '  → Index on Batch.VaultID already exists';

-- ============================================================
-- STEP 2: UPDATE ALL STATISTICS (CRITICAL!)
-- ============================================================
PRINT '';
PRINT 'STEP 2: Updating all statistics (this may take a few minutes)...';

-- Update statistics with fullscan on critical tables
UPDATE STATISTICS [dbo].[Audit] WITH FULLSCAN;
PRINT '  ✓ Updated statistics on Audit table (49M rows)';

UPDATE STATISTICS [dbo].[DocumentIndex] WITH FULLSCAN;
PRINT '  ✓ Updated statistics on DocumentIndex (23M rows)';

UPDATE STATISTICS [dbo].[Invoice] WITH FULLSCAN;
PRINT '  ✓ Updated statistics on Invoice table';

UPDATE STATISTICS [dbo].[Document] WITH FULLSCAN;
PRINT '  ✓ Updated statistics on Document table';

-- Update all other statistics
EXEC sp_updatestats;
PRINT '  ✓ Updated all remaining statistics';

-- ============================================================
-- STEP 3: REBUILD FRAGMENTED INDEXES ON INVOICE TABLE
-- ============================================================
PRINT '';
PRINT 'STEP 3: Rebuilding indexes on Invoice table...';

-- Check SQL Server Edition
DECLARE @Edition NVARCHAR(100);
SET @Edition = CAST(SERVERPROPERTY('Edition') AS NVARCHAR(100));

IF @Edition LIKE '%Enterprise%' OR @Edition LIKE '%Developer%'
BEGIN
    -- Enterprise/Developer Edition - Use ONLINE rebuild
    ALTER INDEX ALL ON [dbo].[Invoice] REBUILD WITH (ONLINE = ON);
    PRINT '  ✓ Rebuilt all indexes on Invoice table (ONLINE)';
END
ELSE
BEGIN
    -- Standard Edition - Use OFFLINE rebuild (faster but locks table)
    ALTER INDEX ALL ON [dbo].[Invoice] REBUILD;
    PRINT '  ✓ Rebuilt all indexes on Invoice table (OFFLINE - Standard Edition)';
END

-- ============================================================
-- STEP 4: CLEAR BAD EXECUTION PLANS
-- ============================================================
PRINT '';
PRINT 'STEP 4: Clearing cached execution plans...';

-- Clear plan cache for this database to force new plans
DECLARE @dbid INT = DB_ID();
DBCC FLUSHPROCINDB(@dbid);
PRINT '  ✓ Cleared execution plan cache';

-- ============================================================
-- STEP 5: CHECK FOR CURRENT BLOCKING
-- ============================================================
PRINT '';
PRINT 'STEP 5: Checking for blocking sessions...';

IF EXISTS (
    SELECT 1 FROM sys.dm_exec_requests
    WHERE blocking_session_id > 0
)
BEGIN
    PRINT '  ⚠ WARNING: Blocking detected!';
    SELECT
        'KILL ' + CAST(blocking_session_id AS VARCHAR(10)) + ';' AS KillCommand,
        blocking_session_id AS BlockingSession,
        session_id AS BlockedSession,
        wait_time / 1000 AS WaitTimeSec
    FROM sys.dm_exec_requests
    WHERE blocking_session_id > 0;
END
ELSE
    PRINT '  ✓ No blocking detected';

-- ============================================================
-- STEP 6: OPTIMIZE AUDIT TABLE (LARGEST TABLE)
-- ============================================================
PRINT '';
PRINT 'STEP 6: Optimizing Audit table (49M rows)...';

-- Check if audit table has a clustered index
IF NOT EXISTS (
    SELECT 1 FROM sys.indexes
    WHERE object_id = OBJECT_ID('dbo.Audit')
    AND type_desc = 'CLUSTERED'
)
BEGIN
    PRINT '  ⚠ WARNING: Audit table has no clustered index!';
    PRINT '  → Consider creating a clustered index on the primary key';
END

-- Add index for common audit queries (adjust based on your queries)
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Audit_Date')
AND EXISTS (SELECT 1 FROM sys.columns WHERE object_id = OBJECT_ID('dbo.Audit') AND name = 'AuditDate')
BEGIN
    -- Create filtered index for recent audit records (last 90 days)
    DECLARE @sql NVARCHAR(MAX);
    SET @sql = 'CREATE NONCLUSTERED INDEX IX_Audit_Date
                ON [dbo].[Audit] ([AuditDate])
                WHERE [AuditDate] >= DATEADD(day, -90, GETDATE())';
    EXEC sp_executesql @sql;
    PRINT '  ✓ Created filtered index on Audit.AuditDate (last 90 days)';
END

-- ============================================================
-- VERIFICATION
-- ============================================================
PRINT '';
PRINT '============================================================';
PRINT 'VERIFICATION';
PRINT '============================================================';

-- Show current running queries
PRINT '';
PRINT 'Currently running queries:';
SELECT
    session_id,
    total_elapsed_time / 1000 AS ElapsedSec,
    status,
    command,
    DB_NAME(database_id) AS DatabaseName
FROM sys.dm_exec_requests
WHERE session_id > 50
    AND total_elapsed_time > 5000  -- Over 5 seconds
ORDER BY total_elapsed_time DESC;

-- Show index usage on Invoice table
PRINT '';
PRINT 'Index usage on Invoice table:';
SELECT
    i.name AS IndexName,
    s.user_seeks,
    s.user_scans,
    s.user_lookups,
    s.user_updates
FROM sys.dm_db_index_usage_stats s
INNER JOIN sys.indexes i ON s.object_id = i.object_id AND s.index_id = i.index_id
WHERE s.object_id = OBJECT_ID('dbo.Invoice')
    AND s.database_id = DB_ID();

-- ============================================================
-- COMPLETION
-- ============================================================
PRINT '';
PRINT '============================================================';
PRINT 'IMMEDIATE FIX COMPLETED SUCCESSFULLY!';
PRINT 'Time: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT '============================================================';
PRINT '';
PRINT 'Next Steps:';
PRINT '1. Test the invoice loading functionality NOW';
PRINT '2. Monitor query performance for next 30 minutes';
PRINT '3. If still experiencing timeouts:';
PRINT '   - Increase application timeout to 60 seconds';
PRINT '   - Consider archiving old Audit records (49M rows!)';
PRINT '4. Schedule regular index maintenance';
PRINT '';
PRINT 'To monitor performance, run:';
PRINT '  python monitor_query_performance.py';
PRINT '============================================================';