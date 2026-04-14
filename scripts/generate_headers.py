# /// script
# dependencies = [
# ]
# ///

import os
import json
import hashlib
import uuid
import argparse
from pathlib import Path
from datetime import datetime, timezone

# Constants
DEFAULT_UUID_NAMESPACE = uuid.uuid5(uuid.NAMESPACE_DNS, "fixtures")
FILESET_UUID_NAMESPACE = uuid.uuid5(uuid.NAMESPACE_DNS, "fileset")

def dor_urn(leaf: str) -> str:
    return f"urn:umich:lib:dor:model:2026:{leaf}"

def calculate_uuid(resource_path: str, namespace: uuid.UUID) -> str:
    return str(uuid.uuid5(namespace, resource_path))

def calculate_sha512(file_path: Path) -> str:
    sha512 = hashlib.sha512()
    with open(file_path, "rb") as f:
        # Read in 1024 byte chunks as per Ruby script
        for chunk in iter(lambda: f.read(1024), b""):
            sha512.update(chunk)
    return sha512.hexdigest()

def main():
    parser = argparse.ArgumentParser(description="Process DOR resources.")
    parser.add_argument("--resource", required=True, help="Path to resource file")
    args = parser.parse_args()

    resource_input_path = Path(args.resource)
    if not resource_input_path.exists():
        print(f"Resource file not found: {args.resource}", file=os.sys.stderr)
        os.sys.exit(1)

    # Base directory to calculate relative IDs
    base_dir = resource_input_path.parent
    
    # Find all core.dor.json files recursively
    # In Ruby: Dir.glob(File.join(File.dirname(options.resource_path), "**", "*", "core.dor.json"))
    package_cores = list(base_dir.rglob("core.dor.json"))

    for core_path in package_cores:
        resource_dir = core_path.parent
        # Calculate the resource ID relative to the starting directory
        resource_id = str(resource_dir.relative_to(base_dir))
        
        # Iterate through all files in the same directory as the core.dor.json
        for resource_file in resource_dir.iterdir():
            if not resource_file.is_file():
                continue
            
            # Prepare header data
            header_dir = resource_dir / ".dor"
            header_file = header_dir / f"{resource_file.name}.json"

            header_data = json.load(open(header_file))
            header_data["digests"] = [f"urn:sha-512:{calculate_sha512(resource_file)}"]
            header_data["contentSize"] = resource_file.stat().st_size

            # print(json.dumps(header_data, indent=2))

            with open(header_file, "w") as f:
                json.dump(header_data, f, indent=2)

if __name__ == "__main__":
    main()