require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require 'open3'
require 'json'
require 'yaml'
require 'rbconfig'

class LocalizeTest < Minitest::Test
  SCRIPT = File.expand_path('../skills/localize-skill-ui/scripts/localize.rb', __dir__)
  DESCRIPTION = '根据技能的当前说明生成准确中文描述，同时保留原始详细说明与其他配置'.freeze

  def setup
    @temporary = Dir.mktmpdir('skill ui ')
    @root = File.join(@temporary, 'skills with spaces')
    FileUtils.mkdir_p(@root)
  end

  def teardown
    FileUtils.remove_entry(@temporary)
  end

  def skill(name, description = nil)
    directory = File.join(@root, name)
    FileUtils.mkdir_p(directory)
    File.write(File.join(directory, 'SKILL.md'), "---\nname: #{name}\ndescription: Current source description\n---\nOriginal details.\n")
    unless description.nil?
      FileUtils.mkdir_p(File.join(directory, 'agents'))
      File.write(ui(name), YAML.dump({
        'interface' => {'display_name' => 'Custom name', 'short_description' => description,
                        'icon_small' => './icon.svg', 'default_prompt' => 'Keep prompt'},
        'policy' => {'allow_implicit_invocation' => false},
        'dependencies' => {'tools' => []}, 'future_field' => {'value' => 42}
      }))
    end
    directory
  end

  def ui(name)
    File.join(@root, name, 'agents', 'openai.yaml')
  end

  def mapping(data)
    path = File.join(@temporary, 'review.json')
    File.write(path, JSON.generate(data))
    path
  end

  def invoke(*arguments, code: 0)
    output, error, status = Open3.capture3(RbConfig.ruby, SCRIPT, '--root', @root, *arguments)
    assert_equal code, status.exitstatus, error
    output.empty? ? nil : JSON.parse(output)
  end

  def snapshot
    Dir.glob(File.join(@root, '**', '*')).select { |path| File.file?(path) }.to_h { |path| [path, File.binread(path)] }
  end

  def test_preview_collects_sources_without_writing
    skill('english', 'English UI'); skill('chinese', '已有中文'); skill('new')
    original = snapshot
    plan = invoke(code: 2)
    assert_equal original, snapshot
    assert_equal %w[needs_review missing_translation missing_translation], plan['skills'].map { |entry| entry['status'] }
    assert plan['skills'].all? { |entry| entry['source_description'] == 'Current source description' }
  end

  def test_create_update_preserve_and_repeat
    skill('english', 'English UI'); skill('accurate', '准确中文'); skill('new')
    original = snapshot
    metadata = YAML.load_file(ui('english'))
    review = mapping({'english' => DESCRIPTION, 'accurate' => '准确中文', 'new' => DESCRIPTION})
    invoke('--translations', review, '--apply')
    assert_equal original[ui('accurate')], File.binread(ui('accurate'))
    result = YAML.load_file(ui('english'))
    assert_equal DESCRIPTION, result['interface']['short_description']
    result['interface']['short_description'] = 'English UI'
    assert_equal metadata, result
    original.select { |path, _| path.end_with?('SKILL.md') }.each { |path, bytes| assert_equal bytes, File.binread(path) }
    assert File.file?(ui('new'))
    written = snapshot
    assert invoke('--translations', review, '--apply')['skills'].all? { |entry| entry['status'] == 'unchanged' }
    assert_equal written, snapshot
  end

  def test_missing_review_prevents_all_writes
    skill('first', 'English UI'); skill('second')
    original = snapshot
    invoke('--translations', mapping({'first' => DESCRIPTION}), '--apply', code: 1)
    assert_equal original, snapshot
  end

  def test_invalid_yaml_prevents_all_writes
    skill('first', 'English UI'); skill('second', 'English UI')
    File.write(ui('second'), 'interface: [broken')
    original = snapshot
    invoke('--translations', mapping({'first' => DESCRIPTION, 'second' => DESCRIPTION}), '--apply', code: 1)
    assert_equal original, snapshot
  end

  def test_rejects_invalid_new_description
    skill('new')
    invoke('--translations', mapping({'new' => '太短'}), '--apply', code: 1)
    refute File.exist?(ui('new'))
  end

  def test_symlink_is_not_modified
    skill('real', 'English UI')
    File.symlink(File.join(@root, 'real'), File.join(@root, 'linked'))
    original = File.binread(ui('real'))
    invoke('--apply', code: 1)
    assert_equal original, File.binread(ui('real'))
  end

  def test_empty_root
    assert_empty invoke['skills']
  end
end
