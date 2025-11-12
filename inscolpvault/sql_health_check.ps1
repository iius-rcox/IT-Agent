# SQL Server Health Check PowerShell Script
# Server: inscolpvault.insulationsinc.local
# Purpose: Comprehensive health check and diagnostics

param(
    [string]$ServerInstance = "inscolpvault.insulationsinc.local,55859",
    [string]$Database = "PaperlessEnvironments",
    [string]$Username,
    [string]$Password
)

# Import SQL Server module if available
if (Get-Module -ListAvailable -Name SqlServer) {
    Import-Module SqlServer
} elseif (Get-Module -ListAvailable -Name SQLPS) {
    Import-Module SQLPS -DisableNameChecking
}

# Function to execute SQL query
function Execute-SQLQuery {
    param(
        [string]$Query,
        [string]$ServerInstance,
        [string]$Database,
        [string]$Username,
        [string]$Password
    )

    $connectionString = "Server=$ServerInstance;Database=$Database;User Id=$Username;Password=$Password;TrustServerCertificate=True;"

    try {
        $connection = New-Object System.Data.SqlClient.SqlConnection($connectionString)
        $connection.Open()

        $command = $connection.CreateCommand()
        $command.CommandText = $Query
        $command.CommandTimeout = 30

        $adapter = New-Object System.Data.SqlClient.SqlDataAdapter $command
        $dataset = New-Object System.Data.DataSet
        $adapter.Fill($dataset) | Out-Null

        $connection.Close()

        return $dataset.Tables[0]
    }
    catch {
        Write-Host "Error executing query: $_" -ForegroundColor Red
        return $null
    }
}

