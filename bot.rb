#! /usr/bin/env ruby

require 'bundler'
Bundler.require(:default)
if ENV['BOT_ENV'] == 'development'
  Bundler.require(:development)
  Dotenv.load
end
require 'net/http'
require 'json'

docs_uri = URI('http://builds.emberjs.com/release/ember-docs.json')

ember_docs = JSON.parse Net::HTTP.get(docs_uri)
$class_list = ember_docs['classes']
$valid_classes = {}

$class_list.keys.each do |class_name|
  $valid_classes[class_name.downcase] = class_name
  $class_list[class_name]['methods'] = {}
end

$method_list = ember_docs['classitems'].select { |item| item['itemtype'] == 'method' }
$method_list.each do |method|
  $class_list[method['class']]['methods'][method['name']] = method
end

$tag = '1.8.0'
class ApiPlugin
  include Cinch::Plugin

  match /api/, method: :api
  match /help/, method: :help
  match /learn (.+?) (.+)/, method: :learn
  match /forget (.+)/, method: :forget
  match /get (.+)/, method: :get
  # match /source/, method: :source

  def help(m)
    m.reply 'Commands:'
    m.reply ' !api <class name> - Links to documentation and source for the given class'
    m.reply ' !api <class name>#<method name> - Links to documentation and source for the given function'
  end

  def api(m)
    debug "api"
    matches = m.message.match(/!api (.*?)(?:#(.*))?$/)
    class_name = matches[1]
    method_name = matches[2]

    debug "Class: " + class_name
    debug "Method: " + method_name unless method_name.nil?

    class_name = $valid_classes[class_name.downcase]
    class_details = $class_list[class_name]

    if method_name
      class_methods = class_details['methods']
      method_details = class_methods[method_name]
    end

    if class_details && (!method_name || method_details)
      docs_url = "http://emberjs.com/api/classes/#{class_name}.html"
      if method_details
        method_anchor = "\#method_" + method_name.gsub(/[^a-z0-9_-]+/i, '_');
        docs_url += method_anchor
      end

      src_details = method_name ? method_details : class_details

      file_name =  src_details['file'][3..-1]
      line = src_details['line']
      src_url = "https://github.com/emberjs/ember.js/blob/v#{$tag}/#{file_name}#L#{line}"

      m.reply "Docs: #{docs_url}"
      m.reply "Source: #{src_url}"
    else
      m.reply 'I blame rwjblue'
    end
  end

  def learn(m, key, value)
    unless has_access?(m)
      return m.reply "#{m.user.nick} does not have access"
    end

    json = JSON.load(File.open('learnings.json', 'r')) || {}
    return if json.key? key
    json[key] = value

    write_learnings(json)
    m.reply "#{key} learned"
  end

  def forget(m, key)
    return nil unless has_access?(m)

    json = JSON.load(File.open('learnings.json', 'r')) || {}
    json.delete(key)

    write_learnings(json)
  end

  def get(m, key)
    File.open('learnings.json', 'r') do |file|
      json = JSON.load(file)

      if json.key?(key)
        m.reply json[key]
      else
        m.reply "404 not found: #{key}"
      end
    end
  end

  private

  def has_access?(m)
    m.channel.voiced?(m.user) || m.channel.half_opped?(m.user) || m.channel.opped?(m.user)
  end

  def write_learnings(json)
    File.open('learnings.json', 'w+') do |file|
      file.puts JSON.dump(json)
    end
  end

end

bot = Cinch::Bot.new do
  configure do |c|
    c.server = "irc.freenode.org"
    c.channels = ["#emberjs", "#emberjs-dev", "#bostonember"]
    c.nick = "docster"
    c.password = ENV['PASSWORD']
    c.plugins.plugins = [ApiPlugin]
  end
end

bot.start
