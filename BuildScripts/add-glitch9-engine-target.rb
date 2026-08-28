#!/usr/bin/env ruby
# frozen_string_literal: true

require 'xcodeproj'

root = File.expand_path('..', __dir__)
project_path = File.join(root, 'Moonlight.xcodeproj')
project = Xcodeproj::Project.open(project_path)
target = project.targets.find { |item| item.name == 'Glitch9MoonlightEngine' }
target ||= project.new_target(:framework, 'Glitch9MoonlightEngine', :ios, '15.0')

group = project.main_group.find_subpath('Glitch9MoonlightEngine', true)
group.set_source_tree('<group>')
group.path = 'Glitch9MoonlightEngine'
reference = group.files.find { |file| file.path == 'G9MoonlightEngine.swift' }
reference ||= group.new_file('G9MoonlightEngine.swift')
unless target.source_build_phase.files_references.include?(reference)
  target.add_file_references([reference])
end

target.build_configurations.each do |configuration|
  configuration.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.glitch9.MoonlightEngine'
  configuration.build_settings['PRODUCT_MODULE_NAME'] = 'Glitch9MoonlightEngine'
  configuration.build_settings['DEFINES_MODULE'] = 'YES'
  configuration.build_settings['SKIP_INSTALL'] = 'NO'
  configuration.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'YES'
  configuration.build_settings['SWIFT_VERSION'] = '5.0'
end

project.save
