import os
import pandas as pd
from supabase import create_client, Client
from datetime import datetime

# Initialize Supabase client
# Ensure you set SUPABASE_URL and SUPABASE_KEY in your environment variables
url = os.environ.get("SUPABASE_URL", "https://qmcsxfqizvjbzffbrakp.supabase.co")
key = os.environ.get("SUPABASE_KEY", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFtY3N4ZnFpenZqYnpmZmJyYWtwIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzkyNzI1NjgsImV4cCI6MjA5NDg0ODU2OH0.3zWXIpO4Ruyk25LG9JS1hQwAE5Q2uLe7BKSJyV-eZ7c")

try:
    supabase: Client = create_client(url, key)
except Exception as e:
    print(f"Error initializing Supabase client. Please install supabase package: pip install supabase")
    exit(1)

def main():
    file_path = "NATRAX_Comprehensive_Billing_Final_V15 (1).xlsm"
    
    if not os.path.exists(file_path):
        print(f"Error: Could not find {file_path}")
        return

    # Authenticate to bypass RLS (using demo credentials)
    try:
        supabase.auth.sign_in_with_password({
            "email": "arjun.sharma@goodyear.com",
            "password": "Goodyear@2026"
        })
    except Exception as e:
        print("Auth error:", e)
        return

    # Get engineer ID
    response = supabase.table("engineer_profiles").select("id").limit(1).execute()
    if not response.data:
        print("No users found.")
        return
    engineer_id = response.data[0]["id"]
    
    # 1. Import Detailed Utilisation
    print("Importing Detailed Utilisation...")
    try:
        util_df = pd.read_excel(file_path, sheet_name="Detailed Utilisation")
        
        session_map = {}
        
        for _, row in util_df.iterrows():
            # Date is parsed automatically by pandas
            date_val = row.iloc[0]
            track_code = str(row.iloc[1])
            in_time = row.iloc[2]
            out_time = row.iloc[3]
            decimal_hrs = float(row.iloc[4]) if pd.notna(row.iloc[4]) else 0
            
            if pd.isna(date_val) or pd.isna(track_code) or track_code == 'nan':
                continue
                
            # Convert decimal hrs to minutes
            duration_mins = int(round(decimal_hrs * 60))
            
            started_at = date_val.strftime("%Y-%m-%dT00:00:00Z")
            ended_at = date_val.strftime("%Y-%m-%dT23:59:59Z")
            date_key = date_val.strftime("%Y-%m-%d")
            
            rate = 90000 if 'Exclusive' in track_code else 25000
            
            session_data = {
                "engineer_id": engineer_id,
                "track_code": track_code,
                "track_name": track_code,
                "vehicle_category": "below_3_5t",
                "booking_type": "standard",
                "session_status": "completed",
                "started_at": started_at,
                "ended_at": ended_at,
                "duration_minutes": duration_mins,
                "hourly_rate": rate,
                "total_cost": decimal_hrs * rate,
                "notes": "Imported via Python script"
            }
            
            res = supabase.table("engineer_sessions").insert(session_data).execute()
            if res.data:
                session_id = res.data[0]["id"]
                if date_key not in session_map:
                    session_map[date_key] = session_id
                print(f"Inserted session for {track_code} on {date_key}")
                
    except Exception as e:
        print(f"Error parsing Detailed Utilisation: {e}")

    # 2. Import Other Services Log
    print("\nImporting Other Services Log...")
    try:
        services_df = pd.read_excel(file_path, sheet_name="Other Services Log")
        
        for _, row in services_df.iterrows():
            date_val = row.iloc[0]
            service_cat = str(row.iloc[1])
            qty = float(row.iloc[2]) if pd.notna(row.iloc[2]) else 0
            rate = float(row.iloc[3]) if pd.notna(row.iloc[3]) else 0
            
            if pd.isna(date_val) or pd.isna(service_cat) or service_cat == 'nan':
                continue
                
            date_key = date_val.strftime("%Y-%m-%d")
            
            session_id = session_map.get(date_key)
            if not session_id:
                # Create dummy session
                dummy = {
                    "engineer_id": engineer_id,
                    "track_code": "Workshop/Other",
                    "track_name": "Workshop/Other",
                    "vehicle_category": "below_3_5t",
                    "booking_type": "standard",
                    "session_status": "completed",
                    "started_at": date_val.strftime("%Y-%m-%dT12:00:00Z"),
                    "ended_at": date_val.strftime("%Y-%m-%dT12:00:00Z"),
                    "duration_minutes": 0,
                    "hourly_rate": 0,
                    "total_cost": 0,
                    "notes": "Dummy session for services"
                }
                res = supabase.table("engineer_sessions").insert(dummy).execute()
                if res.data:
                    session_id = res.data[0]["id"]
                    session_map[date_key] = session_id
            
            service_data = {
                "session_id": session_id,
                "service_name": service_cat,
                "quantity": qty,
                "rate": rate
            }
            
            supabase.table("session_additional_services").insert(service_data).execute()
            print(f"Inserted service {service_cat} for {date_key}")
            
    except Exception as e:
        print(f"Error parsing Other Services Log: {e}")

    print("\nImport complete!")

if __name__ == "__main__":
    main()
