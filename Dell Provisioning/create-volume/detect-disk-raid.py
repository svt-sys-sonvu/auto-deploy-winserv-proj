import requests
import sys

# Disable SSL warnings (not recommended for production)
requests.packages.urllib3.disable_warnings()
# Command-line arguments
idrac_ip = sys.argv[1]
idrac_user = sys.argv[2]
idrac_pw = sys.argv[3]
required_number_disk = int(sys.argv[4])  # Number of disks needed
required_capacity = int(sys.argv[5])  # Capacity in bytes
required_protocol = sys.argv[6].lower()  # Protocol (e.g., sata, sas)
required_media_type = sys.argv[7].lower()  # Media type (e.g., hdd, ssd)

#print(f"{idrac_ip} {idrac_user} {idrac_pw} {required_number_disk } {required_capacity} {required_protocol} {required_media_type}")
# Initialize variables
n = 0

# Fetch storage data to get the storage ID
controller_response = requests.get(f"https://{idrac_ip}/redfish/v1/Systems/System.Embedded.1/Storage", auth=(idrac_user, idrac_pw), verify=False)
if controller_response.status_code == 200:
    controller_data = controller_response.json()

    #storage_id = storage_data.get("Members", [])[0].get("@odata.id", "No storage ID").split("/")[-1]
    for controller in controller_data.get("Members",[]):
        controller_url = controller.get("@odata.id", "")
        if "RAID" in controller_url:
            storage_id = controller_url.split("/")[-1]
    print(f"{storage_id}")
else:
    print(f"Failed to fetch storage data. Status code: {controller_response.status_code}", flush=True)
    sys.exit(1)

# Construct the storage URL
url_storage = f"https://{idrac_ip}/redfish/v1/Systems/System.Embedded.1/Storage/{storage_id}"

# Function to check if the disk matches the criteria
def is_disk_valid(disk):
    capacity = disk.get('CapacityBytes', 0)
    protocol = disk.get('Protocol', '').lower()
    media_type = disk.get('MediaType', '').lower()
    min_capacity = required_capacity * 0.95
    max_capacity = required_capacity * 1.05
    return (min_capacity <= capacity <= max_capacity) and protocol == required_protocol and media_type == required_media_type
drive_paths = []
# Fetch the storage data to get the list of drives
response_storage = requests.get(url_storage, auth=(idrac_user, idrac_pw), verify=False)
if response_storage.status_code == 200:
    storage_data = response_storage.json()
    drives = storage_data.get('Drives', [])

    if drives:
        for drive in drives:
            drive_id = drive.get('@odata.id')
            if drive_id:
                response_drive = requests.get(f"https://{idrac_ip}{drive_id}", auth=(idrac_user, idrac_pw), verify=False)
                if response_drive.status_code == 200:
                    drive_data = response_drive.json()
                    volumes_count = drive_data.get("Links", {}).get("Volumes@odata.count", "Not found")
                    #volumes_list = drive_data.get("Links", {}).get("Volumes", [])
                    #volumes_id = volumes_list[0].get("@odata.id", "Not Found").split("/")[-1] if volumes_list else "No Volumes"
                    #print(f"  Volume ID: {volumes_id}")
                    if is_disk_valid(drive_data) and n < required_number_disk:
                        if volumes_count == 0:
                            n += 1
                            drive_name = drive_id.split("/")[-1]
                            drive_paths.append(drive_name)
#                            print("Disk found matching criteria:")
#                            print(f"  Name: {drive_data.get('Name', 'Unknown')}")
#                            print(f"  Capacity: {drive_data.get('CapacityBytes', 'Unknown')} bytes")
#                            print(f"  Protocol: {drive_data.get('Protocol', 'Unknown')}")
#                            print(f"  Media Type: {drive_data.get('MediaType', 'Unknown')}")
#                            print(f"  Drive path: {drive_id}")
                            #print(f"  Volume ID: {volumes_id}")
#                            print("----------------------------------------")
#                        else:
#                            print(f"The drive is already in use")
                else:
                    print(f"Failed to fetch details for drive: {drive_id}, Status: {response_drive.status_code}")
            else:
                print("Invalid drive ID found.")
    else:
        print("No drives found in the storage system.")
else:
    print(f"Failed to fetch storage data. Status code: {response_storage.status_code}")
if len(drive_paths) == required_number_disk:
    #print("Drives selected for RAID:")
    for drive_path in drive_paths:
        print(drive_path)

