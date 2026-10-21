#!/usr/bin/env ruby
# Local UI localization; Ruby standard library only. Default: preview.
require 'json'
require 'yaml'
require 'optparse'
require 'fileutils'
require 'tempfile'

options = {root: File.expand_path('~/.agents/skills'), apply: false}
OptionParser.new do |parser|
  parser.banner = 'Usage: ruby localize.rb [--root DIR] [--translations JSON] [--apply]'
  parser.on('--root DIR') { |value| options[:root] = File.expand_path(value) }
  parser.on('--translations JSON') { |value| options[:translations] = value }
  parser.on('--apply') { options[:apply] = true }
end.parse!

def read_mapping(path)
  data = JSON.parse(File.read(path, encoding: 'UTF-8'))
  raise "Translation file must contain an object: #{path}" unless data.is_a?(Hash)
  data.each do |name, description|
    valid = description.is_a?(String) && description.match?(/[\u4e00-\u9fff]/)
    raise "Invalid Chinese description for #{name}" unless valid
  end
  data
end

begin
  root = options[:root]
  raise "Skills directory not found: #{root}" unless File.directory?(root)
  translations = options[:translations] ? read_mapping(options[:translations]) : {}
  plans = []
  Dir.children(root).sort.each do |name|
    directory = File.join(root, name)
    next unless File.directory?(directory) && File.file?(File.join(directory, 'SKILL.md'))
    path = File.join(directory, 'agents', 'openai.yaml')
    raise "Refusing symlink: #{directory}" if File.symlink?(directory)
    raise "Refusing symlink: #{path}" if File.symlink?(File.dirname(path)) || File.symlink?(path)
    original = File.exist?(path) ? File.read(path, encoding: 'UTF-8') : nil
    data = original.nil? ? {} : YAML.safe_load(original, permitted_classes: [], permitted_symbols: [], aliases: false)
    raise "Expected YAML mapping: #{path}" unless data.is_a?(Hash)
    data['interface'] = {} unless data.key?('interface')
    raise "Expected interface mapping: #{path}" unless data['interface'].is_a?(Hash)
    source_path = File.join(directory, 'SKILL.md')
    source = File.read(source_path, encoding: 'UTF-8')
    header = source.match(/\A---\r?\n(.*?)\r?\n---(?:\r?\n|\z)/m)
    raise "Missing skill frontmatter: #{source_path}" unless header
    metadata = YAML.safe_load(header[1], permitted_classes: [], permitted_symbols: [], aliases: false)
    raise "Expected skill frontmatter mapping: #{source_path}" unless metadata.is_a?(Hash)
    unless metadata['name'].is_a?(String) && !metadata['name'].strip.empty? && metadata['description'].is_a?(String) && !metadata['description'].strip.empty?
      raise "Skill name and description must be nonempty strings: #{source_path}"
    end
    previous = data['interface']['short_description']
    description = translations[name]
    if description && description != previous && !description.length.between?(25, 64)
      raise "New description must contain 25–64 characters: #{name}"
    end
    status = if description.nil?
               previous.is_a?(String) && previous.match?(/[\u4e00-\u9fff]/) ? 'needs_review' : 'missing_translation'
             elsif data['interface']['short_description'] == description && data['interface']['display_name']
               'unchanged'
             else
               original.nil? ? 'create' : 'update'
             end
    data['interface']['display_name'] ||= name.split('-').map(&:capitalize).join(' ')
    data['interface']['short_description'] = description unless description.nil?
    plans << {name: name, path: path, status: status, previous: previous,
              source_path: source_path, source_description: metadata['description'],
              description: description, original: original, source: source, data: data}
  end
  missing = plans.any? { |plan| ['missing_translation', 'needs_review'].include?(plan[:status]) }
  if options[:apply]
    raise 'Review current source descriptions and supply --translations for every skill before applying. No files written.' if missing
    plans.each do |plan|
      current = File.exist?(plan[:path]) ? File.read(plan[:path], encoding: 'UTF-8') : nil
      raise "File changed during planning: #{plan[:path]}" unless current == plan[:original]
      raise "Source changed during planning: #{plan[:source_path]}" unless File.read(plan[:source_path], encoding: 'UTF-8') == plan[:source]
    end
    plans.each do |plan|
      next if plan[:status] == 'unchanged'
      path = plan[:path]
      FileUtils.mkdir_p(File.dirname(path))
      Tempfile.create(['.localize-', '.yaml'], File.dirname(path)) do |file|
        file.write(YAML.dump(plan[:data]))
        file.flush
        file.chmod(File.exist?(path) ? File.stat(path).mode & 0777 : 0644)
        File.rename(file.path, path)
      end
    end
  end
  puts JSON.pretty_generate({mode: options[:apply] ? 'apply' : 'preview',
                             skills: plans.map { |plan| plan.reject { |key, _| [:original, :source, :data].include?(key) } }})
  exit(missing ? 2 : 0)
rescue StandardError => error
  warn error.message
  exit 1
end
