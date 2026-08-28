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

native_header = group.files.find { |file| file.path == 'G9MoonlightNativeEngine.h' }
native_header ||= group.new_file('G9MoonlightNativeEngine.h')
native_source = group.files.find { |file| file.path == 'G9MoonlightNativeEngine.m' }
native_source ||= group.new_file('G9MoonlightNativeEngine.m')
unless target.source_build_phase.files_references.include?(native_source)
  target.source_build_phase.add_file_reference(native_source)
end
umbrella_header = group.files.find { |file| file.path == 'Glitch9MoonlightEngine.h' }
umbrella_header ||= group.new_file('Glitch9MoonlightEngine.h')
unless target.headers_build_phase.files_references.include?(umbrella_header)
  header_build_file = target.headers_build_phase.add_file_reference(umbrella_header)
  header_build_file.settings = { 'ATTRIBUTES' => ['Public'] }
end
unless target.headers_build_phase.files_references.include?(native_header)
  header_build_file = target.headers_build_phase.add_file_reference(native_header)
  header_build_file.settings = { 'ATTRIBUTES' => ['Public'] }
end

target.build_configurations.each do |configuration|
  configuration.build_settings['PRODUCT_BUNDLE_IDENTIFIER'] = 'com.glitch9.MoonlightEngine'
  configuration.build_settings['PRODUCT_MODULE_NAME'] = 'Glitch9MoonlightEngine'
  configuration.build_settings['DEFINES_MODULE'] = 'YES'
  configuration.build_settings['GENERATE_INFOPLIST_FILE'] = 'YES'
  configuration.build_settings['SKIP_INSTALL'] = 'NO'
  configuration.build_settings['BUILD_LIBRARY_FOR_DISTRIBUTION'] = 'YES'
  configuration.build_settings['SWIFT_VERSION'] = '5.0'
  configuration.build_settings['GCC_PREFIX_HEADER'] = '$(PROJECT_DIR)/Limelight/Limelight-Prefix.pch'
  configuration.build_settings['GCC_PRECOMPILE_PREFIX_HEADER'] = 'YES'
  configuration.build_settings['HEADER_SEARCH_PATHS'] = [
    '$(inherited)',
    '$(PROJECT_DIR)/moonlight-common/moonlight-common-c/src'
  ]
  configuration.build_settings['LIBRARY_SEARCH_PATHS[sdk=iphoneos*]'] = [
    '$(inherited)',
    '$(PROJECT_DIR)/libs/opus/lib/iOS',
    '$(PROJECT_DIR)/libs/SDL2/lib/iOS',
    '$(PROJECT_DIR)/libs/FFmpeg/lib/iOS'
  ]
  configuration.build_settings['LIBRARY_SEARCH_PATHS[sdk=iphonesimulator*]'] = [
    '$(inherited)',
    '$(PROJECT_DIR)/libs/opus/lib/iOS-Sim',
    '$(PROJECT_DIR)/libs/SDL2/lib/iOS-Sim',
    '$(PROJECT_DIR)/libs/FFmpeg/lib/iOS-Sim'
  ]
  configuration.build_settings['OTHER_LDFLAGS'] = [
    '$(inherited)',
    '-Wl,-u,_LiInitializeStreamConfiguration',
    '-framework',
    'GameController',
    '-framework',
    'CoreHaptics'
  ]
end

moonlight_target = project.targets.find { |item| item.name == 'Moonlight' }
common_dependency = moonlight_target&.dependencies&.find { |item| item.name == 'moonlight-common' }
common_product = moonlight_target&.frameworks_build_phase&.files&.map(&:file_ref)&.compact&.find do |item|
  item.path == 'libmoonlight-common.a'
end

if common_dependency && target.dependencies.none? { |item| item.name == 'moonlight-common' }
  proxy = project.new(Xcodeproj::Project::Object::PBXContainerItemProxy)
  proxy.container_portal = common_dependency.target_proxy.container_portal
  proxy.proxy_type = common_dependency.target_proxy.proxy_type
  proxy.remote_global_id_string = common_dependency.target_proxy.remote_global_id_string
  proxy.remote_info = common_dependency.target_proxy.remote_info
  dependency = project.new(Xcodeproj::Project::Object::PBXTargetDependency)
  dependency.name = 'moonlight-common'
  dependency.target_proxy = proxy
  target.dependencies << dependency
end

if common_product && target.frameworks_build_phase.files_references.none? { |item| item == common_product }
  target.frameworks_build_phase.add_file_reference(common_product)
end

engine_sources = %w[
  Limelight/Limelight.xcdatamodeld
  Limelight/Crypto/CryptoManager.m
  Limelight/Crypto/mkcert.c
  Limelight/Database/TemporaryApp.m
  Limelight/Database/TemporaryHost.m
  Limelight/Network/HttpManager.m
  Limelight/Network/HttpRequest.m
  Limelight/Network/HttpResponse.m
  Limelight/Network/AppListResponse.m
  Limelight/Network/PairManager.m
  Limelight/Network/ServerInfoResponse.m
  Limelight/Stream/Connection.m
  Limelight/Stream/StreamConfiguration.m
  Limelight/Stream/StreamManager.m
  Limelight/Stream/VideoDecoderRenderer.m
  Limelight/Utility/Logger.m
  Limelight/Utility/Utils.m
]

moonlight_sources = moonlight_target.source_build_phase.files_references
engine_sources.each do |path|
  reference = moonlight_sources.find { |item| item.real_path.to_s == File.join(root, path) }
  target.source_build_phase.add_file_reference(reference) if reference && !target.source_build_phase.files_references.include?(reference)
end

moonlight_target.frameworks_build_phase.files.each do |source_build_file|
  next if source_build_file.file_ref == common_product
  already_linked = target.frameworks_build_phase.files.any? do |candidate|
    candidate.file_ref == source_build_file.file_ref && candidate.product_ref == source_build_file.product_ref
  end
  next if already_linked
  build_file = project.new(Xcodeproj::Project::Object::PBXBuildFile)
  build_file.file_ref = source_build_file.file_ref if source_build_file.file_ref
  build_file.product_ref = source_build_file.product_ref if source_build_file.product_ref
  target.frameworks_build_phase.files << build_file
end

target.build_configurations.each do |configuration|
  configuration.build_settings['HEADER_SEARCH_PATHS'] += [
    '$(PROJECT_DIR)/Limelight/**',
    '$(PROJECT_DIR)/libs/**',
    '$(SDKROOT)/usr/include/libxml2/**'
  ]
end

project.save
