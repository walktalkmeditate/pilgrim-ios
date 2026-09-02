#!/usr/bin/env ruby
# Registers a source file with an Xcode target. The Pilgrim and UnitTests
# groups are plain PBXGroups (not synchronized folders), so a file on disk
# is invisible to the build until it has a file reference and a sources
# build-phase entry. Groups are created to mirror the on-disk path.
require "xcodeproj"

target_name, rel_path = ARGV
abort "usage: xcode-add.rb <target> <path/from/repo/root.swift>" unless target_name && rel_path

project = Xcodeproj::Project.open("Pilgrim.xcodeproj")
target = project.targets.find { |t| t.name == target_name } or abort "target #{target_name} not found"

parts = rel_path.split("/")
filename = parts.pop
group = project.main_group
parts.each do |part|
  child = group.children.find { |c| c.is_a?(Xcodeproj::Project::Object::PBXGroup) && (c.path == part || c.name == part) }
  child ||= group.new_group(part, part)
  group = child
end

file_ref = group.files.find { |f| f.path == filename }
file_ref ||= group.new_file(filename)

phase = target.source_build_phase
unless phase.files_references.include?(file_ref)
  phase.add_file_reference(file_ref)
  puts "added #{rel_path} to #{target_name}"
end
project.save
