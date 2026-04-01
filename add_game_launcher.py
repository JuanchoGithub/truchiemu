#!/usr/bin/env python3
import uuid

# Generate UUIDs for the new file
file_ref_uuid = "A1B2C3D4E5F6A7B8C9D0E1F2"
build_file_uuid = "F2E1D0C9B8A7F6E5D4C3B2A1"

# Read the project file
with open('TruchieEmu.xcodeproj/project.pbxproj', 'r') as f:
    content = f.read()

# 1. Add PBXBuildFile entry
old_build = '785352A1776D2F26AE6E9BDA /* CLILauncher.swift in Sources */ = {isa = PBXBuildFile; fileRef = C8CF37F3EE97D10E700B56DF /* CLILauncher.swift */; };'
new_build = old_build + '\n\t\t' + build_file_uuid + ' /* GameLauncher.swift in Sources */ = {isa = PBXBuildFile; fileRef = ' + file_ref_uuid + ' /* GameLauncher.swift */; };'
content = content.replace(old_build, new_build)

# 2. Add PBXFileReference entry
old_ref = 'C8CF37F3EE97D10E700B56DF /* CLILauncher.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CLILauncher.swift; sourceTree = "<group>"; };'
new_ref = old_ref + '\n\t\t' + file_ref_uuid + ' /* GameLauncher.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = GameLauncher.swift; sourceTree = "<group>"; };'
content = content.replace(old_ref, new_ref)

# 3. Add file reference to the group
old_group = 'C8CF37F3EE97D10E700B56DF /* CLILauncher.swift */,'
new_group = old_group + '\n\t\t\t\t' + file_ref_uuid + ' /* GameLauncher.swift */,'
content = content.replace(old_group, new_group)

# 4. Add to Sources build phase
old_sources = '785352A1776D2F26AE6E9BDA /* CLILauncher.swift in Sources */,'
new_sources = old_sources + '\n\t\t\t\t' + build_file_uuid + ' /* GameLauncher.swift in Sources */,'
content = content.replace(old_sources, new_sources)

# Write back
with open('TruchieEmu.xcodeproj/project.pbxproj', 'w') as f:
    f.write(content)

print(f'Added GameLauncher.swift with fileRef={file_ref_uuid} buildFile={build_file_uuid}')