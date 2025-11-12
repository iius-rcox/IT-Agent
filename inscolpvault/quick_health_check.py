"""
Quick SQL Server Health Check (No pandas required)
Works with existing pyodbc installation
"""

import pyodbc
import sys
from datetime import datetime

# Connection parameters - UPDATE THESE
SERVER = "inscolpvault.insulationsinc.local"
PORT = 55859  # SQL Server port
DATABASE = "PaperlessEnvironments"
USERNAME = "sa"
PASSWORD = input("Enter SQL password for sa: ")  # Prompts for password

def connect_to_sql():
    """Establish SQL Server connection"""
    # Try multiple connection strategies
    connection_configs = [
        # Strategy 1: ODBC Driver 18 with explicit port and encryption (primary)
        {
            "driver": "ODBC Driver 18 for SQL Server",
            "server": f"{SERVER},{PORT}",
            "encrypt": "yes",
            "trust_cert": "yes"
        },
        # Strategy 2: ODBC Driver 18 with explicit port without encryption
        {
            "driver": "ODBC Driver 18 for SQL Server",
            "server": f"{SERVER},{PORT}",
            "encrypt": "no"
        },
        # Strategy 3: ODBC Driver 18 without port (let it try default discovery)
        {
            "driver": "ODBC Driver 18 for SQL Server",
            "server": SERVER,
            "encrypt": "yes",
            "trust_cert": "yes"
        },
        # Strategy 4: ODBC Driver 17 with explicit port
        {
            "driver": "ODBC Driver 17 for SQL Server",
            "server": f"{SERVER},{PORT}",
            "encrypt": "yes",
            "trust_cert": "yes"
        },
        # Strategy 5: SQL Server Native Client 11.0 with explicit port
        {
            "driver": "SQL Server Native Client 11.0",
            "server": f"{SERVER},{PORT}"
        },
        # Strategy 6: Legacy SQL Server driver with explicit port
        {
            "driver": "SQL Server",
            "server": f"{SERVER},{PORT}"
        }
    ]

    print(f"\nConnecting to {SERVER}...")
    
    for i, config in enumerate(connection_configs, 1):
        try:
            # Build connection string
            conn_parts = [
                f"DRIVER={{{config['driver']}}};",
                f"SERVER={config['server']};",
                f"DATABASE={DATABASE};",
                f"UID={USERNAME};",
                f"PWD={PASSWORD};"
            ]
            
            if "encrypt" in config:
                conn_parts.append(f"Encrypt={config['encrypt']};")
            if "trust_cert" in config:
                conn_parts.append(f"TrustServerCertificate=yes;")
            
            connection_string = "".join(conn_parts)
            
            if i > 1:
                print(f"Trying strategy {i} ({config['driver']})...")
            
            conn = pyodbc.connect(connection_string, timeout=15)
            print(f"✓ Connected successfully with {config['driver']}!\n")
            return conn
            
        except pyodbc.Error as e:
            if i == 1:
                print(f"✗ Initial connection failed: {str(e)[:200]}")
            continue
        except Exception as e:
            if i == 1:
                print(f"✗ Connection error: {str(e)[:200]}")
            continue

    # All connection attempts failed
    print("\n" + "="*60)
    print("CONNECTION FAILED - TROUBLESHOOTING")
    print("="*60)
    print("\nPossible issues:")
    print("1. Network connectivity:")
    print("   - Verify VPN is connected")
    print("   - Test: ping inscolpvault.insulationsinc.local")
    print(f"   - Test: Test-NetConnection -ComputerName inscolpvault.insulationsinc.local -Port {PORT}")
    print(f"\n2. SQL Server configuration (port {PORT}):")
    print("   - SQL Server Browser service must be running")
    print("   - TCP/IP protocol must be enabled")
    print("   - SQL Server must allow remote connections")
    print(f"   - Firewall must allow port {PORT}")
    print("\n3. Authentication:")
    print("   - Verify username and password are correct")
    print("   - Check if SQL authentication is enabled")
    print("   - Verify user has access to the database")
    print("\n4. ODBC Driver:")
    print("   - Install ODBC Driver: https://aka.ms/downloadmsodbcsql")
    print("   - Verify driver is installed: pyodbc.drivers()")
    
    # Show available drivers
    try:
        print("\nAvailable ODBC drivers:")
        drivers = pyodbc.drivers()
        if drivers:
            for driver in drivers:
                print(f"  - {driver}")
        else:
            print("  No ODBC drivers found!")
    except:
        pass
    
    sys.exit(1)

