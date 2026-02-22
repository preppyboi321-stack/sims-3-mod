"""
Sims 3 Package Builder
======================
Takes a compiled .NET DLL and wraps it into a .package file
that the Sims 3 can load as a script mod (S3SA resource).

Also embeds the XML tuning file as a tuning resource.

Usage: python build_package.py
"""

import os
import sys
import struct
import hashlib
import time

# DBPF constants
DBPF_MAGIC = b'DBPF'
DBPF_MAJOR = 2
DBPF_MINOR = 1

# Resource types
S3SA_TYPE = 0x073FAA07       # Sims 3 Script Assembly
XML_TUNING_TYPE = 0xC0DB5AE7  # XML tuning resource

# FNV hash constants for generating instance IDs
FNV_OFFSET_32 = 0x811C9DC5
FNV_PRIME_32 = 0x01000193
FNV_OFFSET_64 = 0xCBF29CE484222325
FNV_PRIME_64 = 0x00000100000001B3


def fnv64(name):
    """Compute FNV-1a 64-bit hash of a string (used for instance IDs)."""
    name = name.lower()
    h = FNV_OFFSET_64
    for c in name.encode('ascii'):
        h ^= c
        h = (h * FNV_PRIME_64) & 0xFFFFFFFFFFFFFFFF
    return h


def fnv32(name):
    """Compute FNV-1a 32-bit hash of a string."""
    name = name.lower()
    h = FNV_OFFSET_32
    for c in name.encode('ascii'):
        h ^= c
        h = (h * FNV_PRIME_32) & 0xFFFFFFFF
    return h


def build_s3sa_resource(dll_path):
    """
    Build an S3SA resource from a .NET DLL.
    
    S3SA format:
      - 4 bytes: version (2)
      - 4 bytes: flags (0)
      - 4 bytes: assembly name length
      - N bytes: assembly name (ASCII)
      - 4 bytes: DLL data length
      - M bytes: DLL data
    """
    dll_data = open(dll_path, 'rb').read()
    assembly_name = os.path.splitext(os.path.basename(dll_path))[0]
    name_bytes = assembly_name.encode('ascii')
    
    # S3SA v2 format
    resource = bytearray()
    resource += struct.pack('<I', 2)                    # version
    resource += struct.pack('<I', 0)                    # flags  
    resource += struct.pack('<I', len(name_bytes))      # name length
    resource += name_bytes                               # assembly name
    resource += struct.pack('<I', len(dll_data))        # DLL size
    resource += dll_data                                 # raw DLL bytes
    
    return bytes(resource)


