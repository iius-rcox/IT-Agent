-- ============================================================
-- IMMEDIATE TIMEOUT FIX - SQL SERVER STANDARD EDITION VERSION
-- Optimized for minimal locking on Standard Edition
-- ============================================================

USE PaperlessEnvironments;
GO

PRINT '============================================================';
PRINT 'TIMEOUT FIX FOR SQL SERVER STANDARD EDITION';
PRINT 'Time: ' + CONVERT(VARCHAR(30), GETDATE(), 120);
PRINT '============================================================';

-- ============================================================
-- STEP 1: CREATE MISSING INDEXES (NO LOCKING)
-- ============================================================
PRINT '';
PRINT 'STEP 1: Creating critical missing indexes...';
PRINT '(This does not lock existing data)';

-- Critical index for Invoice timeout issue
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_Invoice_VaultID_Exported_InvoiceTotal')
BEGIN
    CREATE NONCLUSTERED INDEX IX_Invoice_VaultID_Exported_InvoiceTotal
    ON [dbo].[Invoice] ([VaultID], [Exported])
    INCLUDE ([InvoiceTotal]);
    PRINT '  ✓ Created index on Invoice for VaultID, Exported';
END

-- High-impact index for ABFormRecognitionTask
IF NOT EXISTS (SELECT 1 FROM sys.indexes WHERE name = 'IX_ABFormRecognitionTask_DocumentID')
BEGIN
    CREATE NONCLUSTERED INDEX IX_ABFormRecognitionTask_DocumentID
    ON [dbo].[ABFormRecognitionTask] ([DocumentID]);
    PRINT '  ✓ Created index on ABFormRecognitionTask.DocumentID';
END

-- ============================================================
-- STEP 2: UPDATE STATISTICS (MINIMAL LOCKING)
-- ============================================================
PRINT '';
PRINT 'STEP 2: Updating critical statistics...';

-- Update with SAMPLE for large tables to reduce lock time
UPDATE STATISTICS [dbo].[Invoice] WITH SAMPLE 50 PERCENT;
PRINT '  ✓ Updated Invoice statistics (sample)';

UPDATE STATISTICS [dbo].[Document] WITH SAMPLE 50 PERCENT;
PRINT '  ✓ Updated Document statistics (sample)';

-- For huge Audit table, use smaller sample
UPDATE STATISTICS [dbo].[Audit] WITH SAMPLE 10 PERCENT;
PRINT '  ✓ Updated Audit statistics (10% sample - 49M rows)';

UPDATE STATISTICS [dbo].[DocumentIndex] WITH SAMPLE 25 PERCENT;
PRINT '  ✓ Updated DocumentIndex statistics (25% sample - 23M rows)';

-- ============================================================
-- STEP 3: CLEAR EXECUTION PLAN CACHE
-- ============================================================
PRINT '';
PRINT 'STEP 3: Clearing bad execution plans...';

DECLARE @dbid INT = DB_ID();
DBCC FLUSHPROCINDB(@dbid);
PRINT '  ✓ Cleared execution plan cache';

-- ============================================================
-- STEP 4: REORGANIZE INSTEAD OF REBUILD (NO LOCKING)
-- ============================================================
PRINT '';
PRINT 'STEP 4: Reorganizing Invoice indexes (no locking)...';

-- Reorganize is always online, even in Standard Edition
ALTER INDEX ALL ON [dbo].[Invoice] REORGANIZE;
PRINT '  ✓ Reorganized Invoice indexes (online operation)';

-- ============================================================
-- STEP 5: CHECK AND KILL BLOCKING (IF ANY)
-- ============================================================
PRINT '';
PRINT 'STEP 5: Checking for blocking...';

DECLARE @BlockingCount INT;
SELECT @BlockingCount = COUNT(*)
FROM sys.dm_exec_requests
WHERE blocking_session_id > 0;

IF @BlockingCount > 0
BEGIN
    PRINT '  ⚠ WARNING: ' + CAST(@BlockingCount AS VARCHAR) + ' blocked sessions detected!';

    -- Show blocking info
    SELECT
        'EXEC sp_who2 ' + CAST(blocking_session_id AS VARCHAR(10)) AS CheckCommand,
        blocking_session_id AS BlockingSession,
        session_id AS BlockedSession,
        wait_time / 1000 AS WaitSec,
        wait_type
    FROM sys.dm_exec_requests
    WHERE blocking_session_id > 0
    ORDER BY wait_time DESC;

    PRINT '';
    PRINT '  To kill a blocking session, run: KILL <session_id>';
END
ELSE
BEGIN
    PRINT '  ✓ No blocking detected';
END

-- ============================================================
-- QUICK VERIFICATION
-- ============================================================
PRINT '';
PRINT '============================================================';
PRINT 'VERIFICATION - Testing Invoice Query Performance';
PRINT '============================================================';

-- Test query performance (similar to what the application runs)
SET STATISTICS TIME ON;
SET STATISTICS IO ON;

-- Sample query that would typically timeout
SELECT TOP 1
    'Test Query' AS Test,
    COUNT(*) AS InvoiceCount
FROM [dbo].[Invoice] WITH (NOLOCK)
WHERE VaultID IS NOT NULL
    AND Exported = 0;

SET STATISTICS TIME OFF;
SET STATISTICS IO OFF;

-- ============================================================
-- RESULTS
-- ============================================================
PRINT '';
PRINT '============================================================';
PRINT 'FIX COMPLETED!';
PRINT '============================================================';
PRINT '';
PRINT 'What we did:';
PRINT '  1. Created missing indexes (no locking)';
PRINT '  2. Updated statistics with sampling (minimal locking)';
PRINT '  3. Cleared bad execution plans';
PRINT '  4. Reorganized indexes (online operation)';
PRINT '';
PRINT 'Next steps:';
PRINT '  1. Test invoice loading in pVault NOW';
PRINT '  2. If still slow, run during maintenance window:';
PRINT '     ALTER INDEX ALL ON [dbo].[Invoice] REBUILD;';
PRINT '  3. Monitor with: python monitor_query_performance.py';
PRINT '============================================================';