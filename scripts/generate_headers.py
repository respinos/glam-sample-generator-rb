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

def guess_file_info(file_path: Path) -> dict:
    info = {}
    basename = file_path.name
    ext = file_path.suffix.lower()

    # Match specific filenames
    if basename == "core.dor.json":
        info["interactionModel"] = dor_urn("resource:glam")
        info["mimeType"] = "application/json"
    elif basename == "structure.dor.xml":
        info["interactionModel"] = dor_urn("structure")
        info["mimeType"] = "application/xml"
    elif basename == "rights.dor.json":
        info["interactionModel"] = dor_urn("rights")
        info["mimeType"] = "application/json"
    
    if info:
        return info

    # Match extensions
    if ext == ".json":
        info["interactionModel"] = dor_urn("file:metadata")
        info["mimeType"] = "application/json"
    elif ext in [".tif", ".tiff"]:
        info["interactionModel"] = dor_urn("file:data")
        info["mimeType"] = "image/tiff"
        info["filename"] = basename
    elif ext == ".txt":
        info["interactionModel"] = dor_urn("file:data")
        info["mimeType"] = "text/plain"
        info["filename"] = basename
    elif ext == ".xml":
        info["interactionModel"] = dor_urn("file:data")
        info["mimeType"] = "application/xml"
        info["filename"] = basename
    else:
        raise ValueError(f"Unknown file type for {file_path}")
    
    return info

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
                
            info = guess_file_info(resource_file)
            
            # Determine ID
            if resource_file.name == "core.dor.json":
                resource_full_id = f"info:root/{resource_id}"
            else:
                resource_full_id = f"info:root/{resource_id}/{resource_file.name}"
            
            # Prepare header data
            parent_id = str(Path(resource_full_id).parent)
            
            # System Identifier Logic
            if resource_file.name == "core.dor.json" and parent_id > "info:root":
                sys_id = calculate_uuid(str(resource_dir), FILESET_UUID_NAMESPACE)
            else:
                sys_id = calculate_uuid(resource_file.name, DEFAULT_UUID_NAMESPACE)

            header_data = {
                "id": resource_full_id,
                "parent": parent_id,
                "systemIdentifier": sys_id,
                "interactionModel": info["interactionModel"],
                "contentSize": resource_file.stat().st_size,
            }

            if "mimeType" in info:
                header_data["mimeType"] = info["mimeType"]

            if "filename" in info and info["filename"]:
                header_data["filename"] = info.get("filename")

            header_data.update({
                "digests": [f"urn:sha-512:{calculate_sha512(resource_file)}"],
                "updatedAt": datetime.fromtimestamp(resource_file.stat().st_mtime, tz=timezone.utc).isoformat().replace("+00:00", "Z"),
                "updatedBy": "dlxsadm",
                "deleted": False,
                "visibility": "visible",
                "contentPath": resource_file.name,
                "headersVersion": "1.0"
            })

            # Ensure .dor directory exists
            header_dir = resource_dir / ".dor"
            header_dir.mkdir(exist_ok=True)
            
            header_file = header_dir / f"{resource_file.name}.json"
            
            with open(header_file, "w") as f:
                json.dump(header_data, f, indent=2)

if __name__ == "__main__":
    main()