import requests
import sys

# Disable SSL warnings (not recommended for production)
requests.packages.urllib3.disable_warnings()
# Command-line arguments
idrac_ip = sys.argv[1]
idrac_user = sys.argv[2]
idrac_pw = sys.argv[3]
#required_number_disk = int(sys.argv[4])  # Number of disks needed
#required_capacity = int(sys.argv[5])  # Capacity in bytes
#required_protocol = sys.argv[6].lower()  # Protocol (e.g., sata, sas)
#required_media_type = sys.argv[7].lower()  # Media type (e.g., hdd, ssd)

#print(f"{ilo_ip} {ilo_user} {ilo_pw} {required_number_disk } {required_capacity} {required_protocol} {required_media_type}")
# Initialize variablesn = 0

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

# Construct the storage URL
url_volumes = f"https://{idrac_ip}/redfish/v1/Systems/System.Embedded.1/Storage/{storage_id}/Volumes"
# Function to check if the disk matches the criteria

# Fetch the storage data to get the list of drives
response_volume = requests.get(url_volumes, auth=(idrac_user, idrac_pw), verify=False)
if response_volume.status_code == 200:
    volume_data = response_volume.json()
    volumes = volume_data.get('Members', [])

    if volumes:
        for volume in volumes:
            volume_path = volume.get('@odata.id')
            #print(f"{volume_path}")
            volume_id = volume_path.split("/")[-1]
            print(f"{volume_id}")
