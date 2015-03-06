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
redis_uri = URI(ENV['REDISTOGO_URL'])

REDIS = Redis.new(url: redis_uri)

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

$tag = ENV['EMBER_VERSION']
class LearnPlugin
  include Cinch::Plugin
  match /learn (\w+) (.+)$/, method: :learn
  match /relearn (\w+) (.+)$/, method: :relearn
  match /forget (\w+)/, method: :forget
  match /get (\w+)/, method: :get
  match /learned/, method: :all

  def learn(m, key, value)
    if REDIS.exists(namespace_key(m, key))
      m.reply "I already know \"#{key}\""
      return
    end
    relearn(m, key, value)
  end

  def relearn(m, key, value)
    unless has_access?(m)
      return m.reply "#{m.user.nick} does not have access"
    end

    REDIS.set(namespace_key(m, key), value)
    m.reply "I learned that \"#{key}\" means: #{value}"
  end

  def forget(m, key)
    return nil unless has_access?(m)

    REDIS.del(namespace_key(m, key))
    m.reply "I forgot \"#{key}\""
  end

  def get(m, key)
    if REDIS.exists(namespace_key(m, key))
      m.reply REDIS.get(namespace_key(m, key))
    else
      m.reply "I don't know what \"#{key}\" means"
    end
  end

  def all(m)
    namespace = "learned:#{m.channel.name}:"
    keys = REDIS.keys("#{namespace}*")

    keys.each do |key|
      m.reply "#{key.gsub(namespace,'')}: #{REDIS.get(key)}"
    end

    m.reply "And that's all I know!"
  end

  def self.help_reply(m)
    m.reply ' !learn <key> <value> - Teaches me that the meaning of <key> is <value>, unless I already know a meaning for <key> (requires voice)'
    m.reply ' !relearn <key> <value> - Teaches me the new meaning of <key> is <value> (requires voice)'
    m.reply ' !forget <key> - Tells me to foget about <key> (requires voice)'
    m.reply ' !get <key> - Displays what I know about <key>'
    m.reply ' !learned - Displays everything I know'
  end

  private

  def namespace_key(m, key)
    "learned:#{m.channel.name}:#{key}"
  end

  def has_access?(m)
    m.channel.voiced?(m.user) || m.channel.half_opped?(m.user) || m.channel.opped?(m.user)
  end
end

class ApiPlugin
  include Cinch::Plugin

  match /api/, method: :api

  def self.help_reply(m)
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
end

class HelpPlugin
  include Cinch::Plugin
  match /help/, method: :help

  def help(m)
    m.reply("Commands:")
    ApiPlugin.help_reply(m)
    LearnPlugin.help_reply(m)
  end
end


bot = Cinch::Bot.new do
  configure do |c|
    c.server = "irc.freenode.org"
    c.channels = ENV['CHANNELS'].split(',')#["#emberjs", "#emberjs-dev", "#bostonember"]
    c.nick = "docster"
    c.password = ENV['PASSWORD']
    c.plugins.plugins = [ApiPlugin,LearnPlugin,HelpPlugin]
  end
end

bot.start