def run_quick_checks(conn):
    """Run essential health checks"""
    cursor = conn.cursor()

    print("="*60)
    print("SQL SERVER QUICK HEALTH CHECK")
    print("="*60)
    print(f"Timestamp: {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}\n")

    # 1. Server Info
    print("[SERVER INFO]")
    cursor.execute("""
        SELECT
            @@SERVERNAME AS ServerName,
            SERVERPROPERTY('Edition') AS Edition,
            SERVERPROPERTY('ProductVersion') AS Version
    """)
    result = cursor.fetchone()
    print(f"Server: {result.ServerName}")
    print(f"Edition: {result.Edition}")
    print(f"Version: {result.Version}\n")

    # 2. Database Status
    print("[DATABASE STATUS]")
    cursor.execute("""
        SELECT COUNT(*) as TotalDBs,
               SUM(CASE WHEN state_desc = 'ONLINE' THEN 1 ELSE 0 END) as OnlineDBs,
               SUM(CASE WHEN state_desc != 'ONLINE' THEN 1 ELSE 0 END) as OfflineDBs
        FROM sys.databases WHERE database_id > 4
    """)
    result = cursor.fetchone()
    print(f"Total User Databases: {result.TotalDBs}")
    print(f"Online: {result.OnlineDBs}")
    if result.OfflineDBs > 0:
        print(f"⚠ OFFLINE: {result.OfflineDBs}\n")

        # Show offline databases
        cursor.execute("""
            SELECT name, state_desc FROM sys.databases
            WHERE database_id > 4 AND state_desc != 'ONLINE'
        """)
        for db in cursor.fetchall():
            print(f"  - {db.name}: {db.state_desc}")
    print()

    # 3. Performance - Current Activity
    print("[CURRENT ACTIVITY]")
    cursor.execute("""
        SELECT COUNT(*) as ActiveConnections,
               COUNT(DISTINCT session_id) as UniqueSessions
        FROM sys.dm_exec_connections WHERE session_id > 50
    """)
    result = cursor.fetchone()
    print(f"Active Connections: {result.ActiveConnections}")
    print(f"Unique Sessions: {result.UniqueSessions}\n")

    # 4. Blocking Check
    print("[BLOCKING CHECK]")
    cursor.execute("""
        SELECT COUNT(*) as BlockedSessions
        FROM sys.dm_exec_requests
        WHERE blocking_session_id > 0
    """)
    result = cursor.fetchone()
    if result.BlockedSessions > 0:
        print(f"⚠ BLOCKING DETECTED: {result.BlockedSessions} blocked sessions!")

        # Show blocking details
        cursor.execute("""
            SELECT
                blocking_session_id as Blocker,
                session_id as Blocked,
                wait_time/1000 as WaitSec,
                wait_type
            FROM sys.dm_exec_requests
            WHERE blocking_session_id > 0
        """)
        for block in cursor.fetchall():
            print(f"  Session {block.Blocker} blocking {block.Blocked} ({block.WaitSec}s)")
    else:
        print("✓ No blocking detected\n")

    # 5. Long Running Queries
    print("[LONG RUNNING QUERIES]")
    cursor.execute("""
        SELECT COUNT(*) as LongQueries
        FROM sys.dm_exec_requests
        WHERE total_elapsed_time > 30000 AND session_id > 50
    """)
    result = cursor.fetchone()
    if result.LongQueries > 0:
        print(f"⚠ {result.LongQueries} queries running >30 seconds")

        # Show top 3
        cursor.execute("""
            SELECT TOP 3
                session_id,
                command,
                total_elapsed_time/1000 as ElapsedSec,
                status
            FROM sys.dm_exec_requests
            WHERE total_elapsed_time > 30000 AND session_id > 50
            ORDER BY total_elapsed_time DESC
        """)
        for query in cursor.fetchall():
            print(f"  Session {query.session_id}: {query.command} ({query.ElapsedSec}s)")
    else:
        print("✓ No long-running queries\n")

    # 6. Resource Usage
    print("[RESOURCE USAGE]")

    # CPU
    cursor.execute("""
        SELECT TOP 1 SQLProcessUtilization as SQL_CPU
        FROM (
            SELECT record.value('(./Record/SchedulerMonitorEvent/SystemHealth/ProcessUtilization)[1]', 'int') AS SQLProcessUtilization
            FROM (
                SELECT convert(xml, record) AS record
                FROM sys.dm_os_ring_buffers
                WHERE ring_buffer_type = N'RING_BUFFER_SCHEDULER_MONITOR'
                AND record LIKE '%<SystemHealth>%'
            ) AS x
        ) AS y
        ORDER BY SQLProcessUtilization DESC
    """)
    result = cursor.fetchone()
    if result:
        print(f"SQL CPU Usage: {result.SQL_CPU}%")
        if result.SQL_CPU > 80:
            print("  ⚠ High CPU usage!")

    # Memory
    cursor.execute("""
        SELECT
            (physical_memory_in_use_kb/1024) AS MemoryMB,
            process_physical_memory_low as LowMemory
        FROM sys.dm_os_process_memory
    """)
    result = cursor.fetchone()
    print(f"Memory Used: {result.MemoryMB:,.0f} MB")
    if result.LowMemory:
        print("  ⚠ Low memory condition!\n")
    else:
        print()

    # 7. Top Wait Types
    print("[TOP WAIT TYPES]")
    cursor.execute("""
        SELECT TOP 3
            wait_type,
            wait_time_ms/1000 as WaitSec,
            waiting_tasks_count as Count
        FROM sys.dm_os_wait_stats
        WHERE wait_type NOT IN (
            'SLEEP_TASK', 'BROKER_TASK_STOP', 'WAITFOR',
            'LAZYWRITER_SLEEP', 'CHECKPOINT_QUEUE'
        )
        AND wait_time_ms > 0
        ORDER BY wait_time_ms DESC
    """)
    for wait in cursor.fetchall():
        print(f"  {wait.wait_type}: {wait.WaitSec:,.0f}s ({wait.Count:,} waits)")

    # 8. Error Log Check
    print("\n[RECENT ERRORS]")
    try:
        cursor.execute("EXEC sp_readerrorlog 0, 1, 'Error'")
        errors = cursor.fetchmany(5)
        if errors:
            print("⚠ Recent errors found in log:")
            for error in errors[:3]:
                if len(error) > 2:
                    print(f"  {error[0]} - {str(error[2])[:80]}...")
        else:
            print("✓ No recent errors in log")
    except:
        print("  Unable to read error log")

    print("\n" + "="*60)
    print("SUMMARY")
    print("="*60)

    # Collect all issues
    issues = []
    cursor.execute("SELECT COUNT(*) as c FROM sys.databases WHERE database_id > 4 AND state_desc != 'ONLINE'")
    if cursor.fetchone().c > 0:
        issues.append("Offline databases")

    cursor.execute("SELECT COUNT(*) as c FROM sys.dm_exec_requests WHERE blocking_session_id > 0")
    if cursor.fetchone().c > 0:
        issues.append("Blocking sessions")

    cursor.execute("SELECT COUNT(*) as c FROM sys.dm_exec_requests WHERE total_elapsed_time > 30000 AND session_id > 50")
    if cursor.fetchone().c > 0:
        issues.append("Long-running queries")

    if issues:
        print("Issues found:")
        for issue in issues:
            print(f"  ⚠ {issue}")
        print("\nRecommendation: Investigate the issues above immediately")
    else:
        print("✓ No critical issues detected")
        print("  System appears to be running normally")

    conn.close()
    print("\nHealth check completed successfully!")

if __name__ == "__main__":
    try:
        conn = connect_to_sql()
        run_quick_checks(conn)
    except Exception as e:
        print(f"Error: {str(e)}")
        sys.exit(1)