"""
SQL Server Health Check Script for pvault
Server: inscolpvault.insulationsinc.local
Purpose: Comprehensive health check and diagnostics
"""

import pyodbc
import pandas as pd
from datetime import datetime
import sys
import json
from tabulate import tabulate

class SQLServerHealthCheck:
    def __init__(self, server, database, username, password, port=55859):
        self.server = server
        self.database = database
        self.username = username
        self.password = password
        self.port = port
        self.connection = None
        self.results = {}

    def connect(self):
        """Establish connection to SQL Server"""
        # Try multiple connection strategies
        connection_configs = [
            # ODBC Driver 18 (preferred)
            {
                "driver": "ODBC Driver 18 for SQL Server",
                "extra": "Encrypt=yes;TrustServerCertificate=yes;"
            },
            # ODBC Driver 17
            {
                "driver": "ODBC Driver 17 for SQL Server",
                "extra": "TrustServerCertificate=yes;"
            },
            # SQL Server Native Client 11.0
            {
                "driver": "SQL Server Native Client 11.0",
                "extra": ""
            }
        ]

        print(f"[INFO] Connecting to {self.server}:{self.port}...")

        for config in connection_configs:
            try:
                connection_string = (
                    f"DRIVER={{{config['driver']}}};"
                    f"SERVER={self.server},{self.port};"
                    f"DATABASE={self.database};"
                    f"UID={self.username};"
                    f"PWD={self.password};"
                    f"{config['extra']}"
                )

                self.connection = pyodbc.connect(connection_string, timeout=30)
                print(f"[SUCCESS] Connected to SQL Server using {config['driver']}")
                return True
            except Exception as e:
                continue

        print(f"[ERROR] Failed to connect with all drivers")
        return False

    def check_server_info(self):
        """Get basic server information"""
        print("\n" + "="*60)
        print("SERVER INFORMATION")
        print("="*60)

        cursor = self.connection.cursor()

        # Server version and edition
        cursor.execute("""
            SELECT
                @@VERSION AS Version,
                @@SERVERNAME AS ServerName,
                SERVERPROPERTY('Edition') AS Edition,
                SERVERPROPERTY('ProductLevel') AS ProductLevel,
                SERVERPROPERTY('ProductVersion') AS ProductVersion
        """)

        result = cursor.fetchone()
        if result:
            print(f"Server Name: {result.ServerName}")
            print(f"Edition: {result.Edition}")
            print(f"Product Level: {result.ProductLevel}")
            print(f"Product Version: {result.ProductVersion}")
            print(f"Full Version Info:\n{result.Version[:200]}...")

    def check_database_status(self):
        """Check database status and properties"""
        print("\n" + "="*60)
        print("DATABASE STATUS")
        print("="*60)

        cursor = self.connection.cursor()

        query = """
        SELECT
            name AS DatabaseName,
            state_desc AS Status,
            recovery_model_desc AS RecoveryModel,
            compatibility_level AS CompatibilityLevel,
            is_read_only AS IsReadOnly,
            is_auto_close_on AS AutoClose,
            is_auto_shrink_on AS AutoShrink,
            page_verify_option_desc AS PageVerifyOption
        FROM sys.databases
        WHERE name NOT IN ('master', 'tempdb', 'model', 'msdb')
        ORDER BY name
        """

        cursor.execute(query)
        databases = cursor.fetchall()

        if databases:
            df = pd.DataFrame([tuple(row) for row in databases],
                            columns=['Database', 'Status', 'Recovery', 'Compat',
                                   'ReadOnly', 'AutoClose', 'AutoShrink', 'PageVerify'])
            print(tabulate(df, headers='keys', tablefmt='grid'))

            # Flag any issues
            for db in databases:
                if db.Status != 'ONLINE':
                    print(f"[WARNING] Database {db.DatabaseName} is {db.Status}")
                if db.AutoClose:
                    print(f"[WARNING] Database {db.DatabaseName} has AutoClose enabled")
                if db.AutoShrink:
                    print(f"[WARNING] Database {db.DatabaseName} has AutoShrink enabled")

    def check_performance_metrics(self):
        """Check key performance metrics"""
        print("\n" + "="*60)
        print("PERFORMANCE METRICS")
        print("="*60)

        cursor = self.connection.cursor()

        # CPU usage
        print("\n[CPU Usage - Last Hour]")
        cursor.execute("""
        SELECT TOP 10
            record_id,
            DateAdd(mi, -1 * (sys.dm_os_sys_info.os_quantum / 1000 / 60), GetDate()) AS EventTime,
            SQLProcessUtilization AS SQL_CPU,
            100 - SystemIdle - SQLProcessUtilization AS Other_CPU,
            SystemIdle AS System_Idle
        FROM (
            SELECT
                record.value('(./Record/@id)[1]', 'int') AS record_id,
                record.value('(./Record/SchedulerMonitorEvent/SystemHealth/SystemIdle)[1]', 'int') AS SystemIdle,
                record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS SQLProcessUtilization,
                timestamp
            FROM (
                SELECT timestamp, convert(xml, record) AS record
                FROM sys.dm_os_ring_buffers
                WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
                AND record LIKE '%<SystemHealth>%'
            ) AS x
        ) AS y
        CROSS JOIN sys.dm_os_sys_info
        ORDER BY record_id DESC
        """)

        cpu_data = cursor.fetchall()
        if cpu_data:
            df = pd.DataFrame([tuple(row) for row in cpu_data],
                            columns=['RecordID', 'Time', 'SQL_CPU%', 'Other_CPU%', 'Idle%'])
            print(tabulate(df.head(5), headers='keys', tablefmt='grid'))

        # Memory usage
        print("\n[Memory Usage]")
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
            print(f"Physical Memory Used: {memory[0]:,.0f} MB")
            print(f"Total Virtual Address Space: {memory[1]:,.0f} MB")
            if memory[2]:
                print("[WARNING] Physical memory is low!")
            if memory[3]:
                print("[WARNING] Virtual memory is low!")

    def check_wait_stats(self):
        """Check top wait statistics"""
        print("\n" + "="*60)
        print("TOP WAIT STATISTICS")
        print("="*60)

        cursor = self.connection.cursor()

        query = """
        SELECT TOP 10
            wait_type,
            wait_time_ms / 1000.0 AS WaitSec,
            (wait_time_ms - signal_wait_time_ms) / 1000.0 AS ResourceSec,
            signal_wait_time_ms / 1000.0 AS SignalSec,
            waiting_tasks_count AS WaitCount,
            100.0 * wait_time_ms / SUM(wait_time_ms) OVER() AS Percentage
        FROM sys.dm_os_wait_stats
        WHERE wait_type NOT IN (
            'CLR_SEMAPHORE', 'LAZYWRITER_SLEEP', 'RESOURCE_QUEUE',
            'SLEEP_TASK', 'SLEEP_SYSTEMTASK', 'SQLTRACE_BUFFER_FLUSH',
            'WAITFOR', 'LOGMGR_QUEUE', 'CHECKPOINT_QUEUE',
            'REQUEST_FOR_DEADLOCK_SEARCH', 'XE_TIMER_EVENT',
            'BROKER_TO_FLUSH', 'BROKER_TASK_STOP', 'CLR_MANUAL_EVENT',
            'CLR_AUTO_EVENT', 'DISPATCHER_QUEUE_SEMAPHORE',
            'FT_IFTS_SCHEDULER_IDLE_WAIT', 'XE_DISPATCHER_WAIT',
            'XE_DISPATCHER_JOIN', 'BROKER_EVENTHANDLER',
            'TRACEWRITE', 'FT_IFTSHC_MUTEX', 'SQLTRACE_INCREMENTAL_FLUSH_SLEEP'
        )
        ORDER BY wait_time_ms DESC
        """

        cursor.execute(query)
        waits = cursor.fetchall()

        if waits:
            df = pd.DataFrame([tuple(row) for row in waits],
                            columns=['Wait Type', 'Wait(s)', 'Resource(s)',
                                   'Signal(s)', 'Count', 'Percentage'])
            df['Percentage'] = df['Percentage'].round(2)
            print(tabulate(df, headers='keys', tablefmt='grid'))

    def check_blocking(self):
        """Check for current blocking sessions"""
        print("\n" + "="*60)
        print("BLOCKING SESSIONS")
        print("="*60)

        cursor = self.connection.cursor()

        query = """
        SELECT
            blocking.session_id AS BlockingSessionID,
            blocked.session_id AS BlockedSessionID,
            blocked.wait_time / 1000.0 AS WaitTimeSec,
            blocked.wait_type,
            blocking_text.text AS BlockingQuery,
            blocked_text.text AS BlockedQuery
        FROM sys.dm_exec_requests AS blocked
        INNER JOIN sys.dm_exec_requests AS blocking
            ON blocked.blocking_session_id = blocking.session_id
        CROSS APPLY sys.dm_exec_sql_text(blocking.sql_handle) AS blocking_text
        CROSS APPLY sys.dm_exec_sql_text(blocked.sql_handle) AS blocked_text
        WHERE blocked.blocking_session_id > 0
        """

        cursor.execute(query)
        blocks = cursor.fetchall()

        if blocks:
            for block in blocks:
                print(f"[BLOCKING DETECTED]")
                print(f"Blocking Session: {block[0]}")
                print(f"Blocked Session: {block[1]}")
                print(f"Wait Time: {block[2]:.2f} seconds")
                print(f"Wait Type: {block[3]}")
                print(f"Blocking Query: {block[4][:100]}...")
                print(f"Blocked Query: {block[5][:100]}...")
                print("-" * 40)
        else:
            print("[OK] No blocking detected")

    def check_long_running_queries(self):
        """Check for long-running queries"""
        print("\n" + "="*60)
        print("LONG-RUNNING QUERIES (>30 seconds)")
        print("="*60)

        cursor = self.connection.cursor()

        query = """
        SELECT TOP 10
            r.session_id,
            r.status,
            r.command,
            r.total_elapsed_time / 1000.0 AS ElapsedSec,
            r.cpu_time / 1000.0 AS CPUSec,
            r.reads,
            r.writes,
            t.text AS QueryText,
            DB_NAME(r.database_id) AS DatabaseName
        FROM sys.dm_exec_requests r
        CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
        WHERE r.total_elapsed_time > 30000  -- 30 seconds
            AND r.session_id > 50  -- User sessions
        ORDER BY r.total_elapsed_time DESC
        """

        cursor.execute(query)
        queries = cursor.fetchall()

        if queries:
            for q in queries:
                print(f"[Session {q[0]}]")
                print(f"Status: {q[1]}, Command: {q[2]}")
                print(f"Elapsed: {q[3]:.2f}s, CPU: {q[4]:.2f}s")
                print(f"Reads: {q[5]:,}, Writes: {q[6]:,}")
                print(f"Database: {q[8]}")
                print(f"Query: {q[7][:200]}...")
                print("-" * 40)
        else:
            print("[OK] No long-running queries detected")

    def check_disk_space(self):
        """Check database file sizes and growth"""
        print("\n" + "="*60)
        print("DATABASE FILE SIZES")
        print("="*60)

        cursor = self.connection.cursor()

        query = """
        SELECT
            DB_NAME(database_id) AS DatabaseName,
            type_desc AS FileType,
            name AS FileName,
            physical_name AS Path,
            size * 8 / 1024.0 AS SizeMB,
            CASE max_size
                WHEN -1 THEN 'Unlimited'
                ELSE CAST(max_size * 8 / 1024.0 AS VARCHAR(20))
            END AS MaxSizeMB,
            growth * 8 / 1024.0 AS GrowthMB
        FROM sys.master_files
        WHERE database_id > 4  -- Exclude system databases
        ORDER BY database_id, type_desc
        """

        cursor.execute(query)
        files = cursor.fetchall()

        if files:
            df = pd.DataFrame([tuple(row) for row in files],
                            columns=['Database', 'Type', 'FileName', 'Path',
                                   'Size(MB)', 'MaxSize(MB)', 'Growth(MB)'])
            print(tabulate(df, headers='keys', tablefmt='grid'))

    def check_recent_errors(self):
        """Check SQL Server error log for recent issues"""
        print("\n" + "="*60)
        print("RECENT ERROR LOG ENTRIES")
        print("="*60)

        cursor = self.connection.cursor()

        try:
            cursor.execute("""
            EXEC sp_readerrorlog 0, 1, NULL, NULL, NULL, NULL, 'desc'
            """)

            errors = cursor.fetchmany(20)  # Get last 20 entries

            critical_keywords = ['error', 'failed', 'severity', 'corrupt', 'deadlock',
                               'timeout', 'cannot', 'unable']

            print("\n[Recent Log Entries with Issues]")
            issue_count = 0
            for entry in errors:
                log_text = str(entry[2]).lower() if len(entry) > 2 else ""
                if any(keyword in log_text for keyword in critical_keywords):
                    print(f"{entry[0]} | {entry[1]} | {entry[2][:150]}...")
                    issue_count += 1
                    if issue_count >= 10:
                        break

            if issue_count == 0:
                print("[OK] No critical issues in recent logs")

        except Exception as e:
            print(f"[WARNING] Could not read error log: {str(e)}")

    def check_query_timeouts(self):
        """Check for queries that may be timing out"""
        print("\n" + "="*60)
        print("TIMEOUT ANALYSIS")
        print("="*60)

        cursor = self.connection.cursor()

        # Check currently executing queries approaching timeout
        print("\n[CURRENTLY EXECUTING QUERIES]")
        cursor.execute("""
        SELECT
            r.session_id,
            r.status,
            r.command,
            r.total_elapsed_time / 1000 AS ElapsedSec,
            r.wait_type,
            r.wait_time / 1000 AS WaitSec,
            t.text AS QueryText,
            DB_NAME(r.database_id) AS DatabaseName
        FROM sys.dm_exec_requests r
        CROSS APPLY sys.dm_exec_sql_text(r.sql_handle) t
        WHERE r.session_id > 50
        ORDER BY r.total_elapsed_time DESC
        """)

        queries = cursor.fetchall()
        timeout_risk = []
        for q in queries[:10]:
            print(f"Session {q.session_id}: {q.command} in {q.DatabaseName}")
            print(f"  Status: {q.status}, Elapsed: {q.ElapsedSec}s")
            if q.wait_type:
                print(f"  Waiting on: {q.wait_type} for {q.WaitSec}s")
            print(f"  Query: {str(q.QueryText)[:100] if q.QueryText else 'N/A'}...")
            if q.ElapsedSec > 25:  # Near 30-second default timeout
                timeout_risk.append(q.session_id)
                print("  [WARNING] Approaching timeout threshold!")
            print("-" * 40)

        if timeout_risk:
            print(f"\n[ALERT] {len(timeout_risk)} queries at risk of timeout")

    def check_large_tables(self):
        """Check for large tables that might cause timeouts"""
        print("\n" + "="*60)
        print("LARGE TABLE ANALYSIS")
        print("="*60)

        cursor = self.connection.cursor()

        cursor.execute("""
        SELECT TOP 20
            s.name AS SchemaName,
            t.name AS TableName,
            p.rows AS RowCount,
            SUM(a.total_pages) * 8 / 1024.0 AS TotalSpaceMB,
            SUM(a.used_pages) * 8 / 1024.0 AS UsedSpaceMB,
            CASE
                WHEN p.rows > 10000000 THEN 'VERY LARGE'
                WHEN p.rows > 1000000 THEN 'LARGE'
                WHEN p.rows > 100000 THEN 'MEDIUM'
                ELSE 'SMALL'
            END AS SizeCategory
        FROM sys.tables t
        INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
        INNER JOIN sys.indexes i ON t.object_id = i.object_id
        INNER JOIN sys.partitions p ON i.object_id = p.object_id AND i.index_id = p.index_id
        INNER JOIN sys.allocation_units a ON p.partition_id = a.container_id
        WHERE t.is_ms_shipped = 0 AND i.object_id > 255
        GROUP BY s.name, t.name, p.rows
        HAVING p.rows > 100000  -- Tables with >100k rows
        ORDER BY p.rows DESC
        """)

        tables = cursor.fetchall()
        if tables:
            print("\n[Tables that may cause timeout issues]")
            for t in tables[:10]:
                print(f"{t.SchemaName}.{t.TableName}: {t.RowCount:,} rows ({t.SizeCategory})")
                print(f"  Size: {t.TotalSpaceMB:.1f} MB")
                if t.RowCount > 10000000:
                    print("  [WARNING] Very large table - queries need proper indexing!")

    def check_missing_indexes(self):
        """Check for missing indexes that could cause timeouts"""
        print("\n" + "="*60)
        print("MISSING INDEX ANALYSIS")
        print("="*60)

        cursor = self.connection.cursor()

        cursor.execute("""
        SELECT TOP 10
            CONVERT(decimal(18,2), user_seeks * avg_total_user_cost * (avg_user_impact * 0.01)) AS IndexAdvantage,
            migs.last_user_seek,
            mid.statement AS TableName,
            mid.equality_columns,
            mid.inequality_columns,
            mid.included_columns,
            migs.user_seeks,
            migs.avg_total_user_cost,
            migs.avg_user_impact
        FROM sys.dm_db_missing_index_group_stats AS migs
        INNER JOIN sys.dm_db_missing_index_groups AS mig
            ON migs.group_handle = mig.index_group_handle
        INNER JOIN sys.dm_db_missing_index_details AS mid
            ON mig.index_handle = mid.index_handle
        WHERE mid.database_id = DB_ID()
        ORDER BY IndexAdvantage DESC
        """)

        indexes = cursor.fetchall()
        if indexes:
            print("\n[Top Missing Indexes (causing slow queries)]")
            for idx in indexes[:5]:
                print(f"Table: {idx.TableName}")
                print(f"  Impact Score: {idx.IndexAdvantage:.2f}")
                print(f"  Seeks: {idx.user_seeks}, Avg Cost: {idx.avg_total_user_cost:.2f}")
                print(f"  Columns needed: {idx.equality_columns}")
                if idx.inequality_columns:
                    print(f"  Inequality columns: {idx.inequality_columns}")
                if idx.included_columns:
                    print(f"  Include columns: {idx.included_columns}")
                print("-" * 40)

    def check_table_fragmentation(self):
        """Check index fragmentation that can cause timeouts"""
        print("\n" + "="*60)
        print("INDEX FRAGMENTATION ANALYSIS")
        print("="*60)

        cursor = self.connection.cursor()

        cursor.execute("""
        SELECT
            s.name AS SchemaName,
            t.name AS TableName,
            i.name AS IndexName,
            ps.avg_fragmentation_in_percent,
            ps.page_count
        FROM sys.dm_db_index_physical_stats(DB_ID(), NULL, NULL, NULL, 'LIMITED') ps
        INNER JOIN sys.indexes i ON ps.object_id = i.object_id AND ps.index_id = i.index_id
        INNER JOIN sys.tables t ON i.object_id = t.object_id
        INNER JOIN sys.schemas s ON t.schema_id = s.schema_id
        WHERE ps.avg_fragmentation_in_percent > 30
            AND ps.page_count > 1000
            AND i.name IS NOT NULL
        ORDER BY ps.avg_fragmentation_in_percent DESC
        """)

        fragments = cursor.fetchall()
        if fragments:
            print("\n[Fragmented Indexes (>30% fragmentation)]")
            for f in fragments[:10]:
                print(f"{f.SchemaName}.{f.TableName}.{f.IndexName}")
                print(f"  Fragmentation: {f.avg_fragmentation_in_percent:.1f}%")
                print(f"  Pages: {f.page_count:,}")
                if f.avg_fragmentation_in_percent > 70:
                    print("  [CRITICAL] Rebuild index immediately!")
                elif f.avg_fragmentation_in_percent > 50:
                    print("  [WARNING] Consider rebuilding this index")

    def check_statistics_age(self):
        """Check for outdated statistics that cause bad query plans"""
        print("\n" + "="*60)
        print("STATISTICS AGE ANALYSIS")
        print("="*60)

        cursor = self.connection.cursor()

        cursor.execute("""
        SELECT
            OBJECT_NAME(s.object_id) AS TableName,
            s.name AS StatisticName,
            sp.last_updated,
            DATEDIFF(day, sp.last_updated, GETDATE()) AS DaysOld,
            sp.rows,
            sp.modification_counter AS ModificationsSinceUpdate
        FROM sys.stats s
        CROSS APPLY sys.dm_db_stats_properties(s.object_id, s.stats_id) sp
        WHERE s.object_id > 100
            AND sp.last_updated IS NOT NULL
            AND (DATEDIFF(day, sp.last_updated, GETDATE()) > 7
                 OR sp.modification_counter > 1000)
        ORDER BY DaysOld DESC, sp.modification_counter DESC
        """)

        stats = cursor.fetchall()
        if stats:
            print("\n[Outdated Statistics (can cause timeout issues)]")
            for s in stats[:10]:
                print(f"{s.TableName}.{s.StatisticName}")
                print(f"  Last Updated: {s.last_updated} ({s.DaysOld} days ago)")
                print(f"  Rows: {s.rows:,}, Modifications: {s.ModificationsSinceUpdate:,}")
                if s.DaysOld > 30 or s.ModificationsSinceUpdate > 10000:
                    print("  [WARNING] Statistics need updating!")

    def generate_report(self):
        """Generate summary report"""
        print("\n" + "="*60)
        print("HEALTH CHECK SUMMARY")
        print("="*60)
        print(f"Server: {self.server}")
        print(f"Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}")
        print("\n[Recommendations for Timeout Issues]")
        print("1. Review and create missing indexes immediately")
        print("2. Update outdated statistics (sp_updatestats)")
        print("3. Rebuild fragmented indexes (>50% fragmentation)")
        print("4. Optimize queries on large tables")
        print("5. Check for blocking sessions causing timeouts")
        print("6. Consider query timeout settings in application")
        print("7. Review execution plans for expensive operations")

    def run_all_checks(self):
        """Run all health checks"""
        if not self.connect():
            return False

        try:
            self.check_server_info()
            self.check_database_status()
            self.check_performance_metrics()
            self.check_wait_stats()
            self.check_blocking()
            self.check_long_running_queries()
            self.check_query_timeouts()
            self.check_large_tables()
            self.check_missing_indexes()
            self.check_table_fragmentation()
            self.check_statistics_age()
            self.check_disk_space()
            self.check_recent_errors()
            self.generate_report()

        except Exception as e:
            print(f"\n[ERROR] Health check failed: {str(e)}")
            import traceback
            traceback.print_exc()
        finally:
            if self.connection:
                self.connection.close()
                print("\n[INFO] Connection closed")

def main():
    print("SQL Server Health Check Tool")
    print("="*60)

    # Connection parameters
    server = input("Server (inscolpvault.insulationsinc.local): ").strip() or "inscolpvault.insulationsinc.local"
    database = input("Database (PaperlessEnvironments): ").strip() or "PaperlessEnvironments"
    username = input("Username: ").strip()
    password = input("Password: ").strip()
    port = input("Port (55859): ").strip() or "55859"

    # Create health check instance
    health_check = SQLServerHealthCheck(server, database, username, password, int(port))

    # Run checks
    health_check.run_all_checks()

if __name__ == "__main__":
    main()