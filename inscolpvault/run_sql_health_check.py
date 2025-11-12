"""
Non-interactive SQL Server Health Check Runner
Usage: python run_sql_health_check.py --username YOUR_USER --password YOUR_PASS
"""

import argparse
import pyodbc
import sys
from datetime import datetime
import traceback

def run_health_check(server, database, username, password, port=55859):
    """Run comprehensive SQL Server health check"""

    print("="*60)
    print("SQL SERVER HEALTH CHECK")
    print("="*60)
    print(f"Server: {server}:{port}")
    print(f"Database: {database}")
    print(f"Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
    print("="*60)

    # Connection string - try ODBC Driver 18 first, then 17
    drivers = ["ODBC Driver 18 for SQL Server", "ODBC Driver 17 for SQL Server"]
    connection = None

    for driver in drivers:
        connection_string = (
            f"DRIVER={{{driver}}};"
            f"SERVER={server},{port};"
            f"DATABASE={database};"
            f"UID={username};"
            f"PWD={password};"
            f"TrustServerCertificate=yes;"
            f"Encrypt=yes;"
        )

        try:
            print(f"\n[INFO] Connecting to {server} with {driver}...")
            connection = pyodbc.connect(connection_string, timeout=30)
            print(f"[SUCCESS] Connected to SQL Server using {driver}\n")
            cursor = connection.cursor()
            break
        except pyodbc.Error:
            if driver == drivers[-1]:  # Last driver in list
                raise
            continue

        # 1. SERVER INFORMATION
        print("\n" + "="*60)
        print("SERVER INFORMATION")
        print("="*60)

        cursor.execute("""
            SELECT
                @@SERVERNAME AS ServerName,
                SERVERPROPERTY('Edition') AS Edition,
                SERVERPROPERTY('ProductLevel') AS ProductLevel,
                SERVERPROPERTY('ProductVersion') AS ProductVersion,
                SERVERPROPERTY('IsClustered') AS IsClustered
        """)

        result = cursor.fetchone()
        if result:
            print(f"Server Name: {result.ServerName}")
            print(f"Edition: {result.Edition}")
            print(f"Product Level: {result.ProductLevel}")
            print(f"Product Version: {result.ProductVersion}")
            print(f"Is Clustered: {result.IsClustered}")

        # 2. DATABASE STATUS
        print("\n" + "="*60)
        print("DATABASE STATUS")
        print("="*60)

        cursor.execute("""
            SELECT
                name AS DatabaseName,
                state_desc AS Status,
                recovery_model_desc AS RecoveryModel,
                compatibility_level AS CompatibilityLevel,
                is_auto_close_on AS AutoClose,
                is_auto_shrink_on AS AutoShrink
            FROM sys.databases
            WHERE name NOT IN ('master', 'tempdb', 'model', 'msdb')
            ORDER BY name
        """)

        databases = cursor.fetchall()
        if databases:
            print(f"\n{'Database':<30} {'Status':<15} {'Recovery':<15} {'AutoClose':<10} {'AutoShrink':<10}")
            print("-"*80)
            for db in databases:
                print(f"{db.DatabaseName:<30} {db.Status:<15} {db.RecoveryModel:<15} {str(db.AutoClose):<10} {str(db.AutoShrink):<10}")
                if db.Status != 'ONLINE':
                    print(f"  [WARNING] Database is {db.Status}!")
                if db.AutoClose:
                    print(f"  [WARNING] AutoClose is enabled!")
                if db.AutoShrink:
                    print(f"  [WARNING] AutoShrink is enabled!")

        # 3. PERFORMANCE METRICS - CPU
        print("\n" + "="*60)
        print("CPU USAGE (Last 10 samples)")
        print("="*60)

        cursor.execute("""
            SELECT TOP 10
                record_id,
                SQLProcessUtilization AS SQL_CPU,
                100 - SystemIdle - SQLProcessUtilization AS Other_CPU,
                SystemIdle AS System_Idle
            FROM (
                SELECT
                    record.value('(./Record/@id)[1]', 'int') AS record_id,
                    record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS SystemIdle,
                    record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS SQLProcessUtilization
                FROM (
                    SELECT convert(xml, record) AS record
                    FROM sys.dm_os_ring_buffers
                    WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
                    AND record LIKE '%<SystemHealth>%'
                ) AS x
            ) AS y
            ORDER BY record_id DESC
        """)

        cpu_data = cursor.fetchall()
        if cpu_data:
            print(f"\n{'Sample':<10} {'SQL CPU %':<15} {'Other CPU %':<15} {'Idle %':<10}")
            print("-"*50)
            for i, row in enumerate(cpu_data[:5], 1):
                print(f"{i:<10} {row.SQL_CPU:<15} {row.Other_CPU:<15} {row.System_Idle:<10}")

            avg_sql_cpu = sum(row.SQL_CPU for row in cpu_data) / len(cpu_data)
            if avg_sql_cpu > 80:
                print(f"\n[WARNING] High average SQL CPU usage: {avg_sql_cpu:.1f}%")

        # 4. MEMORY USAGE
        print("\n" + "="*60)
        print("MEMORY USAGE")
        print("="*60)

        cursor.execute("""
            SELECT
                (physical_memory_in_use_kb/1024) AS Memory_Used_MB,
                (total_virtual_address_space_kb/1024) AS Total_VAS_MB,
                process_physical_memory_low,
                process_virtual_memory_low
            FROM sys.dm_os_process_memory
        """)

        memory = cursor.fetchone()
        if memory:
            print(f"Physical Memory Used: {memory.Memory_Used_MB:,.0f} MB")
            print(f"Total Virtual Address Space: {memory.Total_VAS_MB:,.0f} MB")
            if memory.process_physical_memory_low:
                print("[WARNING] Physical memory is LOW!")
            if memory.process_virtual_memory_low:
                print("[WARNING] Virtual memory is LOW!")

        # 5. BLOCKING SESSIONS
        print("\n" + "="*60)
        print("BLOCKING SESSIONS")
        print("="*60)

        cursor.execute("""
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
        """)

        blocks = cursor.fetchall()
        if blocks:
            print("[ALERT] BLOCKING DETECTED!")
            for block in blocks:
                print(f"  Blocking Session: {block.BlockingSessionID}")
                print(f"  Blocked Session: {block.BlockedSessionID}")
                print(f"  Wait Time: {block.WaitTimeSec:.2f} seconds")
                print(f"  Wait Type: {block.wait_type}")
                print(f"  Database: {block.DatabaseName}")
                print("-" * 40)
        else:
            print("[OK] No blocking detected")

        # 6. LONG RUNNING QUERIES
        print("\n" + "="*60)
        print("LONG-RUNNING QUERIES (>30 seconds)")
        print("="*60)

        cursor.execute("""
            SELECT TOP 5
                r.session_id,
                r.status,
                r.command,
                r.total_elapsed_time / 1000.0 AS ElapsedSec,
                r.cpu_time / 1000.0 AS CPUSec,
                DB_NAME(r.database_id) AS DatabaseName
            FROM sys.dm_exec_requests r
            WHERE r.total_elapsed_time > 30000
                AND r.session_id > 50
            ORDER BY r.total_elapsed_time DESC
        """)

        queries = cursor.fetchall()
        if queries:
            print("[WARNING] Long-running queries found:")
            for q in queries:
                print(f"  Session {q.session_id}: {q.command}")
                print(f"    Status: {q.status}")
                print(f"    Elapsed: {q.ElapsedSec:.1f}s, CPU: {q.CPUSec:.1f}s")
                print(f"    Database: {q.DatabaseName}")
        else:
            print("[OK] No long-running queries detected")

        # 7. TOP WAIT STATISTICS
        print("\n" + "="*60)
        print("TOP WAIT STATISTICS")
        print("="*60)

        cursor.execute("""
            SELECT TOP 10
                wait_type,
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
        """)

        waits = cursor.fetchall()
        if waits:
            print(f"\n{'Wait Type':<30} {'Total Wait (s)':<15} {'Count':<10} {'%':<5}")
            print("-"*60)
            for wait in waits[:5]:
                print(f"{wait.wait_type:<30} {wait.WaitSec:<15,.1f} {wait.WaitCount:<10,} {wait.Percentage:.1f}")

        # 8. DATABASE FILE SIZES
        print("\n" + "="*60)
        print("DATABASE FILE SIZES (Top 10 by size)")
        print("="*60)

        cursor.execute("""
            SELECT TOP 10
                DB_NAME(database_id) AS DatabaseName,
                type_desc AS FileType,
                name AS FileName,
                size * 8 / 1024.0 AS SizeMB
            FROM sys.master_files
            WHERE database_id > 4
            ORDER BY size DESC
        """)

        files = cursor.fetchall()
        if files:
            print(f"\n{'Database':<25} {'Type':<10} {'File':<25} {'Size (MB)':<15}")
            print("-"*75)
            for file in files:
                print(f"{file.DatabaseName:<25} {file.FileType:<10} {file.FileName:<25} {file.SizeMB:>10,.1f}")

        # SUMMARY
        print("\n" + "="*60)
        print("HEALTH CHECK SUMMARY")
        print("="*60)
        print("\n[Key Findings]")

        issues_found = []
        if blocks:
            issues_found.append("- CRITICAL: Blocking sessions detected")
        if queries:
            issues_found.append("- WARNING: Long-running queries found")
        if memory and memory.process_physical_memory_low:
            issues_found.append("- WARNING: Low physical memory")
        if cpu_data and avg_sql_cpu > 80:
            issues_found.append(f"- WARNING: High CPU usage ({avg_sql_cpu:.1f}%)")

        if issues_found:
            for issue in issues_found:
                print(issue)
        else:
            print("- No critical issues detected")

        print("\n[Recommendations]")
        print("1. Review any blocking sessions immediately")
        print("2. Investigate long-running queries for optimization")
        print("3. Monitor wait statistics for bottlenecks")
        print("4. Check database configurations (AutoClose/AutoShrink)")
        print("5. Review error logs for additional issues")

        connection.close()
        print("\n[INFO] Health check completed successfully")

    except pyodbc.Error as e:
        print(f"\n[ERROR] Database connection failed: {str(e)}")
        if "08001" in str(e):
            print("  → Check VPN connection and network connectivity")
        elif "28000" in str(e):
            print("  → Verify username and password")
        elif "IM002" in str(e):
            print("  → ODBC Driver not found - install ODBC Driver 17 for SQL Server")
        return False
    except Exception as e:
        print(f"\n[ERROR] Health check failed: {str(e)}")
        traceback.print_exc()
        return False

    return True

def main():
    parser = argparse.ArgumentParser(description='SQL Server Health Check for pvault')
    parser.add_argument('--server', default='inscolpvault.insulationsinc.local',
                        help='SQL Server hostname (default: inscolpvault.insulationsinc.local)')
    parser.add_argument('--database', default='PaperlessEnvironments',
                        help='Database name (default: PaperlessEnvironments)')
    parser.add_argument('--username', required=True,
                        help='SQL Server username')
    parser.add_argument('--password', required=True,
                        help='SQL Server password')
    parser.add_argument('--port', type=int, default=55859,
                        help='SQL Server port (default: 55859)')

    args = parser.parse_args()

    # Run the health check
    success = run_health_check(
        server=args.server,
        database=args.database,
        username=args.username,
        password=args.password,
        port=args.port
    )

    sys.exit(0 if success else 1)

if __name__ == "__main__":
    main()