def build_package(dll_path, xml_path, output_path):
    """Build a complete DBPF .package file containing the S3SA and XML resources."""
    
    print(f"\n{'='*55}")
    print(f"  Sims 3 Package Builder")
    print(f"{'='*55}")
    
    # Prepare resources
    resources = []
    
    # 1. S3SA assembly resource
    if dll_path and os.path.isfile(dll_path):
        s3sa_data = build_s3sa_resource(dll_path)
        assembly_name = os.path.splitext(os.path.basename(dll_path))[0]
        instance_id = fnv64(assembly_name)
        resources.append({
            'type': S3SA_TYPE,
            'group': 0x00000000,
            'instance': instance_id,
            'data': s3sa_data,
            'name': f'S3SA: {assembly_name}',
        })
        print(f"  [+] Assembly: {assembly_name} ({len(s3sa_data)} bytes)")
        print(f"      Instance: 0x{instance_id:016X}")
    
    # 2. XML tuning resource
    if xml_path and os.path.isfile(xml_path):
        xml_data = open(xml_path, 'rb').read()
        tuning_name = os.path.splitext(os.path.basename(xml_path))[0]
        instance_id = fnv64(tuning_name)
        resources.append({
            'type': XML_TUNING_TYPE,
            'group': 0x00000000,
            'instance': instance_id,
            'data': xml_data,
            'name': f'XML: {tuning_name}',
        })
        print(f"  [+] Tuning:   {tuning_name} ({len(xml_data)} bytes)")
        print(f"      Instance: 0x{instance_id:016X}")
    
    if not resources:
        print("  [ERROR] No resources to package!")
        return False
    
    # Build DBPF v2 package
    # Layout:
    #   - Header (96 bytes)
    #   - Resource data (sequential)
    #   - Index table
    
    HEADER_SIZE = 96
    
    # Calculate data offsets
    current_offset = HEADER_SIZE
    for res in resources:
        res['offset'] = current_offset
        res['file_size'] = len(res['data'])
        res['mem_size'] = len(res['data'])
        current_offset += len(res['data'])
    
    index_offset = current_offset
    
    # Build index
    # Index format for DBPF v2:
    #   4 bytes: index flags (0 = all fields per entry)
    #   Per entry:
    #     4 bytes: type
    #     4 bytes: group  
    #     4 bytes: instance high
    #     4 bytes: instance low
    #     4 bytes: offset
    #     4 bytes: file_size | 0x80000000 (high bit = compressed flag, 0 = uncompressed)
    #     4 bytes: mem_size
    #     2 bytes: compressed (0xFFFF = uncompressed)
    #     2 bytes: unknown (0x0001)
    
    index_data = bytearray()
    index_data += struct.pack('<I', 0)  # index flags: no constant fields
    
    for res in resources:
        inst_hi = (res['instance'] >> 32) & 0xFFFFFFFF
        inst_lo = res['instance'] & 0xFFFFFFFF
        
        index_data += struct.pack('<I', res['type'])
        index_data += struct.pack('<I', res['group'])
        index_data += struct.pack('<I', inst_hi)
        index_data += struct.pack('<I', inst_lo)
        index_data += struct.pack('<I', res['offset'])
        index_data += struct.pack('<I', res['file_size'] | 0x80000000)  # uncompressed flag
        index_data += struct.pack('<I', res['mem_size'])
        index_data += struct.pack('<H', 0x0000)  # not compressed
        index_data += struct.pack('<H', 0x0001)  # unknown flag
    
    index_size = len(index_data)
    
    # Build header (96 bytes)
    header = bytearray(96)
    struct.pack_into('<4s', header, 0x00, DBPF_MAGIC)           # Magic
    struct.pack_into('<I', header, 0x04, DBPF_MAJOR)            # Major version
    struct.pack_into('<I', header, 0x08, DBPF_MINOR)            # Minor version
    # 0x0C - 0x23: reserved/unknown (leave as zeros)
    struct.pack_into('<I', header, 0x24, len(resources))        # Index entry count
    # 0x28: unknown
    struct.pack_into('<I', header, 0x2C, index_size)            # Index size
    # 0x30 - 0x3B: reserved
    struct.pack_into('<I', header, 0x3C, 3)                     # Index version
    struct.pack_into('<I', header, 0x40, index_offset)          # Index offset
    # Rest is zeros
    
    # Write the package
    with open(output_path, 'wb') as f:
        f.write(header)
        for res in resources:
            f.write(res['data'])
        f.write(index_data)
    
    total_size = os.path.getsize(output_path)
    print(f"\n  [SUCCESS] Package built!")
    print(f"  Output: {output_path}")
    print(f"  Size:   {total_size / 1024:.1f} KB")
    print(f"  Resources: {len(resources)}")
    print(f"\n  INSTALL: Copy to Documents/Electronic Arts/The Sims 3/Mods/Packages/")
    print(f"{'='*55}")
    
    return True


def main():
    # Default paths
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    dll_path = os.path.join(script_dir, 'TurboEngine.dll')
    xml_path = os.path.join(script_dir, 'TurboEngine_Tuning.xml')
    output_path = os.path.join(script_dir, 'TurboEngine.package')
    
    # Check for DLL
    if not os.path.isfile(dll_path):
        # Try bin/Debug or bin/Release
        for sub in ['bin\\Debug', 'bin\\Release', 'bin\\Debug\\net20', 'bin\\Release\\net20',
                     'bin\\Debug\\net35', 'bin\\Release\\net35']:
            candidate = os.path.join(script_dir, sub, 'TurboEngine.dll')
            if os.path.isfile(candidate):
                dll_path = candidate
                break
    
    if not os.path.isfile(dll_path):
        print("[ERROR] TurboEngine.dll not found!")
        print("  Compile the project first, then run this script.")
        print(f"  Expected at: {dll_path}")
        print()
        print("  Quick compile with csc.exe:")
        print('  "C:\\Windows\\Microsoft.NET\\Framework\\v3.5\\csc.exe" /target:library /out:TurboEngine.dll '
              '/reference:"C:\\MagiPacks\\The Sims 3\\Tools\\Create a World Tool\\ScriptCore.dll" '
              '/reference:"C:\\MagiPacks\\The Sims 3\\Tools\\Create a World Tool\\SimIFace.dll" '
              'TurboEngine.cs')
        input("\nPress Enter to exit...")
        sys.exit(1)
    
    build_package(dll_path, xml_path, output_path)
    input("\nPress Enter to exit...")


if __name__ == '__main__':
    main()