# Main health check function
function Start-SQLHealthCheck {
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-Host "SQL SERVER HEALTH CHECK" -ForegroundColor Cyan
    Write-Host "=" * 60 -ForegroundColor Cyan
    Write-Host "Server: $ServerInstance"
    Write-Host "Database: $Database"
    Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    Write-Host ""

    # 1. Server Information
    Write-Host "`n[SERVER INFORMATION]" -ForegroundColor Yellow
    Write-Host "-" * 40

    $serverInfoQuery = @"
    SELECT
        @@SERVERNAME AS ServerName,
        SERVERPROPERTY('Edition') AS Edition,
        SERVERPROPERTY('ProductLevel') AS ProductLevel,
        SERVERPROPERTY('ProductVersion') AS ProductVersion,
        SERVERPROPERTY('IsClustered') AS IsClustered,
        SERVERPROPERTY('IsHadrEnabled') AS IsAlwaysOnEnabled
"@

    $serverInfo = Execute-SQLQuery -Query $serverInfoQuery -ServerInstance $ServerInstance -Database $Database -Username $Username -Password $Password

    if ($serverInfo) {
        $serverInfo | Format-Table -AutoSize
    }

    # 2. Database Status
    Write-Host "`n[DATABASE STATUS]" -ForegroundColor Yellow
    Write-Host "-" * 40

    $dbStatusQuery = @"
    SELECT
        name AS DatabaseName,
        state_desc AS Status,
        recovery_model_desc AS RecoveryModel,
        compatibility_level AS CompatLevel,
        is_read_only AS IsReadOnly,
        is_auto_close_on AS AutoClose,
        is_auto_shrink_on AS AutoShrink
    FROM sys.databases
    WHERE name NOT IN ('master', 'tempdb', 'model', 'msdb')
    ORDER BY name
"@

    $dbStatus = Execute-SQLQuery -Query $dbStatusQuery -ServerInstance $ServerInstance -Database $Database -Username $Username -Password $Password

    if ($dbStatus) {
        $dbStatus | Format-Table -AutoSize

        # Check for issues
        foreach ($db in $dbStatus) {
            if ($db.Status -ne 'ONLINE') {
                Write-Host "[WARNING] Database $($db.DatabaseName) is $($db.Status)" -ForegroundColor Red
            }
            if ($db.AutoClose -eq $true) {
                Write-Host "[WARNING] Database $($db.DatabaseName) has AutoClose enabled" -ForegroundColor Yellow
            }
            if ($db.AutoShrink -eq $true) {
                Write-Host "[WARNING] Database $($db.DatabaseName) has AutoShrink enabled" -ForegroundColor Yellow
            }
        }
    }

    # 3. Performance Metrics - CPU
    Write-Host "`n[CPU USAGE - LAST HOUR]" -ForegroundColor Yellow
    Write-Host "-" * 40

    $cpuQuery = @"
    SELECT TOP 10
        SQLProcessUtilization AS SQL_CPU_Percent,
        100 - SystemIdle - SQLProcessUtilization AS Other_CPU_Percent,
        SystemIdle AS System_Idle_Percent,
        record_id,
        EventTime = DATEADD(ms, -1 * (cpu_ticks / (cpu_ticks/ms_ticks)), GETDATE())
    FROM (
        SELECT
            record.value('(./Record/@id)[1]', 'int') AS record_id,
            record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS SystemIdle,
            record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS SQLProcessUtilization,
            timestamp,
            cpu_ticks,
            ms_ticks
        FROM (
            SELECT
                timestamp,
                convert(xml, record) AS record,
                cpu_ticks,
                ms_ticks = cpu_ticks/(cpu_ticks/ms_ticks)
            FROM sys.dm_os_ring_buffers
            CROSS JOIN sys.dm_os_sys_info
            WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
            AND record LIKE '%<SystemHealth>%'
        ) AS x
    ) AS y
    ORDER BY record_id DESC
"@

    $cpuUsage = Execute-SQLQuery -Query $cpuQuery -ServerInstance $ServerInstance -Database $Database -Username $Username -Password $Password

    if ($cpuUsage) {
        $cpuUsage | Select-Object -First 5 | Format-Table -AutoSize

        $avgSQLCPU = ($cpuUsage | Measure-Object -Property SQL_CPU_Percent -Average).Average
        if ($avgSQLCPU -gt 80) {
            Write-Host "[WARNING] High SQL Server CPU usage detected (Avg: $([Math]::Round($avgSQLCPU, 2))%)" -ForegroundColor Red
        }
    }

    # 4. Memory Usage
    Write-Host "`n[MEMORY USAGE]" -ForegroundColor Yellow
    Write-Host "-" * 40

    $memoryQuery = @"
    SELECT
        (physical_memory_in_use_kb/1024) AS Physical_Memory_Used_MB,
        (total_virtual_address_space_kb/1024) AS Total_VAS_MB,
        process_physical_memory_low,
        process_virtual_memory_low,
        (committed_kb/1024) AS Committed_MB,
        (committed_target_kb/1024) AS Committed_Target_MB
    FROM sys.dm_os_process_memory
"@

    $memoryUsage = Execute-SQLQuery -Query $memoryQuery -ServerInstance $ServerInstance -Database $Database -Username $Username -Password $Password

    if ($memoryUsage) {
        $memoryUsage | Format-List

        if ($memoryUsage.process_physical_memory_low -eq 1) {
            Write-Host "[WARNING] Physical memory is low!" -ForegroundColor Red
        }
        if ($memoryUsage.process_virtual_memory_low -eq 1) {
            Write-Host "[WARNING] Virtual memory is low!" -ForegroundColor Red
        }
    }

    # 5. Blocking Sessions
    Write-Host "`n[BLOCKING SESSIONS]" -ForegroundColor Yellow
    Write-Host "-" * 40

    $blockingQuery = @"
    SELECT
        blocking.session_id AS BlockingSessionID,
        blocked.session_id AS BlockedSessionID,
        blocked.wait_time / 1000.0 AS WaitTimeSec,
        blocked.wait_type,
        DB_NAME(blocked.database_id) AS DatabaseName
    FROM sys.dm_exec_requests AS blocked
    INNER JOIN sys.dm_exec_requests AS blocking
        ON blocked.blocking_session_id = blocking.session_id
    WHERE blocked.blocking_session_id > 0
"@

    $blocking = Execute-SQLQuery -Query $blockingQuery -ServerInstance $ServerInstance -Database $Database -Username $Username -Password $Password

    if ($blocking -and $blocking.Rows.Count -gt 0) {
        Write-Host "[ALERT] Blocking detected!" -ForegroundColor Red
        $blocking | Format-Table -AutoSize
    } else {
        Write-Host "[OK] No blocking detected" -ForegroundColor Green
    }

    # 6. Long Running Queries
    Write-Host "`n[LONG-RUNNING QUERIES (>30 seconds)]" -ForegroundColor Yellow
    Write-Host "-" * 40

    $longQueriesQuery = @"
    SELECT TOP 5
        r.session_id AS SessionID,
        r.status AS Status,
        r.command AS Command,
        r.total_elapsed_time / 1000.0 AS ElapsedSec,
        r.cpu_time / 1000.0 AS CPUSec,
        DB_NAME(r.database_id) AS DatabaseName,
        r.wait_type AS WaitType
    FROM sys.dm_exec_requests r
    WHERE r.total_elapsed_time > 30000
        AND r.session_id > 50
    ORDER BY r.total_elapsed_time DESC
"@

    $longQueries = Execute-SQLQuery -Query $longQueriesQuery -ServerInstance $ServerInstance -Database $Database -Username $Username -Password $Password

    if ($longQueries -and $longQueries.Rows.Count -gt 0) {
        Write-Host "[WARNING] Long-running queries detected!" -ForegroundColor Yellow
        $longQueries | Format-Table -AutoSize
    } else {
        Write-Host "[OK] No long-running queries detected" -ForegroundColor Green
    }

    # 7. Database File Sizes
    Write-Host "`n[DATABASE FILE SIZES]" -ForegroundColor Yellow
    Write-Host "-" * 40

    $fileSizesQuery = @"
    SELECT TOP 10
        DB_NAME(database_id) AS DatabaseName,
        type_desc AS FileType,
        name AS FileName,
        size * 8 / 1024.0 AS SizeMB,
        CASE max_size
            WHEN -1 THEN 'Unlimited'
            ELSE CAST(max_size * 8 / 1024.0 AS VARCHAR(20))
        END AS MaxSizeMB
    FROM sys.master_files
    WHERE database_id > 4
    ORDER BY size DESC
"@

    $fileSizes = Execute-SQLQuery -Query $fileSizesQuery -ServerInstance $ServerInstance -Database $Database -Username $Username -Password $Password

    if ($fileSizes) {
        $fileSizes | Format-Table -AutoSize
    }

    # 8. Wait Statistics
    Write-Host "`n[TOP WAIT STATISTICS]" -ForegroundColor Yellow
    Write-Host "-" * 40

    $waitStatsQuery = @"
    SELECT TOP 10
        wait_type AS WaitType,
        wait_time_ms / 1000.0 AS WaitSec,
        waiting_tasks_count AS WaitCount,
        100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS Percentage
    FROM sys.dm_os_wait_stats
    WHERE wait_type NOT IN (
        'CLR_SEMAPHORE', 'LAZYWRITER_SLEEP', 'RESOURCE_QUEUE',
        'SLEEP_TASK', 'SLEEP_SYSTEMTASK', 'SQLTRACE_BUFFER_FLUSH',
        'WAITFOR', 'LOGMGR_QUEUE', 'CHECKPOINT_QUEUE'
    )
    AND wait_time_ms > 0
    ORDER BY wait_time_ms DESC
"@

    $waitStats = Execute-SQLQuery -Query $waitStatsQuery -ServerInstance $ServerInstance -Database $Database -Username $Username -Password $Password

    if ($waitStats) {
        $waitStats | Format-Table -AutoSize
    }

    # Summary and Recommendations
    Write-Host "`n" + "=" * 60 -ForegroundColor Cyan
    Write-Host "HEALTH CHECK SUMMARY" -ForegroundColor Cyan
    Write-Host "=" * 60 -ForegroundColor Cyan

    Write-Host "`n[Recommendations]" -ForegroundColor Yellow
    Write-Host "1. Review any blocking sessions immediately"
    Write-Host "2. Investigate long-running queries for optimization"
    Write-Host "3. Check wait statistics for performance bottlenecks"
    Write-Host "4. Monitor CPU and memory usage trends"
    Write-Host "5. Review database auto-close and auto-shrink settings"
    Write-Host "6. Check database file growth settings and available disk space"

    Write-Host "`n[Health check completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')]" -ForegroundColor Green
}

# Prompt for credentials if not provided
if (-not $Username) {
    $Username = Read-Host "Enter SQL Username"
}
if (-not $Password) {
    $SecurePassword = Read-Host "Enter SQL Password" -AsSecureString
    $Password = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword))
}

# Run the health check
Start-SQLHealthCheck