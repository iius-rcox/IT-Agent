"""
Quick SQL Server Connection Test Script
Tests basic connectivity to pvault SQL Server
"""

import pyodbc
import sys

def test_connection():
    print("SQL Server Connection Test")
    print("="*50)

    # Get connection details
    server = input("Server [inscolpvault.insulationsinc.local]: ").strip() or "inscolpvault.insulationsinc.local"
    port = input("Port [55859]: ").strip() or "55859"
    database = input("Database [PaperlessEnvironments]: ").strip() or "PaperlessEnvironments"
    username = input("Username: ").strip()
    password = input("Password: ").strip()

    print(f"\nAttempting to connect to {server}:{port}...")

    # Test different connection string variations
    connection_strings = [
        # Try with ODBC Driver 18 (preferred)
        {
            "name": "ODBC Driver 18",
            "string": f"DRIVER={{ODBC Driver 18 for SQL Server}};SERVER={server},{port};DATABASE={database};UID={username};PWD={password};TrustServerCertificate=yes;Encrypt=yes;"
        },
        # Standard connection with ODBC Driver 17
        {
            "name": "ODBC Driver 17",
            "string": f"DRIVER={{ODBC Driver 17 for SQL Server}};SERVER={server},{port};DATABASE={database};UID={username};PWD={password};TrustServerCertificate=yes;"
        },
        # Try with SQL Server Native Client
        {
            "name": "SQL Server Native Client",
            "string": f"DRIVER={{SQL Server Native Client 11.0}};SERVER={server},{port};DATABASE={database};UID={username};PWD={password};"
        },
        # Try with just SQL Server driver
        {
            "name": "SQL Server",
            "string": f"DRIVER={{SQL Server}};SERVER={server},{port};DATABASE={database};UID={username};PWD={password};"
        }
    ]

    # First, list available drivers
    print("\n[Available ODBC Drivers on System]")
    try:
        drivers = pyodbc.drivers()
        for driver in drivers:
            print(f"  - {driver}")
    except:
        print("  Unable to list drivers")

    print("\n[Testing Connections]")
    successful_connection = None

    for conn_config in connection_strings:
        print(f"\nTrying {conn_config['name']}...")
        try:
            conn = pyodbc.connect(conn_config['string'], timeout=10)
            print(f"  ✓ SUCCESS with {conn_config['name']}")

            # Test basic query
            cursor = conn.cursor()
            cursor.execute("SELECT @@VERSION AS Version, @@SERVERNAME AS ServerName")
            result = cursor.fetchone()

            print(f"  Server: {result.ServerName}")
            print(f"  Version: {result.Version[:100]}...")

            # Get database list
            cursor.execute("SELECT name FROM sys.databases ORDER BY name")
            databases = cursor.fetchall()
            print(f"\n  Available Databases:")
            for db in databases[:10]:  # Show first 10
                print(f"    - {db[0]}")
            if len(databases) > 10:
                print(f"    ... and {len(databases)-10} more")

            conn.close()
            successful_connection = conn_config
            break

        except pyodbc.Error as e:
            print(f"  ✗ Failed: {str(e)[:100]}")
            if "08001" in str(e):
                print("    → Network connectivity issue. Check VPN connection and firewall.")
            elif "28000" in str(e):
                print("    → Authentication failed. Check username/password.")
            elif "IM002" in str(e):
                print(f"    → Driver not found. Install {conn_config['name']}.")

        except Exception as e:
            print(f"  ✗ Unexpected error: {str(e)[:100]}")

    print("\n" + "="*50)
    if successful_connection:
        print(f"✓ Connection successful using {successful_connection['name']}")
        print("\nConnection string for your reference:")
        print(successful_connection['string'].replace(password, '***PASSWORD***'))
        print("\nYou can now run the full health check script: python sql_health_check.py")
    else:
        print("✗ All connection attempts failed")
        print("\nTroubleshooting steps:")
        print("1. Verify you're connected to the VPN")
        print("2. Verify the server name: inscolpvault.insulationsinc.local")
        print("3. Check if SQL Server port 1433 is open:")
        print(f"   PowerShell: Test-NetConnection -ComputerName {server} -Port {port}")
        print("4. Verify SQL Server Authentication is enabled (not just Windows Auth)")
        print("5. Install ODBC Driver for SQL Server:")
        print("   https://docs.microsoft.com/en-us/sql/connect/odbc/download-odbc-driver-for-sql-server")

if __name__ == "__main__":
    test_connection()